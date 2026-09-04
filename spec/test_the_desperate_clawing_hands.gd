# The Desperate Clawing Hands Of The Dead - the protocol half of Truth in Filth.
#
#   "For the rest of the scene, something terrible lurks in the cracks."
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-04-clawing-hands-design.md
#
# The buff is the single switch for the whole power. Everything else asks whether it is present, so
# these specs lean on that: apply it directly to set up a scenario rather than driving the protocol
# every time.
extends GutTest

const ClawingHands := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_nuckelavee/cp_truth_in_filth/buff_the_desperate_clawing_hands.gd')
const PoisonedSoil := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_nuckelavee/mt_poisoned_soil/passive_poisoned_soil.gd')

const CP_ID := &'cp_truth_in_filth'
const BUFF_ID := &'buff_the_desperate_clawing_hands'
const PROTOCOL := &'action_the_desperate_clawing_hands_of_the_dead'
const START := Vector2i(0, 0)
## The map is 5x5. Only the trail this unit projects matters, never where it stands, so it sits in
## the far corner away from every lane the tests use.
const BYSTANDER_TILE := Vector2i(4, 4)

var game:Gamemaster
var nuckelavee:Unit
var cp_gear:GearCore
## A THIRD PARTY that owns the difficult ground - see _make_difficult.
var terrain_source:Unit
var soil_gear:GearCore
var _difficult_tiles:Array[Vector2i] = []

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	nuckelavee = SpecFactory.create_unit(game.map, START)
	cp_gear = nuckelavee.core.equip_system(CP_ID)
	SpecFactory.apply_passive_buffs(nuckelavee)

	terrain_source = SpecFactory.create_unit(game.map, BYSTANDER_TILE)
	soil_gear = terrain_source.core.equip_system(&'mt_poisoned_soil')
	SpecFactory.apply_passive_buffs(terrain_source)
	_difficult_tiles = []

## Makes `tile` genuinely difficult ground, cumulatively, and crucially NOT ground the Nuckelavee
## made - which is exactly what the widened power has to be tested against.
##
## SpecFactory.set_terrain CANNOT be used for this, and the reason is worth writing down: it writes
## map.ground_terrain, while everything in this feature reads map.get_surface_terrain_at, and
## calculate_surface_merged_terrain_and_height_at (map_state.gd:475-480) builds surface_terrain from
## get_ground_surface_terrain_at plus DYNAMIC terrain - it never consults ground_terrain at all. A
## tile set that way looks difficult to nothing.
##
## Terrain projected by a PassiveTerrainZone does land in dynamic terrain, which is why
## test_poisoned_soil.gd's pathfinder-cost assertions work. So a bystander carrying Poisoned Soil is
## the honest way to conjure third-party difficult ground, and it is a route already proven by a
## shipped spec.
func _make_difficult(tile:Vector2i) -> void:
	if not _difficult_tiles.has(tile): _difficult_tiles.append(tile)
	PoisonedSoil.write_trail(soil_gear, _difficult_tiles)
	# Writing gear state does not refresh the map - only a sweep does.
	UnitTile.update_tracking_and_statuses(game.map)

# ============================== the protocol and the switch ==============================

func test_the_protocol_applies_the_buff_and_spends_the_core():
	await SpecFactory.start_turn(game, nuckelavee)
	assert_true(nuckelavee.core.has_core_power, 'Starts with the core power available.')
	await SpecFactory.use(game, nuckelavee, CP_ID, PROTOCOL)
	assert_true(UnitCondition.has_buff(nuckelavee, BUFF_ID), 'The protocol woke the hands.')
	assert_false(nuckelavee.core.has_core_power, 'And spent the core doing it.')

func test_the_buff_does_not_stack():
	# Two activations must not leave two buffs behind, or every "is it on" check still works while
	# anything counting them silently doubles.
	#
	# The lever is Buff.multiple_copies_can_stack (buff.gd:131, default false), consulted at
	# unit_condition.gd:740 - NOT the action's can_reapply, which only gates whether the protocol can
	# be clicked again. This test applies the buff directly and never touches the action, so
	# can_reapply is not what it is measuring.
	await SpecFactory.start_turn(game, nuckelavee)
	SpecFactory.apply_buff(nuckelavee, BUFF_ID, cp_gear)
	SpecFactory.apply_buff(nuckelavee, BUFF_ID, cp_gear)
	assert_eq(UnitCondition.get_buffs(nuckelavee, BUFF_ID).size(), 1, 'One set of hands, not two.')

func test_the_buff_dies_with_the_nuckelavee():
	# Buff.is_cleared_on_owner_death() defaults true (buff.gd:184) and that is the ONLY thing ending
	# this power. Pinned rather than trusted: the failure would be silent and would last the scene.
	SpecFactory.apply_buff(nuckelavee, BUFF_ID, cp_gear)
	assert_true(UnitCondition.has_buff(nuckelavee, BUFF_ID), 'Up before the frame dies.')
	await SpecFactory.damage(game, nuckelavee, 999, Lancer.DAMAGE_TYPE.KINETIC)
	assert_false(UnitCondition.has_buff(nuckelavee, BUFF_ID), 'The hands stop when the thing that woke them is gone.')

# ============================== the shared ground predicate ==============================

func test_the_map_is_the_size_this_suite_assumes():
	# Every coordinate in this file is hand-placed inside a 5x5 map. If the harness's landscape ever
	# grows or shrinks, the lanes below stop meaning what their names say - silently, and mostly by
	# passing. Fail loudly here instead.
	assert_eq(game.map.size, Vector2i(5, 5), 'The fixtures in this file are placed for a 5x5 map.')

func test_difficult_ground_sees_map_terrain():
	var tile := Vector2i(2, 0)
	assert_false(ClawingHands.is_difficult_ground(game.map, tile), 'Clean ground to begin with.')
	_make_difficult(tile)
	assert_true(ClawingHands.is_difficult_ground(game.map, tile), 'Difficult terrain on the map counts.')

func test_difficult_ground_does_not_key_off_the_victim_being_prone():
	# THE trap in this power. Pathfinder.Occupation.calculate_for (pathfinder.gd:92-96) treats a tile
	# as difficult if `terrain.is_difficult() OR the unit is PRONE OR it is underwater` - the PRONE
	# clause is a property of the CHARACTER, not the ground. Bullet 1 fires when a hostile is knocked
	# PRONE in difficult terrain, so reusing that definition would make every knockdown anywhere in the
	# world qualify. This predicate asks the GROUND only.
	var tile := Vector2i(2, 0)
	var victim:Unit = SpecFactory.create_unit(game.map, tile, Faction.AI_ENEMY)
	SpecFactory.apply(victim, Lancer.STATUS.PRONE)
	assert_true(victim.has_status(Lancer.STATUS.PRONE), 'The victim really is prone.')
	assert_false(ClawingHands.is_difficult_ground(game.map, tile),
		'Being prone does not make the ground under you difficult.')

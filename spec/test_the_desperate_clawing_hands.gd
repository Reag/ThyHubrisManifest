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

# ============================== bullet 1: knocked prone in the muck ==============================

## The lane the prone tests use: row 0 east of the Nuckelavee, all of it difficult. It has to be a
## LANE rather than a tile, because RAM knocks the victim back one space and the clause is about the
## ground it lands on as much as the ground it left.
const BAD_LANE:Array[Vector2i] = [Vector2i(1,0), Vector2i(2,0), Vector2i(3,0), Vector2i(4,0)]
const VICTIM_TILE := Vector2i(2, 0)

## An enemy standing in the fouled lane, with the power already up.
func _hostile_on_bad_ground() -> Unit:
	for tile:Vector2i in BAD_LANE: _make_difficult(tile)
	SpecFactory.apply_buff(nuckelavee, BUFF_ID, cp_gear)
	var victim:Unit = SpecFactory.create_unit(game.map, VICTIM_TILE, Faction.AI_ENEMY)
	SpecFactory.apply_passive_buffs(victim)
	return victim

## Knocks `victim` prone the way the GAME does, from `from_tile` immediately west of it.
##
## SpecFactory.apply cannot be used here: it passes dummy_event(), so the reaction events
## UnitCondition.on_status_apply queues onto that event are never executed, and a statuses_changed
## reaction never fires. It sets the status and nothing else.
##
## Vanilla RAM applies PRONE through the real pipeline. The dice are forced because RAM is an attack
## and a miss would make this a coin flip. Verified: a victim at (3,3) rammed from (2,3) ends prone
## at (4,3) - so the victim MOVES one tile east, which is why BAD_LANE covers where it lands.
## `rolls` seeds Dice.CHEAT_ROLL_QUEUE for the whole sequence - the ram's own attack roll FIRST, then
## whatever the reaction asks for. **The exact number of rolls a ram consumes is not pinned here.**
## If a save test comes out the wrong way, print the queue length before and after and adjust; a 20
## padding a queue that is already empty is harmless, so err long rather than short.
func _ram_prone(victim:Unit, from_tile:Vector2i, rolls:Array = [20, 20, 20, 20]) -> void:
	var rammer:Unit = SpecFactory.create_unit(game.map, from_tile, Faction.PLAYER)
	SpecFactory.apply_passive_buffs(rammer)
	await SpecFactory.start_turn(game, rammer)
	# Not `Dice.CHEAT_ROLL_QUEUE = rolls.duplicate()`: CHEAT_ROLL_QUEUE is Array[int] (dice.gd:9) and
	# `rolls` is a plain untyped Array, so a direct `=` throws "Invalid assignment of property or key
	# 'CHEAT_ROLL_QUEUE' with value of type 'Array'" - reproduced on every _ram_prone call. clear()
	# + append_array() is the same seeding vanilla's own specs use everywhere else.
	Dice.CHEAT_ROLL_QUEUE.clear()
	Dice.CHEAT_ROLL_QUEUE.append_array(rolls)
	await SpecFactory.use(game, rammer, &'mw_ram', &'action_ram', [victim])

func test_a_hostile_knocked_prone_in_difficult_terrain_takes_damage():
	# RAM itself deals no damage - action_ram.tres carries knockback and an on-hit PRONE and no
	# damage_dice at all - so any health lost here is the hands, not the ram.
	var victim := _hostile_on_bad_ground()
	var before:int = victim.core.current.health
	await _ram_prone(victim, Vector2i(1, 0))
	assert_true(victim.has_status(Lancer.STATUS.PRONE), 'The ram landed, or this test proves nothing.')
	assert_lt(victim.core.current.health, before, 'The hands took hold.')

func test_a_hostile_knocked_prone_on_clean_ground_takes_nothing():
	# The vacuity guard. Without it the test above cannot tell "prone in difficult terrain hurts"
	# from "being knocked prone hurts".
	SpecFactory.apply_buff(nuckelavee, BUFF_ID, cp_gear)
	var victim:Unit = SpecFactory.create_unit(game.map, VICTIM_TILE, Faction.AI_ENEMY)
	SpecFactory.apply_passive_buffs(victim)
	var before:int = victim.core.current.health
	await _ram_prone(victim, Vector2i(1, 0))
	assert_true(victim.has_status(Lancer.STATUS.PRONE), 'The ram landed here too.')
	assert_eq(victim.core.current.health, before, 'Clean ground, nothing lurking in it.')

func test_nothing_happens_without_the_power_up():
	# The whole bullet is gated on the buff; this is what proves the gate rather than the reaction.
	for tile:Vector2i in BAD_LANE: _make_difficult(tile)
	var victim:Unit = SpecFactory.create_unit(game.map, VICTIM_TILE, Faction.AI_ENEMY)
	SpecFactory.apply_passive_buffs(victim)
	var before:int = victim.core.current.health
	await _ram_prone(victim, Vector2i(1, 0))
	assert_eq(victim.core.current.health, before, 'The hands are not awake yet.')

func test_an_ally_knocked_prone_in_difficult_terrain_is_spared():
	# "Hostile characters take..." - bullet 1 is hostile-only, unlike bullet 3's widening.
	for tile:Vector2i in BAD_LANE: _make_difficult(tile)
	SpecFactory.apply_buff(nuckelavee, BUFF_ID, cp_gear)
	var friend:Unit = SpecFactory.create_unit(game.map, VICTIM_TILE, Faction.PLAYER)
	SpecFactory.apply_passive_buffs(friend)
	var before:int = friend.core.current.health
	await _ram_prone(friend, Vector2i(1, 0))
	assert_true(friend.has_status(Lancer.STATUS.PRONE), 'The ally really did go down.')
	assert_eq(friend.core.current.health, before, 'The hands know whose side they are on.')

func test_the_damage_repeats_on_a_second_knockdown_in_one_round():
	# Uncapped, by the designer's call: every knockdown pays. Consistent with a power whose theme is
	# removing limits - and knocking the same target prone twice in a round costs the player real work.
	#
	# Each ram uses a FRESH rammer: RAM is a real action and the first rammer has spent its turn. The
	# victim walks east one tile per ram, which is why BAD_LANE runs to the map edge.
	#
	# Explicit rolls, not the [20,20,20,20] default: CHEAT_ROLL_QUEUE hands back whatever it is fed
	# with no regard for the die it is standing in for (dice.gd:33-35 pops unconditionally), so a
	# queued 20 answering the reaction's 1d6 becomes 20 damage, not a capped 6 - enough to structure
	# and destroy an 8 HP Everest on the FIRST knockdown and leave nothing for a second. A small,
	# survivable damage roll (2) keeps the victim alive to be knocked down twice, which is the only
	# thing this test is checking.
	var victim := _hostile_on_bad_ground()
	await _ram_prone(victim, Vector2i(1, 0), [20, 2, 20, 20])
	var after_first:int = victim.core.current.health
	UnitCondition.clear_status(SpecFactory.dummy_event(), victim, Lancer.STATUS.PRONE)
	await _ram_prone(victim, Vector2i(2, 0), [20, 2, 20, 20])
	assert_lt(victim.core.current.health, after_first, 'The second knockdown pays too.')

func test_a_failed_hull_save_immobilizes():
	# The save gates ONLY the IMMOBILIZED - the damage is unconditional. The queue has to carry the
	# ram's own attack roll first; the trailing 1 is the save, and 1 fails against any target.
	var victim := _hostile_on_bad_ground()
	# Ram hits on the leading 20s; the trailing 1s are the HULL save, and 1 fails any target.
	await _ram_prone(victim, Vector2i(1, 0), [20, 20, 1, 1])
	assert_true(victim.has_status(Lancer.STATUS.IMMOBILIZED), 'Failed the save, held fast.')

func test_a_passed_hull_save_leaves_them_free_but_still_hurt():
	var victim := _hostile_on_bad_ground()
	var before:int = victim.core.current.health
	await _ram_prone(victim, Vector2i(1, 0), [20, 20, 20, 20])
	assert_false(victim.has_status(Lancer.STATUS.IMMOBILIZED), 'Made the save, still standing free.')
	assert_lt(victim.core.current.health, before, 'But the damage was never in question.')

# ============================== bullet 2: the cost of leaving ==============================

## A free corner - the Nuckelavee holds (0,0) and the bystander (4,4), so this one is unoccupied.
## A CORNER matters: on a 5x5 map a mover standing centrally can already reach every tile, so trimming
## its reach by one would change nothing and these tests would pass vacuously. From a corner there
## really are tiles at maximum distance for the penalty to take away.
const MOVER_CORNER := Vector2i(0, 4)

## Every tile the mover may still END on, under whatever restriction buffs are in play.
func _reachable(mover:Unit) -> int:
	var pathfinder:Pathfinder = await Pathfinder.generate_for_standard_move(
		mover, MovementType.create_for_standard_move(mover), false
	)
	return pathfinder.valid_destinations.size()

func test_a_hostile_starting_on_clean_ground_is_unrestricted():
	# The control. Without it the next test cannot tell "the penalty applied" from "this mover was
	# always restricted".
	SpecFactory.apply_buff(nuckelavee, BUFF_ID, cp_gear)
	var victim:Unit = SpecFactory.create_unit(game.map, MOVER_CORNER, Faction.AI_ENEMY)
	await SpecFactory.start_turn(game, victim)
	var free:int = await _reachable(victim)
	assert_gt(free, 0, 'A mover on clean ground can go somewhere.')

func test_a_hostile_starting_in_difficult_terrain_reaches_less():
	SpecFactory.apply_buff(nuckelavee, BUFF_ID, cp_gear)
	var victim:Unit = SpecFactory.create_unit(game.map, MOVER_CORNER, Faction.AI_ENEMY)
	await SpecFactory.start_turn(game, victim)
	var free:int = await _reachable(victim)

	_make_difficult(MOVER_CORNER)
	var taxed:int = await _reachable(victim)
	assert_lt(taxed, free, 'Leaving the muck costs it reach.')

func test_the_penalty_needs_the_power_to_be_up():
	# Vacuity guard on the whole bullet: with no buff, standing in difficult terrain must cost nothing
	# beyond what vanilla difficult terrain already charges.
	var victim:Unit = SpecFactory.create_unit(game.map, MOVER_CORNER, Faction.AI_ENEMY)
	await SpecFactory.start_turn(game, victim)
	var free:int = await _reachable(victim)
	_make_difficult(MOVER_CORNER)
	var still_free:int = await _reachable(victim)
	assert_eq(still_free, free, 'No power up, no extra toll.')

func test_an_ally_starting_in_difficult_terrain_is_not_taxed():
	# "Hostile characters must spend two movement..." - the frame's own team pays nothing here.
	SpecFactory.apply_buff(nuckelavee, BUFF_ID, cp_gear)
	var friend:Unit = SpecFactory.create_unit(game.map, MOVER_CORNER, Faction.PLAYER)
	await SpecFactory.start_turn(game, friend)
	var free:int = await _reachable(friend)
	_make_difficult(MOVER_CORNER)
	var still_free:int = await _reachable(friend)
	assert_eq(still_free, free, 'Allies walk out of the muck at the usual price.')

func test_involuntary_movement_is_not_taxed():
	# THE DECLARED BOUNDARY, and it is load-bearing rather than pedantic: the restriction loop runs for
	# EVERY movement type, while vanilla difficult terrain is skipped outright for forced, flying,
	# teleporting and INTANGIBLE movement. Binding those would be broader than the clause - and it
	# would silently nerf the Kraken drag this power is specifically designed to combo with.
	SpecFactory.apply_buff(nuckelavee, BUFF_ID, cp_gear)
	var victim:Unit = SpecFactory.create_unit(game.map, MOVER_CORNER, Faction.AI_ENEMY)
	_make_difficult(MOVER_CORNER)
	await SpecFactory.start_turn(game, victim)

	var forced := MovementType.create_for_involuntary(victim)
	var pathfinder:Pathfinder = await Pathfinder.generate_for_standard_move(victim, forced, false)
	var voluntary:Pathfinder = await Pathfinder.generate_for_standard_move(
		victim, MovementType.create_for_standard_move(victim), false
	)
	assert_gt(pathfinder.valid_destinations.size(), voluntary.valid_destinations.size(),
		'A character being thrown is not paying a toll for its own footing.')

# ============================== bullet 3: the ground turns on everyone ==============================

## Walks `mover` east across `count` tiles of difficult ground, and reports the health it lost.
## Uses involuntary movement so this reads as the drag the power is designed around - and so it also
## proves bullet 2's boundary is not quietly interfering.
func _damage_taken_crossing(mover:Unit, count:int) -> int:
	var lane_start:int = mover.state.tile.x + 1
	for i:int in count:
		_make_difficult(Vector2i(lane_start + i, mover.state.tile.y))
	var before:int = mover.core.current.health
	var destination := Vector2i(lane_start + count - 1, mover.state.tile.y)
	await SpecFactory.move(game, mover, destination, MovementType.create_for_involuntary(mover))
	# A move that silently fails reads as 0 damage, which would pass every assert_eq(..., 0) in this
	# section vacuously - so the arrival itself has to be checked, not just the health delta.
	assert_eq(mover.state.tile, destination, 'The mover has to actually arrive, or this proves nothing.')
	return before - mover.core.current.health

func test_caustic_earth_reaches_terrain_the_nuckelavee_did_not_make():
	# The widening. Without the power up, Caustic Earth only bites on the frame's own acid, so plain
	# map rubble must do nothing.
	nuckelavee.core.equip_system(&'mt_caustic_earth')
	var victim:Unit = SpecFactory.create_unit(game.map, Vector2i(0, 2), Faction.AI_ENEMY)
	assert_eq(await _damage_taken_crossing(victim, 1), 0, 'Rubble is just rubble until the hands wake.')

	var second:Unit = SpecFactory.create_unit(game.map, Vector2i(0, 3), Faction.AI_ENEMY)
	SpecFactory.apply_buff(nuckelavee, BUFF_ID, cp_gear)
	# Exact value, not just >0: a single-tile crossing deals exactly 1 (DAMAGE in action_caustic_earth.gd).
	# A widening that also uncapped allies at this point (rather than only later, where the asymmetry
	# test checks it) would still pass a bare assert_gt.
	assert_eq(await _damage_taken_crossing(second, 1), 1, 'Now every bad tile on the map is ours - one tile, one hit.')

func test_a_hostile_pays_per_tile_and_an_ally_pays_once():
	# THE ASYMMETRY, and the reason this power pairs with other frames: drag a prisoner across broken
	# ground and it takes a hit per tile, while your own team crossing the same ground takes one.
	# Testing either half alone would miss the point of the ability.
	nuckelavee.core.equip_system(&'mt_caustic_earth')
	SpecFactory.apply_buff(nuckelavee, BUFF_ID, cp_gear)

	var enemy:Unit = SpecFactory.create_unit(game.map, Vector2i(0, 2), Faction.AI_ENEMY)
	var enemy_damage:int = await _damage_taken_crossing(enemy, 3)

	var friend:Unit = SpecFactory.create_unit(game.map, Vector2i(0, 3), Faction.PLAYER)
	var friend_damage:int = await _damage_taken_crossing(friend, 3)

	assert_gt(enemy_damage, friend_damage, 'The enemy pays per tile; the ally does not.')
	assert_eq(friend_damage, 1, 'The ally still pays once - the widening is universal.')
	assert_eq(enemy_damage, 3, 'Three tiles, three hits.')

func test_clearing_the_power_restores_both_the_cap_and_the_scope():
	# Vacuity guard for the whole bullet: everything above must be the buff's doing, not something
	# permanent this task broke.
	nuckelavee.core.equip_system(&'mt_caustic_earth')
	SpecFactory.apply_buff(nuckelavee, BUFF_ID, cp_gear)
	var enemy:Unit = SpecFactory.create_unit(game.map, Vector2i(0, 2), Faction.AI_ENEMY)
	assert_eq(await _damage_taken_crossing(enemy, 3), 3, 'Uncapped while the power is up.')

	UnitCondition.clear_buff_id(SpecFactory.dummy_event(), nuckelavee, BUFF_ID)
	var second:Unit = SpecFactory.create_unit(game.map, Vector2i(0, 3), Faction.AI_ENEMY)
	assert_eq(await _damage_taken_crossing(second, 3), 0, 'And map rubble goes back to being harmless.')

func test_the_nuckelavees_own_acid_still_bites_with_the_power_up():
	# is_victim_on_caustic_ground's two branches read DIFFERENT sources of truth. The narrow branch
	# (power down) computes tiles live from get_voxels_to_apply_terrain, deliberately bypassing the map
	# (action_caustic_earth.gd:69-72 explains why). The widened branch (power up) instead reads
	# map.get_surface_terrain_at, which map_state.gd:24 documents as only "selectively updated" - and
	# this file's own _make_difficult docstring already demonstrates the two can diverge, since writing
	# gear state does not refresh the map without a manual sweep.
	#
	# Every OTHER test in this file sources its difficult ground from the bystander at BYSTANDER_TILE,
	# and test_caustic_earth.gd never applies the core-power buff at all - so nothing anywhere covered
	# the one case where waking the power could silently stop working for the frame's OWN acid: its own
	# Poisoned Soil trail, now read through the widened, map-based branch instead of the narrow one that
	# used to reach it directly. This is the case where the two sources of truth could diverge.
	nuckelavee.core.equip_system(&'mt_caustic_earth')
	var own_soil:GearCore = nuckelavee.core.equip_system(&'mt_poisoned_soil')
	var lane:Array[Vector2i] = [Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4)]
	PoisonedSoil.write_trail(own_soil, lane)
	UnitTile.update_tracking_and_statuses(game.map)
	SpecFactory.apply_buff(nuckelavee, BUFF_ID, cp_gear)

	# NOT _damage_taken_crossing - that helper builds its lane through _make_difficult, which writes to
	# the BYSTANDER's soil_gear. This test's whole point is terrain sourced from the Nuckelavee's own
	# gear instead, so the crossing is done by hand against the `lane` written above.
	var victim:Unit = SpecFactory.create_unit(game.map, Vector2i(0, 4), Faction.AI_ENEMY)
	SpecFactory.apply_passive_buffs(victim)
	var before:int = victim.core.current.health
	var destination:Vector2i = lane[lane.size() - 1]
	await SpecFactory.move(game, victim, destination, MovementType.create_for_involuntary(victim))
	assert_eq(victim.state.tile, destination, 'The mover has to actually arrive, or this proves nothing.')
	assert_lt(victim.core.current.health, before, "The frame's own acid still bites, read through the widened branch.")

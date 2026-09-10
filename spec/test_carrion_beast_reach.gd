# The Carrion Beast's reach. "When targeting characters with INFECTION, your SENSORS increase by 5."
#
# TWO HALVES, ONE SOURCE OF TRUTH. draugr_reach.gd answers "is that within my SENSORS?" for every
# question this mod asks (the Ceaseless Death's kill filter, the Spreading Stain's candidate sweep,
# Atrophy's aura), and buff_carrion_beast_reach turns the same answer into real targeting tiles via
# Buff.TO.ACTION_TILES. The engine has no per-target Sensors hook at all - Unit.get_sensor_range()
# (unit.gd:305) takes no argument - so every +5 in the game is applied by a caller, and one helper is
# the only thing keeping them in step.
#
# THE TILE HALF IS unit_targeting.gd:164-181. get_tiles_in_range's fifth step merges every
# Buff.TO.ACTION_TILES buff on the attacker: values.boolean = true ADDS the tiles in values.object
# (a bitwise array), false INTERSECTS. That is the seam, and it is the one asserted below - not the
# buff's internals.
#
# THE MAP IS 20x20 on purpose: the default spec landscape is 5x5, a unit outside it has no occupied
# tiles, and every distance to it reads Tile's 1000 sentinel - so a "reaches 8 tiles away" test would
# pass for the wrong reason (memory draugr-infection-engine-gotchas item 6). Sensors is pinned to 5,
# so the reach against an infected target is exactly 10.
extends GutTest

const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')
const DraugrReach := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/draugr_reach.gd')

const BEAST := &'ms_carrion_beast'
const TECH := &'ms_fragment_signal'   # basic loadout: an ActionAttackTech invade at sensor range
const SCAN := &'ms_scan'              # basic loadout: an ActionSystem with is_tech = true
const MELEE := &'mw_tactical_melee_weapon'

var game:Gamemaster
var draugr:Unit
var near:Unit    # 3 tiles away: inside plain Sensors
var far:Unit     # 8 tiles away: outside Sensors 5, inside Sensors + 5

func before_each():
	game = SpecFactory.setup_gamemaster(self, false, SpecFactory.create_combat(Landscape.create_default(Vector2i(20, 20))))
	draugr = SpecFactory.create_unit(game.map, Vector2i(0, 0), Faction.PLAYER)
	draugr.core.frame.stat.sensor_range = 5
	draugr.core.frame.stat.heat = 20
	draugr.core.equip_system(MELEE)
	draugr.core.full_repair()
	draugr.core.current.heat = 0
	near = _enemy_at(Vector2i(3, 0))
	far = _enemy_at(Vector2i(8, 0))

func after_each():
	Dice.CHEAT_ROLL_QUEUE.clear()

func _enemy_at(tile:Vector2i) -> Unit:
	var unit := SpecFactory.create_unit(game.map, tile, Faction.AI_ENEMY)
	unit.core.frame.stat.health = 40
	unit.core.frame.stat.heat = 20
	unit.core.full_repair()
	unit.core.current.heat = 0
	return unit

## Equip the Carrion Beast and hand out its passive buffs. apply_passive_buffs full-repairs first
## (spec_factory.gd:243-246), so heat is reset afterwards.
func _equip_beast() -> void:
	draugr.core.equip_system(BEAST)
	SpecFactory.apply_passive_buffs(draugr)
	draugr.core.current.heat = 0

func _infect(unit:Unit, n:int) -> void:
	await Infection.apply(SpecFactory.dummy_event({unit = unit}), unit, n)
	unit.core.current.heat = 0

func _tiles_for(kit_id:StringName) -> Array[Vector2i]:
	var gear:GearCore = draugr.get_gear(kit_id)
	assert_true(GearCore.is_valid(gear), 'Fixture: %s is on the loadout.' % kit_id)
	if not GearCore.is_valid(gear): return [] as Array[Vector2i]
	return UnitTargeting.get_tiles_in_range(SpecificAction.create(draugr, gear, gear.get_solo_action()))

# ---------------------------------------------------------------- the helper

func test_without_the_carrion_beast_sensors_are_just_sensors():
	await _infect(far, 2)
	assert_false(DraugrReach.has_carrion_beast(draugr), 'Fixture: not equipped.')
	assert_eq(DraugrReach.sensors_against(draugr, far), 5, 'Plain Sensors 5.')
	assert_true(DraugrReach.within_sensors(draugr, near), 'Three tiles is inside 5.')
	assert_false(DraugrReach.within_sensors(draugr, far), 'Eight is not, infected or otherwise.')

func test_an_infected_target_is_reached_at_sensors_plus_five():
	_equip_beast()
	await _infect(far, 1)
	assert_eq(DraugrReach.sensors_against(draugr, far), 10, 'Five, plus five.')
	assert_true(DraugrReach.within_sensors(draugr, far), 'Eight tiles is inside 10.')
	assert_eq(DraugrReach.max_reach(draugr), 10, 'The search radius is the widest the reach can be.')

func test_the_bonus_needs_an_infected_target():
	_equip_beast()
	assert_false(Infection.is_infected(far), 'Fixture: clean.')
	assert_eq(DraugrReach.sensors_against(draugr, far), 5, 'No INFECTION, no bonus.')
	assert_false(DraugrReach.within_sensors(draugr, far), 'Still out of reach.')

func test_the_bonus_stops_at_ten():
	_equip_beast()
	var beyond := _enemy_at(Vector2i(11, 0))
	await _infect(beyond, 3)
	assert_false(DraugrReach.within_sensors(draugr, beyond), 'Eleven tiles is outside 10.')

func test_a_destroyed_carrion_beast_grants_nothing():
	# A system that has been shot off does nothing; gear.is_intact() is the engine's own word for it.
	_equip_beast()
	await _infect(far, 2)
	draugr.get_gear(BEAST).is_destroyed = true
	assert_false(DraugrReach.has_carrion_beast(draugr), 'Destroyed.')
	assert_eq(DraugrReach.sensors_against(draugr, far), 5, 'And the bonus went with it.')

func test_infected_in_reach_lists_only_infected_characters_in_reach():
	_equip_beast()
	await _infect(far, 1)
	var beyond := _enemy_at(Vector2i(11, 0))
	await _infect(beyond, 1)
	var found := DraugrReach.infected_in_reach(draugr)
	assert_true(found.has(far), 'The infected one at 8 is in.')
	assert_false(found.has(near), 'The clean one at 3 is not.')
	assert_false(found.has(beyond), 'The infected one at 11 is out of reach.')
	assert_false(found.has(draugr), 'And the Draugr is never its own target.')

# ---------------------------------------------------------------- the tiles

func test_a_tech_attack_reaches_an_infected_character_beyond_sensors():
	# unit_targeting.gd:164-181 merges Buff.TO.ACTION_TILES grants into get_tiles_in_range.
	_equip_beast()
	await _infect(far, 1)
	assert_true(_tiles_for(TECH).has(Vector2i(8, 0)), 'The infected tile is targetable.')

func test_a_tech_attack_does_not_reach_a_clean_character_beyond_sensors():
	_equip_beast()
	assert_false(_tiles_for(TECH).has(Vector2i(8, 0)), 'No INFECTION, no extra reach.')
	assert_true(_tiles_for(TECH).has(Vector2i(3, 0)), 'And ordinary Sensors range is untouched.')

func test_a_quick_tech_system_reaches_too():
	# The second half of the Metahook filter: an ActionSystem with is_tech = true. ms_scan is one.
	_equip_beast()
	await _infect(far, 1)
	assert_true(_tiles_for(SCAN).has(Vector2i(8, 0)), 'Scan reaches the infected tile.')

func test_a_weapon_attack_gets_nothing():
	# "When TARGETING" in the rules row means tech targeting; a melee weapon is not tech and the
	# filter (context.action is ActionAttackTech, or ActionSystem with is_tech) refuses it.
	_equip_beast()
	await _infect(far, 1)
	assert_false(_tiles_for(MELEE).has(Vector2i(8, 0)), 'A melee weapon does not gain 8 tiles of reach.')

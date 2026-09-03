# Poisoned Soil - the Nuckelavee fouls the ground it boosts across.
#
#   "When you BOOST, the Nuckelavee may turn the spaces it moves through into difficult terrain.
#    This terrain lasts until you create terrain this way again."
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-03-poisoned-soil-design.md
#
# The terrain is projected by the TRAIT, not by a deployable: Loadout.get_all_gear includes traits,
# so MapState.add_dynamic_terrain_and_zones_from_unit picks up a PassiveTerrainZone sitting on the
# Nuckelavee itself. That makes "lasts until you create terrain this way again" an overwrite of one
# array rather than a lifetime to manage - and it means the trail dies with the frame, which is the
# behaviour the designer chose.
#
# These specs go through a REAL Pathfinder wherever they can. A terrain zone whose override never
# runs looks exactly like "the engine does not do that", so asserting the stored array is not
# evidence of anything; only the pathfinder charging double is.
extends GutTest

const PoisonedSoil := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_nuckelavee/mt_poisoned_soil/passive_poisoned_soil.gd')

const TRAIT_ID := &'mt_poisoned_soil'
const START := Vector2i(0, 0)
## Directly east of START, so a clean move onto it costs exactly 1 and a fouled one exactly 2.
const NEIGHBOUR := Vector2i(1, 0)

var game:Gamemaster
var nuckelavee:Unit
var trait_gear:GearCore

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	nuckelavee = SpecFactory.create_unit(game.map, START)
	trait_gear = nuckelavee.core.equip_system(TRAIT_ID)
	SpecFactory.apply_passive_buffs(nuckelavee)

## Writing gear state does NOT refresh the map - GearCore.set_state only touches the dictionary, and
## only set_aura_active calls the refresh. So every test that changes the trail has to ask for one,
## exactly as the lay reaction will have to.
func _refresh_terrain() -> void:
	UnitTile.update_tracking_and_statuses(game.map)

## What the game would actually offer this unit, boost excluded so the budget is just its speed.
func _move_options(mover:Unit) -> Pathfinder:
	return await Pathfinder.generate_for_standard_move(
		mover, MovementType.create_for_standard_move(mover), false)

## Cumulative cost of walking to `tile`. Pathfinder.Step.cost accumulates along the path, so the
## last step's cost is the total.
func _cost_to(mover:Unit, tile:Vector2i) -> int:
	var options := await _move_options(mover)
	var path:Array[Pathfinder.Step] = options.path_to(tile)
	if path.is_empty(): return -1
	return path.back().cost

# ============================== the terrain itself ==============================

func test_a_clean_neighbouring_tile_costs_one():
	# The control. Without it the next test cannot tell "difficult terrain works" from "every tile
	# costs 2 around here".
	await SpecFactory.start_turn(game, nuckelavee)
	assert_eq(await _cost_to(nuckelavee, NEIGHBOUR), 1, 'Stepping one space onto clean ground costs 1.')

func test_a_tile_on_the_trail_costs_two():
	# The whole mechanism in one assertion: a trail written onto the trait's gear reaches the
	# pathfinder as real difficult terrain.
	PoisonedSoil.write_trail(trait_gear, [NEIGHBOUR])
	_refresh_terrain()
	await SpecFactory.start_turn(game, nuckelavee)
	assert_eq(await _cost_to(nuckelavee, NEIGHBOUR), 2, 'Stepping onto the trail costs double.')

func test_the_trail_is_the_only_thing_that_made_it_difficult():
	# Vacuity guard. Clearing the trail must put the cost back - otherwise the test above could pass
	# against terrain that was already difficult for some unrelated reason.
	PoisonedSoil.write_trail(trait_gear, [NEIGHBOUR])
	_refresh_terrain()
	PoisonedSoil.write_trail(trait_gear, [])
	_refresh_terrain()
	await SpecFactory.start_turn(game, nuckelavee)
	assert_eq(await _cost_to(nuckelavee, NEIGHBOUR), 1, 'With the trail gone the ground is clean again.')

# ============================== arming on BOOST ==============================

func test_boosting_arms_the_trail_and_seeds_it_with_the_current_tile():
	# The start tile counts: the designer's call is that a 5-space boost fouls 6 tiles, because the
	# space the frame heaves itself out of is fouled too.
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	assert_true(PoisonedSoil.is_armed(trait_gear), 'The boost armed the trail.')
	assert_eq(PoisonedSoil.read_pending(trait_gear), [START], 'Seeded with the tile it boosted from.')

func test_boosting_twice_reseeds_rather_than_banking_two_trails():
	# Speed is a pool, so a player can boost twice before moving. One trail per boost: the second
	# arm clears the buffer and starts again from where the frame is standing now.
	#
	# A normal BOOST is once-per-turn (UnitAction.can_boost gates on state.has_normal_boost, and
	# action_boost.gd clears it on use) - that is a real Lancer rule, not a test-fixture gap. The
	# second boost this test needs has to come from Overcharge instead, exactly as a player would
	# get it; test_ms_boost.gd's own test_uses_overcharge_if_out_of_regular_actions sets the state
	# the same way.
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	await SpecFactory.move(game, nuckelavee, NEIGHBOUR)
	nuckelavee.state.overcharge_actions = 1
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	assert_eq(PoisonedSoil.read_pending(trait_gear), [NEIGHBOUR], 'Re-seeded from the new position.')

func test_another_units_boost_does_not_arm_our_trail():
	var other := SpecFactory.create_unit(game.map, Vector2i(4, 4))
	SpecFactory.apply_passive_buffs(other)
	await SpecFactory.start_turn(game, other)
	await SpecFactory.use_solo(game, other, &'ms_boost')
	assert_false(PoisonedSoil.is_armed(trait_gear), 'Somebody else boosting is not our trigger.')

# ============================== tracking the path ==============================

func test_moving_while_armed_records_every_tile_stepped_onto():
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	await SpecFactory.move(game, nuckelavee, Vector2i(2, 0))
	assert_eq(PoisonedSoil.read_pending(trait_gear),
		[START, Vector2i(1, 0), Vector2i(2, 0)],
		'Start tile plus both tiles it stepped onto, in order.')

func test_moving_without_boosting_records_nothing():
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.move(game, nuckelavee, Vector2i(2, 0))
	assert_eq(PoisonedSoil.read_pending(trait_gear), [], 'No boost, no trail.')

func test_a_tile_is_never_recorded_twice():
	# Boost, walk out and back over the same ground. Duplicate voxels would be merged by
	# add_dynamic_terrain_and_zones_from_unit anyway, but a buffer that grows on every re-crossing
	# is a slow leak into the save file.
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	await SpecFactory.move(game, nuckelavee, NEIGHBOUR)
	await SpecFactory.move(game, nuckelavee, START)
	assert_eq(PoisonedSoil.read_pending(trait_gear), [START, NEIGHBOUR], 'Each tile once.')

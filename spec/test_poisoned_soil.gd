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

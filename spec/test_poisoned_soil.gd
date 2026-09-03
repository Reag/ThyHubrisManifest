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
	# Task 4 note: this move is a complete ENTIRE_MOVEMENT on its own, so by the time it returns the
	# lay reaction has already fired (default responder accepts) and committed pending into trail,
	# clearing pending back to []. read_trail is therefore the only place left to observe this.
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	await SpecFactory.move(game, nuckelavee, Vector2i(2, 0))
	assert_eq(PoisonedSoil.read_trail(trait_gear),
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
	#
	# Task 4 note: two separate SpecFactory.move calls no longer work for this - the first leg alone
	# already pushes pending past size 1, so the lay reaction fires and disarms before the "back"
	# half ever happens. Driving one explicit out-and-back path keeps it within a single
	# ENTIRE_MOVEMENT, the way test_the_all_consuming_tide.gd:476 drives a specific path. read_trail
	# is what is left standing afterwards, same reasoning as the test above.
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	await game.execute_event(&'event_unit_move', {
		unit = nuckelavee,
		array = [Pathfinder.Step.create(NEIGHBOUR, 1), Pathfinder.Step.create(START, 1)],
		resource = MovementType.create(nuckelavee, true),
	})
	assert_eq(PoisonedSoil.read_trail(trait_gear), [START, NEIGHBOUR], 'Each tile once.')

# ============================== laying it down ==============================
#
# SpecFactory's ChoiceBusResponder answers prompts: chosen_yesnos = true accepts, false declines.

func test_accepting_turns_the_whole_path_into_difficult_terrain():
	SpecFactory.current_responder.chosen_yesnos = true
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	await SpecFactory.move(game, nuckelavee, Vector2i(2, 0))

	assert_eq(PoisonedSoil.read_trail(trait_gear), [START, Vector2i(1, 0), Vector2i(2, 0)],
		'The crossed tiles became the trail.')
	assert_false(PoisonedSoil.is_armed(trait_gear), 'And the trail disarmed.')

	# The rule, through the pathfinder, from a fresh mover standing next to the trail.
	var hostile := SpecFactory.create_unit(game.map, Vector2i(1, 1), Faction.AI_ENEMY)
	SpecFactory.apply_passive_buffs(hostile)
	await SpecFactory.start_turn(game, hostile)
	assert_eq(await _cost_to(hostile, Vector2i(1, 0)), 2, 'Stepping onto the laid trail costs double.')

func test_declining_leaves_the_previous_trail_standing():
	# The old trail is not cleared by a boost the player declines - only replaced by one they accept.
	PoisonedSoil.write_trail(trait_gear, [Vector2i(4, 4)])
	_refresh_terrain()

	# chosen_yesnos answers EVERY quick_yesno, including action_boost's own confirm-use prompt - so
	# it has to accept the boost and only flip to decline for the lay prompt the move raises.
	# Toggling it mid-test between two awaits is house precedent: test_the_all_consuming_tide.gd's
	# _its_own_turn helper does the same for the same reason.
	SpecFactory.current_responder.chosen_yesnos = true
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	# Guard against going vacuous again: if the boost ever stopped arming the trail, the assertions
	# below would pass for the wrong reason (nothing to decline) exactly as this test once did.
	assert_true(PoisonedSoil.is_armed(trait_gear), 'The boost armed the trail before the decline.')

	SpecFactory.current_responder.chosen_yesnos = false
	await SpecFactory.move(game, nuckelavee, NEIGHBOUR)

	assert_eq(PoisonedSoil.read_trail(trait_gear), [Vector2i(4, 4)], 'The old trail is untouched.')
	assert_false(PoisonedSoil.is_armed(trait_gear), 'And declining still disarms.')

func test_a_new_trail_replaces_the_old_one_rather_than_adding_to_it():
	# "This terrain lasts until you create terrain this way again" - the whole lifetime rule.
	PoisonedSoil.write_trail(trait_gear, [Vector2i(4, 4)])
	_refresh_terrain()

	SpecFactory.current_responder.chosen_yesnos = true
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	await SpecFactory.move(game, nuckelavee, NEIGHBOUR)

	assert_eq(PoisonedSoil.read_trail(trait_gear), [START, NEIGHBOUR], 'Only the new trail remains.')

	var hostile := SpecFactory.create_unit(game.map, Vector2i(3, 4), Faction.AI_ENEMY)
	SpecFactory.apply_passive_buffs(hostile)
	await SpecFactory.start_turn(game, hostile)
	assert_eq(await _cost_to(hostile, Vector2i(4, 4)), 1, 'The abandoned tile is clean ground again.')

func test_a_second_movement_after_the_trail_is_laid_lays_nothing_more():
	SpecFactory.current_responder.chosen_yesnos = true
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	await SpecFactory.move(game, nuckelavee, NEIGHBOUR)
	await SpecFactory.move(game, nuckelavee, Vector2i(2, 0))
	assert_eq(PoisonedSoil.read_trail(trait_gear), [START, NEIGHBOUR],
		'One trail per boost; the second move added nothing.')

func test_spaces_crossed_before_the_boost_are_not_part_of_the_trail():
	SpecFactory.current_responder.chosen_yesnos = true
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.move(game, nuckelavee, NEIGHBOUR)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	await SpecFactory.move(game, nuckelavee, Vector2i(2, 0))
	assert_eq(PoisonedSoil.read_trail(trait_gear), [NEIGHBOUR, Vector2i(2, 0)],
		'Arming happens on the boost, so the first move is not in it.')

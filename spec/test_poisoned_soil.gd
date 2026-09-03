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
## `movement_type` defaults to a standard voluntary move; pass a different one (e.g.
## MovementType.create_for_involuntary) to see the same tiles priced under different rules.
func _move_options(mover:Unit, movement_type:MovementType = null) -> Pathfinder:
	if movement_type == null: movement_type = MovementType.create_for_standard_move(mover)
	return await Pathfinder.generate_for_standard_move(mover, movement_type, false)

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
	assert_true(PoisonedSoil.is_armed(trait_gear, game.map.game_core.round_count), 'The boost armed the trail.')
	assert_eq(PoisonedSoil.read_pending(trait_gear), [START], 'Seeded with the tile it boosted from.')

func test_boosting_twice_reseeds_rather_than_banking_two_trails():
	# Speed is a pool, so a player can boost twice before moving at all - action_boost.gd only adds
	# to current.speed and never moves anything (see action_poisoned_soil_arm.gd's header). One
	# trail per boost: the second arm has to REPLACE the pending buffer, not append to it, or a
	# reseed at the same tile it already seeded leaves a duplicate entry sitting in front of the
	# eventual trail.
	#
	# A normal BOOST is once-per-turn (UnitAction.can_boost gates on state.has_normal_boost, and
	# action_boost.gd clears it on use) - that is a real Lancer rule, not a test-fixture gap. The
	# second boost this test needs has to come from Overcharge instead, exactly as a player would
	# get it; test_ms_boost.gd's own test_uses_overcharge_if_out_of_regular_actions sets the state
	# the same way.
	#
	# Crucially, nothing moves between the two boosts. The previous version of this test put a
	# SpecFactory.move here - which crossed one tile, pushed pending past size 1, and opened the lay
	# gate right there, committing and clearing pending before the second boost ever ran. Mutating
	# arm to APPEND instead of replace still passed against that version, because by the time the
	# second arm ran, pending had already been reset to empty by the first move's lay - appending to
	# an empty buffer looks identical to replacing it. Boosting twice with no move between is the
	# only way to put a second arm's REPLACE where an APPEND would visibly differ.
	SpecFactory.current_responder.chosen_yesnos = true
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	nuckelavee.state.overcharge_actions = 1
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	assert_eq(PoisonedSoil.read_pending(trait_gear), [START],
		'Re-seeded from the second boost - still just the one entry, not two.')

	await SpecFactory.move(game, nuckelavee, Vector2i(2, 0))
	assert_eq(PoisonedSoil.read_trail(trait_gear), [START, NEIGHBOUR, Vector2i(2, 0)],
		'One trail for the whole move - no leftover duplicate from the first boost.')

func test_another_units_boost_does_not_arm_our_trail():
	var other := SpecFactory.create_unit(game.map, Vector2i(4, 4))
	SpecFactory.apply_passive_buffs(other)
	await SpecFactory.start_turn(game, other)
	await SpecFactory.use_solo(game, other, &'ms_boost')
	assert_false(PoisonedSoil.is_armed(trait_gear, game.map.game_core.round_count), 'Somebody else boosting is not our trigger.')

# ============================== an arm does not survive the turn that made it ==============================

func test_an_armed_boost_does_not_carry_into_a_later_round_it_never_moved_in():
	# Real bug from the final review: set_armed(gear, true) happens only in the arm reaction, and
	# set_armed(gear, false) only in lay - and lay refuses to fire unless pending has more than the
	# seeded tile. Nothing else clears gear state at a turn or round boundary (GearCore.state.clear()
	# only runs on a repair). So a Nuckelavee that boosts and then never moves - ends its turn, gets
	# IMMOBILIZED, or has its very first step silently blocked (event_unit_move.gd breaks out of its
	# step loop with no event on both `not is_next_step_possible` at :209 and
	# `not is_next_step_affordable` at :212) - stays armed forever. On some LATER turn, the first
	# two-step move would then track those tiles and open the lay gate with no boost behind it at
	# all, contradicting both the rules text and the design doc's ordering rules.
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	assert_true(PoisonedSoil.is_armed(trait_gear, game.map.game_core.round_count),
		'Armed by the boost - sanity check before the turn ends.')
	await SpecFactory.end_turn(game, nuckelavee)

	# A round boundary, the same way test_dhiyed_observation.gd's _next_round does it: move only the
	# value the staleness check actually reads, rather than paying for the full event_round_new
	# banner/music/combat-end sweep.
	game.map.game_core.round_count += 1
	await SpecFactory.start_turn(game, nuckelavee)

	var choices_before:int = SpecFactory.current_responder.choices_made
	await SpecFactory.move(game, nuckelavee, Vector2i(2, 0))

	assert_eq(PoisonedSoil.read_trail(trait_gear), [], 'No boost this round - nothing should be laid.')
	assert_eq(SpecFactory.current_responder.choices_made, choices_before,
		'And the lay prompt should never have appeared at all.')

# ============================== tracking the path ==============================
#
# Task 4 note: there used to be a test_moving_while_armed_records_every_tile_stepped_onto here,
# asserting read_pending held every stepped-on tile in order after a boosted move. It is gone, not
# just moved: once action_poisoned_soil_lay.gd exists, ANY completed move while armed pushes
# pending's size past the seeded 1 (a single real step already does it), which opens the lay gate
# and commits+clears pending within that SAME event_unit_move - before the test's await ever
# returns. There is no size of move, boost, or number of SpecFactory calls that leaves a
# multi-tile pending observable afterwards; the state is structurally never there to inspect. The
# equivalent coverage - every tile stepped onto lands in order - is what
# test_accepting_turns_the_whole_path_into_difficult_terrain's read_trail assertion already proves
# (same boost, same move, same expected array), so keeping both was two tests for one behaviour.

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
	assert_false(PoisonedSoil.is_armed(trait_gear, game.map.game_core.round_count), 'And the trail disarmed.')

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
	assert_true(PoisonedSoil.is_armed(trait_gear, game.map.game_core.round_count), 'The boost armed the trail before the decline.')

	SpecFactory.current_responder.chosen_yesnos = false
	await SpecFactory.move(game, nuckelavee, NEIGHBOUR)

	assert_eq(PoisonedSoil.read_trail(trait_gear), [Vector2i(4, 4)], 'The old trail is untouched.')
	assert_false(PoisonedSoil.is_armed(trait_gear, game.map.game_core.round_count), 'And declining still disarms.')

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
	# The second move has to cross MORE THAN ONE tile. A single-step second move only ever leaves
	# pending at size 1 - the lay gate (read_pending(gear).size() > 1) never opens regardless of
	# whether the reaction actually disarmed, so a single-step second move can't tell "disarmed" from
	# "never re-armed". Two steps is what makes this test able to fail if action_poisoned_soil_lay.gd's
	# set_armed(gear, false) were ever deleted - verified by mutation, see task-4-report.md.
	SpecFactory.current_responder.chosen_yesnos = true
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	await SpecFactory.move(game, nuckelavee, NEIGHBOUR)
	await SpecFactory.move(game, nuckelavee, Vector2i(3, 0))
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

# ============================== isolation from other units ==============================

func test_another_units_steps_do_not_pollute_our_pending_buffer():
	# Coverage gap from the Task 3 review: action_poisoned_soil_track.triggers_on_event fires for
	# EVERY step by EVERY unit on the map, and filters down to `triggering_event.context.unit == unit`
	# (the reaction's own owner). Arm first so there is something the buffer could wrongly grow from,
	# then move a completely different unit several tiles and confirm our pending is untouched.
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	assert_eq(PoisonedSoil.read_pending(trait_gear), [START], 'Armed and seeded, so a change would be visible.')

	var other := SpecFactory.create_unit(game.map, Vector2i(4, 4))
	SpecFactory.apply_passive_buffs(other)
	await SpecFactory.start_turn(game, other)
	await SpecFactory.move(game, other, Vector2i(3, 4))
	await SpecFactory.move(game, other, Vector2i(2, 4))

	assert_eq(PoisonedSoil.read_pending(trait_gear), [START],
		"Someone else's steps never reached our pending buffer.")

# ============================== involuntary movement never fouls ground ==============================
#
# Author's ruling from the final review: only the mech's OWN movement fouls ground. Neither track nor
# lay used to check voluntariness at all, so a Nuckelavee knocked back or pulled after boosting would
# foul the ground it got thrown across, and prompt the player mid-enemy-turn to boot.

func test_forced_movement_while_armed_lays_no_trail_and_never_prompts():
	SpecFactory.current_responder.chosen_yesnos = true
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	assert_true(PoisonedSoil.is_armed(trait_gear, game.map.game_core.round_count), 'Armed by the boost.')

	var choices_before:int = SpecFactory.current_responder.choices_made
	await game.execute_event(&'event_unit_move', {
		unit = nuckelavee,
		array = [Pathfinder.Step.create(NEIGHBOUR, 1), Pathfinder.Step.create(Vector2i(2, 0), 1)],
		resource = MovementType.create_for_involuntary(nuckelavee),
	})

	assert_eq(PoisonedSoil.read_pending(trait_gear), [START], 'Forced movement tracked nothing new.')
	assert_eq(PoisonedSoil.read_trail(trait_gear), [], 'And laid nothing.')
	assert_eq(SpecFactory.current_responder.choices_made, choices_before,
		'The lay prompt must not appear for movement the Nuckelavee did not choose.')

func test_ordinary_voluntary_movement_still_lays_a_trail():
	# The paired case, so the fix above cannot pass by disabling the trait outright: the exact same
	# armed state and the exact same path, but driven through an explicit voluntary MovementType
	# instead of create_for_involuntary, still has to foul the ground.
	SpecFactory.current_responder.chosen_yesnos = true
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	await game.execute_event(&'event_unit_move', {
		unit = nuckelavee,
		array = [Pathfinder.Step.create(NEIGHBOUR, 1), Pathfinder.Step.create(Vector2i(2, 0), 1)],
		resource = MovementType.create(nuckelavee, true),
	})

	assert_eq(PoisonedSoil.read_trail(trait_gear), [START, NEIGHBOUR, Vector2i(2, 0)],
		'Voluntary movement still tracks and lays the whole path.')

# ============================== deliberate, and it looks like a bug ==============================

func test_the_nuckelavee_pays_double_to_cross_its_own_trail():
	# Nothing in the trait text exempts its owner, so the terrain is real terrain for everyone.
	# This is NOT a gap - see the Bulwark Mods test below, which is the license's answer to it.
	PoisonedSoil.write_trail(trait_gear, [NEIGHBOUR])
	_refresh_terrain()
	await SpecFactory.start_turn(game, nuckelavee)
	assert_eq(await _cost_to(nuckelavee, NEIGHBOUR), 2, 'Its own filth slows it too.')

func test_bulwark_mods_carries_the_nuckelavee_over_its_own_trail_free():
	# The designed pair. ms_bulwark_mods is RANK 1 of the license the Nuckelavee clones - a 1 SP
	# always-on BuffMovementType with ignore_difficult = true - and
	# MovementType.ignores_difficult_terrain() consumes exactly that flag. The first thing the
	# license unlocks is the tool for the frame's own terrain, the same shape as the Kraken's
	# IMMOBILIZED gate. Asserted so nobody "fixes" the test above by exempting the owner.
	#
	# Both halves are proven against the SAME written trail, in this one test, on purpose: run it
	# alone with --gut-test= and it still has to demonstrate the terrain is real before the Bulwark
	# Mods half means anything. Without this, a completely dead terrain zone - get_voxels_to_apply_
	# terrain broken, _refresh_terrain a no-op, the passive unwired - would let the tile cost 1 for
	# everyone and this test would pass for the wrong reason.
	PoisonedSoil.write_trail(trait_gear, [NEIGHBOUR])
	_refresh_terrain()

	# Without the system: a bare mover crossing the identical trail still pays double.
	var bare := SpecFactory.create_unit(game.map, Vector2i(1, 1), Faction.AI_ENEMY)
	SpecFactory.apply_passive_buffs(bare)
	await SpecFactory.start_turn(game, bare)
	assert_eq(await _cost_to(bare, NEIGHBOUR), 2, 'The trail is real terrain for a mover without Bulwark Mods.')

	# With the system: the Nuckelavee crosses the same tile free.
	nuckelavee.core.equip_system(&'ms_bulwark_mods')
	SpecFactory.apply_passive_buffs(nuckelavee)
	await SpecFactory.start_turn(game, nuckelavee)
	assert_eq(await _cost_to(nuckelavee, NEIGHBOUR), 1, 'Bulwark Mods walks over it.')

func test_forced_movement_crosses_the_trail_free_but_voluntary_movement_still_pays_double():
	# Deviates from the brief, which only asserted involuntary.ignores_difficult_terrain() - a
	# vanilla MovementType predicate that never touches our trail, so that version would pass even
	# with the trait deleted. This version goes through a real Pathfinder built the same way _cost_to
	# does, but with MovementType.create_for_involuntary(mover) instead of create_for_standard_move,
	# so it can only pass if our terrain zone is actually feeding the pathfinder: the fouled tile has
	# to come back at the SAME cost as clean ground for involuntary movement, while the standard
	# (voluntary) pathfinder over the identical tile still pays double.
	#
	# ignores_difficult_terrain() is `ignore_difficult or teleport or flying or not voluntary`, and
	# create_for_involuntary leaves `voluntary` at its default false - so anything knocked or dragged
	# across the trail crosses free. Vanilla behaviour, not ours.
	PoisonedSoil.write_trail(trait_gear, [NEIGHBOUR])
	_refresh_terrain()
	await SpecFactory.start_turn(game, nuckelavee)

	var involuntary := await _move_options(nuckelavee, MovementType.create_for_involuntary(nuckelavee))
	var involuntary_path:Array[Pathfinder.Step] = involuntary.path_to(NEIGHBOUR)
	assert_false(involuntary_path.is_empty(), 'The trail tile is reachable at all - vacuity guard.')
	if not involuntary_path.is_empty():
		assert_eq(involuntary_path.back().cost, 1, 'Forced movement crosses the trail at clean-ground cost.')

	assert_eq(await _cost_to(nuckelavee, NEIGHBOUR), 2, 'The same tile still costs double for voluntary movement.')

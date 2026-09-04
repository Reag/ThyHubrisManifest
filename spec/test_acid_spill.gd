# Acid Spill - the free half of Truth in Filth, the Nuckelavee's core power.
#
#   "This weapon may only be used as a |free action| after you |BOOST|, and deals damage equal to
#    half the distance moved. If you |BOOST| your full speed in a straight line, the attack area
#    becomes difficult terrain which lasts until you create terrain this way again"
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-04-acid-spill-design.md
#
# Acid Spill keeps its OWN trail, separate from Poisoned Soil's. Several tests below exist only to
# pin that separation, because sharing storage was a live design option and the two traits fire on
# the same event.
extends GutTest

const AcidSpill := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_nuckelavee/cp_truth_in_filth/passive_acid_spill.gd')

const CP_ID := &'cp_truth_in_filth'
const START := Vector2i(0, 0)
## Directly east of START, so a clean move onto it costs exactly 1 and a fouled one exactly 2.
const NEIGHBOUR := Vector2i(1, 0)

var game:Gamemaster
var nuckelavee:Unit
var cp_gear:GearCore

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	nuckelavee = SpecFactory.create_unit(game.map, START)
	cp_gear = nuckelavee.core.equip_system(CP_ID)
	SpecFactory.apply_passive_buffs(nuckelavee)

## Writing gear state does NOT refresh the map - GearCore.set_state only touches the dictionary.
func _refresh_terrain() -> void:
	UnitTile.update_tracking_and_statuses(game.map)

func _move_options(mover:Unit) -> Pathfinder:
	return await Pathfinder.generate_for_standard_move(mover, MovementType.create_for_standard_move(mover), false)

func _cost_to(mover:Unit, tile:Vector2i) -> int:
	var options := await _move_options(mover)
	var path:Array[Pathfinder.Step] = options.path_to(tile)
	if path.is_empty(): return -1
	return path.back().cost

# ============================== the terrain patch ==============================

func test_a_clean_neighbouring_tile_costs_one():
	# The control. Without it the next test cannot tell "difficult terrain works" from "every tile
	# around here costs 2".
	await SpecFactory.start_turn(game, nuckelavee)
	assert_eq(await _cost_to(nuckelavee, NEIGHBOUR), 1, 'Stepping one space onto clean ground costs 1.')

func test_a_tile_in_the_spill_costs_two():
	# The whole mechanism in one assertion: a trail written onto the core power's gear reaches the
	# pathfinder as real difficult terrain.
	AcidSpill.write_trail(cp_gear, [NEIGHBOUR] as Array[Vector2i])
	_refresh_terrain()
	await SpecFactory.start_turn(game, nuckelavee)
	assert_eq(await _cost_to(nuckelavee, NEIGHBOUR), 2, 'Stepping into the spill costs double.')

func test_clearing_the_spill_puts_the_cost_back():
	# Vacuity guard: proves the spill is what made it difficult, not something pre-existing.
	AcidSpill.write_trail(cp_gear, [NEIGHBOUR] as Array[Vector2i])
	_refresh_terrain()
	AcidSpill.write_trail(cp_gear, [] as Array[Vector2i])
	_refresh_terrain()
	await SpecFactory.start_turn(game, nuckelavee)
	assert_eq(await _cost_to(nuckelavee, NEIGHBOUR), 1, 'Clearing the spill makes the ground clean again.')

func test_a_new_spill_replaces_the_old_one():
	# "lasts until you create terrain this way again" - replacing the array IS the expiry.
	AcidSpill.write_trail(cp_gear, [NEIGHBOUR] as Array[Vector2i])
	AcidSpill.write_trail(cp_gear, [Vector2i(2, 2)] as Array[Vector2i])
	assert_eq(AcidSpill.read_trail(cp_gear), [Vector2i(2, 2)], 'The second spill replaced the first, it did not add to it.')

# ============================== the state contract ==============================

func test_pending_preserves_duplicates():
	# THE difference from Poisoned Soil, which de-dupes because it is building a set of tiles for
	# terrain. Acid Spill needs a COUNT of steps, so a path that crosses itself must count twice.
	AcidSpill.write_pending(cp_gear, [NEIGHBOUR, START, NEIGHBOUR] as Array[Vector2i])
	assert_eq(AcidSpill.read_pending(cp_gear).size(), 3, 'Revisiting a tile is two steps, not one.')

func test_damage_is_half_the_steps_rounded_down():
	AcidSpill.write_pending(cp_gear, [] as Array[Vector2i])
	assert_eq(AcidSpill.damage_for(cp_gear), 0, 'No movement, no damage.')
	AcidSpill.write_pending(cp_gear, [Vector2i(1,0)] as Array[Vector2i])
	assert_eq(AcidSpill.damage_for(cp_gear), 0, 'One tile halves to zero.')
	AcidSpill.write_pending(cp_gear, [Vector2i(1,0), Vector2i(2,0)] as Array[Vector2i])
	assert_eq(AcidSpill.damage_for(cp_gear), 1, 'Two tiles is 1 damage.')
	AcidSpill.write_pending(cp_gear, [Vector2i(1,0), Vector2i(2,0), Vector2i(3,0), Vector2i(4,0), Vector2i(5,0)] as Array[Vector2i])
	assert_eq(AcidSpill.damage_for(cp_gear), 2, 'Five tiles rounds DOWN to 2, not up to 3.')

func test_the_origin_tile_is_not_in_the_pending_buffer():
	# AoeCalculator.line returns rings 1..length and excludes its own origin, so the buffer must too
	# or is_straight_full_speed can never match. Poisoned Soil seeds WITH the start tile; we must not.
	AcidSpill.write_origin(cp_gear, START)
	AcidSpill.write_pending(cp_gear, [Vector2i(1,0), Vector2i(2,0)] as Array[Vector2i])
	assert_false(AcidSpill.read_pending(cp_gear).has(START), 'The origin is stored separately, not in the path.')

func test_a_straight_run_of_full_boost_speed_qualifies():
	AcidSpill.write_origin(cp_gear, START)
	AcidSpill.write_boost_speed(cp_gear, 3)
	AcidSpill.write_pending(cp_gear, [Vector2i(1,0), Vector2i(2,0), Vector2i(3,0)] as Array[Vector2i])
	assert_true(AcidSpill.is_straight_full_speed(cp_gear, game.map.shape), 'Three straight tiles at boost speed 3 qualifies.')

func test_a_bent_path_does_not_qualify():
	AcidSpill.write_origin(cp_gear, START)
	AcidSpill.write_boost_speed(cp_gear, 3)
	AcidSpill.write_pending(cp_gear, [Vector2i(1,0), Vector2i(2,0), Vector2i(2,1)] as Array[Vector2i])
	assert_false(AcidSpill.is_straight_full_speed(cp_gear, game.map.shape), 'Turning a corner is not a straight line.')

func test_a_short_run_does_not_qualify():
	AcidSpill.write_origin(cp_gear, START)
	AcidSpill.write_boost_speed(cp_gear, 3)
	AcidSpill.write_pending(cp_gear, [Vector2i(1,0), Vector2i(2,0)] as Array[Vector2i])
	assert_false(AcidSpill.is_straight_full_speed(cp_gear, game.map.shape), 'Stopping short of boost speed is not a full-speed charge.')

func test_a_diagonal_charge_qualifies():
	# Ramjet's own math (AoeCalculator.line) is angle-based, not cardinal-only. A diagonal charge is
	# as straight as an orthogonal one, and the intended pairing must not disagree with the frame.
	AcidSpill.write_origin(cp_gear, START)
	AcidSpill.write_boost_speed(cp_gear, 3)
	AcidSpill.write_pending(cp_gear, [Vector2i(1,1), Vector2i(2,2), Vector2i(3,3)] as Array[Vector2i])
	assert_true(AcidSpill.is_straight_full_speed(cp_gear, game.map.shape), 'A diagonal run is a straight line.')

# ============================== arming and tracking ==============================

func test_boosting_arms_the_spill_and_records_the_origin():
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	assert_true(AcidSpill.is_armed(cp_gear, game.map.game_core.round_count), 'The boost armed the spill.')
	assert_eq(AcidSpill.read_origin(cp_gear), START, 'Recorded the tile it boosted out of.')
	assert_eq(AcidSpill.read_pending(cp_gear), [], 'Nothing stepped yet - the origin is NOT in the path.')

func test_boosting_records_the_boost_speed():
	# Recorded at arm time so Ramjet's +2 is honoured and cannot expire out from under the charge.
	await SpecFactory.start_turn(game, nuckelavee)
	var expected:int = UnitAction.get_boost_speed(nuckelavee)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	assert_eq(AcidSpill.read_boost_speed(cp_gear), expected, 'Stored the boost speed the engine would grant.')

func test_moving_after_a_boost_records_every_step():
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	await SpecFactory.move(game, nuckelavee, Vector2i(3, 0))
	assert_eq(AcidSpill.read_pending(cp_gear), [Vector2i(1,0), Vector2i(2,0), Vector2i(3,0)],
		'Three steps east, in order, origin excluded.')

func test_a_boosted_move_is_a_single_event_and_every_tile_is_post_boost():
	# The test above drives a boost and a move as two SEPARATE SpecFactory calls, which is NOT how the
	# game actually boosts: target_action_util.gd:446-458 never runs action_boost first - it appends
	# FLAG.USE_BOOST onto the flags of ONE move event covering the whole path. event_unit_move.gd:80-84
	# then executes event_unit_boost BEFORE the step loop, whose STEP reactions fire later at :196/:281.
	# So every tile of a USE_BOOST move is necessarily post-boost; no base-speed tile can leak in. This
	# pins that with the real flag, closing the open design question from the acid spill design doc.
	#
	# The spec fixture's default speed already reaches every tile of the small test map (5x5, so at
	# most 4 tiles from a corner), which would make ANY move boost-free and the flag inert - so shrink
	# speed first. Everything that follows is still derived at runtime, not hardcoded, so a change to
	# the fixture's frame or map size cannot silently turn this back into a vacuous test.
	var max_reach:int = game.map.size.x - 1 - START.x # farthest tile east of START that is still on the map
	nuckelavee.core.frame.stat.speed = maxi(1, max_reach / 2)

	await SpecFactory.start_turn(game, nuckelavee)
	var base_speed:int = nuckelavee.core.current.speed
	var boost_speed:int = UnitAction.get_boost_speed(nuckelavee)
	assert_gt(boost_speed, 0, 'Need an actual boost available, or this proves nothing.')

	var distance:int = base_speed + 1
	assert_lte(distance, base_speed + boost_speed, 'Chosen distance must be reachable with the boost applied.')
	assert_lte(distance, max_reach, 'Chosen distance must stay on the map.')
	assert_gt(distance, base_speed, 'Vacuity guard: if this move did not exceed base speed, USE_BOOST would be inert and the test would prove nothing.')

	var target := START + Vector2i(distance, 0)
	await SpecFactory.move(game, nuckelavee, target, null, [EventUnitMove.FLAG.USE_BOOST])

	# Built from the same runtime-derived `distance` above, not hardcoded - one tile per step east of
	# START, in order. Asserting only .size() would let a bug that records the right COUNT of wrong
	# tiles pass; this pins the actual sequence.
	var expected_path:Array[Vector2i] = []
	for step in range(1, distance + 1):
		expected_path.append(START + Vector2i(step, 0))
	assert_eq(AcidSpill.read_pending(cp_gear), expected_path,
		'Every tile of the boosted move was recorded, in order - none dropped as "before the boost".')
	assert_eq(AcidSpill.read_origin(cp_gear), START, 'Recorded the tile the move actually began from.')

func test_a_second_boost_reseeds_rather_than_banking_two_charges():
	# Speed is a pool, so a player can boost twice before moving - action_boost.gd only adds to
	# current.speed. One charge per boost: the second arm must RESET the buffer.
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	nuckelavee.state.has_normal_boost = true # a second boost would really come from Overcharge
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	assert_eq(AcidSpill.read_pending(cp_gear), [], 'Re-seeded empty by the second boost.')

func test_another_units_boost_does_not_arm_ours():
	var other:Unit = SpecFactory.create_unit(game.map, Vector2i(4, 4))
	await SpecFactory.start_turn(game, other)
	await SpecFactory.use_solo(game, other, &'ms_boost')
	assert_false(AcidSpill.is_armed(cp_gear, game.map.game_core.round_count), 'Somebody else boosting is not our trigger.')

func test_moving_without_a_boost_records_nothing():
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.move(game, nuckelavee, Vector2i(2, 0))
	assert_eq(AcidSpill.read_pending(cp_gear), [], 'An ordinary move is not a charge.')

func test_ending_the_turn_disarms():
	# The round stamp alone is one level too coarse: a Goblin's cp_instinct_rig can grant a second
	# LINKED turn inside the same round, and a stale arm would then fire with no boost behind it.
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	await SpecFactory.end_turn(game, nuckelavee)
	assert_false(AcidSpill.is_armed(cp_gear, game.map.game_core.round_count), 'The arm did not outlive the turn.')

# ============================== the weapon ==============================

func _spill_action() -> SpecificAction:
	return SpecificAction.create(nuckelavee, cp_gear, cp_gear.kit.get_action(&'action_acid_spill'))

func test_the_weapon_is_unavailable_with_no_boost():
	# DISABLED, not merely unoffered. is_available_to_activate is the single chokepoint behind
	# UnitAction.is_gear_available, which is what the action bar, the AI, the followup-attack path
	# and UnitRelation.is_weapon_available_as_a_rxn all consult. A free-action weapon that advertises
	# itself as available is exactly what an unexamined third-party reaction would pick up.
	await SpecFactory.start_turn(game, nuckelavee)
	assert_false(UnitAction.is_gear_available(_spill_action()), 'No boost, no weapon.')

func test_the_weapon_is_unavailable_after_a_one_tile_charge():
	# floor(1/2) == 0. A weapon that cannot deal damage must not be available to anything.
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	AcidSpill.write_pending(cp_gear, [Vector2i(1,0)] as Array[Vector2i])
	assert_false(UnitAction.is_gear_available(_spill_action()), 'Zero damage means unavailable.')

func test_the_weapon_is_available_after_a_two_tile_charge():
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	AcidSpill.write_pending(cp_gear, [Vector2i(1,0), Vector2i(2,0)] as Array[Vector2i])
	assert_true(UnitAction.is_gear_available(_spill_action()), 'Armed with two tiles behind it, the weapon is live.')

func test_the_weapon_is_unavailable_once_disarmed():
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	AcidSpill.write_pending(cp_gear, [Vector2i(1,0), Vector2i(2,0)] as Array[Vector2i])
	AcidSpill.set_armed(cp_gear, false)
	assert_false(UnitAction.is_gear_available(_spill_action()), 'Disarming closes the window.')

func test_damage_dice_track_the_distance_charged():
	AcidSpill.write_pending(cp_gear, [Vector2i(1,0), Vector2i(2,0), Vector2i(3,0), Vector2i(4,0)] as Array[Vector2i])
	var weapon:ActionAttackWeapon = cp_gear.kit.get_action(&'action_acid_spill')
	assert_eq(weapon.get_damage_dice(cp_gear), '2', 'Four tiles charged is 2 damage.')

func test_the_weapon_is_a_main_melee():
	var weapon:ActionAttackWeapon = cp_gear.kit.get_action(&'action_acid_spill')
	assert_eq(weapon.weapon_size, Lancer.WEAPON_SIZE.MAIN, 'MAIN size.')
	assert_eq(weapon.weapon_type, Lancer.WEAPON_TYPE.MELEE, 'MELEE type.')
	# MELEE is load-bearing: is_difficulty_when_engaged() is `weapon_type != MELEE`, and a BURST 1
	# centred on the frame is always engaged with everything it hits.
	assert_false(weapon.is_difficulty_when_engaged(), 'A self-centred burst must not be permanently at difficulty.')

func test_the_weapon_is_a_self_centred_burst_1():
	var weapon:ActionAttackWeapon = cp_gear.kit.get_action(&'action_acid_spill')
	assert_eq(weapon.range_pattern.pattern, Lancer.AOE_TYPE.BURST, 'BURST pattern.')
	assert_eq(weapon.range_pattern.value, 1, 'Burst 1.')
	assert_eq(weapon.damage_type, Lancer.DAMAGE_TYPE.ENERGY, 'ENERGY damage.')

func test_the_core_power_counts_as_an_integrated_weapon():
	# get_integrated_weapons collects attacks + systems + traits and keeps anything with a weapon
	# action. cp_truth_in_filth is is_trait, so the INTEGRATED tag needs no wiring - but it only
	# appears once the kit actually carries an ActionAttackWeapon.
	var integrated:Array[GearCore] = nuckelavee.core.loadout.get_integrated_weapons()
	assert_true(integrated.has(cp_gear), 'Truth in Filth is an integrated weapon.')

# ============================== firing ==============================

func _fire_action() -> ActionReaction:
	return cp_gear.kit.get_action(&'action_acid_spill_fire')

func test_the_fire_reaction_runs_after_poisoned_soils_lay():
	# Both fire on entire_movement. The designer's order is Poisoned Soil first, then Acid Spill -
	# you trail acid as you charge, then it sloshes off you when you stop. get_priority is the only
	# thing that expresses that; lower is sooner, and Poisoned Soil's lay leaves it at the default 0.
	var soil_gear:GearCore = nuckelavee.core.equip_system(&'mt_poisoned_soil')
	var lay:ActionReaction = soil_gear.kit.get_action(&'action_poisoned_soil_lay')
	assert_gt(_fire_action().get_priority(), lay.get_priority(), 'Acid Spill resolves after the trail is offered.')

func test_a_straight_full_speed_charge_lays_the_burst_as_terrain():
	# "the attack area becomes difficult terrain" - no "may", so this is automatic once the spill
	# fires. The area is the weapon's own range_pattern, so the terrain footprint is definitionally
	# the attack area rather than a second, drifting definition of it.
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	var speed:int = AcidSpill.read_boost_speed(cp_gear)
	await SpecFactory.move(game, nuckelavee, Vector2i(speed, 0))
	assert_false(AcidSpill.read_trail(cp_gear).is_empty(), 'A full-speed straight charge fouled the ground it stopped on.')
	assert_true(AcidSpill.read_trail(cp_gear).has(nuckelavee.tile()), 'The burst is centred on the frame.')

func test_a_short_charge_fires_but_lays_no_terrain():
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	await SpecFactory.move(game, nuckelavee, Vector2i(2, 0))
	assert_true(AcidSpill.read_trail(cp_gear).is_empty(), 'Stopping short attacks, but leaves nothing behind.')

func test_firing_disarms():
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	await SpecFactory.move(game, nuckelavee, Vector2i(3, 0))
	assert_false(AcidSpill.is_armed(cp_gear, game.map.game_core.round_count), 'One boost, one spill.')

func test_the_spill_and_the_trail_each_write_their_own_correct_patch():
	# The real concurrent case, not a stand-in for it: a boost arms BOTH traits off the same event
	# (equip_system(mt_poisoned_soil) arms its own trail the same way ours arms), and both fire on the
	# same entire_movement. Sharing one patch of storage - a live design option the design doc
	# considered - would fail one of the two assertions below: Poisoned Soil's lay is the PATH the
	# frame moved through, with the tile it stops on erased (action_poisoned_soil_lay.gd); Acid
	# Spill's burst is CENTRED on that same stop tile. If the two shared a key, Acid Spill firing
	# after Poisoned Soil (see test_the_fire_reaction_runs_after_poisoned_soils_lay) would stomp the
	# path with the burst, and the "stop tile excluded" assertion below would fail.
	var soil_gear:GearCore = nuckelavee.core.equip_system(&'mt_poisoned_soil')
	var PoisonedSoil := load('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_nuckelavee/mt_poisoned_soil/passive_poisoned_soil.gd')

	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	var speed:int = AcidSpill.read_boost_speed(cp_gear)
	await SpecFactory.move(game, nuckelavee, Vector2i(speed, 0))
	var stop_tile:Vector2i = START + Vector2i(speed, 0)

	# Derived from the same runtime `speed`, not hardcoded: Poisoned Soil seeds WITH the start tile
	# (action_poisoned_soil_arm.gd) and erases only the stop tile, so its trail is every tile from
	# START up to but excluding the stop tile.
	var expected_soil_path:Array[Vector2i] = []
	for step in range(speed):
		expected_soil_path.append(START + Vector2i(step, 0))

	var weapon:ActionAttackWeapon = cp_gear.kit.get_action(&'action_acid_spill')
	var expected_burst:Array[Vector2i] = weapon.range_pattern.get_tiles(game.map.shape, nuckelavee.get_size(), nuckelavee.occupied_tiles())

	assert_eq(PoisonedSoil.read_trail(soil_gear), expected_soil_path, "Poisoned Soil wrote its own path, unaffected by Acid Spill firing on the same move.")
	assert_eq(AcidSpill.read_trail(cp_gear), expected_burst, "Acid Spill wrote its own burst, centred on the tile the frame stopped on.")
	assert_false(PoisonedSoil.read_trail(soil_gear).has(stop_tile), 'The path excludes the stop tile - only the burst covers it.')
	assert_ne(PoisonedSoil.read_trail(soil_gear), AcidSpill.read_trail(cp_gear), 'The two patches are not the same set of tiles.')

func test_an_involuntary_move_after_a_boost_does_not_fire_it():
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	await SpecFactory.move(game, nuckelavee, Vector2i(3, 0), MovementType.create_for_involuntary(nuckelavee))
	assert_true(AcidSpill.read_trail(cp_gear).is_empty(), 'Being thrown across the map is not a charge.')

func test_two_boosts_in_one_round_both_offer_the_spill():
	# Uncapped, by the designer's call. ActionReaction.get_per_round_hard_limit already returns 99
	# for a reaction that does not consume the reaction economy, so this is the default - the test
	# exists to stop someone "tidying up" by adding a 1/round limit later.
	assert_gt(_fire_action().get_per_round_hard_limit(_spill_action()), 1, 'Acid Spill is not once per round.')

func test_firing_the_spill_costs_one_heat():
	# self_heat_dice = "1" on action_acid_spill.tres is a designer-specified cost - nothing else in
	# this file drives the weapon far enough to actually fire it, so nothing else would have caught
	# the .tres losing that value.
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	var speed:int = AcidSpill.read_boost_speed(cp_gear)
	nuckelavee.core.current.heat = 0
	await SpecFactory.move(game, nuckelavee, Vector2i(speed, 0))
	assert_eq(nuckelavee.core.current.heat, 1, 'Firing the weapon burned its one self-heat.')

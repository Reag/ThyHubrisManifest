# Caustic Earth - the Nuckelavee's ground bites whoever stands in it.
#
#   "Characters who start their turn in or enter a space of |difficult terrain| created by the
#    Nuckelavee take |1 AP ENERGY|. Characters can take this damage 1/round. Characters who ignore
#    |difficult terrain| ignore this damage"
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-04-caustic-earth-design.md
#
# TerrainData.DANGEROUS_TERRAIN.ENERGY is NOT this trait - it fires at turn END for 5 on a failed
# engineering check and limits per TURN. The chassis is ActionReactionOnComingWithin, which owns
# both triggers and a per-character 1/round limiter built on buff_track_affection.
#
# Every case here asserts on real HP loss. A silently-dead reaction looks exactly like "the engine
# does not do that", so asserting on the affection buff or on the tile query alone would be evidence
# of nothing. Every damage assertion is paired with the same manoeuvre over clean ground.
extends GutTest

const PoisonedSoil := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_nuckelavee/mt_poisoned_soil/passive_poisoned_soil.gd')

const SOIL_ID := &'mt_poisoned_soil'
const CAUSTIC_ID := &'mt_caustic_earth'

const NUCK_TILE := Vector2i(0, 0)
const VICTIM_TILE := Vector2i(4, 0)
## The fouled tile. Directly west of where the victim starts, so one step reaches it.
##
## SpecFactory.setup_gamemaster's default combat is a 5x5 map (Tile.MIN_MAP_DIMENSION), so every
## tile below is kept inside x,y in [0,4] - the brief's original (5,0)/(5,1) sat one column off the
## east edge, which silently produced a zero-step pathfinder (no move, no reaction, tile unchanged)
## rather than an error. Confirmed via victim.tile() logging before landing on this fix.
const ACID := Vector2i(3, 0)
## Same distance from the victim, never fouled - the control tile for every vacuity guard.
const CLEAN := Vector2i(4, 1)

var game:Gamemaster
var nuckelavee:Unit
var soil_gear:GearCore
var victim:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	nuckelavee = SpecFactory.create_unit(game.map, NUCK_TILE)
	soil_gear = nuckelavee.core.equip_system(SOIL_ID)
	nuckelavee.core.equip_system(CAUSTIC_ID)
	SpecFactory.apply_passive_buffs(nuckelavee)

	victim = SpecFactory.create_unit(game.map, VICTIM_TILE, Faction.AI_ENEMY)
	SpecFactory.apply_passive_buffs(victim)

## Foul `tiles` as Poisoned Soil would. Caustic Earth reads the passive directly rather than the
## map, so no terrain refresh is needed here - unlike test_poisoned_soil.gd, which goes through the
## pathfinder and does need one.
func _foul(tiles:Array[Vector2i]) -> void:
	PoisonedSoil.write_trail(soil_gear, tiles)

func _health(unit:Unit) -> int:
	return unit.core.current.health

# ============================== entering the terrain ==============================

func test_stepping_into_the_acid_costs_one_hp():
	_foul([ACID])
	await SpecFactory.start_turn(game, victim)
	var before:int = _health(victim)
	await SpecFactory.move(game, victim, ACID)
	assert_eq(_health(victim), before - 1, 'One step into the acid, one HP.')

func test_stepping_onto_clean_ground_costs_nothing():
	# Vacuity guard for the test above. Without it, a trait that damaged EVERY mover would pass.
	_foul([ACID])
	await SpecFactory.start_turn(game, victim)
	var before:int = _health(victim)
	await SpecFactory.move(game, victim, CLEAN)
	assert_eq(_health(victim), before, 'The same move onto unfouled ground is free.')

func test_the_damage_is_armour_piercing():
	# 1 AP ENERGY. Without the AP flag, 1 point of armour absorbs the whole thing and the trait
	# silently does nothing to any armoured target.
	_foul([ACID])
	victim.core.current.armor = 1
	await SpecFactory.start_turn(game, victim)
	var before:int = _health(victim)
	await SpecFactory.move(game, victim, ACID)
	assert_eq(_health(victim), before - 1, 'Armour does not reduce it.')
	assert_eq(victim.state.burn, 0, 'And it is not BURN, which would deal the damage AND stack burn.')

func test_the_armour_in_that_fixture_really_does_absorb_ordinary_damage():
	# Pairs with the test above: proves the armour was actually applied, so "AP works" cannot pass
	# because the fixture never had armour in the first place.
	victim.core.current.armor = 1
	var before:int = _health(victim)
	await SpecFactory.damage(game, victim, 1, Lancer.DAMAGE_TYPE.ENERGY)
	assert_eq(_health(victim), before, 'A plain 1 ENERGY is absorbed by 1 armour.')

# ============================== starting a turn in the terrain ==============================

func test_starting_a_turn_in_the_acid_costs_one_hp():
	# The victim is already standing on the tile when its turn begins - no movement involved, so
	# this can only come from the new_turn trigger.
	_foul([VICTIM_TILE])
	var before:int = _health(victim)
	await SpecFactory.start_turn(game, victim)
	assert_eq(_health(victim), before - 1, 'Waking up in the acid costs a point.')

func test_starting_a_turn_on_clean_ground_costs_nothing():
	# Vacuity guard.
	_foul([ACID])
	var before:int = _health(victim)
	await SpecFactory.start_turn(game, victim)
	assert_eq(_health(victim), before, 'Its own tile is clean, so nothing happens.')

# ============================== 1/round, per CHARACTER ==============================

func test_two_different_characters_both_take_it_in_one_round():
	# "1/round" is per CHARACTER. This pins that it is not accidentally per NUCKELAVEE.
	#
	# It passes without any code change, and that is worth explaining rather than deleting.
	# ActionReactionOnComingWithin overrides get_per_round_hard_limit to
	# `99 if can_trigger_any_number_of_times_per_round else 1` (:36-37), ignoring consumes_rxn, and
	# is_under_per_round_limit really is consulted on every trigger check
	# (ReactionBus.does_reaction_trigger -> can_activate_gear -> unit_action.gd:170). But it counts
	# GearCore.uses_this_round, and NOTHING increments that for this action: the only writer is
	# increment_action_usage_for_action at unit_action.gd:279, reached only via
	# UnitAction.spend_actions_gain_heat, which an action reaches only by calling
	# Action.spend_actions(activation) from its own activate (action.gd:144-147). That call is
	# opt-in, and neither we nor vanilla's action_apocalypse_burn.gd make it.
	#
	# So the cap is LATENT, not active - the trait is one added spend_actions call away from
	# collapsing this rule into 1/round-per-Nuckelavee. can_trigger_any_number_of_times_per_round
	# closes that door permanently, and this test is what would notice if it ever opened.
	#
	# Two fouled tiles, one each: the first character is still standing on its own when the second
	# moves, so they cannot share one. Both inside the 5x5 default map.
	const SECOND_ACID := Vector2i(3, 2)
	_foul([ACID, SECOND_ACID])
	var second := SpecFactory.create_unit(game.map, Vector2i(4, 2), Faction.AI_ENEMY)
	SpecFactory.apply_passive_buffs(second)

	await SpecFactory.start_turn(game, victim)
	var victim_before:int = _health(victim)
	await SpecFactory.move(game, victim, ACID)
	assert_eq(_health(victim), victim_before - 1, 'The first character took it.')
	await SpecFactory.end_turn(game, victim)

	await SpecFactory.start_turn(game, second)
	var second_before:int = _health(second)
	await SpecFactory.move(game, second, SECOND_ACID)
	assert_eq(_health(second), second_before - 1,
		'And so did the second - the limit is per character, not per Nuckelavee.')

func test_the_same_character_only_takes_it_once_in_a_round():
	# "Characters can take this damage 1/round." Two fouled tiles, one continuous walk across both.
	# Only meaningful now the round cap is lifted - before Task 4 step 3 this passed for the wrong
	# reason.
	# ACID is (3,0), so the second fouled tile is (2,0) - one further west, still on the map.
	_foul([ACID, Vector2i(2, 0)])
	await SpecFactory.start_turn(game, victim)
	var before:int = _health(victim)
	await SpecFactory.move(game, victim, ACID)
	assert_eq(_health(victim), before - 1, 'The first fouled tile bit.')
	await SpecFactory.move(game, victim, Vector2i(2, 0))
	assert_eq(_health(victim), before - 1, 'The second one did not - once per round.')

func test_the_limit_lifts_on_the_characters_next_turn():
	# buff_track_affection expires at Lancer.UNTIL.START_OF_TURN, cleared by
	# UnitCondition.new_turn_for_statuses inside event_turn_start's handle_starting_unit - which runs
	# BEFORE the NEW_TURN POST reactions are queued, so a character that starts its turn on the
	# fouled tile takes it again next round. That ordering only matters on the start-turn path, so
	# round 2 stays put rather than re-entering - walking out and back would exercise the entering
	# path twice and never prove the start-of-turn clear runs before the reaction queue.
	_foul([ACID])
	await SpecFactory.start_turn(game, victim)
	var before:int = _health(victim)
	await SpecFactory.move(game, victim, ACID)
	assert_eq(_health(victim), before - 1, 'Taken this round.')
	await SpecFactory.end_turn(game, victim)

	# A round boundary the cheap way, as test_poisoned_soil.gd and test_dhiyed_observation.gd do it.
	game.map.game_core.round_count += 1
	await SpecFactory.start_turn(game, victim)
	assert_eq(_health(victim), before - 2, 'Still standing in it, and bitten again next round.')

# ============================== who walks over it untouched ==============================

func test_a_flying_character_crosses_free():
	_foul([ACID])
	SpecFactory.apply(victim, Lancer.STATUS.FLYING)
	await SpecFactory.start_turn(game, victim)
	var before:int = _health(victim)
	await SpecFactory.move(game, victim, ACID)
	assert_eq(victim.tile(), ACID, 'It actually crossed - "no damage" must not mean "no movement".')
	assert_eq(_health(victim), before, 'It is over the ground, not in it.')

func test_bulwark_mods_carries_its_wearer_over_the_acid_free():
	# The designed pair. ms_bulwark_mods is RANK 1 of the license the Nuckelavee clones - a 1 SP
	# always-on BuffMovementType with ignore_difficult = true - and
	# MovementType.ignores_difficult_terrain() consumes exactly that flag. The license's first
	# unlock is the answer to the frame's own ground. Asserted so nobody later "fixes" the
	# self-damage test by exempting the owner instead.
	#
	# Both halves run against the SAME fouled tile in this one test on purpose: run it alone with
	# --gut-test= and it still has to show the acid bites somebody before "Bulwark Mods is exempt"
	# means anything. Without that, a completely dead reaction passes this.
	_foul([ACID])

	# Starts directly south of ACID (3,0), so one step reaches it and one step retreats.
	var bare := SpecFactory.create_unit(game.map, Vector2i(3, 1), Faction.AI_ENEMY)
	SpecFactory.apply_passive_buffs(bare)
	await SpecFactory.start_turn(game, bare)
	var bare_before:int = _health(bare)
	await SpecFactory.move(game, bare, ACID)
	assert_eq(bare.tile(), ACID, 'It actually crossed - "no damage" must not mean "no movement".')
	assert_eq(_health(bare), bare_before - 1, 'A mover without the system still takes it.')
	await SpecFactory.move(game, bare, Vector2i(3, 1))
	await SpecFactory.end_turn(game, bare)

	victim.core.equip_system(&'ms_bulwark_mods')
	SpecFactory.apply_passive_buffs(victim)
	await SpecFactory.start_turn(game, victim)
	var before:int = _health(victim)
	await SpecFactory.move(game, victim, ACID)
	assert_eq(victim.tile(), ACID, 'It actually crossed - "no damage" must not mean "no movement".')
	assert_eq(_health(victim), before, 'Bulwark Mods walks over it.')

func test_a_character_knocked_into_the_acid_still_takes_it():
	# The designer's ruling, and DESIGNED PLAY: several frames carry substantial knockback, and
	# throwing a target onto the Nuckelavee's ground is intended emergent strategy.
	#
	# This is a deliberate asymmetry with Poisoned Soil, where forced movement crosses the trail
	# free - that was an engine fact inherited from the pathfinder's own
	# ignores_difficult_terrain(), not a ruling. Here the clause is read as a property of the
	# CHARACTER, so is_exempt asks MovementType.create(victim) and never the movement that brought
	# them in. Pinned so nobody later "restores consistency" and deletes the play.
	_foul([ACID])
	await SpecFactory.start_turn(game, victim)
	var before:int = _health(victim)
	await game.execute_event(&'event_unit_move', {
		unit = victim,
		array = [Pathfinder.Step.create(ACID, 1)],
		resource = MovementType.create_for_involuntary(victim),
	})
	assert_eq(_health(victim), before - 1, 'Thrown in is still in.')

func test_another_units_difficult_terrain_is_not_ours_to_punish():
	# "difficult terrain created by the NUCKELAVEE". get_caustic_tiles is handed the reaction's own
	# owner, so a second frame's trail must be invisible to us - it is difficult ground, but not our
	# acid. This becomes load-bearing the moment the core power widens seam 1 to "all difficult
	# terrain": at that point this test SHOULD start failing, and that is the signal to revisit it.
	var stranger := SpecFactory.create_unit(game.map, Vector2i(0, 3), Faction.AI_ENEMY)
	var stranger_soil:GearCore = stranger.core.equip_system(SOIL_ID)
	SpecFactory.apply_passive_buffs(stranger)
	PoisonedSoil.write_trail(stranger_soil, [ACID] as Array[Vector2i])

	await SpecFactory.start_turn(game, victim)
	var before:int = _health(victim)
	await SpecFactory.move(game, victim, ACID)
	assert_eq(victim.tile(), ACID, 'It actually crossed.')
	assert_eq(_health(victim), before, "Somebody else's ground is not our acid.")

# ============================== deliberate, and it looks like a bug ==============================

func test_the_nuckelavee_takes_its_own_damage():
	# Nothing in the trait text exempts the frame, and nothing in the code does either -
	# ActionReactionOnComingWithin hard-excludes its own owner at :49, which is the main reason
	# triggers_on_event is overridden wholesale rather than calling super.
	#
	# It is not the constant self-harm it looks like: Poisoned Soil no longer fouls the space the
	# frame stops in, so this only bites when it walks back over an old trail - and Bulwark Mods is
	# the license's answer, exactly as for everyone else.
	_foul([Vector2i(1, 0)])
	await SpecFactory.start_turn(game, nuckelavee)
	var before:int = _health(nuckelavee)
	await SpecFactory.move(game, nuckelavee, Vector2i(1, 0))
	assert_eq(_health(nuckelavee), before - 1, 'Its own filth burns it too.')

func test_an_exiled_nuckelavees_ground_bites_nobody():
	# MapState.add_dynamic_terrain_and_zones_from_unit returns before collecting any terrain zone
	# for an EXILED or INTANGIBLE owner (map_state.gd:423-425), so that frame's terrain does not
	# exist on the map - the behaviour Poisoned Soil's design chose ("the living mech fouling the
	# ground, not a crater").
	#
	# EXILED costs us nothing: ReactionBus.does_reaction_trigger:120 calls
	# UnitAction.can_activate_gear, whose first check is REASON.EXILED at unit_action.gd:138. Pinned
	# anyway, because "correctly guarded" and "silently dead" look identical from outside.
	_foul([ACID])
	SpecFactory.apply(nuckelavee, Lancer.STATUS.EXILED)
	await SpecFactory.start_turn(game, victim)
	var before:int = _health(victim)
	await SpecFactory.move(game, victim, ACID)
	assert_eq(_health(victim), before, 'No frame on the board, no acid on the ground.')

func test_an_intangible_nuckelavees_ground_bites_nobody():
	# The half that DOES need code. Nothing in the can_activate_gear chain checks INTANGIBLE, and
	# get_caustic_tiles calls get_voxels_to_apply_terrain directly, bypassing map_state's guard - so
	# without an explicit check the acid keeps biting from a frame that is not really there.
	_foul([ACID])
	SpecFactory.apply(nuckelavee, Lancer.STATUS.INTANGIBLE)
	await SpecFactory.start_turn(game, victim)
	var before:int = _health(victim)
	await SpecFactory.move(game, victim, ACID)
	assert_eq(_health(victim), before, 'An intangible frame projects no terrain.')

func test_the_same_acid_bites_when_the_nuckelavee_is_present_and_solid():
	# Vacuity guard for both tests above: identical fixture, no status applied. Without it, a
	# reaction broken in any way at all would make both guards pass.
	_foul([ACID])
	await SpecFactory.start_turn(game, victim)
	var before:int = _health(victim)
	await SpecFactory.move(game, victim, ACID)
	assert_eq(_health(victim), before - 1, 'Present and solid, the acid bites.')

# ============================== the two traits, composed ==============================

func test_a_bare_nuckelavee_does_not_poison_itself_after_a_boost():
	# THE POINT OF THE WHOLE BRANCH, and the one thing neither suite proved on its own:
	# test_poisoned_soil.gd asserts the trail ARRAY excludes the stopping tile, and every other test
	# in this file writes its trail with _foul(), which never runs action_poisoned_soil_lay.gd. So
	# the producer and the consumer were each correct in isolation with nothing showing they compose.
	#
	# A real boost, a real move, a real lay - then a real turn start on the tile it stopped on.
	# Bulwark Mods is deliberately NOT equipped: the frame must be safe here without it, because that
	# system is an optional purchase and needing it was the bug this branch fixed.
	SpecFactory.current_responder.chosen_yesnos = true
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	await SpecFactory.move(game, nuckelavee, Vector2i(2, 0))
	assert_eq(nuckelavee.tile(), Vector2i(2, 0), 'It actually moved, so the trail is real.')

	var trail:Array[Vector2i] = PoisonedSoil.read_trail(soil_gear)
	assert_false(trail.is_empty(), 'A trail was laid - otherwise there is nothing to be safe from.')
	assert_false(trail.has(nuckelavee.tile()), 'And it does not include the tile it stopped on.')

	await SpecFactory.end_turn(game, nuckelavee)
	game.map.game_core.round_count += 1
	var before:int = _health(nuckelavee)
	await SpecFactory.start_turn(game, nuckelavee)
	assert_eq(_health(nuckelavee), before, 'Waking up where it stopped costs nothing.')

func test_but_a_nuckelavee_that_walks_back_onto_its_own_fresh_trail_is_bitten():
	# The paired control. Without it the test above passes just as well against a Caustic Earth that
	# never fires at all, or a Poisoned Soil that lays nothing.
	SpecFactory.current_responder.chosen_yesnos = true
	await SpecFactory.start_turn(game, nuckelavee)
	await SpecFactory.use_solo(game, nuckelavee, &'ms_boost')
	await SpecFactory.move(game, nuckelavee, Vector2i(2, 0))

	var trail:Array[Vector2i] = PoisonedSoil.read_trail(soil_gear)
	assert_true(trail.has(Vector2i(1, 0)), 'The tile it crossed IS fouled.')

	var before:int = _health(nuckelavee)
	await SpecFactory.move(game, nuckelavee, Vector2i(1, 0))
	assert_eq(nuckelavee.tile(), Vector2i(1, 0), 'It actually stepped back onto the trail.')
	assert_eq(_health(nuckelavee), before - 1, 'Its own filth burns it.')

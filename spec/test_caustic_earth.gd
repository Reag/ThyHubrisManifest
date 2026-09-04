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
	# Action.spend_actions(activation) from its own activate (action.gd:143-146). That call is
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
	# BEFORE the NEW_TURN POST reactions are queued, so a character that walks out and comes back
	# next round takes it again.
	_foul([ACID])
	await SpecFactory.start_turn(game, victim)
	var before:int = _health(victim)
	await SpecFactory.move(game, victim, ACID)
	assert_eq(_health(victim), before - 1, 'Taken this round.')
	await SpecFactory.move(game, victim, VICTIM_TILE)
	await SpecFactory.end_turn(game, victim)

	# A round boundary the cheap way, as test_poisoned_soil.gd and test_dhiyed_observation.gd do it.
	game.map.game_core.round_count += 1
	await SpecFactory.start_turn(game, victim)
	await SpecFactory.move(game, victim, ACID)
	assert_eq(_health(victim), before - 2, 'And again the next round.')

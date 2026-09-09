# The Spreading Stain. "1/round, on a critical hit against a target with |INFECTION|, the Draugr may
# apply 1 |INFECTION| to another character within |SENSORS|." (gear.mt_spreading_stain.effect)
#
# An OnHitEffect at on_crit, injected by buff_spreading_stain (BuffWeaponTypeOnHit) which
# mt_spreading_stain hands out through a PassiveBuffApplicator. The pick goes through the mod's
# compat shim, so it is a real choice-bus request on 1.4.0 - observed here with
# testkit/prompt_watcher.gd and answered by SpecFactory's own responder, exactly as
# spec/test_tear_pick.gd does. Never connect to bus signals directly.
#
# WHAT THE PROMPT ASSERTIONS ARE ACTUALLY FOR. The responder will answer any unit pick, including
# one the real UI cannot resolve, so "the outcome was right" proves nothing about pickability. That
# is why test_the_candidates_are_all_pickable_characters exists: a MARKER offered to choose_unit
# highlights its tile and then swallows the click forever (see spec/test_tear_pick.gd's header).
#
# Dice (plan section B3): [20, 2, 3] against mw_tactical_melee_weapon (1d6+2) is a crit with no 1s,
# so no overkill fires and The Seeping Rot stays out of the way.
extends GutTest

const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')
const PromptWatcher := preload('res://testkit/prompt_watcher.gd')
const StainEffect := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/mt_spreading_stain/onhit_spreading_stain.gd')
const DRAUGR_FRAME := 'res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/mf_draugr.tres'

const MELEE := &'mw_tactical_melee_weapon'
const TRAIT_ID := &'mt_spreading_stain'
const CRIT_NO_OVERKILL := [20, 2, 3]

var game:Gamemaster
var draugr:Unit
var target:Unit
var bystander:Unit
var watcher:PromptWatcher

func before_each():
	# DEVIATION FROM THE BRIEF (documented in task-3-report.md): a 30x30 landscape, not the default.
	# SpecFactory.create_combat falls back to Landscape.create_default(), which is
	# Tile.MIN_MAP_DIMENSION squared - a 5x5 map. Every unit this file places outside that (the
	# distant one at (11, 0), the whole AI cluster at (20, 20)+) then lands OFF the map, where
	# occupied_tiles() is empty and Tile.get_closest_pair_between returns its 1000 sentinel
	# (tile.gd:408-415). Distance to such a unit is 1000 from anywhere, so it is never a candidate
	# and never has candidates: test_an_ai_draugr_... failed with an empty list, and
	# test_a_character_beyond_sensors_... passed for the wrong reason. Measured 2026-09-09.
	game = SpecFactory.setup_gamemaster(self, false, SpecFactory.create_combat(Landscape.create_default(Vector2i(30, 30))))
	draugr = _draugr_at(Vector2i(0, 0), Faction.PLAYER)
	target = _enemy_at(Vector2i(1, 0))
	bystander = _enemy_at(Vector2i(3, 0)) # 3 tiles: inside the Draugr's sensor_range of 5
	watcher = add_child_autoqfree(PromptWatcher.new())

func after_each():
	Dice.CHEAT_ROLL_QUEUE.clear()

func _draugr_at(tile:Vector2i, faction:Faction.SIDE) -> Unit:
	var unit := SpecFactory.create_unit(game.map, tile, faction)
	unit.core.change_mech_frame(load(DRAUGR_FRAME))
	unit.core.equip_system(MELEE)
	SpecFactory.apply_passive_buffs(unit)
	unit.core.frame.stat.heat = 20
	unit.core.current.heat = 0
	return unit

func _enemy_at(tile:Vector2i, faction:Faction.SIDE = Faction.AI_ENEMY) -> Unit:
	var unit := SpecFactory.create_unit(game.map, tile, faction)
	unit.core.frame.stat.health = 40
	unit.core.frame.stat.evasion = -10
	unit.core.frame.stat.armor = 0
	unit.core.full_repair()
	unit.core.current.heat = 0
	return unit

func _infect(unit:Unit, n:int) -> void:
	await Infection.apply(SpecFactory.dummy_event({unit = unit}), unit, n)

func _crit(attacker:Unit, victim:Unit) -> void:
	var gear:GearCore = attacker.get_gear(MELEE)
	assert_true(GearCore.is_valid(gear), 'Fixture: the melee weapon is equipped.')
	if not GearCore.is_valid(gear): return
	Dice.CHEAT_ROLL_QUEUE.append_array(CRIT_NO_OVERKILL)
	await game.execute_event('event_gear_activate', {
		action = gear.get_solo_action(), unit = attacker, gear = gear, target_unit = victim,
	})
	Dice.CHEAT_ROLL_QUEUE.clear()

func _unit_prompts() -> Array[Dictionary]:
	return watcher.kinds(PromptWatcher.KIND.unit)

func test_a_crit_on_an_infected_target_asks_who_else_catches_it():
	await _infect(target, 1)
	SpecFactory.current_responder.chosen_unit = bystander
	await _crit(draugr, target)
	assert_eq(_unit_prompts().size(), 1, 'The Draugr was asked exactly once.')

func test_the_chosen_character_gains_one_infection():
	await _infect(target, 1)
	SpecFactory.current_responder.chosen_unit = bystander
	await _crit(draugr, target)
	assert_eq(Infection.count(bystander), 1, 'The picked character caught it.')

func test_a_crit_on_an_uninfected_target_asks_nothing():
	SpecFactory.current_responder.chosen_unit = bystander
	await _crit(draugr, target)
	assert_eq(_unit_prompts().size(), 0, 'No infection on the target, no spread.')
	assert_eq(Infection.count(bystander), 0, 'And nobody caught anything.')

func test_the_candidates_are_all_pickable_characters_and_never_the_target():
	# "ANOTHER character": the unit just hit is excluded. And every candidate must be something the
	# engine's own unit-pick path can resolve a click to - a MARKER cannot be (test_tear_pick.gd).
	await _infect(target, 1)
	SpecFactory.current_responder.chosen_unit = bystander
	var marker_free := true
	await _crit(draugr, target)
	if _unit_prompts().is_empty(): return fail_test('A pick was offered.')
	var offered:Array = _unit_prompts().front().units
	assert_false(offered.has(target), 'The character that was hit is not a candidate.')
	assert_false(offered.has(draugr), 'Nor is the Draugr itself.')
	for candidate in offered:
		if candidate is Unit and candidate.is_marker(): marker_free = false
	assert_true(marker_free, 'Every candidate is clickable: no markers were offered.')

func test_a_character_beyond_sensors_is_not_a_candidate():
	var distant := _enemy_at(Vector2i(11, 0)) # 11 tiles: well beyond the Draugr's sensor_range of 5
	await _infect(target, 1)
	SpecFactory.current_responder.chosen_unit = bystander
	await _crit(draugr, target)
	if _unit_prompts().is_empty(): return fail_test('A pick was offered.')
	assert_false(_unit_prompts().front().units.has(distant), 'Out of Sensors, out of the list.')

func test_it_only_spreads_once_per_round():
	await _infect(target, 1)
	SpecFactory.current_responder.chosen_unit = bystander
	await _crit(draugr, target)
	# The engine's no-repeat-action rule blocks a second use of the SAME gear within one turn
	# (action.gd:161-163); without a turn boundary the second attack aborts before it ever rolls.
	# See spec/test_seeping_rot.gd's test_a_second_overkill_stacks_a_second_point for the full note.
	# event_turn_start does NOT touch game_core.round_count, so this is still the same round.
	Dice.CHEAT_ROLL_QUEUE.clear()
	await SpecFactory.start_turn(game, draugr)
	await _crit(draugr, target)
	assert_eq(_unit_prompts().size(), 1, 'The second crit in the same round asked nothing.')
	assert_eq(Infection.count(bystander), 1, 'And spread nothing.')

func test_a_new_round_lets_it_spread_again():
	await _infect(target, 1)
	SpecFactory.current_responder.chosen_unit = bystander
	await _crit(draugr, target)
	game.core.round_count += 1
	# Same turn-boundary requirement as above; the round bump is what this test is actually about.
	Dice.CHEAT_ROLL_QUEUE.clear()
	await SpecFactory.start_turn(game, draugr)
	await _crit(draugr, target)
	assert_eq(_unit_prompts().size(), 2, 'A new round, a new spread.')
	assert_eq(Infection.count(bystander), 2, 'And a second point on the same bystander.')

func test_an_ai_draugr_takes_the_nearest_hostile_without_asking():
	# Vanilla never raises a human dialog for an AI's own decision (action_blinkspace_jump.gd:14),
	# and this mod already follows that at onhit_mourning_call.gd:117-124.
	var ai_draugr := _draugr_at(Vector2i(20, 20), Faction.AI_ENEMY)
	var ai_target := _enemy_at(Vector2i(21, 20), Faction.PLAYER)
	var far_player := _enemy_at(Vector2i(23, 20), Faction.PLAYER)  # 3 away
	var near_player := _enemy_at(Vector2i(22, 20), Faction.PLAYER) # 2 away: the nearest hostile
	await _infect(ai_target, 1)
	await _crit(ai_draugr, ai_target)
	assert_eq(_unit_prompts().size(), 0, 'The AI was never asked.')
	assert_eq(Infection.count(near_player), 1, 'It took the nearest hostile that was not the target.')
	assert_eq(Infection.count(far_player), 0, 'And left the further one alone.')

func test_a_declined_prompt_spreads_nothing_and_keeps_the_round_free():
	# "may apply": declining is free. The round stamp is written only after a valid pick
	# (onhit_spreading_stain.gd, the set_state after the pick), so the Draugr can still spread
	# later this round.
	await _infect(target, 1)
	SpecFactory.current_responder.abort_all = true
	await _crit(draugr, target)
	SpecFactory.current_responder.abort_all = false
	assert_eq(_unit_prompts().size(), 1, 'It asked.')
	assert_eq(Infection.count(bystander), 0, 'Nobody was infected.')
	var gear:GearCore = draugr.get_gear(TRAIT_ID)
	assert_eq(gear.get_state(StainEffect.SPREAD_ROUND_KEY, -1), -1, 'The round was not spent.')

# Copyright (c) 2026 Wickworks ♡ Lancer Tactics v1.3.3
# Mourning Call, Task 1: the trigger and the hand-off (clauses 1-2). After a RANGED hit the player
# is offered Mourning Call; accepting spends a quick action (on top of the weapon's own) plus the
# core point and runs action_mourning_call.gd's activate(). The action's body -- teleport,
# tangibility, damage, the crit rider -- is Task 2 and is NOT covered here.
#
# spec/test_mourning_call_probe.gd (probe 1, deleted by Task 5) proved this exact hand-off shape
# first: buff -> OnHitEffect -> CommonActionUtil.choose_and_use -> action. This spec is the real
# build against the actual cp_the_keening trait rather than a standalone probe kit.
extends GutTest

const BANSHEE_FRAME := 'res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/mf_banshee.tres'
const RANGED_WEAPON_ID := &'mw_smartgun' # weapon_type unset -> defaults to RIFLE (ranged)
const MELEE_WEAPON_ID := &'mw_tactical_melee_weapon' # weapon_type = MELEE, aim_range = 0
const KEENING_KIT_ID := &'cp_the_keening'
const MOURNING_CALL_USAGE_GROUP := &'action_mourning_call'

var game:Gamemaster

func before_each():
	game = SpecFactory.setup_gamemaster(self)

## Arms the Banshee with its own frame. change_mech_frame, NOT core.frame = load(...) - the latter
## skips loadout.regenerate_derived_gear (unit_printer.gd:94), so cp_the_keening's
## PassiveBuffApplicator never runs and buff_mourning_call is never applied.
func _arm_banshee(tile:Vector2i = Vector2i(1,1)) -> Unit:
	var banshee := SpecFactory.create_unit(game.map, tile)
	banshee.core.change_mech_frame(load(BANSHEE_FRAME))
	SpecFactory.apply_passive_buffs(banshee) # full_repair() happens inside this
	banshee.core.has_core_power = true
	SpecFactory.start_turn(game, banshee)
	return banshee

func _mourning_call_ran(unit:Unit) -> bool:
	var gear:GearCore = unit.get_gear(KEENING_KIT_ID)
	if not GearCore.is_valid(gear): return false
	return gear.get_uses_this_round_alt(MOURNING_CALL_USAGE_GROUP) > 0

## Drives a guaranteed-hit weapon attack through event_gear_activate, the way
## test/gear/test_wm_throughbolt_rounds.gd does: queue a CompconPlan naming the target directly
## (no movement) so SpecFactory.current_responder just hands it back when the plan is requested.
func _attack(attacker:Unit, weapon_id:StringName, target_unit:Unit) -> void:
	var weapon:GearCore = attacker.get_gear(weapon_id)
	SpecFactory.current_responder.chosen_plan_queue = [CompconPlan.create([], [], [target_unit])]
	Dice.CHEAT_ROLL_QUEUE.append_array([20, 20, 20, 20]) # guarantee the hit (and any crit/damage rolls)
	await game.execute_event(&'event_gear_activate', {
		action = weapon.get_solo_action(),
		gear = weapon,
		unit = attacker,
	})


func test_a_ranged_hit_offers_mourning_call_and_accepting_runs_it():
	var banshee := _arm_banshee()
	banshee.core.equip_system(RANGED_WEAPON_ID)
	var target := SpecFactory.create_unit(game.map, Vector2i(1, 6), Faction.AI_ENEMY)
	target.core.full_repair()

	# SpecFactory.ChoiceBusResponder.chosen_yesnos defaults to true, so the prompt is auto-accepted.
	await _attack(banshee, RANGED_WEAPON_ID, target)

	assert_true(_mourning_call_ran(banshee), 'A ranged hit offers Mourning Call, and accepting runs it.')

func test_a_melee_hit_does_not_offer_mourning_call():
	var banshee := _arm_banshee()
	banshee.core.equip_system(MELEE_WEAPON_ID)
	# aim_range = 0 -- the target has to be adjacent for a melee attack to land at all.
	var target := SpecFactory.create_unit(game.map, Vector2i(1, 2), Faction.AI_ENEMY)
	target.core.full_repair()

	await _attack(banshee, MELEE_WEAPON_ID, target)

	assert_false(_mourning_call_ran(banshee), 'A melee hit never offers it - the trait says ranged.')

func test_accepting_spends_the_core_point_and_a_quick_action():
	var banshee := _arm_banshee()
	banshee.core.equip_system(RANGED_WEAPON_ID)
	var target := SpecFactory.create_unit(game.map, Vector2i(1, 6), Faction.AI_ENEMY)
	target.core.full_repair()

	var actions_before:int = banshee.state.actions
	assert_true(banshee.core.has_core_power, 'sanity: the Banshee starts with a core point to spend.')
	assert_gt(actions_before, 0, 'sanity: the Banshee starts with actions to spend.')

	# The weapon attack itself is ALSO a QUICK action and spends its own cost -- compute it
	# dynamically rather than assume, and subtract it back out. What this test cares about is the
	# cost ON TOP of that.
	var weapon:GearCore = banshee.get_gear(RANGED_WEAPON_ID)
	var weapon_specific := SpecificAction.create(banshee, weapon, weapon.get_solo_action())
	var weapon_cost:int = weapon_specific.action.get_action_cost(weapon_specific)

	await _attack(banshee, RANGED_WEAPON_ID, target)

	assert_true(_mourning_call_ran(banshee), 'sanity: Mourning Call actually ran.')
	assert_eq(
		banshee.state.actions, actions_before - weapon_cost - Lancer.ACTION_COST_QUICK,
		'unit.state.actions went down by exactly the QUICK cost, on top of the weapon\'s own.'
	)
	assert_false(banshee.core.has_core_power, 'unit.core.has_core_power went from true to false.')

func test_declining_costs_nothing():
	var banshee := _arm_banshee()
	banshee.core.equip_system(RANGED_WEAPON_ID)
	var target := SpecFactory.create_unit(game.map, Vector2i(1, 6), Faction.AI_ENEMY)
	target.core.full_repair()

	SpecFactory.current_responder.chosen_yesnos = false # decline the prompt

	var actions_before:int = banshee.state.actions
	var weapon:GearCore = banshee.get_gear(RANGED_WEAPON_ID)
	var weapon_specific := SpecificAction.create(banshee, weapon, weapon.get_solo_action())
	var weapon_cost:int = weapon_specific.action.get_action_cost(weapon_specific)

	await _attack(banshee, RANGED_WEAPON_ID, target)

	assert_false(_mourning_call_ran(banshee), 'Declining does not run the action.')
	assert_eq(
		banshee.state.actions, actions_before - weapon_cost,
		'Declining spends only the weapon\'s own cost -- nothing extra for Mourning Call.'
	)
	assert_true(banshee.core.has_core_power, 'Declining leaves the core point unspent.')

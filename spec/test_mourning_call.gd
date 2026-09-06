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
	await _attack_with_roll(attacker, weapon_id, target_unit, [20, 20, 20, 20]) # guarantee the hit (and any crit/damage rolls)

## Same shape as _attack(), but lets the caller control the attack roll instead of a hardcoded
## guaranteed crit. Task 2's damage tests need to force a hit that is NOT a crit as well as one
## that IS -- [20,20,20,20] would crit every time, which is exactly the trap this spec exists to
## catch. A couple of low spare values are appended by the callers below so a stray extra accuracy
## die (if one ever gets rolled) doesn't accidentally borrow from the NEXT attack's queued values.
func _attack_with_roll(attacker:Unit, weapon_id:StringName, target_unit:Unit, dice:Array) -> void:
	var weapon:GearCore = attacker.get_gear(weapon_id)
	SpecFactory.current_responder.chosen_plan_queue = [CompconPlan.create([], [], [target_unit])]
	Dice.CHEAT_ROLL_QUEUE.append_array(dice)
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


# ============================================================================
# Task 2: clauses 3-6 -- what activate() actually does. THE TRAP: event_unit_attack.gd calls
# apply_on_hits AND THEN apply_on_crits on a critical hit (:85-93), so an implementation that
# splits 4 into on_hit and 6 into on_crit deals 10, not 6. action_mourning_call.gd must read the
# crit off the DeclaredAttackSummary living on the OUTER (event_unit_attack) activation instead.
# ============================================================================

func test_it_teleports_the_banshee_adjacent_to_the_target():
	var banshee := _arm_banshee()
	banshee.core.equip_system(RANGED_WEAPON_ID)
	# NOT (1,6) like Task 1's fixture -- the test map is only Tile.MIN_MAP_DIMENSION (5x5), so (1,6)
	# sits off it. Task 1's tests never move anyone so that never mattered; teleporting adjacent needs
	# a real, on-map tile with real neighbors.
	var target := SpecFactory.create_unit(game.map, Vector2i(3, 3), Faction.AI_ENEMY)
	target.core.full_repair()

	await _attack(banshee, RANGED_WEAPON_ID, target)

	assert_true(_mourning_call_ran(banshee), 'sanity: Mourning Call actually ran.')
	assert_true(UnitRelation.is_adjacent(banshee, target), 'The Banshee ends adjacent to its target.')

func test_it_deals_4_on_a_hit():
	var banshee := _arm_banshee()
	banshee.core.equip_system(RANGED_WEAPON_ID)
	var target := SpecFactory.create_unit(game.map, Vector2i(3, 3), Faction.AI_ENEMY) # on the 5x5 test map
	target.core.frame.stat.health = 100 # headroom -- don't let the weapon hit + Mourning Call kill it
	target.core.full_repair()

	# Baseline: the SAME hit, declined, so we know exactly what the weapon's own damage was and can
	# isolate Mourning Call's contribution by subtraction, rather than assuming the weapon deals
	# zero (mw_smartgun does not -- damage_dice = "4", flat).
	#
	# Dice queue order per attack is THREE values, not two: buff_to_twist_truth.gd's
	# check_if_passive_applies unconditionally calls Dice.roll_d6() every time the Banshee attacks
	# (attack_util.gd's invisibility check consults it before the attack roll even starts), so the
	# first value popped is that d6, not the attack roll. [dummy, base_roll_d20, accuracy_d6].
	SpecFactory.current_responder.chosen_yesnos = false
	await _attack_with_roll(banshee, RANGED_WEAPON_ID, target, [6, 15, 1]) # hits (evasion 8), does not crit (<20)
	var weapon_only_damage:int = target.current_damage()
	assert_false(_mourning_call_ran(banshee), 'sanity: the declined baseline did not run Mourning Call.')

	target.core.full_repair()
	await SpecFactory.start_turn(game, banshee) # refresh the actions the baseline attack spent
	SpecFactory.current_responder.chosen_yesnos = true
	await _attack_with_roll(banshee, RANGED_WEAPON_ID, target, [6, 15, 1]) # same hit, still not a crit

	assert_true(_mourning_call_ran(banshee), 'sanity: Mourning Call actually ran this time.')
	assert_eq(
		target.current_damage() - weapon_only_damage, 4,
		'A plain hit deals 4 AP KINETIC, on top of whatever the weapon itself already did.'
	)

func test_it_deals_6_on_a_crit_and_not_10():
	var banshee := _arm_banshee()
	banshee.core.equip_system(RANGED_WEAPON_ID)
	var target := SpecFactory.create_unit(game.map, Vector2i(3, 3), Faction.AI_ENEMY) # on the 5x5 test map
	target.core.frame.stat.health = 100
	target.core.full_repair()

	# Same three-value queue shape as test_it_deals_4_on_a_hit (see its comment): [dummy_for_
	# to_twist_truth, base_roll_d20, accuracy_d6]. A natural 20 crits regardless of accuracy.
	SpecFactory.current_responder.chosen_yesnos = false
	await _attack_with_roll(banshee, RANGED_WEAPON_ID, target, [6, 20, 1]) # natural 20 -- guaranteed crit
	var weapon_only_damage:int = target.current_damage()
	assert_false(_mourning_call_ran(banshee), 'sanity: the declined baseline did not run Mourning Call.')

	target.core.full_repair()
	await SpecFactory.start_turn(game, banshee)
	SpecFactory.current_responder.chosen_yesnos = true
	await _attack_with_roll(banshee, RANGED_WEAPON_ID, target, [6, 20, 1]) # same guaranteed crit

	assert_true(_mourning_call_ran(banshee), 'sanity: Mourning Call actually ran this time.')
	assert_eq(
		target.current_damage() - weapon_only_damage, 6,
		'A crit deals 6, NOT 4+6 = 10 -- apply_on_hits and apply_on_crits both fired, but only one of them should have dealt damage.'
	)

func test_it_clears_intangible():
	var banshee := _arm_banshee()
	banshee.core.equip_system(RANGED_WEAPON_ID)
	var target := SpecFactory.create_unit(game.map, Vector2i(3, 3), Faction.AI_ENEMY) # on the 5x5 test map
	target.core.full_repair()
	SpecFactory.apply(banshee, Lancer.STATUS.INTANGIBLE)
	assert_true(banshee.has_status(Lancer.STATUS.INTANGIBLE), 'sanity: the Banshee starts INTANGIBLE.')

	await _attack(banshee, RANGED_WEAPON_ID, target)

	assert_true(_mourning_call_ran(banshee), 'sanity: Mourning Call actually ran.')
	assert_false(banshee.has_status(Lancer.STATUS.INTANGIBLE), 'The Banshee becomes tangible.')

func test_it_works_while_immobilized():
	var banshee := _arm_banshee()
	banshee.core.equip_system(RANGED_WEAPON_ID)
	var target := SpecFactory.create_unit(game.map, Vector2i(3, 3), Faction.AI_ENEMY) # on the 5x5 test map
	target.core.full_repair()
	SpecFactory.apply(banshee, Lancer.STATUS.IMMOBILIZED)
	assert_true(UnitCondition.is_immobilized(banshee), 'sanity: the Banshee starts immobilized.')

	await _attack(banshee, RANGED_WEAPON_ID, target)

	assert_true(_mourning_call_ran(banshee), 'sanity: Mourning Call actually ran.')
	assert_true(UnitRelation.is_adjacent(banshee, target), 'IMMOBILIZED does not stop the teleport.')

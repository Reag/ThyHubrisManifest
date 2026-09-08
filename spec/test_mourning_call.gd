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

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')

const BANSHEE_FRAME := 'res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/mf_banshee.tres'
const RANGED_WEAPON_ID := &'mw_smartgun' # weapon_type unset -> defaults to RIFLE (ranged)
const MELEE_WEAPON_ID := &'mw_tactical_melee_weapon' # weapon_type = MELEE, aim_range = 0
const KEENING_KIT_ID := &'cp_the_keening'
const MOURNING_CALL_USAGE_GROUP := &'action_mourning_call'
const MourningCallAction := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/action_mourning_call.gd')

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
	var target := SpecFactory.create_unit(game.map, Vector2i(3, 3), Faction.AI_ENEMY) # on the 5x5 test map, away from the banshee at (1,1) so it keeps free neighbours
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
	var target := SpecFactory.create_unit(game.map, Vector2i(3, 3), Faction.AI_ENEMY) # on the 5x5 test map, away from the banshee at (1,1) so it keeps free neighbours
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
	var target := SpecFactory.create_unit(game.map, Vector2i(3, 3), Faction.AI_ENEMY) # on the 5x5 test map, away from the banshee at (1,1) so it keeps free neighbours
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

## Defect 1 regression: on_hit's pre-check was asking whether the BANSHEE has a free neighbouring
## tile, not the TARGET -- nearly always true at range, so the guard validated nothing. This boxes
## the target into a corner so none of its on-map neighbours are free, and leaves
## SpecFactory.current_responder.chosen_yesnos at its default `true` (see the class default at
## spec_factory.gd:373) rather than declining -- that is what makes this a real regression test: if
## the broken guard is checking the banshee's own (mostly-free) tiles instead, the prompt WOULD be
## offered and auto-accepted, and Mourning Call would run. Only a guard that genuinely checks the
## target's neighbours stops it here.
func test_the_prompt_is_not_offered_when_the_target_has_no_free_adjacent_tile():
	var banshee := _arm_banshee(Vector2i(4, 4)) # far corner, so the banshee's own tile is never one of the target's neighbours
	banshee.core.equip_system(RANGED_WEAPON_ID)
	var target := SpecFactory.create_unit(game.map, Vector2i(0, 0), Faction.AI_ENEMY) # opposite corner -- only 3 tiles are on-map neighbours (Tile.DIRECTIONS is 8-way, clipped by map.shape.is_playable)
	target.core.full_repair()

	# Occupy all 3 of the target's on-map neighbours with other units. Frame.is_obstruction
	# defaults to true (frame.gd:64), and Pathfinder.Occupation.calculate_for treats a present,
	# non-shareable obstruction unit as an invalid_endpoint (pathfinder.gd:106-132) -- so a plain
	# SpecFactory unit standing on each tile is sufficient to make it unstandable, no terrain needed.
	var target_neighbors := UnitTile.get_adjacent_tiles(target)
	assert_eq(target_neighbors.size(), 3, 'sanity: a corner tile on a 5x5 map has exactly 3 on-map neighbours.')
	for blocker_tile:Vector2i in target_neighbors:
		SpecFactory.create_unit(game.map, blocker_tile, Faction.AI_ENEMY)

	var actions_before:int = banshee.state.actions
	assert_true(banshee.core.has_core_power, 'sanity: the Banshee starts with a core point to spend.')
	var weapon:GearCore = banshee.get_gear(RANGED_WEAPON_ID)
	var weapon_specific := SpecificAction.create(banshee, weapon, weapon.get_solo_action())
	var weapon_cost:int = weapon_specific.action.get_action_cost(weapon_specific)

	await _attack(banshee, RANGED_WEAPON_ID, target)

	assert_false(_mourning_call_ran(banshee), 'Boxed in with no free adjacent tile, the prompt is not offered (and so never auto-accepted) at all.')
	assert_eq(
		banshee.state.actions, actions_before - weapon_cost,
		'Not being offered spends only the weapon\'s own cost -- nothing extra for Mourning Call.'
	)
	assert_true(banshee.core.has_core_power, 'Not being offered leaves the core point unspent.')


# ============================================================================
# Task 2: clauses 3-6 -- what activate() actually does. THE TRAP: event_unit_attack.gd calls
# apply_on_hits AND THEN apply_on_crits on a critical hit (:85-93), so an implementation that
# splits 4 into on_hit and 6 into on_crit deals 10, not 6. action_mourning_call.gd must read the
# crit off the DeclaredAttackSummary living on the OUTER (event_unit_attack) activation instead.
# ============================================================================

func test_it_teleports_the_banshee_adjacent_to_the_target():
	var banshee := _arm_banshee()
	banshee.core.equip_system(RANGED_WEAPON_ID)
	# The test map is only Tile.MIN_MAP_DIMENSION (5x5); Task 1's fixtures used to place targets at
	# (1,6), which sits off it. That never mattered there because those tests never moved anyone,
	# but teleporting adjacent needs a real, on-map tile with real neighbors -- so all of Task 1's
	# fixtures were brought onto the board too (see the fix for Defect 1's off-map fixture bug).
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
	# Dice queue order per attack is two values: [base_roll_d20, accuracy_d6]. Nothing in this fixture
	# is invisible (no INVISIBLE status, no TREAT_AS_INVISIBLE buff), so buff_to_twist_truth.gd's
	# check_if_passive_applies gate never fires and never touches Dice.CHEAT_ROLL_QUEUE -- there is no
	# extra die to account for here.
	SpecFactory.current_responder.chosen_yesnos = false
	await _attack_with_roll(banshee, RANGED_WEAPON_ID, target, [15, 1]) # hits (evasion 8), does not crit (<20)
	var weapon_only_damage:int = target.current_damage()
	assert_false(_mourning_call_ran(banshee), 'sanity: the declined baseline did not run Mourning Call.')

	target.core.full_repair()
	await SpecFactory.start_turn(game, banshee) # refresh the actions the baseline attack spent
	SpecFactory.current_responder.chosen_yesnos = true
	await _attack_with_roll(banshee, RANGED_WEAPON_ID, target, [15, 1]) # same hit, still not a crit

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

	# Same two-value queue shape as test_it_deals_4_on_a_hit (see its comment): [base_roll_d20,
	# accuracy_d6]. A natural 20 crits regardless of accuracy.
	SpecFactory.current_responder.chosen_yesnos = false
	await _attack_with_roll(banshee, RANGED_WEAPON_ID, target, [20, 1]) # natural 20 -- guaranteed crit
	var weapon_only_damage:int = target.current_damage()
	assert_false(_mourning_call_ran(banshee), 'sanity: the declined baseline did not run Mourning Call.')

	target.core.full_repair()
	await SpecFactory.start_turn(game, banshee)
	SpecFactory.current_responder.chosen_yesnos = true
	await _attack_with_roll(banshee, RANGED_WEAPON_ID, target, [20, 1]) # same guaranteed crit

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


# ============================================================================
# Task 3: the kill rider (clauses 7-8). THE RISK: probe 2 (spec/test_mourning_call_probe.gd) proved
# a DEATH:PRE reaction CAN strip LEAVES_WRECK, but proved it on the DYING unit's own gear and by
# invoking event_unit_die directly. Neither shape is production-correct -- see
# action_mourning_call_wreckless.gd for why the reaction has to live on the Banshee instead, and the
# comments below for why these tests kill their targets through event_unit_structure/event_unit_damage
# instead of the probe's shortcut.
#
# action_mourning_call.gd AWAITS its own damage (execute_events, not queue_damage_events) so it can
# tell, synchronously, whether THIS blow killed the target.
#
# UPDATED for the on_resolution fix: Mourning Call now fires AFTER the weapon's own damage has
# already been applied (onhit_mourning_call.gd fires from OnHitEffect.on_resolution, which runs
# after event_unit_attack_declared.gd's core.execute_events(damage_events) at :199) -- the opposite
# of the old on_hit ordering these tests were originally written against. So a target killed
# specifically BY Mourning Call now needs enough health that the weapon's own flat 4
# (mw_smartgun.damage_dice = "4") does NOT kill it on its own, but the weapon's 4 plus Mourning
# Call's own 4 (non-crit) does -- health = 8 gives that exactly (4 remaining after the weapon's hit,
# 0 after Mourning Call's). Health = 4 (the OLD fixture value) would now die to the weapon's hit
# ALONE, before Mourning Call ever got to run at all -- which would make these tests pass for the
# wrong reason (an ordinary weapon kill) rather than actually exercising Mourning Call's kill rider.
#
# structure = 1 keeps event_unit_structure.gd's OUTCOME.DIE path from needing a structure-check
# roll/brochure at all (unit.get_structure_max() > 1 is false) -- straight to queuing event_unit_die
# with LEAVES_WRECK, no extra dice or responder configuration needed.
# ============================================================================

func _wreck_count() -> int:
	var count := 0
	for u:Unit in game.map.get_all_units():
		if Frame.is_valid(u.core.frame) and u.core.frame.compcon_id.begins_with('dep_wreck'):
			count += 1
	return count

func test_a_target_killed_by_mourning_call_leaves_no_wreck():
	var banshee := _arm_banshee()
	banshee.core.equip_system(RANGED_WEAPON_ID)
	var target := SpecFactory.create_unit(game.map, Vector2i(3, 3), Faction.AI_ENEMY)
	target.core.frame.stat.structure = 1 # one hit below zero structure kills outright -- see header
	# 8 = the weapon's flat 4 (leaves exactly 4, alive) + Mourning Call's non-crit 4 (0, dead) -- see
	# the Task 3 header for why this changed from the old fixture value of 4.
	target.core.frame.stat.health = 8
	target.core.full_repair()
	var wrecks_before := _wreck_count()

	# Killed BY THE DAMAGE, via event_unit_structure -- never by invoking event_unit_die directly.
	# The probe took the direct route; this must not.
	await _attack_with_roll(banshee, RANGED_WEAPON_ID, target, [15, 1]) # hits (evasion 8), does not crit

	assert_true(_mourning_call_ran(banshee), 'sanity: Mourning Call actually ran.')
	assert_false(Unit.is_valid(target), 'sanity: the target actually died.')
	assert_eq(_wreck_count(), wrecks_before, 'A target destroyed by Mourning Call leaves no wreckage.')

## THE GATE. Without buff_mourning_call_mark scoping the reaction to this one kill, wrecklessness
## would become a property of the TARGET (or of the Banshee's mere presence) rather than of Mourning
## Call's own damage specifically -- and every other test in this section would still pass. A Banshee
## is present (so mt_mourning_call_wreckless -- the reaction -- actually exists on the map for the
## reaction bus to find; without one there'd be nothing to strip the flag regardless of the mark
## check, and this test would pass for the wrong reason), but it isn't the one doing the killing:
## ordinary damage, nothing to do with Mourning Call at all.
func test_a_target_killed_BY_ANYTHING_ELSE_STILL_leaves_a_wreck():
	var banshee := _arm_banshee() # present (carries the wreckless trait), but not involved in this kill
	var target := SpecFactory.create_unit(game.map, Vector2i(3, 3), Faction.AI_ENEMY)
	target.core.frame.stat.structure = 1
	target.core.full_repair()
	var wrecks_before := _wreck_count()

	await SpecFactory.damage(game, target, target.core.current.health + 10, Lancer.DAMAGE_TYPE.KINETIC)

	assert_false(Unit.is_valid(target), 'sanity: the target actually died.')
	assert_gt(_wreck_count(), wrecks_before, 'An ordinary death still leaves a wreck.')

func test_the_banshee_becomes_intangible_on_a_kill():
	var banshee := _arm_banshee()
	banshee.core.equip_system(RANGED_WEAPON_ID)
	var target := SpecFactory.create_unit(game.map, Vector2i(3, 3), Faction.AI_ENEMY)
	target.core.frame.stat.structure = 1
	target.core.frame.stat.health = 8 # weapon's 4 (survives) + Mourning Call's 4 (dies) -- see Task 3 header
	target.core.full_repair()

	await _attack_with_roll(banshee, RANGED_WEAPON_ID, target, [15, 1])

	assert_true(_mourning_call_ran(banshee), 'sanity: Mourning Call actually ran.')
	assert_false(Unit.is_valid(target), 'sanity: the target actually died.')
	assert_true(banshee.has_status(Lancer.STATUS.INTANGIBLE), 'Clause 8: a kill phases the Banshee out.')

func test_the_banshee_stays_tangible_when_the_target_survives():
	var banshee := _arm_banshee()
	banshee.core.equip_system(RANGED_WEAPON_ID)
	var target := SpecFactory.create_unit(game.map, Vector2i(3, 3), Faction.AI_ENEMY)
	target.core.frame.stat.health = 100 # headroom -- survives the weapon hit AND Mourning Call's damage
	target.core.full_repair()

	await _attack_with_roll(banshee, RANGED_WEAPON_ID, target, [15, 1])

	assert_true(_mourning_call_ran(banshee), 'sanity: Mourning Call actually ran.')
	assert_true(Unit.is_valid(target), 'sanity: the target survived.')
	assert_false(banshee.has_status(Lancer.STATUS.INTANGIBLE), 'No kill, no phase-out.')


# ============================================================================
# THE FIX ITSELF: onhit_mourning_call.gd used to fire from OnHitEffect.on_hit, which runs BEFORE
# the weapon's own damage is applied (event_unit_attack.gd:83-88 fires while
# event_unit_attack_declared.gd's damage_events are still only QUEUED, not executed until :199).
# So Mourning Call always struck a target at the health it had BEFORE the weapon's own hit landed --
# a target that only dies to the COMBINATION of the weapon's damage and Mourning Call's damage
# would, at the instant Mourning Call's old on_hit checked Unit.is_valid(target), still read as
# alive (only Mourning Call's own 4 had applied yet). Mourning Call would have concluded "survived",
# taken its mark back off, and left the ACTUAL kill -- which only happens later, once the weapon's
# queued damage finally lands -- to run as an ordinary death: a wreck left behind, and no
# re-triggered INTANGIBLE for the Banshee, because by then Mourning Call's own kill-rider logic had
# already run and decided nothing needed to trigger.
#
# This test pins exactly that scenario against the fixed on_resolution ordering.
# ============================================================================

func test_it_finishes_off_a_target_the_weapon_already_wounded():
	var banshee := _arm_banshee()
	banshee.core.equip_system(RANGED_WEAPON_ID)
	var target := SpecFactory.create_unit(game.map, Vector2i(3, 3), Faction.AI_ENEMY)
	target.core.frame.stat.structure = 1
	# 7, not the kill tests' 8: the weapon's flat 4 alone leaves 3 -- comfortably alive, not a
	# hairline zero, so "the weapon's hit alone does not kill" is unambiguous. Only Mourning Call's
	# own follow-up 4 (3 - 4 = -1) actually crosses zero and triggers the death.
	target.core.frame.stat.health = 7
	target.core.full_repair()
	var wrecks_before := _wreck_count()

	await _attack_with_roll(banshee, RANGED_WEAPON_ID, target, [15, 1]) # hits (evasion 8), does not crit

	assert_true(_mourning_call_ran(banshee), 'sanity: Mourning Call actually ran.')
	assert_false(
		Unit.is_valid(target),
		'The weapon\'s hit alone (4, leaving 3) does not kill -- the target dies to Mourning Call\'s follow-up finishing it off. Under the old on_hit ordering this would not have killed at all.'
	)
	assert_eq(_wreck_count(), wrecks_before, 'Killed specifically by Mourning Call: no wreckage.')
	assert_true(banshee.has_status(Lancer.STATUS.INTANGIBLE), 'Killed specifically by Mourning Call: the Banshee ends INTANGIBLE.')


# ============================================================================
# Task 4: clauses 9-10, the kill rider's tail end. "...you may move a void tear anywhere within
# SENSORS. 1/scene after destroying a target this way, regain your core point." Both only run from
# the kill branch Task 3 already proved out, so these reuse that exact fixture shape (structure = 1,
# health = 8, a non-crit [15, 1] roll -- the weapon's own 4 leaves exactly 4, Mourning Call's own 4
# finishes it) and add only what each clause needs on top.
# ============================================================================

func test_a_kill_lets_the_banshee_relocate_a_tear_within_sensors():
	var banshee := _arm_banshee()
	banshee.core.equip_system(RANGED_WEAPON_ID)
	# Room for action_tear's own quick action on top of the weapon attack + Mourning Call (3 quick
	# actions total against a turn's default budget of 2) -- the same fix test_tear_move.gd uses to
	# combine a tear action with something else in one turn.
	banshee.state.overcharge_actions = 99
	var target := SpecFactory.create_unit(game.map, Vector2i(3, 3), Faction.AI_ENEMY)
	target.core.frame.stat.structure = 1
	target.core.frame.stat.health = 8 # see the Task 4 header
	target.core.full_repair()

	# Placed in the FAR corner, away from (0,0): UnitTile.get_tiles_within fills its candidate array
	# starting from the low corner of its bounding box, so with the Banshee's huge default sensor
	# range covering the whole 5x5 board, (0,0) is what choose_target_tiles's front()-picking test
	# responder ends up choosing -- a tile the tear does NOT already occupy, so the resulting move is
	# a real relocation rather than a same-tile no-op the engine would abort.
	await SpecFactory.use(game, banshee, KEENING_KIT_ID, &'action_tear', [Vector2i(4, 4)])
	var tears:Array[Unit] = TearRouting.open_tears(game.map)
	assert_eq(tears.size(), 1, 'sanity: exactly one tear was placed.')
	var tear:Unit = tears.front()

	# Capture what was actually OFFERED to the relocation pick, without displacing SpecFactory's own
	# responder -- it still answers the request (front of the candidate list, same as every other
	# choose_target_tiles fixture in this mod; see action_bind_thy_flesh.gd's choose_anchor_tile), so
	# there is exactly one thing "the chosen tile" can mean here: the front of what we captured.
	#
	# assign(), NOT `=` -- a GDScript lambda captures an outer local by a COPY of its value at
	# creation time, so reassigning the captured slot inside the lambda never reaches the outer
	# variable. Mutating the array IN PLACE (same object, same capture) does.
	var offered_tiles:Array[Vector2i] = []
	var capture_offer := func(_request, _specific, from_tiles):
		offered_tiles.assign(from_tiles)
	SpecFactory.choice_bus.on_choose_target_tiles.connect(capture_offer)

	await _attack_with_roll(banshee, RANGED_WEAPON_ID, target, [15, 1]) # hits (evasion 8), does not crit, kills

	SpecFactory.choice_bus.on_choose_target_tiles.disconnect(capture_offer)

	assert_true(_mourning_call_ran(banshee), 'sanity: Mourning Call actually ran.')
	assert_false(Unit.is_valid(target), 'sanity: the target actually died.')
	assert_false(offered_tiles.is_empty(), 'sanity: the relocation prompt actually offered candidate tiles.')
	assert_eq(tear.tile(), offered_tiles.front(), 'The tear moves to the chosen tile within sensor range.')

func test_a_tile_beyond_sensors_is_not_offerable():
	var banshee := _arm_banshee(Vector2i(0, 0))
	# A private copy: load(BANSHEE_FRAME) is shared (cached) across every test in this file via
	# _arm_banshee, so mutating sensor_range on it directly would leak a shrunk Banshee sensor range
	# into every OTHER test that arms one afterward. duplicate(true) deep-copies the Statblock
	# sub-resource too, so this mutation is private to this test alone.
	banshee.core.frame = banshee.core.frame.duplicate(true)
	banshee.core.frame.stat.sensor_range = 1 # shrinks SENSORS so the 5x5 test map's far corner is out of range
	banshee.core.equip_system(RANGED_WEAPON_ID)
	banshee.state.overcharge_actions = 99 # see the sibling test above

	var target := SpecFactory.create_unit(game.map, Vector2i(3, 3), Faction.AI_ENEMY)
	target.core.frame.stat.structure = 1
	target.core.frame.stat.health = 8
	target.core.full_repair()

	await SpecFactory.use(game, banshee, KEENING_KIT_ID, &'action_tear', [Vector2i(1, 1)]) # inside the shrunk range
	assert_eq(TearRouting.open_tears(game.map).size(), 1, 'sanity: the tear was actually placed.')

	var offered_tiles:Array[Vector2i] = []
	var capture_offer := func(_request, _specific, from_tiles):
		offered_tiles.assign(from_tiles) # see the sibling test above for why assign(), not `=`
	SpecFactory.choice_bus.on_choose_target_tiles.connect(capture_offer)

	await _attack_with_roll(banshee, RANGED_WEAPON_ID, target, [15, 1])

	SpecFactory.choice_bus.on_choose_target_tiles.disconnect(capture_offer)

	assert_true(_mourning_call_ran(banshee), 'sanity: Mourning Call actually ran.')
	assert_false(Unit.is_valid(target), 'sanity: the target actually died.')
	assert_false(offered_tiles.is_empty(), 'sanity: the relocation was still offered -- a tear exists, just not everywhere.')
	assert_false(
		offered_tiles.has(Vector2i(4, 4)),
		'A tile at the far corner of the map, well beyond the shrunk sensor range of 1, is not offerable.'
	)

func test_the_core_point_comes_back_after_a_kill():
	var banshee := _arm_banshee()
	banshee.core.equip_system(RANGED_WEAPON_ID)
	var target := SpecFactory.create_unit(game.map, Vector2i(3, 3), Faction.AI_ENEMY)
	target.core.frame.stat.structure = 1
	target.core.frame.stat.health = 8
	target.core.full_repair()

	await _attack_with_roll(banshee, RANGED_WEAPON_ID, target, [15, 1]) # hits, does not crit, kills

	assert_true(_mourning_call_ran(banshee), 'sanity: Mourning Call actually ran.')
	assert_false(Unit.is_valid(target), 'sanity: the target actually died.')
	assert_true(banshee.core.has_core_power, 'The core point is refunded after a kill.')

## THE 1/SCENE GATE. Two kills in the same scene must refund exactly once, not twice.
func test_the_core_point_does_not_come_back_a_second_time_in_the_same_scene():
	var banshee := _arm_banshee()
	banshee.core.equip_system(RANGED_WEAPON_ID)

	var target1 := SpecFactory.create_unit(game.map, Vector2i(3, 3), Faction.AI_ENEMY)
	target1.core.frame.stat.structure = 1
	target1.core.frame.stat.health = 8
	target1.core.full_repair()
	await _attack_with_roll(banshee, RANGED_WEAPON_ID, target1, [15, 1])

	assert_true(_mourning_call_ran(banshee), 'sanity: the first kill actually ran Mourning Call.')
	assert_false(Unit.is_valid(target1), 'sanity: the first target actually died.')
	assert_true(banshee.core.has_core_power, 'sanity: the first kill refunded the core point.')

	# Clause 8 leaves the Banshee INTANGIBLE after the first kill, and vanilla can_affect
	# (unit_relation.gd:397) refuses ANY interaction across a tangibility mismatch -- an ordinary
	# ranged attack against a tangible target2 would never land, so Mourning Call would never even be
	# offered a second time. Clearing it here stands in for whatever tangibles the Banshee back up
	# between kills in a real game; Mourning Call's own clause 4 would also do it, but only once its
	# activate() actually runs -- which is exactly what this second attack needs to reach.
	UnitCondition.clear_status(SpecFactory.dummy_event(), banshee, Lancer.STATUS.INTANGIBLE)

	await SpecFactory.start_turn(game, banshee) # refresh actions and the per-round usage counter
	var target2 := SpecFactory.create_unit(game.map, Vector2i(3, 3), Faction.AI_ENEMY)
	target2.core.frame.stat.structure = 1
	target2.core.frame.stat.health = 8
	target2.core.full_repair()
	await _attack_with_roll(banshee, RANGED_WEAPON_ID, target2, [15, 1])

	assert_true(_mourning_call_ran(banshee), 'sanity: the second kill actually ran Mourning Call too.')
	assert_false(Unit.is_valid(target2), 'sanity: the second target actually died.')
	assert_false(
		banshee.core.has_core_power,
		'The refund is once per scene: the second kill spends the point again but does not get it back.'
	)


# ============================================================================
# Task 6 (playtest fixes): the accounting and the prompting around Mourning Call. The mechanics
# above -- damage, the crit path, the kill test, wreck-stripping, the refund -- were all already
# proven; what nothing here counted was HOW MANY TIMES each of them was billed, or WHETHER the
# prompt should have been shown at all. That is what this section counts.
# ============================================================================

## Every `-CP` popup the run emitted. spend_core_power (unit_action.gd:286-289) plays exactly this
## text once per call, so counting the popup counts the calls -- which is the only direct evidence
## of the double-billing bug that does not require instrumenting the engine.
var _cp_pops:int = 0
func _count_cp_pop(text:String, _tile:Vector2i, _is_large:bool) -> void:
	if text == X.tr('battle.spent.cp.pop'): _cp_pops += 1

## Every yes/no prompt title the run raised. Titles, not a bare count, so a test can say WHICH
## prompt it did or did not expect without being confused by an unrelated confirmation.
var _yesno_titles:Array[String] = []
func _record_yesno(_request, _tile:Vector2i, title:String, _description:String, _encourage_yes:bool) -> void:
	_yesno_titles.append(title)

func _mourning_call_prompt_title() -> String:
	return X.tr('battle.confirm.use').format({action = tr('gear.cp_the_keening.action_mourning_call.name')})

func _mourning_call_prompts() -> int:
	var count := 0
	for title:String in _yesno_titles:
		if title == _mourning_call_prompt_title(): count += 1
	return count

func _watch_buses() -> void:
	_cp_pops = 0
	_yesno_titles = []
	SpecFactory.effect_bus.on_play_text.connect(_count_cp_pop)
	SpecFactory.choice_bus.on_quick_yesno.connect(_record_yesno)

func _unwatch_buses() -> void:
	if SpecFactory.effect_bus.on_play_text.is_connected(_count_cp_pop):
		SpecFactory.effect_bus.on_play_text.disconnect(_count_cp_pop)
	if SpecFactory.choice_bus.on_quick_yesno.is_connected(_record_yesno):
		SpecFactory.choice_bus.on_quick_yesno.disconnect(_record_yesno)

func _uses_this_round(unit:Unit) -> int:
	var gear:GearCore = unit.get_gear(KEENING_KIT_ID)
	if not GearCore.is_valid(gear): return -1
	return gear.get_uses_this_round_alt(MOURNING_CALL_USAGE_GROUP)

## SUB-FIX 1. onhit_mourning_call.gd handed the SAME SpecificAction to choose_and_use as both
## `using` and `chosen`, so UnitAction.spend ran twice for it: once non-freebie (via the
## deferred_spend that choose_and_use_spend_action installs) and once as the child activation's own
## freebie spend. unit.state.actions is guarded by `if not as_freebie` so the QUICK was only ever
## charged once -- which is why the pre-existing action-economy test above stayed green -- but
## everything OUTSIDE that guard ran twice: spend_core_power (two "-CP" popups and two core_power
## barks), increment_action_usage_for_action, log_usage and popcorn_usage.
func test_activating_spends_the_core_point_exactly_once():
	var banshee := _arm_banshee()
	banshee.core.equip_system(RANGED_WEAPON_ID)
	var target := SpecFactory.create_unit(game.map, Vector2i(3, 3), Faction.AI_ENEMY)
	target.core.frame.stat.health = 100 # survive, so the refund cannot muddy the count
	target.core.full_repair()

	_watch_buses()
	await _attack_with_roll(banshee, RANGED_WEAPON_ID, target, [15, 1])
	_unwatch_buses()

	assert_true(_mourning_call_ran(banshee), 'sanity: Mourning Call actually ran.')
	assert_eq(_cp_pops, 1, 'The core point is spent ONCE -- one "-CP" popup, not two.')

## SUB-FIX 1, the other half of the same double spend: gear usage is recorded twice, so a
## once-per-round Mourning Call would read as already-spent the instant it was first used.
func test_activating_records_exactly_one_use():
	var banshee := _arm_banshee()
	banshee.core.equip_system(RANGED_WEAPON_ID)
	var target := SpecFactory.create_unit(game.map, Vector2i(3, 3), Faction.AI_ENEMY)
	target.core.frame.stat.health = 100
	target.core.full_repair()

	await _attack_with_roll(banshee, RANGED_WEAPON_ID, target, [15, 1])

	assert_eq(_uses_this_round(banshee), 1, 'One activation records exactly one use of the usage group.')

## SUB-FIX 2. The kill rider used Lancer.UNTIL.MANUAL, which never expires -- an accidental permanent
## intangibility. Author decision: START_OF_TURN, matching Whispering (see spec/test_whispering.gd's
## own expiry test, whose shape this mirrors).
func test_the_intangibility_from_a_kill_expires_at_the_start_of_the_next_turn():
	var banshee := _arm_banshee()
	banshee.core.equip_system(RANGED_WEAPON_ID)
	var target := SpecFactory.create_unit(game.map, Vector2i(3, 3), Faction.AI_ENEMY)
	target.core.frame.stat.structure = 1
	target.core.frame.stat.health = 8 # weapon's 4 (survives) + Mourning Call's 4 (dies)
	target.core.full_repair()

	await _attack_with_roll(banshee, RANGED_WEAPON_ID, target, [15, 1])

	assert_false(Unit.is_valid(target), 'sanity: the target actually died.')
	assert_true(banshee.has_status(Lancer.STATUS.INTANGIBLE), 'sanity: the kill phased the Banshee out.')

	await SpecFactory.end_turn(game, banshee)
	assert_true(
		banshee.has_status(Lancer.STATUS.INTANGIBLE),
		'Still intangible through the end of this turn -- START_OF_TURN, not END_OF_THIS_TURN.'
	)

	await SpecFactory.start_turn(game, banshee)
	assert_false(banshee.has_status(Lancer.STATUS.INTANGIBLE), 'Tangible again at the start of its next turn.')

## SUB-FIX 3. After a non-killing use the core point is gone for the rest of the mission, but the
## prompt kept being offered on every subsequent ranged hit; accepting then failed deep inside
## UnitAction with NO_CORE_POWER, to the console only. Nothing player-facing said why.
func test_no_prompt_is_offered_without_a_core_point():
	var banshee := _arm_banshee()
	banshee.core.equip_system(RANGED_WEAPON_ID)
	banshee.core.has_core_power = false # already spent it earlier in the mission
	var target := SpecFactory.create_unit(game.map, Vector2i(3, 3), Faction.AI_ENEMY)
	target.core.frame.stat.health = 100
	target.core.full_repair()

	_watch_buses()
	await _attack_with_roll(banshee, RANGED_WEAPON_ID, target, [15, 1])
	_unwatch_buses()

	assert_eq(_mourning_call_prompts(), 0, 'With no core point, the prompt is not offered at all.')
	assert_false(_mourning_call_ran(banshee), 'And Mourning Call does not run.')

## SUB-FIX 4. An AI Banshee was raising ITS decision as a human yes/no dialog -- the human player was
## being asked whether the enemy should use its core power. Vanilla always guards these on
## is_player_controlled and gives the AI a default (action_blinkspace_jump.gd, action_mag_parry.gd,
## action_consume_lock_on.gd all do exactly this); the default here is yes, as it is there.
func test_an_ai_banshee_is_never_prompted():
	var banshee := SpecFactory.create_unit(game.map, Vector2i(1, 1), Faction.AI_ENEMY)
	banshee.core.change_mech_frame(load(BANSHEE_FRAME))
	SpecFactory.apply_passive_buffs(banshee)
	banshee.core.has_core_power = true
	await SpecFactory.start_turn(game, banshee)
	banshee.core.equip_system(RANGED_WEAPON_ID)
	assert_false(banshee.is_player_controlled(), 'sanity: this Banshee is AI-controlled.')

	var target := SpecFactory.create_unit(game.map, Vector2i(3, 3), Faction.PLAYER)
	target.core.frame.stat.health = 100
	target.core.full_repair()

	_watch_buses()
	await _attack_with_roll(banshee, RANGED_WEAPON_ID, target, [15, 1])
	_unwatch_buses()

	assert_true(_mourning_call_ran(banshee), 'sanity: the AI still used Mourning Call (its default is yes).')
	assert_eq(_mourning_call_prompts(), 0, 'The AI never hands its own decision to the human player.')

## SUB-FIX 5. MovementType.create_for_involuntary + voluntary = false waives every gate that reads
## `voluntary and UnitCondition.is_immobilized(unit)` -- and is_immobilized (unit_condition.gd:412)
## covers GRAPPLED and SHUTDOWN as well as IMMOBILIZED. The prose licenses IMMOBILIZED only; being
## held in a grapple is not something "even while IMMOBILIZED" excuses.
func test_a_grappled_banshee_cannot_mourning_call():
	var banshee := _arm_banshee()
	banshee.core.equip_system(RANGED_WEAPON_ID)
	var target := SpecFactory.create_unit(game.map, Vector2i(3, 3), Faction.AI_ENEMY)
	target.core.frame.stat.health = 100
	target.core.full_repair()
	SpecFactory.apply(banshee, Lancer.STATUS.GRAPPLED)
	assert_true(UnitCondition.is_immobilized(banshee), 'sanity: a grapple immobilizes.')

	_watch_buses()
	await _attack_with_roll(banshee, RANGED_WEAPON_ID, target, [15, 1])
	_unwatch_buses()

	assert_eq(_mourning_call_prompts(), 0, 'GRAPPLED, the teleport cannot happen, so nothing is offered.')
	assert_false(_mourning_call_ran(banshee), 'And Mourning Call does not run.')
	assert_true(banshee.core.has_core_power, 'And the core point is not spent.')

## SUB-FIX 6. The teleport took the first standable tile in UnitTile.get_adjacent_tiles order, with
## no say from the player -- which side of the target you land on is a real tactical decision
## (cover, engagement, the next turn's reach). The player now picks from the free adjacent tiles.
func test_the_player_picks_the_landing_tile():
	var banshee := _arm_banshee()
	banshee.core.equip_system(RANGED_WEAPON_ID)
	var target := SpecFactory.create_unit(game.map, Vector2i(3, 3), Faction.AI_ENEMY)
	target.core.frame.stat.health = 100 # survive, so the tear-relocation pick never runs and cannot
	target.core.full_repair()           # overwrite what this capture saw

	# Same capture shape as the tear-relocation tests above: SpecFactory's own responder still
	# answers (front of the offered list), so the landing tile must be offered_tiles.front().
	var offered_tiles:Array[Vector2i] = []
	var capture_offer := func(_request, _specific, from_tiles):
		offered_tiles.assign(from_tiles)
	SpecFactory.choice_bus.on_choose_target_tiles.connect(capture_offer)
	await _attack_with_roll(banshee, RANGED_WEAPON_ID, target, [15, 1])
	SpecFactory.choice_bus.on_choose_target_tiles.disconnect(capture_offer)

	assert_true(_mourning_call_ran(banshee), 'sanity: Mourning Call actually ran.')
	assert_false(offered_tiles.is_empty(), 'The player is offered the free tiles adjacent to the target.')
	assert_true(
		UnitRelation.is_adjacent(banshee, target),
		'sanity: wherever it landed, it landed adjacent to the target.'
	)
	assert_eq(banshee.tile(), offered_tiles.front(), 'The Banshee lands on the tile that was chosen.')


# ============================================================================
# WHAT THE PLAYER IS SHOWN (playtest fixes 8.1 and 8.2). Every test above this line asserts
# BEHAVIOUR, and behaviour was never the problem with these two: both abilities worked exactly as
# specified while presenting themselves wrongly. Task 1 this week found a completely unreachable
# action that 510 green tests had missed for the same reason - nothing asked what the player could
# actually see or click.
# ============================================================================

func test_mourning_call_is_not_offered_as_a_clickable_action():
	# It sat on the gear bar next to Tear and did nothing when clicked: reached cold it has no target,
	# so activate() falls out of its first guard. It cannot simply be deleted from the Kit -
	# SpecificAction.from_id is how onhit_mourning_call.gd finds it - so it is refused instead.
	var banshee := _arm_banshee()
	banshee.core.has_core_power = true
	banshee.state.actions = Lancer.ACTION_COST_FULL

	var mourning_call := SpecificAction.from_id(banshee, KEENING_KIT_ID, &'action_mourning_call')
	assert_true(SpecificAction.is_valid(mourning_call),
		'The action is still on the Kit, so the on-hit hand-off can still find it.')
	assert_false(UnitAction.can_activate_gear(mourning_call),
		'But it is never offered as something to click - this is the question the UI and the AI ask.')

	# WHY it is refused, spelled out so a later reader does not mistake this for "the Banshee cannot
	# act". onhit_mourning_call.gd opens an offer window for the span of the hand-off and shuts it
	# again immediately; outside that window the action is unreachable from anywhere, gear bar
	# included. The window is also why a flat `return false` was wrong here: the event choose_and_use
	# builds runs this same check (event_gear_activate.gd:50), so a flat false killed the on-hit path
	# too.
	var keening:GearCore = banshee.get_gear(KEENING_KIT_ID)
	assert_false(MourningCallAction.is_offer_window_open(keening), 'The offer window is shut at rest.')
	MourningCallAction.open_offer_window(keening)
	assert_true(UnitAction.can_activate_gear(mourning_call),
		'And it IS reachable inside the window - which is the only reason the on-hit hand-off works.')
	MourningCallAction.close_offer_window(keening)

	# THE POSITIVE CONTROL. Without it this test would also pass on a Banshee that simply could not
	# act at all, which is not what is being asserted.
	var tear := SpecificAction.from_id(banshee, KEENING_KIT_ID, &'action_tear')
	assert_true(UnitAction.can_activate_gear(tear),
		'Its sibling on the same Kit, with the same core point and the same actions, IS offered.')

func test_mourning_call_hides_itself_rather_than_sitting_greyed_out():
	# is_available_to_activate takes it out of play; hide_if_disabled is what takes it off the bar
	# (gear_bar.gd:147). Without the flag the player just gets a permanently dead button instead.
	var kit:Kit = ContentLibrary.get_kit(KEENING_KIT_ID)
	if not Kit.is_valid(kit): return fail_test('%s loaded.' % KEENING_KIT_ID)
	var action:Action = kit.get_action(&'action_mourning_call')
	if not Action.is_valid(action): return fail_test('action_mourning_call is on the Kit.')
	assert_true(action.hide_if_disabled, 'Mourning Call hides rather than greying out.')
	# And the reason it is NOT is_situationally_activated, which would have done the same job:
	# situational actions are stripped out of the kit tooltip (kit.gd:229), so the player would stop
	# being told what Mourning Call does.
	assert_true(action.show_in_tooltip(kit), 'It still describes itself in The Keening\'s tooltip.')

func test_the_wreckless_reaction_is_not_a_frame_trait():
	# It used to have a Kit of its own wired into mf_banshee.tres's traits, purely to carry one
	# hidden reaction - and the playtest saw it in the book as a fourth, nameless trait with no text.
	# It now rides on cp_the_keening. test_content_integrity.gd pins the trait list itself; this pins
	# the half that matters here, that folding it in did not stop it working.
	var frame:Frame = ContentLibrary.get_mech_frame(&'mf_banshee')
	if not is_instance_valid(frame): return fail_test('mf_banshee loaded.')
	for kit:Kit in frame.traits:
		assert_ne(kit.compcon_id, &'mt_mourning_call_wreckless', 'No nameless helper trait in the list.')

	var kit:Kit = ContentLibrary.get_kit(KEENING_KIT_ID)
	if not Kit.is_valid(kit): return fail_test('%s loaded.' % KEENING_KIT_ID)
	var reaction:Action = kit.get_action(&'action_mourning_call_wreckless')
	assert_true(Action.is_valid(reaction), 'The reaction rides on the core power instead.')
	if not Action.is_valid(reaction): return
	assert_false(reaction.show_in_tooltip(kit), 'And it stays out of the core power\'s tooltip.')
	assert_eq(reaction.usage_group, &'action_mourning_call_wreckless',
		'With its own usage_group, so it does not eat Tear\'s or Mourning Call\'s round allowance.')

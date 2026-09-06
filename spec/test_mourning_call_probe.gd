# Mourning Call gauntlet -- THROWAWAY PROBES, deleted after the real build.
#
# Three yes/no questions, each with an agreed fallback if the answer is no.
# Design: D:\DEV\lancer-tactics-claude\specs\2026-09-06-banshee-mourning-call-design.md
#
# Every probe is a SPEC, not a print statement -- this project has four confirmed cases of
# script extensions/hooks that install cleanly, log success, and never run.
extends GutTest

var game:Gamemaster

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	_clear_meta(P1_ACTIVATED_META)
	_clear_meta(P2_FIRED_META)

func _clear_meta(key:StringName) -> void:
	if Engine.has_meta(key): Engine.remove_meta(key)


# ============================================================================
# PROBE 1 -- can an OnHitEffect activate a QUICK action mid-resolution
# through CommonActionUtil.choose_and_use, actually spending the action AND
# the core point?
#
# Kills: the hand-off architecture (buff -> OnHitEffect -> choose_and_use -> action).
# Fallback: the on-hit effect applies a short-lived buff that *enables* the action;
# the player clicks it separately.
# ============================================================================

const P1_WEAPON_KIT_ID := &'mw_smartgun'
const P1_MOURNING_CALL_KIT_ID := &'cp_probe_mourning_call'
const P1_MOURNING_CALL_BUFF_ID := &'buff_probe_mourning_call'
const P1_ACTIVATED_META := &'probe_mourning_call_activated'

func _p1_setup_attacker() -> Unit:
	var attacker := SpecFactory.create_unit(game.map, Vector2i(0, 0))
	attacker.core.equip_system(P1_WEAPON_KIT_ID)
	attacker.core.equip_system(P1_MOURNING_CALL_KIT_ID)
	SpecFactory.apply_passive_buffs(attacker) # full_repair() happens inside this
	attacker.core.has_core_power = true
	SpecFactory.apply_buff(attacker, P1_MOURNING_CALL_BUFF_ID)
	SpecFactory.start_turn(game, attacker)
	return attacker

func test_probe_1_choose_and_use_activates_pays_action_and_cp():
	var attacker := _p1_setup_attacker()
	var target := SpecFactory.create_unit(game.map, Vector2i(0, 3), Faction.AI_ENEMY)
	target.core.full_repair()

	var actions_before:int = attacker.state.actions
	assert_true(attacker.core.has_core_power, 'sanity: attacker starts with a core point to spend.')
	assert_gt(actions_before, 0, 'sanity: attacker starts with actions to spend.')

	# The weapon attack itself is ALSO a QUICK action and spends its own cost -- that's not
	# part of what this probe is testing, so compute it dynamically rather than assume, and
	# subtract it back out. What this probe cares about is the cost ON TOP of that.
	var weapon_gear:GearCore = attacker.get_gear(P1_WEAPON_KIT_ID)
	var weapon_specific := SpecificAction.create(attacker, weapon_gear, weapon_gear.get_solo_action())
	var weapon_cost:int = weapon_specific.action.get_action_cost(weapon_specific)

	Dice.CHEAT_ROLL_QUEUE.append_array([20, 20, 20, 20]) # guarantee the weapon attack hits
	await SpecFactory.use_solo(game, attacker, P1_WEAPON_KIT_ID, [target.tile()])

	var activate_ran:bool = Engine.has_meta(P1_ACTIVATED_META) and bool(Engine.get_meta(P1_ACTIVATED_META))
	assert_true(activate_ran, 'PROBE 1a: the chosen QUICK action\'s activate() actually ran.')

	assert_eq(
		attacker.state.actions, actions_before - weapon_cost - Lancer.ACTION_COST_QUICK,
		'PROBE 1b: unit.state.actions went DOWN by exactly the QUICK cost, on top of the weapon\'s own.'
	)

	assert_false(attacker.core.has_core_power, 'PROBE 1c: unit.core.has_core_power went from true to false.')

func test_probe_1_baseline_a_melee_hit_never_offers_mourning_call():
	# Sanity check on the harness: the buff is a BuffWeaponTypeOnHit and this probe doesn't
	# gate on weapon type, so this isn't testing clause 1-2's ranged gate -- it's confirming
	# that when the buff/onhit machinery is simply never wired to a unit, nothing fires.
	var attacker := SpecFactory.create_unit(game.map, Vector2i(0, 0))
	attacker.core.equip_system(P1_WEAPON_KIT_ID)
	SpecFactory.apply_passive_buffs(attacker)
	# deliberately NOT applying buff_probe_mourning_call or equipping the CP kit
	var target := SpecFactory.create_unit(game.map, Vector2i(0, 3), Faction.AI_ENEMY)
	target.core.full_repair()

	Dice.CHEAT_ROLL_QUEUE.append_array([20, 20, 20, 20])
	await SpecFactory.use_solo(game, attacker, P1_WEAPON_KIT_ID, [target.tile()])

	var activate_ran:bool = Engine.has_meta(P1_ACTIVATED_META) and bool(Engine.get_meta(P1_ACTIVATED_META))
	assert_false(activate_ran, 'sanity: without the buff wired up, nothing fires.')


# ============================================================================
# PROBE 2 -- can a TRIGGER.DEATH / TIMING.PRE reaction strip LEAVES_WRECK
# from the death context before event_unit_die.execute() reads it?
#
# Kills: clause 7 only. Fallback: despawn-after-spawn, or shelve clause 7.
# ============================================================================

const P2_STRIP_WRECK_KIT_ID := &'mt_probe_strip_wreck'
const P2_FIRED_META := &'probe_strip_wreck_reaction_fired'

func _wreck_count() -> int:
	var count := 0
	for u:Unit in game.map.get_all_units():
		if Frame.is_valid(u.core.frame) and u.core.frame.compcon_id.begins_with('dep_wreck'):
			count += 1
	return count

func test_probe_2_baseline_an_unmodified_death_leaves_a_wreck():
	# Sanity check on the assertion method itself: prove a wreck normally DOES appear,
	# so a "no wreck" result in the other tests can't be a false negative from the harness.
	var unit := SpecFactory.create_unit(game.map, Vector2i(0, 0))
	var wrecks_before := _wreck_count()

	await game.execute_event(&'event_unit_die', {
		unit = unit,
		flags = [EventService.DIE_FLAG.LEAVES_WRECK],
	})

	assert_gt(_wreck_count(), wrecks_before, 'BASELINE: an unmodified death leaves a wreck on the map.')

func test_probe_2a_the_pre_death_reaction_fires_at_all():
	var unit := SpecFactory.create_unit(game.map, Vector2i(0, 0))
	unit.core.equip_system(P2_STRIP_WRECK_KIT_ID)
	SpecFactory.apply_passive_buffs(unit)

	await game.execute_event(&'event_unit_die', {
		unit = unit,
		flags = [EventService.DIE_FLAG.LEAVES_WRECK],
	})

	var fired:bool = Engine.has_meta(P2_FIRED_META) and bool(Engine.get_meta(P2_FIRED_META))
	assert_true(fired, 'PROBE 2a: the DEATH:PRE reaction fired at all (separate from whether the strip worked).')

func test_probe_2b_stripping_the_flag_prevents_the_wreck():
	var unit := SpecFactory.create_unit(game.map, Vector2i(0, 0))
	unit.core.equip_system(P2_STRIP_WRECK_KIT_ID)
	SpecFactory.apply_passive_buffs(unit)

	var wrecks_before := _wreck_count()

	await game.execute_event(&'event_unit_die', {
		unit = unit,
		flags = [EventService.DIE_FLAG.LEAVES_WRECK],
	})

	assert_eq(_wreck_count(), wrecks_before, 'PROBE 2b: no wreck exists after death -- the strip worked (assert on absence, not the flag).')


# ============================================================================
# PROBE 3 -- does teleport=true, voluntary=false move an IMMOBILIZED unit?
# And (the control) does the SAME move FAIL with voluntary=true?
#
# Kills: clause 6 only. Fallback: drop clause 6, or place the unit directly.
# ============================================================================

func _p3_immobilized_unit() -> Unit:
	var unit := SpecFactory.create_unit(game.map, Vector2i(0, 0))
	SpecFactory.apply(unit, Lancer.STATUS.IMMOBILIZED)
	assert_true(UnitCondition.is_immobilized(unit), 'sanity: unit starts immobilized.')
	return unit

func test_probe_3a_involuntary_teleport_moves_an_immobilized_unit():
	var unit := _p3_immobilized_unit()
	var start_tile := unit.tile()
	var target_tile := Vector2i(2, 2)

	var movement_type := MovementType.new()
	movement_type.teleport = true
	movement_type.voluntary = false

	await SpecFactory.move(game, unit, target_tile, movement_type)

	assert_eq(unit.tile(), target_tile, 'PROBE 3a: an involuntary (voluntary=false) teleport moved an immobilized unit.')
	assert_ne(unit.tile(), start_tile, 'sanity: it actually left its starting tile.')

func test_probe_3b_control_voluntary_teleport_is_blocked_while_immobilized():
	var unit := _p3_immobilized_unit()
	var start_tile := unit.tile()
	var target_tile := Vector2i(2, 2)

	var movement_type := MovementType.new()
	movement_type.teleport = true
	movement_type.voluntary = true

	await SpecFactory.move(game, unit, target_tile, movement_type)

	assert_eq(unit.tile(), start_tile, 'PROBE 3b (control): a VOLUNTARY teleport does NOT move an immobilized unit -- proves the test isolates voluntary, not something else.')

# Lockdown - the second of Quarantine's two Invade options.
#
#   "Your target takes 2 INFECTION instead of Invade's normal heat and cannot take Quick Tech or Full
#    Tech actions until the end of their next turn."
#
# buff_lockdown is `to = action_forbidden` carrying Hacker rank 2's Hack/Slash filter verbatim
# (content/talents/other/t_hacker/rank_2/buff_hack_slash.gd): an action is forbidden when it is an
# ActionAttackTech, or an ActionSystem with is_tech. The gate is UnitAction.get_gear_unavailable_reason's
# last clause (unit_action.gd:157, REASON.FORBIDDEN), which every activation passes through
# (event_gear_activate.gd:33-52) and every reaction passes through twice (reaction_bus.gd:121 as well).
#
# "CANNOT TAKE" ONLY. Vanilla Hack/Slash's own text also says "benefit from" and its code does not
# implement that half either; the mod's row says only what the code does (design section 5).
#
# THE FOUR PROBES, all vanilla and all on a stock player mech's basic loadout except the weapon
# (plan section B4):
#   ms_fragment_signal - an ActionAttackTech invade         -> forbidden
#   ms_scan            - an ActionSystem with is_tech = true -> forbidden
#   ms_stabilize       - an ActionSystem with is_tech false  -> allowed
#   mw_tactical_melee_weapon - an ActionAttackWeapon         -> allowed
# For gear whose sole action has no action_*.tres of its own, Action.get_id() is the KIT id
# (action.gd:90-92), so these are reached with GearCore.get_solo_action() rather than by action id.
#
# DEVIATION (task-4-report.md): test_a_non_tech_system_is_allowed and test_a_weapon_attack_is_allowed
# each gained one extra assertion beyond the brief's text - that ms_fragment_signal (a tech attack) IS
# forbidden on the same locked-down target, in the same test. Task 3's reviewer flagged that an
# "X is still allowed" test with no positive control in the same test cannot tell a working filter from
# an inert buff; the brief's other tests already carry one (test_an_invade_is_refused compares
# before/after, test_a_locked_down_draugr_cannot_use_its_own_invades is end-to-end), so only these two
# needed the addition. Test names and stated purposes are unchanged.
#
# THE FREE-ACTION PROBE (bug fix: buff_lockdown was catching FREE tech too - see buff_lockdown.gd's
# header). Of the three vanilla FREE tech actions (all on ms_h0r_os_system_upgrade_iii), only
# action_dimensional_emblems_deploy reads NONE with no extra setup: action_celestial_shackles_return and
# action_dimensional_emblems_delete both gate on UnitAction.REASON.SPECIFIC (their own
# is_available_to_activate) until something is actually deployed, which would mask FORBIDDEN behind
# SPECIFIC either way and prove nothing about the buff. action_dimensional_emblems_deploy's own gate
# (ActionSystemDeploy.is_available_to_activate) only checks INTANGIBLE and disable_while_deployed, both
# clear on a fresh unit, so it is NONE unlocked and (before the fix) FORBIDDEN locked - a clean RED/GREEN.
# It is also not reachable through GearCore.get_action() / the refusal() helper: it is invoked internally
# by onhit_dimensional_emblems.gd rather than listed in the kit's own `actions` array
# (ms_h0r_os_system_upgrade_iii.tres), so test_the_free_tech_deploy_is_allowed builds its own
# SpecificAction from the loaded .tres instead of going through refusal().
extends GutTest

const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')

const QUARANTINE := &'ms_quarantine'
const ISOLATION := &'action_isolation'
const LOCKDOWN := &'action_lockdown'
const LOCKDOWN_BUFF := &'buff_lockdown'
const DISEASE := &'ms_disease'
const SYMPTOM := &'action_symptom'
const MELEE := &'mw_tactical_melee_weapon'
const FULL_TECH := &'ms_aggressive_system_sync' # excommunicate: a FULL ActionAttackTech
const FULL_TECH_ACTION := &'action_excommunicate'
const FREE_TECH := &'ms_h0r_os_system_upgrade_iii' # dimensional emblems / celestial shackles
const FREE_TECH_DEPLOY_ACTION_PATH := 'res://content/gear/horus/systems/ms_h0r_os_system_upgrade_iii/dimensional_emblems/action_dimensional_emblems_deploy.tres'

var game:Gamemaster
var draugr:Unit
var target:Unit
var quarantine:GearCore

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	draugr = SpecFactory.create_unit(game.map, Vector2i(0, 0), Faction.PLAYER)
	quarantine = draugr.core.equip_system(QUARANTINE)
	draugr.core.full_repair()
	target = SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	target.core.frame.stat.edef = -10 # a cheated 20 always lands
	target.core.frame.stat.heat = 30
	target.core.full_repair()
	target.core.current.heat = 0

func after_each():
	Dice.CHEAT_ROLL_QUEUE.clear()

func lock_down(victim:Unit) -> void:
	Dice.CHEAT_ROLL_QUEUE.append(20)
	await SpecFactory.use(game, draugr, QUARANTINE, LOCKDOWN, victim)

func locks_on(unit:Unit) -> Array[BuffCore]:
	return UnitCondition.get_buffs(unit, LOCKDOWN_BUFF)

## What the engine would give as its reason for refusing this gear's action right now. Defaults to the
## gear's solo action; pass action_id for a kit with more than one action (e.g. FULL_TECH).
func refusal(unit:Unit, kit_id:StringName, action_id:StringName = &'') -> UnitAction.REASON:
	var gear:GearCore = unit.get_gear(kit_id)
	if not GearCore.is_valid(gear): return UnitAction.REASON.DESTROYED # fixture failure; the test says so
	var action:Action = gear.get_action(action_id) if not action_id.is_empty() else gear.get_solo_action()
	if not Action.is_valid(action): return UnitAction.REASON.DESTROYED
	return UnitAction.get_gear_unavailable_reason(SpecificAction.create(unit, gear, action))

func test_lockdown_applies_two_infection_and_none_of_the_invades_own_heat():
	await lock_down(target)
	assert_eq(Infection.count(target), 2, 'Two Infection.')
	assert_eq(target.core.current.heat, 2, 'Two heat, from the Infection alone - not four.')

func test_lockdown_locks_the_target():
	await lock_down(target)
	assert_eq(locks_on(target).size(), 1, 'One buff_lockdown.')
	assert_eq(locks_on(target).front().from_gear, quarantine.persistent_id, 'Attributed to Quarantine.')

func test_a_miss_does_nothing():
	target.core.frame.stat.edef = 30
	target.core.full_repair()
	Dice.CHEAT_ROLL_QUEUE.append(1)
	await SpecFactory.use(game, draugr, QUARANTINE, LOCKDOWN, target)
	assert_eq(Infection.count(target), 0, 'No Infection.')
	assert_true(locks_on(target).is_empty(), 'And no lock.')

func test_an_invade_is_refused():
	assert_eq(refusal(target, &'ms_fragment_signal'), UnitAction.REASON.NONE, 'Available before.')
	await lock_down(target)
	assert_eq(refusal(target, &'ms_fragment_signal'), UnitAction.REASON.FORBIDDEN, 'No tech attacks.')

func test_a_tech_system_is_refused():
	await lock_down(target)
	assert_eq(refusal(target, &'ms_scan'), UnitAction.REASON.FORBIDDEN, 'ms_scan sets is_tech = true.')

func test_a_full_tech_attack_is_refused_too():
	# WHY: buff_hack_slash's filter is "an ActionAttackTech", full stop - not just QUICK ones like
	# ms_fragment_signal. Excommunicate is a vanilla FULL-action ActionAttackTech (action_type = 2) on
	# a kit unrelated to Quarantine, so this proves Lockdown's reach beyond the QUICK case the other
	# tests already cover.
	target.core.equip_system(FULL_TECH)
	target.core.full_repair()
	assert_eq(refusal(target, FULL_TECH, FULL_TECH_ACTION), UnitAction.REASON.NONE, 'Available before.')
	await lock_down(target)
	assert_eq(refusal(target, FULL_TECH, FULL_TECH_ACTION), UnitAction.REASON.FORBIDDEN, 'And forbidden after - FULL, not just QUICK.')
	assert_eq(refusal(target, &'ms_fragment_signal'), UnitAction.REASON.FORBIDDEN, 'Positive control: the QUICK invade is forbidden too, in the same test.')

func test_a_non_tech_system_is_allowed():
	await lock_down(target)
	assert_eq(refusal(target, &'ms_stabilize'), UnitAction.REASON.NONE, 'Stabilize is not tech.')
	assert_eq(refusal(target, &'ms_fragment_signal'), UnitAction.REASON.FORBIDDEN, 'Positive control: a tech attack IS forbidden in this same test.')

func test_a_weapon_attack_is_allowed():
	target.core.equip_system(MELEE)
	target.core.full_repair()
	await lock_down(target)
	assert_eq(refusal(target, MELEE), UnitAction.REASON.NONE, 'It can still swing.')
	assert_eq(refusal(target, &'ms_fragment_signal'), UnitAction.REASON.FORBIDDEN, 'Positive control: a tech attack IS forbidden in this same test.')

func test_a_locked_down_draugr_cannot_use_its_own_invades():
	# The end-to-end proof: event_gear_activate.check_specific_context refuses the activation and
	# prints "[ Gear not available ] reason : FORBIDDEN" (:33-52). ms_disease is tech too.
	target.core.equip_system(DISEASE)
	target.core.full_repair()
	await lock_down(target)
	Dice.CHEAT_ROLL_QUEUE.append(20)
	await SpecFactory.use(game, target, DISEASE, SYMPTOM, draugr)
	assert_eq(Infection.count(draugr), 0, 'Symptom never went off.')

func test_the_lock_survives_the_draugrs_own_turn_end():
	await lock_down(target)
	await SpecFactory.pass_turn(game, draugr)
	assert_eq(locks_on(target).size(), 1, 'turn_count only rises on the HOLDER own turn start.')

func test_the_lock_ends_with_the_targets_next_turn():
	await lock_down(target)
	Dice.CHEAT_ROLL_QUEUE.append(1) # the end-of-turn Infection check fails; irrelevant, but seeded
	await SpecFactory.pass_turn(game, target)
	assert_true(locks_on(target).is_empty(), 'Until the end of their next turn, and no longer.')

func test_the_lock_does_not_survive_the_draugrs_death():
	# D6, mirrored from test_isolation.gd: from_gear is a LIFETIME. event_unit_die.gd's execute()
	# calls UnitCondition.clear_outgoing_buffs_from_unit(core, unit, ..., true), which strips every
	# buff attributed to the dying unit's own gear off every other unit, gated on
	# is_cleared_on_owner_death() (unit_condition.gd:1015-1029) - buff_lockdown never overrides that,
	# so it defaults true. Infection carries no from_gear and must outlive the Draugr that caused it.
	# No core power on this fixture Draugr, so no death reaction complicates it.
	await lock_down(target)
	assert_eq(locks_on(target).size(), 1, 'Locked before the Draugr dies (positive control).')
	await game.execute_event(&'event_unit_die', {unit = draugr})
	assert_true(locks_on(target).is_empty(), 'The lock died with the unit that owned the gear that applied it.')
	assert_eq(Infection.count(target), 2, 'Infection has no from_gear, and survives its source.')

func test_the_free_tech_deploy_is_allowed():
	# See "THE FREE-ACTION PROBE" above for why this is the action of the three that can prove the
	# fix, and why it has to build its own SpecificAction rather than go through refusal().
	var free_tech:GearCore = target.core.equip_system(FREE_TECH)
	target.core.full_repair()
	var deploy_action:Action = load(FREE_TECH_DEPLOY_ACTION_PATH)
	var specific := SpecificAction.create(target, free_tech, deploy_action)
	assert_eq(UnitAction.get_gear_unavailable_reason(specific), UnitAction.REASON.NONE, 'Available before (positive control: proves this probe is not blocked for some other reason).')
	await lock_down(target)
	assert_eq(UnitAction.get_gear_unavailable_reason(specific), UnitAction.REASON.NONE, 'Still available: it is FREE tech, not Quick or Full.')
	assert_eq(refusal(target, &'ms_fragment_signal'), UnitAction.REASON.FORBIDDEN, 'Positive control: a Quick tech invade IS forbidden in this same test.')

func test_isolation_and_lockdown_do_not_share_an_allowance():
	# "Each may be used 1/round" - each, not one of them. Separate usage_groups
	# (gear_core.gd:166-168). Both uses stay inside one turn: a start_turn between them would reset
	# the per-round counter (memory draugr-infection-engine-gotchas item 12) and prove nothing.
	# Two quick actions is exactly a fresh unit's whole pool (Lancer.ACTION_COST_FULL).
	await lock_down(target)
	assert_eq(locks_on(target).size(), 1, 'Lockdown landed.')
	Dice.CHEAT_ROLL_QUEUE.append(20)
	await SpecFactory.use(game, draugr, QUARANTINE, ISOLATION, target)
	assert_eq(UnitCondition.get_buffs(target, &'buff_isolation').size(), 1, 'And Isolation still had its own use.')
	assert_eq(Infection.count(target), 4, 'Two invades, two Infection each.')

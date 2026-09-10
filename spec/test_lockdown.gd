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
extends GutTest

const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')

const QUARANTINE := &'ms_quarantine'
const ISOLATION := &'action_isolation'
const LOCKDOWN := &'action_lockdown'
const LOCKDOWN_BUFF := &'buff_lockdown'
const DISEASE := &'ms_disease'
const SYMPTOM := &'action_symptom'
const MELEE := &'mw_tactical_melee_weapon'

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

## What the engine would give as its reason for refusing this gear's solo action right now.
func refusal(unit:Unit, kit_id:StringName) -> UnitAction.REASON:
	var gear:GearCore = unit.get_gear(kit_id)
	if not GearCore.is_valid(gear): return UnitAction.REASON.DESTROYED # fixture failure; the test says so
	var action:Action = gear.get_solo_action()
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

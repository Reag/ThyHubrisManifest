# The Injector Drill's attack. A heavy melee weapon whose four charges are a fuel tank for the tech
# strike it delivers on a hit, not ammunition for the swing.
#
#   "You may attack with this weapon without expending or requiring charges, and it can be destroyed
#    even with no charges remaining."
#
# ONE OVERRIDE COVERS THE WHOLE FIRST SENTENCE. Action.consumes_charges (action.gd:108) defaults to
# true and is read in exactly two places: unit_action.gd:153 refuses the action with REASON.NO_CHARGES
# when the gear is empty ("without requiring"), and unit_action.gd:274 spends one on every use
# ("without expending"). Vanilla's precedents are one line each - action_turret_attack.gd:11,
# action_recall.gd:43, action_redeploy.gd:42.
#
# THE SECOND SENTENCE IS A KNOWN, RECORDED GAP. UnitPrinter.get_destructable_gear
# (unit_printer.gd:311-320) requires gear.has_charges_left(), so an empty drill is not offered as a
# destruction target, and no mod-side seam on unit_printer.gd has been proven live
# (memory lancer-tactics-dead-extension-seams). Design 2026-09-09-draugr-design.md section 5 accepts
# it for now; spec/test_injector_drill.gd asserts the current behaviour so the gap cannot be forgotten.
#
# The charges are spent by hand in on_hit (task 2).
extends ActionAttackWeapon

func consumes_charges(specific:SpecificAction) -> bool: return false


# ---------------------------------------------------------------- the free tech
#
#   "You may expend a charge to use Invade or a Quick Tech as a free action against the target."
#
# The Monitor Module's shape (action_monitor_module_skirmish.gd:26-55) with two changes:
#   - a CONFIRMATION FIRST. choose_and_use gives a player with exactly one option no prompt at all
#     (common_action_util.gd:657-658), and a plain mech has exactly one (basic Fragment Signal), so
#     without this "you MAY expend a charge" would fire automatically on every hit. confirm_use is also
#     the only one of the two calls that answers for an AI unit rather than opening a request
#     (common_action_util.gd:304-310). Plan decision D2.
#   - the deferred spend takes the CHARGE ONLY. Monitor Module also calls spend_actions to eat its
#     reaction; the drill's attack already paid its own quick action, and calling it again would charge
#     the Draugr twice.
#
# WHY THE CHARGE IS SAFE. The deferred callable is stored on the CHILD activation's context and run by
# UnitAction.spend_actions_gain_heat (unit_action.gd:219) via Context.run_deferred_spend
# (context.gd:42) - i.e. only when the chosen tech actually commits. Cancelling out of its targeting
# costs nothing, which is why there is no refund path here.
#
# WHERE THE TECH RESOLVES. choose_and_use_after_triggering_event walks context.event upwards for
# event_unit_attack_declared (common_action_util.gd:600-608). From a weapon's on_hit that is one hop:
# event_unit_attack carries it in required context, documented at event_unit_attack.gd:20. So the free
# tech is queued at Priority.ATTACK.tertiary_attack and runs AFTER this attack's damage.

const INFO_KEY := 'on_hit' ## the effect row shown in the confirmation brochure

func on_hit(activation:EventCore, attacked_unit:Unit) -> void:
	super.on_hit(activation, attacked_unit) # knockback and thrown bookkeeping; synchronous
	var context := activation.context
	if not Unit.is_valid(attacked_unit): return
	var gear:GearCore = context.gear
	if not GearCore.is_valid(gear) or gear.charges_current <= 0: return
	# NOT context.unit raw: an attack relayed through a targeting proxy carries the PROXY there
	# (action_attack.gd:233), and Unit.get_attacker (unit.gd:276-282) is the engine's own undo.
	var attacker:Unit = context.unit.get_attacker(context) if Unit.is_valid(context.unit) else null
	if not Unit.is_valid(attacker): return

	var options := free_tech_options(attacker, attacked_unit)
	if options.is_empty(): return

	var confirmed:bool = await CommonActionUtil.confirm_use(
		context, [attacked_unit], [], null, Translate.action(gear.kit, self, INFO_KEY, false)
	)
	if activation.abort_without_units([attacker, attacked_unit]): return
	if not confirmed: return

	# DEVIATION FROM THE BRIEF: additional_action_flags must carry AS_FREEBIE. `using` here is the
	# DRILL'S OWN attack action, and ActionAttack.activate already called spend_actions for it
	# (action_attack.gd:260) before on_hit ever runs - so its usage_group already shows one use this
	# turn. Without AS_FREEBIE, event_gear_choose_and_use.check_specific_context re-validates `using`
	# with can_activate_gear(specific, false), which checks is_under_per_turn_limit and fails (the
	# per_turn_soft_limit for a QUICK action is 1, already spent) - the whole queued event aborts
	# silently ("[ ABORT event_gear_choose_and_use ] ... specific: invalid"), before choose_and_use ever
	# runs, so no prompt, no tech, no charge. Reactive Code and the Monitor Module never hit this: their
	# `using` is a REACTION that has not yet been spent at the point they queue it. AS_FREEBIE makes
	# can_activate_gear skip the per-turn/afford checks entirely (unit_action.gd:114), which is correct -
	# the drill already paid its own cost; this queued event is not asking to pay it again.
	CommonActionUtil.choose_and_use_after_triggering_event(
		activation,
		SpecificAction.create(attacker, gear, self),
		options,
		spend_a_charge.bind(gear),
		attacked_unit,
		[Action.FLAG.AS_FREEBIE],
	)

## Every Invade or Quick Tech this attacker could aim at this target right now.
##
## The Goblin's Reactive Code (action_reactive_code.gd:34-42) is the template: tech ATTACKS come from
## UnitRelation.get_tech_attacks_that_can_react_against, which already checks sensor range, elevation,
## targeting, line of sight and availability (unit_relation.gd:254-269); quick tech SYSTEMS have to be
## swept separately, because that helper only looks at ActionAttackTech actions.
##
## Two deliberate deviations from Reactive Code:
##  - THE COST FILTER. The rules say "Invade or a QUICK Tech", so a full-action tech attack is dropped.
##    An invade is Lancer.ACTION.QUICK by default (action_attack_tech.gd:7).
##  - `action is ActionSystem and action.is_tech`, never a bare `action.is_tech`. is_tech is an export
##    on ActionSystem alone (action_system.gd:11); reading it off any other Action is a runtime error.
##    Reactive Code gets away with the bare form only because nothing in vanilla puts a non-system
##    action on a system kit - a mod can.
##
## KNOWN LIMITATION, inherited from Reactive Code and stated rather than hidden: ActionSystem.can_target_unit
## (action_system.gd:53) checks tech immunity but not range, so a quick tech system out of sensor range
## can still be offered. The tech attacks - the common case - are range-checked properly above.
func free_tech_options(attacker:Unit, target:Unit) -> Array[SpecificAction]:
	var options:Array[SpecificAction] = []

	for specific:SpecificAction in UnitRelation.get_tech_attacks_that_can_react_against(attacker, target, true):
		if specific.action.get_action_type(specific) != Lancer.ACTION.QUICK: continue
		options.append(specific)

	for tech_gear:GearCore in attacker.core.loadout.get_all_systems():
		for action:Action in tech_gear.kit.actions:
			if not (action is ActionSystem and action.is_tech): continue
			var specific := SpecificAction.create(attacker, tech_gear, action)
			if action.get_action_cost(specific) != Lancer.ACTION_COST_QUICK: continue
			if not action.can_target_unit(target, specific): continue
			options.append(specific)

	Util.filter(options, func(specific:SpecificAction) -> bool: return UnitAction.is_gear_available(specific, true))
	return options

## choose_and_use's deferred_spend: called (bound to the drill) only when the chosen tech commits.
## Deliberately does NOT call spend_actions - see the header.
func spend_a_charge(_activation:EventCore, _using:SpecificAction, _chosen:SpecificAction, gear:GearCore) -> void:
	if GearCore.is_valid(gear): gear.spend_charge()

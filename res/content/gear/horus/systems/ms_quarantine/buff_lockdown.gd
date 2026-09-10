# Lockdown's lock: "Cannot take Quick Tech or Full Tech actions until the end of your next turn."
# (gear.buff_lockdown.effect - the victim's voice, its own CSV rows, no localization_key_override.)
#
# Hacker rank 2's Hack/Slash filter (content/talents/other/t_hacker/rank_2/buff_hack_slash.gd) PLUS a
# type gate Hack/Slash has no need of. Hack/Slash's own filter is Hack/Slash's filter verbatim; Lockdown
# adds `action_type == QUICK or FULL` because the rules text says "Quick Tech or Full Tech" and the
# engine has real FREE tech that would otherwise be swept up: action_celestial_shackles_return,
# action_dimensional_emblems_deploy, action_dimensional_emblems_delete (all under
# content/gear/horus/systems/ms_h0r_os_system_upgrade_iii/, is_tech = true, action_type = FREE). The
# `action is` clauses are still the two shapes "a tech action" takes in this engine, and testing for
# ActionSystem alone would miss Fragment Signal, the commonest tech in the game. UnitAction.is_tech
# (unit_action.gd:567-571) is the same pair, at gear level.
#
# "FREE ACTION" HERE MEANS THE ACTION'S OWN action_type - Action.get_action_type(specific) - NOT an
# AS_FREEBIE flag on a use of a normally-QUICK/FULL action. An Invade granted as a freebie (the mod's
# own Injector Drill offers one with AS_FREEBIE) still has get_action_type QUICK: AS_FREEBIE only waives
# cost/limit checks in UnitAction.can_activate_gear (unit_action.gd:108-122), it does not change what
# kind of action was taken, so a freebied Invade stays forbidden - correctly, since the rules text does
# not exempt a freebied Quick Tech.
#
# NO REBOOT ACTION, unlike Hack/Slash: the clock ends this one (until = END_OF_NEXT_TURN), which is why
# this .tres sets an `until` where buff_hack_slash.tres does not.
#
# "CANNOT TAKE" ONLY. Vanilla Hack/Slash's rules text also says "benefit from" and its code does not
# implement that half either; the mod's row says only what the code does (design section 5).
#
# The gate this feeds is UnitAction.get_gear_unavailable_reason's last clause (unit_action.gd:157,
# REASON.FORBIDDEN), reached from UnitCondition.has_buff_to -> get_buffs_to -> does_buff_apply
# (unit_condition.gd:833-851), which calls the two methods below in that order.
extends Buff

func is_buff_context_valid_for_passive(core:BuffCore, context:Context) -> bool:
	return (
		context and
		Action.is_valid(context.action)
	)

## TRUE means "this action is forbidden".
func check_if_passive_applies(core:BuffCore, context:Context) -> bool:
	var action:Action = context.action
	var specific := SpecificAction.from_context(context)
	var action_type:Lancer.ACTION = action.get_action_type(specific)
	return (
		(action is ActionAttackTech or (action is ActionSystem and action.is_tech)) and
		(action_type == Lancer.ACTION.QUICK or action_type == Lancer.ACTION.FULL)
	)

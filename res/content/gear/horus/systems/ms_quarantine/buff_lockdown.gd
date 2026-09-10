# Lockdown's lock: "Cannot take Quick Tech or Full Tech actions until the end of your next turn."
# (gear.buff_lockdown.effect - the victim's voice, its own CSV rows, no localization_key_override.)
#
# Hacker rank 2's Hack/Slash filter VERBATIM (content/talents/other/t_hacker/rank_2/buff_hack_slash.gd).
# The two clauses are the two shapes "a tech action" takes in this engine, and testing for ActionSystem
# alone would miss Fragment Signal, the commonest tech in the game. UnitAction.is_tech
# (unit_action.gd:567-571) is the same pair, at gear level.
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
	return (
		action is ActionAttackTech or
		(action is ActionSystem and action.is_tech)
	)

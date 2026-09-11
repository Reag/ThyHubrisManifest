# Isolation's lock: "Cannot take reactions until the end of your next turn."
# (gear.buff_isolation.effect - the victim's voice, its own CSV rows, no localization_key_override.)
#
# The Infiltrator's Ambush filter VERBATIM (content/talents/mobility/t_infiltrator/rank_2/
# buff_ambush_no_reactions.gd). Do not "improve" it: `requires_reaction_available()` is what draws the
# line the rules text draws. It inherits Action.requires_reaction_available -> consumes_reaction
# (action.gd:170) which ActionReaction answers with `consumes_rxn` (action_reaction.gd:58), so real
# reactions - Dig In, Flash Anchor, Overwatch, Brace - are forbidden and free "trait" reactions with
# consumes_rxn = false are not. That is exactly what design section 5 promises.
#
# The gate this feeds is UnitAction.get_gear_unavailable_reason's last clause (unit_action.gd:157,
# REASON.FORBIDDEN), reached from UnitCondition.has_buff_to -> get_buffs_to -> does_buff_apply
# (unit_condition.gd:833-851), which calls the two methods below in that order. EVERY reaction passes
# that gate twice: once when ReactionBus decides whether to queue it at all (reaction_bus.gd:121) and
# again when event_gear_activate re-checks before executing (:33-52).
extends Buff

func is_buff_context_valid_for_passive(core:BuffCore, context:Context) -> bool:
	return SpecificAction.is_valid(SpecificAction.from_context(context))

## TRUE means "this action is forbidden".
func check_if_passive_applies(core:BuffCore, context:Context) -> bool:
	return (context.action is ActionReaction and context.action.requires_reaction_available())

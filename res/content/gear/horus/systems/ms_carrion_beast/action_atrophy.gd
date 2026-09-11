# Atrophy's reaction shell - exists ONLY to give the engine's own reaction machinery something to
# ask about. Atrophy itself is not prompted (see buff_atrophy.gd's header): the buff decides
# eligibility and pays the cost directly in check_if_passive_applies/on_consumption. This resource
# never runs - activate() is never reached, so it is not overridden here.
#
# WHY IT EXISTS AT ALL (Task 3b, 2026-09-10). The rules call Atrophy a reaction, and Isolation's
# "cannot take reactions" gate is UnitAction.get_gear_unavailable_reason's REASON.FORBIDDEN clause
# (unit_action.gd:157), reached via UnitCondition.has_buff_to(unit, Buff.TO.ACTION_FORBIDDEN,
# buff_context) - but that clause needs a context.action that IS an ActionReaction requiring a
# reaction point (buff_isolation.gd:22-23: `context.action is ActionReaction and
# context.action.requires_reaction_available()`). With no Action at all, Isolation could never see
# Atrophy, so an Isolated Draugr kept Atrophying. This resource gives buff_atrophy something to hand
# to UnitAction.get_gear_unavailable_reason, so it asks the SAME question the engine asks before any
# other reaction fires.
#
# NEVER FIRES FROM THE REACTION BUS. triggers_on is empty (see the .tres), so
# LoadoutCore.recalculate's reactions_by_trigger (loadout_core.gd:292-296) never indexes this action
# under any trigger key at all - ReactionBus.trigger_reactions_for_event only ever looks a gear's
# reactions up BY the triggers already collected in that dictionary (reaction_bus.gd:51), so this is
# structurally unreachable from there regardless of what triggers_on_event says. The override below
# is belt-and-braces, in case anything ever calls it directly without going through triggers_on.
#
# NEVER SHOWS IN THE PLAYER-FACING ACTION BAR. gear_bar.gd's collect_gear_actions filters out every
# ActionReaction outright (`action is not ActionReaction`), so simply being one is enough - no
# is_situationally_activated needed, and setting it would also hide Atrophy from the kit tooltip
# (action.gd:342's show_in_tooltip), which is the other half of the point of this file: the CSV rows
# gear.ms_carrion_beast.action_atrophy.name/effect/trigger already exist for exactly this tooltip.
#
# consumes_rxn = true (the ActionReaction default, left untouched here) is load-bearing, not
# decorative: it is what makes requires_reaction_available() true, which is what
# buff_isolation.check_if_passive_applies actually tests. Anything falser and Isolation would ignore
# this the way it already ignores consumes_rxn = false trait reactions like the Balor's Regeneration
# (see test_isolation.gd's test_a_free_trait_reaction_still_fires).
extends ActionReaction

func triggers_on_event(unit:Unit, gear:GearCore, triggering_event:EventCore) -> bool:
	return false

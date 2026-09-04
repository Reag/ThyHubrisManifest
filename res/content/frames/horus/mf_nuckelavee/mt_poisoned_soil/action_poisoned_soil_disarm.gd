# Poisoned Soil, part 4 of 4: an arm cannot outlive the turn that made it.
#
# Real bug from the final review, round 2: the round stamp in passive_poisoned_soil.gd (added for
# finding 1, round 1) bounds a stale arm to the rest of the arming ROUND, not the arming TURN - and
# this game can grant two turns in one round. content/frames/horus/mf_goblin/cp_instinct_rig/
# action_symbiosis_shared_turn.gd drives a linked turn for a fused ally off the host's own turn
# start/end, so a Nuckelavee fused to a Goblin can boost on turn A, never move, end turn A, then take
# a second, LINKED turn B in the SAME round - the round stamp still matches, and a two-space move in
# turn B tracks and lays with no boost behind it. Ours is a turn-scoped effect; the round stamp alone
# is round-scoped, one level too coarse.
#
# Fix: disarm unconditionally whenever OUR OWN turn ends, regardless of whether anything moved. The
# round stamp stays too - belt and braces, and it still covers anything that disarms outside the
# normal turn cycle (e.g. death mid-turn skipping END_TURN entirely).
#
# ActionReactionSelf already restricts triggers_on_event to "the triggering unit is our own owner",
# which is exactly what END_TURN needs here - no further condition to add.
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-03-poisoned-soil-design.md
extends ActionReactionSelf

## Bookkeeping, not an ability the pilot uses - keep it out of the trait's tooltip.
##
## Action.show_in_tooltip returns TRUE for any trait reaction whose KIT carries a trigger row
## (action.gd:343-344), and mt_poisoned_soil has one ("On |Boost|"). Without this override all four
## of the trait's reactions list themselves separately in the tooltip, which is four lines of
## internal machinery the player can neither see nor act on. The trait's own name, effect and
## trigger text still render - they come from the kit, not from these.
##
## Same move as vanilla's action_system_clear_buff.gd:21.
func show_in_tooltip(_kit:Kit) -> bool: return false


const PoisonedSoil := preload('./passive_poisoned_soil.gd')

func activate(context:Context, _activation:EventCore) -> void:
	PoisonedSoil.set_armed(context.gear, false)

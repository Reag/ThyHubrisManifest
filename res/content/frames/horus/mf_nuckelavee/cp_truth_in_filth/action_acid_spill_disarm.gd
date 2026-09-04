# Acid Spill, part 4 of 4: an arm cannot outlive the turn that made it.
#
# The round stamp in passive_acid_spill.gd bounds a stale arm to the rest of the arming ROUND, not
# the arming TURN - and this game can grant two turns in one round. content/frames/horus/mf_goblin/
# cp_instinct_rig/action_symbiosis_shared_turn.gd drives a linked turn for a fused ally off the
# host's own turn start/end, so a Nuckelavee fused to a Goblin could boost on turn A, never move, end
# turn A, then move in a second LINKED turn B in the SAME round with the stamp still matching.
#
# ActionReactionSelf already restricts triggers_on_event to "the triggering unit is our own owner",
# which is exactly what END_TURN needs - no further condition to add.
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-04-acid-spill-design.md
extends ActionReactionSelf

## Bookkeeping, not an ability the pilot uses - keep it out of the core power's tooltip.
func show_in_tooltip(_kit:Kit) -> bool: return false


const AcidSpill := preload('./passive_acid_spill.gd')

func activate(context:Context, _activation:EventCore) -> void:
	AcidSpill.set_armed(context.gear, false)

# The Efficient tag: a core power that is refunded at the end of combat.
#
# Refunds on the unit's next spawn rather than on combat_end, which is how fateofman-imi_alt_frames
# does it for the Tritton's Fusillade. Same net effect - the point of Efficient is that the core
# power is available again for the NEXT scene - and it survives a scene ending in ways that do not
# reach the mech (destroyed, exited, campaign save/load between scenes).
#
# Unconditional rather than flagged: a mech has exactly one core power, so restoring the core point
# on spawn cannot hand back anything that was spent on something else, and Efficient means it should
# be there at the start of every scene regardless.
extends ActionReaction

func triggers_on_event(unit:Unit, gear:GearCore, triggering_event:EventCore) -> bool:
	if triggering_event.context.unit != unit: return false
	return not unit.core.has_core_power

func activate(context:Context, activation:EventCore) -> void:
	context.unit.core.has_core_power = true

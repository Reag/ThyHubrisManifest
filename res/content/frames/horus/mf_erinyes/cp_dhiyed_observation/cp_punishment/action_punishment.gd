# Punishment - the spendable half of DHIYED Observation.
#
# "no action required": this is never clicked. It is spent by the engine when the player accepts the
# offer that buff_punishment makes during a d20 roll (dice.gd:200 calls spend_actions_gain_heat on
# it), and consumes_cp on the .tres is what makes accepting cost the core power.
#
# So it deliberately reports itself unavailable and hides when disabled - it exists to be spent, not
# to be pressed, and a button that did nothing would be misleading. The effect lives in the buff.
extends ActionSystem

func is_available_to_activate(unit:Unit, gear:GearCore) -> bool:
	return false

func activate(context:Context, activation:EventCore) -> void:
	pass # never activated directly; see the note above

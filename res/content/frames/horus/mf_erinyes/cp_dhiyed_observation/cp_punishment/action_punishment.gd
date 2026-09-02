# Punishment - the upgraded half of DHIYED Observation. STUB.
#
# A free action that spends the core power (consumes_cp on the .tres).
#
# TODO: the effect, and the Efficient tag - which has no equivalent anywhere in this engine, so what
# it should do mechanically is still an open question.
#
# Reports itself unavailable while it is a stub: it still appears in the action bar, greyed out, so
# the name and icon can be eyeballed in game, but it cannot be activated. Spending a core power on an
# action that does nothing would be a nasty thing to hand a player mid-verification.
extends ActionSystem

func is_available_to_activate(unit:Unit, gear:GearCore) -> bool:
	return false # TODO: remove once implemented

func activate(context:Context, activation:EventCore) -> void:
	pass # TODO: implement Punishment

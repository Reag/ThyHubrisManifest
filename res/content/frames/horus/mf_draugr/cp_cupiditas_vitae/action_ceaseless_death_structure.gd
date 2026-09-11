# The Ceaseless Death, gain half B.
#
#   "At the start of its turn, it gains 1 Resilience if it has less than 4 structure."
#
# A SEPARATE action from action_ceaseless_death, with its own usage_group, because the two halves
# must not share the engine's per-turn allowance: they are two independent 1/turn effects, and one
# group would mean the start-of-turn point silently cancelled the kill point for the rest of the
# Draugr's own turn. See the plan's decision C3.
#
# Being a separate .tres would normally mean a separate localization row - Translate.action looks up
# gear.<kit>.<action_id>.name (translate.gd:19-28) - and there is none for this one, because the
# rules present both halves as one paragraph under "The Ceaseless Death". So this action never shows
# itself: show_in_tooltip is forced false here and suppress_logging is set in the .tres. Same move as
# action_caustic_earth.gd and vanilla's own action_system_clear_buff.gd:21.
#
# No explicit 1/turn limit is needed or wanted: a turn only starts once, and the "less than 4
# structure" gate is re-read each time. get_per_turn_soft_limit stays at its inherited 99 so that a
# second, granted turn in the same round (linked activations) pays again, which is the natural
# reading of "at the start of its turn".
#
# 4 is the Draugr's own structure maximum and is written as a literal on purpose: the rules say
# "less than 4", not "less than maximum". A future +structure bonus does not widen this window.
extends ActionReaction

const Resilience := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/cp_cupiditas_vitae/resilience.gd')

const STRUCTURE_THRESHOLD := 4

func show_in_tooltip(_kit:Kit) -> bool: return false

# No required-context override: see action_ceaseless_death.gd for why (Task 2).

func triggers_on_event(unit:Unit, gear:GearCore, triggering_event:EventCore) -> bool:
	# event_turn_start also fires virtual NEW_TURN cores for a unit's own deployables
	# (event_turn_start.gd:17-21 and :57-59), so the identity test is not redundant.
	if triggering_event.context.unit != unit: return false
	return unit.core.current.structure < STRUCTURE_THRESHOLD

func activate(context:Context, activation:EventCore) -> void:
	spend_actions(activation)
	Resilience.gain(context.unit, 1)

# TO BEND REALITY - the wrapper. Structurally mirrors content/gear/ipsn/systems/wm_throughbolt_rounds/
# action_throughbolt_line.gd: the variant callable REPLACES the pilot's weapon action with a
# duplicate of this one carrying the original as followup_attack, and this action then runs that
# original inside the same activation.
extends ActionAttackWeapon

@export var followup_attack:ActionAttackWeapon

func activate(context:Context, activation:EventCore) -> void:
	if activation.abort_when(not Action.is_valid(followup_attack)): return
	# Delegate with a context re-pointed at the FOLLOWUP, not the wrapper. SpecificAction.from_context
	# rebuilds specific.action straight from context.action, and that is what event_unit_attack_declared
	# and friends read damage_dice/aim_range/weapon_size/threat/tags from - not from `self`, even though
	# `self` (the object this activate() runs on) is already the followup. Handing the followup our own
	# (wrapper) context would run its targeting and damage resolution against the wrapper's unset
	# defaults instead of the real weapon. Mirrors action_throughbolt_line.gd's followup_context swap.
	var followup_context := Context.clone(context, { action = followup_attack })
	activation.context = followup_context
	await followup_attack.activate(followup_context, activation)

# TO BEND REALITY - the wrapper. Structurally mirrors content/gear/ipsn/systems/wm_throughbolt_rounds/
# action_throughbolt_line.gd: the variant callable REPLACES the pilot's weapon action with a
# duplicate of this one carrying the original as followup_attack, and this action then runs that
# original inside the same activation.
extends ActionAttackWeapon

@export var followup_attack:ActionAttackWeapon

func activate(context:Context, activation:EventCore) -> void:
	if activation.abort_when(not Action.is_valid(followup_attack)): return
	await followup_attack.activate(context, activation)

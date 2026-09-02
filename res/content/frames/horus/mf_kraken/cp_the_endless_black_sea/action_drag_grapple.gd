# Drag To The Depths: Grapple. Behaviour arrives in Task 3.
extends "res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_kraken/cp_the_endless_black_sea/action_drag_to_the_depths.gd"

## Grapple takes no target of its own - the grapple action it routes to does its own targeting.
func get_target_requirements(specific:SpecificAction) -> TargetRequirements:
	if target_requirements_override: return target_requirements_override
	var reqs := TargetRequirements.new()
	reqs.count = 0
	return reqs

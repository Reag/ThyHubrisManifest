# Drag To The Depths: Grapple.
#
#   "While |IMMOBILIZED|, you may expend your base movement to: • |Grapple|."
#
# Routes to the unit's OWN action_grapple through CommonActionUtil.choose_and_use rather than
# reimplementing an attack. That is the vanilla mechanism for one action firing another it does not
# own - Overwatch uses it to pick and fire a weapon - and it buys a genuine contested roll for free.
#
# Two useful things fall out of routing rather than reimplementing:
#   - action_grapple.can_target_unit already strips anyone in the katamari, so only new victims are
#     offered and re-grabbing a prisoner is impossible.
#   - action_grapple.is_jammable() is false, so a jammed Kraken keeps this option, exactly as every
#     other mech keeps Grapple while jammed.
#
# choose_and_use auto-picks when there is one option and a player is driving, so no menu appears,
# and it stamps Action.FLAG.AS_FREEBIE on the grapple, which is what makes it cost no action.
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-02-kraken-design.md
extends "res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_kraken/cp_the_endless_black_sea/action_drag_to_the_depths.gd"

const GRAPPLE_KIT := &'mw_grapple'
const GRAPPLE_ACTION := &'action_grapple'

## Grapple takes no target of its own - the grapple action it routes to does its own targeting.
func get_target_requirements(specific:SpecificAction) -> TargetRequirements:
	if target_requirements_override: return target_requirements_override
	var reqs := TargetRequirements.new()
	reqs.count = 0
	return reqs

## The unit's own basic Grapple, which every mech carries.
func grapple_for(unit:Unit) -> SpecificAction:
	if not Unit.is_valid(unit): return null
	return SpecificAction.from_id(unit, GRAPPLE_KIT, GRAPPLE_ACTION)

func is_available_to_activate(unit:Unit, gear:GearCore) -> bool:
	if not super(unit, gear): return false
	return SpecificAction.is_valid(grapple_for(unit))

func activate(context:Context, activation:EventCore) -> void:
	var specific := SpecificAction.from_context(context)
	var grapple := grapple_for(context.unit)
	if activation.abort_when(not SpecificAction.is_valid(grapple)): return

	# The movement is paid through choose_and_use's deferred spend rather than up front, so backing
	# out of the grapple's own targeting costs the Kraken nothing.
	await CommonActionUtil.choose_and_use(
		activation,
		specific,
		[grapple],
		func(deferred:EventCore, _using:SpecificAction, _chosen:SpecificAction) -> void:
			spend_actions(deferred),
	)

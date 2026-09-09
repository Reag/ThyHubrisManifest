# Script extension on Stabilize: offer the Burn-clearing variant to a unit that has Infection but
# no Burn. The rules tie the two together ("if an action would clear BURN, such as stabilize, it
# also clears INFECTION"); the actual clearing is buff_infection reacting to the stabilize trigger.
# This file only unlocks the button, which vanilla disables on burn <= 0 (action_stabilize.gd:95).
#
# Deliberately does NOT override clear_burn(): its arity differs between 1.3.3 (unit) and 1.4.0
# (unit, activation), and a mismatched override is a parse error that would take this whole
# extension down on one engine. spec/test_infection.gd proves this override runs; an install log
# line is not evidence (CLAUDE.md, "never trust a .gd_ext.gd until a spec proves it").
extends "res://content/gear/basic/ms_stabilize/action_stabilize.gd"

const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')

func get_alternate_actions(specific:SpecificAction, action_flags:Array = []) -> Array[VariantActionGroup]:
	var groups := super.get_alternate_actions(specific, action_flags)
	if not Unit.is_valid(specific.unit) or not Infection.is_infected(specific.unit): return groups
	for group:VariantActionGroup in groups:
		if group.key != &'stabilize_secondary': continue
		for variant:VariantAction in group.list:
			if variant.key != &'burn': continue
			variant.is_disabled = false
			variant.desc = tr('gear.ms_stabilize.burn.effect')
		# vanilla adds "skip" only when every secondary is disabled; burn is live now, so drop it
		for i:int in range(group.list.size() - 1, -1, -1):
			if group.list[i].key == &'skip_secondary': group.list.remove_at(i)
	return groups

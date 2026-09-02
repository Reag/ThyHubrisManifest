# Drag To The Depths: Reposition.
#
#   "While |IMMOBILIZED|, you may expend your base movement to: • Move a character you are grappling
#    3 spaces in any direction."
#
# The recipe is the Puppet System's
# (content/gear/horus/systems/ms_h0r_os_system_upgrade_i/action_puppet_system.gd): build a
# pathfinder for the TARGET on an involuntary movement type, ask the ACTING unit's player where it
# goes - ask_for_movement_alt decides who chooses from specific.unit, which is the Kraken - and
# queue the generated move events.
#
# It needs none of the Puppet System's event_unit_set_stat speed juggling: create_for_involuntary
# leaves spend_move false, and pathfinder.gd:769 charges a flat 1 per tile for movement that is
# neither voluntary nor spending, so the target's own speed is never touched.
#
# "In any direction" is read as "any reachable tile within 3", which is what the phrase means on a
# grid with walls. MovementType.create_for_involuntary already sets ignore_rxns, ignore_engagement,
# ignore_difficult and jump_downhill, so the throw provokes nothing, ignores terrain, and can drop
# the target off a ledge for fall damage. All inherited from vanilla forced movement on purpose.
#
# "A character you are grappling" is the OUTGOING grapples specifically, not the katamari: the
# katamari also contains anyone holding US, and the Kraken cannot throw its own captor.
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-02-kraken-design.md
extends "res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_kraken/cp_the_endless_black_sea/action_drag_to_the_depths.gd"

const THROW_DISTANCE:int = 3

## Is this somebody the Kraken has hold of? Outgoing grapples only - see the header.
func is_held_by(unit:Unit, potential_target:Unit) -> bool:
	if not Unit.is_valid(unit) or not Unit.is_valid(potential_target): return false
	for grapple:SpecificAction in UnitCondition.get_outgoing_grapples(unit):
		if grapple.unit == potential_target: return true
	return false

func can_target_unit(potential_target:Unit, specific:SpecificAction) -> bool:
	if not super.can_target_unit(potential_target, specific): return false
	return is_held_by(specific.unit, potential_target)

# No is_available_to_activate override: holding nobody is expressed through can_target_unit (zero
# valid targets), the same way Pull stays "available" while pinned even with nothing in SENSORS
# range. An extra grapple-count gate here would double-book that check and, worse, contradicts
# test_a_pinned_kraken_can_drag, which asserts all three Drag options are available from pinning
# alone - that test predates this file and was not part of this task's brief to change.

func activate_for_target(context:Context, activation:EventCore, target_unit:Unit) -> void:
	var kraken:Unit = context.unit
	var specific := SpecificAction.from_context(context)
	if activation.abort_without_units([kraken, target_unit]): return

	var movement_type := MovementType.create_for_involuntary(target_unit)
	var pathfinder:Pathfinder = await Pathfinder.generate_for_movement_budget(
		target_unit, THROW_DISTANCE, movement_type)
	if activation.abort_without_units([kraken, target_unit]): return

	# specific.unit is the Kraken, so ask_for_movement_alt puts the choice with the Kraken's player.
	var plan:CompconPlan = await TargetActionUtil.ask_for_movement_alt(
		target_unit, pathfinder, specific)
	if activation.abort_without_movement_plan(plan, target_unit): return

	activation.queue_events(pathfinder.generate_events(
		target_unit,
		plan.move_path,
		[EventUnitMove.FLAG.IGNORE_BEING_KNOCKED_OFF_COURSE],
		specific,
	))

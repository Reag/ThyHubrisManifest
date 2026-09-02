# Drag To The Depths: Pull.
#
#   "While |IMMOBILIZED|, you may expend your base movement to: • Pull a character within |SENSORS|
#    2 spaces towards you (|HULL| save resists)"
#
# The pull itself is the Goliath's Coercive Force
# (content/frames/npc/npcc_goliath/coercive_force/action_coercive_force_goliath.gd), down to the
# involuntary movement type and must_move_max_possible. Two differences: one target rather than a
# burst, and a HULL save in front of it.
#
# "Resists" is read as no movement at all rather than a shortened pull, which is what the word means
# everywhere else in the book.
#
# Any character, hostile or allied. The rules text says "a character" and the save lets an ally
# decline - unlike My Domain, whose hostiles-only rule exists because a blanket auto-grapple would
# spend an ally's reactions without asking.
#
# Range comes from target_range_is_sensors on the resource, so it tracks the statblock.
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-02-kraken-design.md
extends "res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_kraken/cp_the_endless_black_sea/action_drag_to_the_depths.gd"

const PULL_DISTANCE:int = 2

## Strip out anyone immune to the knockback this pull would deal - generate_pull_events performs no
## such check of its own (unlike generate_knockback_events), and event_unit_move.gd exempts the
## primary mover, so nothing downstream catches it. The movement type mirrors the one
## activate_for_target actually moves the target with, so the check matches the movement.
func can_target_unit(potential_target:Unit, specific:SpecificAction) -> bool:
	if not super.can_target_unit(potential_target, specific): return false
	var movement_type := MovementType.create_for_involuntary(potential_target)
	movement_type.must_move_max_possible = true
	return not UnitCondition.is_immune_to_knockback_from(potential_target, specific, movement_type)

func activate_for_target(context:Context, activation:EventCore, target_unit:Unit) -> void:
	var kraken:Unit = context.unit
	var specific := SpecificAction.from_context(context)
	if activation.abort_without_units([kraken, target_unit]): return

	var resisted:bool = await UnitHasecheck.make_save(
		activation, target_unit, specific, Lancer.HASE.HULL, [EventService.SAVE_FLAG.KNOCKBACK])
	if activation.abort_without_units([kraken, target_unit]): return
	if resisted: return

	var movement_type := MovementType.create_for_involuntary(target_unit)
	movement_type.must_move_max_possible = true
	var pull_events := await CommonActionUtil.generate_pull_events(
		target_unit,
		kraken.occupied_tiles(),
		specific,
		movement_type,
		true, # always force landing on arrival, unconditionally - matches Coercive Force's template
		PULL_DISTANCE,
	)
	if activation.abort_without_unit(kraken): return

	activation.queue_events(pull_events)

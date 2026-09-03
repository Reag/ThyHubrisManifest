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

## The movement the pull actually performs, in one place so the immunity check above and the pull
## below can never drift apart - the check only means anything if it is handed the same movement.
##
## A pull is a knockback pointed the other way, and it takes all three of these flags to behave like
## one. Either half alone is inert, which is why they are set together and documented together:
##
##   straight_line + must_move_max_possible are what make event_unit_move.gd:410-414 read a unit in
##   the way as something to CRASH INTO rather than a reason to stop quietly one space short. Vanilla's
##   knockback sets both (common_action_util.gd:118-121) and movement_type.gd:20 says outright that
##   must_move_max_possible "assumes that straight_line is also true". Without them a pull that runs
##   into somebody ends on a silent break, and nothing downstream can react to it.
##
##   can_move_through_enemies is what lets the PLANNER draw the line into that unit's space at all.
##   pathfinder.gd:136 prices an occupied tile at INVALID_COST otherwise, so generate_pull_events hands
##   back a path that stops before the obstruction - and a step never taken is a step never blocked, so
##   the move event has nothing to call a collision. Vanilla's nanobot whip puts the same flag on the
##   same kind of pull (action_nanobot_whip.gd:11). It does not let the target pass THROUGH anybody:
##   event_unit_move stops it at the first body regardless.
func movement_type_for(target_unit:Unit) -> MovementType:
	var movement_type := MovementType.create_for_involuntary(target_unit)
	movement_type.straight_line = true
	movement_type.must_move_max_possible = true
	movement_type.can_move_through_enemies = true
	return movement_type

## Strip out anyone immune to the knockback this pull would deal - generate_pull_events performs no
## such check of its own (unlike generate_knockback_events), and event_unit_move.gd exempts the
## primary mover, so nothing downstream catches it. The movement type mirrors the one
## activate_for_target actually moves the target with, so the check matches the movement.
func can_target_unit(potential_target:Unit, specific:SpecificAction) -> bool:
	if not super.can_target_unit(potential_target, specific): return false
	return not UnitCondition.is_immune_to_knockback_from(
		potential_target, specific, movement_type_for(potential_target))

func activate_for_target(context:Context, activation:EventCore, target_unit:Unit) -> void:
	var kraken:Unit = context.unit
	var specific := SpecificAction.from_context(context)
	if activation.abort_without_units([kraken, target_unit]): return

	var resisted:bool = await UnitHasecheck.make_save(
		activation, target_unit, specific, Lancer.HASE.HULL, [EventService.SAVE_FLAG.KNOCKBACK])
	if activation.abort_without_units([kraken, target_unit]): return
	if resisted: return

	var movement_type := movement_type_for(target_unit)
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

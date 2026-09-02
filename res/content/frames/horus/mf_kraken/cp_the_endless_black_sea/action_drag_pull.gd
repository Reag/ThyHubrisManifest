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

func activate_for_target(context:Context, activation:EventCore, target_unit:Unit) -> void:
	var kraken:Unit = context.unit
	var specific := SpecificAction.from_context(context)
	if activation.abort_without_units([kraken, target_unit]): return

	var resisted:bool = await UnitHasecheck.make_save(activation, target_unit, specific, Lancer.HASE.HULL)
	if activation.abort_without_units([kraken, target_unit]): return
	if resisted: return

	var movement_type := MovementType.create_for_involuntary(target_unit)
	movement_type.must_move_max_possible = true
	var pull_events := await CommonActionUtil.generate_pull_events(
		target_unit,
		kraken.occupied_tiles(),
		specific,
		movement_type,
		true, # force them to land if they were flying and we are not
		PULL_DISTANCE,
	)
	if activation.abort_without_unit(kraken): return

	activation.queue_events(pull_events)

# Poisoned Soil, part 2 of 3: remember each tile actually stepped onto.
#
# STEP rather than reading the path off ENTIRE_MOVEMENT, and this is a correctness choice, not a
# stylistic one. event_unit_move breaks out of its step loop SILENTLY on two of the three ways a
# step can fail - `not is_next_step_possible` (:209) and `not is_next_step_affordable` (:212); only
# a blocked step emits anything. A path read from the event's context would therefore foul tiles the
# Nuckelavee never reached.
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-03-poisoned-soil-design.md
extends ActionReaction

const PoisonedSoil := preload('./passive_poisoned_soil.gd')

func get_required_triggering_context() -> Array[Context.PROP]:
	return [Context.PROP.unit]

func triggers_on_event(unit:Unit, gear:GearCore, triggering_event:EventCore) -> bool:
	if not PoisonedSoil.is_armed(gear): return false
	return triggering_event.context.unit == unit

func activate(context:Context, _activation:EventCore) -> void:
	var gear:GearCore = context.gear
	# POST timing, so the unit is already standing on the new tile.
	var tile:Vector2i = context.unit.tile()
	var pending:Array[Vector2i] = PoisonedSoil.read_pending(gear)
	if pending.has(tile): return # crossing your own trail twice is one fouled tile, not two entries
	pending.append(tile)
	PoisonedSoil.write_pending(gear, pending)

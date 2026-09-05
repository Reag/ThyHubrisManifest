# Acid Spill, part 2 of 4: remember each tile actually stepped onto.
#
# STEP rather than reading the path off ENTIRE_MOVEMENT, and this is a correctness choice:
# event_unit_move breaks out of its step loop SILENTLY on two of the three ways a step can fail
# (:209 and :212); only a blocked step emits anything. A path read from the event's context would
# therefore count tiles the Nuckelavee never reached, and inflate the damage.
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-04-acid-spill-design.md
extends ActionReaction

## Bookkeeping, not an ability the pilot uses - keep it out of the core power's tooltip.
func show_in_tooltip(_kit:Kit) -> bool: return false


const AcidSpill := preload('./passive_acid_spill.gd')

func get_required_triggering_context() -> Array[Context.PROP]:
	return [Context.PROP.unit]

func triggers_on_event(unit:Unit, gear:GearCore, triggering_event:EventCore) -> bool:
	if not AcidSpill.is_armed(gear, triggering_event.context.map.game_core.round_count): return false
	if triggering_event.context.unit != unit: return false
	# A knockback or pull crossing an armed charge is not a charge.
	return AcidSpill.is_voluntary_movement(triggering_event)

func activate(context:Context, _activation:EventCore) -> void:
	var gear:GearCore = context.gear
	# POST timing, so the unit is already standing on the new tile.
	var pending:Array[Vector2i] = AcidSpill.read_pending(gear)
	# NO de-dupe, unlike Poisoned Soil: crossing your own path twice is two steps of distance.
	pending.append(context.unit.tile())
	AcidSpill.write_pending(gear, pending)

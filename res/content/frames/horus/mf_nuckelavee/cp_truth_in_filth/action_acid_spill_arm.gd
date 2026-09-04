# Acid Spill, part 1 of 4: the boost arms the charge.
#
# action_boost.gd does NOT move anything - it is `current.speed += get_boost_speed(unit)` and
# nothing else, with the movement following as a separate action out of a pooled budget. So there is
# no engine notion of "boost distance" to read off, and the path has to be built: arm here, append on
# each STEP, resolve on ENTIRE_MOVEMENT.
#
# Unlike action_poisoned_soil_arm.gd this does NOT seed the buffer with the current tile. The origin
# goes in its own slot, because AoeCalculator.line excludes its origin and the two have to line up.
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-04-acid-spill-design.md
extends ActionReaction

## Bookkeeping, not an ability the pilot uses - keep it out of the core power's tooltip.
## Same move as vanilla's action_system_clear_buff.gd:21.
func show_in_tooltip(_kit:Kit) -> bool: return false


const AcidSpill := preload('./passive_acid_spill.gd')

func get_required_triggering_context() -> Array[Context.PROP]:
	return [Context.PROP.unit]

func triggers_on_event(unit:Unit, _gear:GearCore, triggering_event:EventCore) -> bool:
	# Only our owner's own boost. Every boost on the map reaches this.
	return triggering_event.context.unit == unit

func activate(context:Context, _activation:EventCore) -> void:
	var gear:GearCore = context.gear
	# RESET, not append: two boosts before moving is one charge, not two.
	AcidSpill.write_pending(gear, [] as Array[Vector2i])
	AcidSpill.write_origin(gear, context.unit.tile())
	# Read now, not at resolution: Ramjet's buff_ramjet_boost is UNTIL 3 and could lapse mid-charge.
	AcidSpill.write_boost_speed(gear, UnitAction.get_boost_speed(context.unit))
	AcidSpill.set_armed(gear, true, context.map.game_core.round_count)

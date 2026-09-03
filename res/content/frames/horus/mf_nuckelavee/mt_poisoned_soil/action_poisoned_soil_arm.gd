# Poisoned Soil, part 1 of 3: the boost arms the trail.
#
# action_boost.gd does NOT move anything - it is `current.speed += get_boost_speed(unit)` and
# nothing else, with the movement following as a separate action out of a pooled budget. So there
# is no engine notion of "boost movement" to read off, and "the spaces it moves through" has to be
# built: arm here, append on each STEP, commit on ENTIRE_MOVEMENT.
#
# Seeding with the current tile is deliberate - the designer's rule is that the space the frame
# boosted OUT of is fouled too.
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-03-poisoned-soil-design.md
extends ActionReaction

const PoisonedSoil := preload('./passive_poisoned_soil.gd')

func get_required_triggering_context() -> Array[Context.PROP]:
	return [Context.PROP.unit]

func triggers_on_event(unit:Unit, _gear:GearCore, triggering_event:EventCore) -> bool:
	# Only our owner's own boost. Every boost on the map reaches this.
	return triggering_event.context.unit == unit

func activate(context:Context, _activation:EventCore) -> void:
	var gear:GearCore = context.gear
	PoisonedSoil.write_pending(gear, [context.unit.tile()] as Array[Vector2i])
	PoisonedSoil.set_armed(gear, true)

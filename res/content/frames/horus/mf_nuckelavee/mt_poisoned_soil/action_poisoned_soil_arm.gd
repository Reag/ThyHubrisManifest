# Poisoned Soil, part 1 of 4: the boost arms the trail.
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

## Bookkeeping, not an ability the pilot uses - keep it out of the trait's tooltip.
##
## Action.show_in_tooltip returns TRUE for any trait reaction whose KIT carries a trigger row
## (action.gd:343-344), and mt_poisoned_soil has one ("On |Boost|"). Without this override all four
## of the trait's reactions list themselves separately in the tooltip, which is four lines of
## internal machinery the player can neither see nor act on. The trait's own name, effect and
## trigger text still render - they come from the kit, not from these.
##
## Same move as vanilla's action_system_clear_buff.gd:21.
func show_in_tooltip(_kit:Kit) -> bool: return false


const PoisonedSoil := preload('./passive_poisoned_soil.gd')

func get_required_triggering_context() -> Array[Context.PROP]:
	return [Context.PROP.unit]

func triggers_on_event(unit:Unit, _gear:GearCore, triggering_event:EventCore) -> bool:
	# Only our owner's own boost. Every boost on the map reaches this.
	return triggering_event.context.unit == unit

func activate(context:Context, _activation:EventCore) -> void:
	var gear:GearCore = context.gear
	PoisonedSoil.write_pending(gear, [context.unit.tile()] as Array[Vector2i])
	# Stamped with the round so a boost that never gets followed by a move cannot arm the trail into
	# some later turn - see PoisonedSoil.is_armed.
	PoisonedSoil.set_armed(gear, true, context.map.game_core.round_count)

# Poisoned Soil, part 3 of 3: offer the trail, and commit it.
#
#   "...may turn the spaces it moves through into difficult terrain. This terrain lasts until you
#    create terrain this way again."
#
# One yes/no for the whole path, by the designer's decision - not a per-tile selection. The
# "lasts until you create terrain this way again" clause is the write on line `write_trail` below
# and nothing else: replacing the array IS the expiry, so there is no lifetime to track and no
# cleanup path that can leak.
#
# Declining leaves the previous trail alone. A boost the player does not cash in is not a boost that
# scrubs the ground clean.
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-03-poisoned-soil-design.md
extends ActionReaction

const PoisonedSoil := preload('./passive_poisoned_soil.gd')

func get_required_triggering_context() -> Array[Context.PROP]:
	return [Context.PROP.unit]

func triggers_on_event(unit:Unit, gear:GearCore, triggering_event:EventCore) -> bool:
	if not PoisonedSoil.is_armed(gear, triggering_event.context.map.game_core.round_count): return false
	if triggering_event.context.unit != unit: return false
	# Only the Nuckelavee's own movement offers a trail - a knockback or pull must not prompt the
	# player mid-enemy-turn over ground it was thrown across.
	if not PoisonedSoil.is_voluntary_movement(triggering_event): return false
	# An armed boost the frame never moved off is not a decision worth a prompt. The seeded start
	# tile alone means no step was ever taken.
	return PoisonedSoil.read_pending(gear).size() > 1

func activate(context:Context, activation:EventCore) -> void:
	var gear:GearCore = context.gear
	var trail:Array[Vector2i] = PoisonedSoil.read_pending(gear)

	# Disarm first and unconditionally: whichever way the player answers, this boost is spent. An
	# early return past the disarm would leave the trail armed into the next movement.
	PoisonedSoil.set_armed(gear, false)
	PoisonedSoil.write_pending(gear, [] as Array[Vector2i])

	# Passing the trail as aoe_tiles highlights exactly which ground is about to be fouled.
	var confirmed:bool = await CommonActionUtil.confirm_use(context, [], trail)
	if not confirmed: return

	PoisonedSoil.write_trail(gear, trail)
	# GearCore.set_state does not refresh the map - only set_aura_active does - so the new terrain
	# would not exist until something unrelated happened to trigger a sweep. Ask for one.
	UnitTile.update_tracking_and_statuses(context.unit.map, activation)

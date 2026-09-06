# Copyright (c) 2026 Wickworks ♡ Lancer Tactics v1.3.3
# Clauses 1-2: "After hitting a target with a ranged attack, you may activate your core..."
#
# on_hit ONLY -- never on_crit. event_unit_attack.gd calls apply_on_hits() and THEN
# apply_on_crits() on a critical hit (event_unit_attack.gd:85-93), so anything placed in on_crit
# would run IN ADDITION TO on_hit, not instead of it. Task 2 reads the crit off the attack summary
# instead of on_crit.
#
# The ranged gate lives on buff_mourning_call.tres (BuffWeaponTypeOnHit.weapon_types_forbidden =
# [MELEE]) -- by the time this effect runs, that filter has already passed.
extends OnHitEffect

const KEENING_KIT_ID := &'cp_the_keening'
const MOURNING_CALL_ACTION_ID := &'action_mourning_call'

func on_hit(activation:EventCore, attacked_unit:Unit) -> void:
	var unit:Unit = activation.context.unit
	if not Unit.is_valid(unit): return

	var mourning_call := SpecificAction.from_id(unit, KEENING_KIT_ID, MOURNING_CALL_ACTION_ID)
	if not SpecificAction.is_valid(mourning_call): return

	# Don't ask the player to pay a core point for a teleport that cannot happen. The teleport
	# itself is Task 2's job; this only needs the check so the prompt is honest.
	if not _has_free_adjacent_tile(unit, attacked_unit): return

	var confirmed:bool = await choice_bus.quick_yesno(
		unit.tile(),
		tr('battle.confirm.use').format({action = Translate.action(mourning_call.gear.kit, mourning_call.action, 'name')})
	)
	if not Unit.is_valid(unit) or not confirmed: return

	await CommonActionUtil.choose_and_use(activation, mourning_call, [mourning_call])

# The teleport lands next to the TARGET, not next to the Banshee -- so the check has to walk
# target_unit's neighbours, not teleporting_unit's. (This was Defect 1: the old code checked
# teleporting_unit's own neighbours, which is nearly always free at ranged distance and
# validated nothing.)
#
# If teleporting_unit is ALREADY adjacent to target_unit, one of target_unit's adjacent tiles is
# teleporting_unit's own current tile. Occupation.calculate_for explicitly excludes a unit from
# blocking its own current tile (pathfinder.gd's "other_unit == unit: return false"), so that
# tile still reads as standable and this correctly returns true -- the teleport is then a no-op
# rather than "impossible", which is the right call: the Banshee doesn't need a free tile to
# stay exactly where it already is. Occupying_size (2+ frames) is likewise already handled by
# Occupation/is_tile_standable, so no extra size-specific logic is needed here.
func _has_free_adjacent_tile(teleporting_unit:Unit, target_unit:Unit) -> bool:
	var movement_type := MovementType.create_for_involuntary(teleporting_unit)
	movement_type.teleport = true
	var katamari := Katamari.create(teleporting_unit)
	for tile:Vector2i in UnitTile.get_adjacent_tiles(target_unit):
		if Pathfinder.is_tile_standable(teleporting_unit, tile, movement_type, katamari): return true
	return false

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
	if not _has_free_adjacent_tile(unit): return

	var confirmed:bool = await choice_bus.quick_yesno(
		unit.tile(),
		tr('battle.confirm.use').format({action = Translate.action(mourning_call.gear.kit, mourning_call.action, 'name')})
	)
	if not Unit.is_valid(unit) or not confirmed: return

	await CommonActionUtil.choose_and_use(activation, mourning_call, [mourning_call])

func _has_free_adjacent_tile(unit:Unit) -> bool:
	var movement_type := MovementType.create_for_involuntary(unit)
	movement_type.teleport = true
	var katamari := Katamari.create(unit)
	for tile:Vector2i in UnitTile.get_adjacent_tiles(unit):
		if Pathfinder.is_tile_standable(unit, tile, movement_type, katamari): return true
	return false

# Acid Spill: the integrated weapon itself.
#
# An Integrated Weapon of type MAIN MELEE, firing a BURST 1 centred on the Nuckelavee for ENERGY
# equal to half the distance charged. It rolls to hit normally and catches everyone in the burst,
# allies included - a self-centred area effect does not pick sides.
#
# The self-centred burst shape is copied from vanilla's mw_annihilation_nexus: range_pattern plus a
# target_requirements_override with can_target_units false and can_target_empty_tiles true.
# ActionAttackWeapon.can_target_unit already keeps the frame itself out of its own burst
# (action_attack_weapon.gd:229-230).
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-04-acid-spill-design.md
extends ActionAttackWeapon

const AcidSpill := preload('./passive_acid_spill.gd')

## DISABLED outside its window, not merely unoffered - and this is the designer's explicit
## instruction, for containment rather than tidiness.
##
## unit_action.gd:156 consults this inside get_gear_unavailable_reason, yielding REASON.SPECIFIC.
## That one function backs UnitAction.is_gear_available, which backs the action bar, ai_action_decider,
## the followup-attack path in action_attack_weapon.gd, and UnitRelation.is_weapon_available_as_a_rxn.
## Gating inside action_acid_spill_fire.gd alone would have left every one of those routes open: a
## free-action weapon that reports itself available is what an unexamined third-party reaction
## ("fire an available weapon as a free action") goes looking for.
##
## The damage clause doubles as the zero-damage guard - boost, move one tile, and there is nothing
## worth offering.
func is_available_to_activate(unit:Unit, gear:GearCore) -> bool:
	if not super.is_available_to_activate(unit, gear): return false
	if not Unit.is_valid(unit) or unit.map == null: return false
	if not AcidSpill.is_armed(gear, unit.map.game_core.round_count): return false
	return AcidSpill.damage_for(gear) >= 1

## "deals damage equal to half the distance moved" - a flat number, not dice. The engine accepts a
## bare integer string here; vanilla uses the same form for self_heat_dice ("2").
func get_damage_dice(gear:GearCore = null) -> String:
	if not GearCore.is_valid(gear): return ''
	return str(AcidSpill.damage_for(gear))

## Acid Spill is designer-specified as a FREE action, usable only in the window after a boost - not
## an offered choice, a consequence of how it arms. ActionAttackWeapon.get_action_type
## (action_attack_weapon.gd:87-91) computes the type from weapon_size instead, returning QUICK for
## anything short of SUPERHEAVY, and exposes no field to pin it - so the scaffold stub's
## `action_type = 3` (Lancer.ACTION.FREE) pin was silently lost when the stub was replaced with this
## real ActionAttackWeapon. Restored here by override.
##
## This is load-bearing past the tooltip and the 0-vs-1 action cost: Action.can_be_used_while_dazed
## (action.gd:114) keys directly off get_action_type() == Lancer.ACTION.QUICK, so leaving this unset
## would let a DAZED mech fire Acid Spill when a genuine free action must not be usable.
func get_action_type(specific:SpecificAction) -> Lancer.ACTION:
	return Lancer.ACTION.FREE

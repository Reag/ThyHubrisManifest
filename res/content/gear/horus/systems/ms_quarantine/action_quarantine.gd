# Quarantine's Invade options. ONE script, two .tres: action_isolation.tres and action_lockdown.tres
# differ only in `usage_group` and `lock_buff`, so there is one place to fix an ordering bug rather
# than two (plan decision D4). The two BUFFS are separate scripts, because their filters differ.
#
#   Isolation: "Your target takes 2 INFECTION instead of Invade's normal heat and cannot take
#              reactions until the end of their next turn."
#   Lockdown:  "... and cannot take Quick Tech or Full Tech actions until the end of their next turn."
#
# EACH .tres MUST KEEP ITS OWN usage_group. Per-round counters key on the usage group, defaulting to
# the KIT id (gear_core.gd:166-168), so without one Isolation and Lockdown share a single 1/round
# allowance and using either locks out both - memory kit-actions-share-a-round-allowance, and the trap
# the Erinyes documents at action_face_thy_judgement.gd:26-31. Vanilla's own two-invade system
# (ms_h0r_os_system_upgrade_i) has exactly that bug. The cap is get_per_round_hard_limit and not the
# per-turn one, because ActionAttackTech turns the per-turn limit off for invades
# (action_attack_tech.gd:13-15).
#
# get_damage_dice -> '' is "instead of Invade's normal heat": ActionAttackTech.get_damage_dice (:17)
# returns '2' for every invade, and that is the heat this replaces.
#
# THE LOCK IS APPLIED HERE AND NOT FROM AN OnHitEffect (plan decision D5): the rules say the target
# takes the Infection AND is locked, in that order, and both belong in one readable function.
#
# THE LOCK CARRIES from_gear AND THE INFECTION DOES NOT (plan decision D6). That is deliberate, not an
# oversight copied wrong: a from_gear attribution is a lifetime - the engine clears attributed buffs
# when the owner dies (event_service.gd:71) or the gear is destroyed (event_gear_destroy.gd:42). For a
# one-turn tech lock that is the RIGHT rule ("the Draugr that locked you down is dead, so act"), while
# Infection is a plague that must outlive its source. It also makes a re-application from the same
# Quarantine REFRESH the lock rather than stack it (unit_condition.gd:741-747), which is why there is
# no duplicate guard below.
extends ActionAttackTech

const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')

const INFECTION_APPLIED:int = 2

## buff_isolation or buff_lockdown; set per .tres. Empty means "no lock", which is a broken resource.
@export var lock_buff:StringName = &''

func get_damage_dice(gear:GearCore = null) -> String: return ''
func get_per_round_hard_limit(specific:SpecificAction) -> int: return 1

func on_hit(activation:EventCore, attacked_unit:Unit) -> void:
	var context := activation.context
	if not Unit.is_valid(attacked_unit): return

	await Infection.apply(activation, attacked_unit, INFECTION_APPLIED)
	if activation.abort_without_unit(attacked_unit): return
	# apply() refuses tech-immune targets, and this is a tech lock: if the Infection did not land, the
	# target is beyond the reach of both halves of the effect.
	if not Infection.is_infected(attacked_unit): return
	if lock_buff.is_empty(): return

	UnitCondition.apply_buff_id(activation, attacked_unit, lock_buff, context.gear)

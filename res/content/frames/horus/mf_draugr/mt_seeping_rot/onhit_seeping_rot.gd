# The Seeping Rot. "When the Draugr triggers OVERKILL, the target gains 1 INFECTION."
#
# on_resolution, not on_hit, because overkill does not EXIST yet at on_hit time. The per-target
# event_unit_attack events (which is where on_hit/on_crit run, event_unit_attack.gd:83-93) all
# resolve BEFORE event_unit_attack_declared rolls any damage at :88-91, and it is that roll which
# calls action.apply_overkill and fills in overkill_heat_on_hit / _on_crit
# (action_attack_weapon.gd:259-265). apply_on_resolutions runs at :212-215, after the damage events
# at :199 - the same slot Mourning Call uses, and for the same reason.
#
# One Infection PER OVERKILLING ROLL, applied to that roll's own target: a blast can overkill several
# characters in one declared attack, and each of them "is the target" for its own roll. The rolls and
# their per-roll damage summaries both live on the DeclaredAttackSummary
# (declared_attack_summary.gd:15, attack_roll.gd:9; the summary is assigned to every roll at
# event_unit_attack_declared.gd:145).
#
# The hit / crit / maximized branch mirrors the engine's own accounting at
# event_unit_attack_declared.gd:131-134 exactly: a MISSED roll still carries a damage summary with
# overkill heat in it, and a MAXIMIZED roll deliberately produces none.
#
# Reading roll.damage rather than recomputing means this also counts overkill ticks that came from
# per-roll bonus damage (rolled into the same summary at :288). The engine bills those separately at
# :143 but into the same heat total; either way the answer to "did this roll overkill" is the same.
extends OnHitEffect

const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')

func on_resolution(activation:EventCore) -> void:
	var context := activation.context
	if not Unit.is_valid(context.unit): return
	if not DeclaredAttackSummary.is_valid(context.resource): return
	var declared:DeclaredAttackSummary = context.resource

	for roll:AttackRoll in declared.attack_rolls:
		if not AttackRoll.is_valid(roll): continue
		if not roll.hit or roll.maximized: continue
		if not AttackUtil.DamageRollSummary.is_valid(roll.damage): continue
		var heat:int = roll.damage.get_overkill_heat_on_crit() if roll.crit else roll.damage.get_overkill_heat_on_hit()
		if heat <= 0: continue
		await Infection.apply(activation, roll.target_unit, 1)
		if activation.abort_if_level_exited(): return

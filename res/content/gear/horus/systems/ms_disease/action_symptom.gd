# Symptom - Disease's first Invade option.
#
#   "Your target takes 2 INFECTION instead of Invade's normal heat. Choose one tech effect currently
#    affecting the target that lasts until the end of their next turn (other than STUNNED). That
#    effect instead lasts until the target clears INFECTION."
#
# THE .tres GIVES THIS ACTION ITS OWN usage_group AND IT MUST KEEP IT. Per-round counters key on the
# usage group, defaulting to the KIT id (gear_core.gd:166-168), so without it Symptom and Spreader
# share one 1/round allowance and using either locks out both. Vanilla's own two-invade system has
# exactly that bug (ms_h0r_os_system_upgrade_i); the trap is documented at
# action_face_thy_judgement.gd:26-31. The cap is get_per_round_hard_limit and not the per-turn one,
# because ActionAttackTech turns the per-turn limit off for invades (action_attack_tech.gd:13-15).
#
# get_damage_dice -> '' is "instead of Invade's normal heat": ActionAttackTech.get_damage_dice (:17)
# returns '2' for every invade, and that is the heat this replaces.
extends ActionAttackTech

const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')
const InfectionLinks := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection_links.gd')
const Compat := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/reag_compat.gd')

const INFECTION_APPLIED:int = 2

func get_damage_dice(gear:GearCore = null) -> String: return ''
func get_per_round_hard_limit(specific:SpecificAction) -> int: return 1

func on_hit(activation:EventCore, attacked_unit:Unit) -> void:
	var context := activation.context
	if not Unit.is_valid(attacked_unit): return
	# NOT context.unit raw: an attack relayed through a targeting proxy carries the PROXY there
	# (action_attack.gd:233), and Unit.get_attacker (unit.gd:276-282) is the engine's own undo.
	var draugr:Unit = context.unit.get_attacker(context) if Unit.is_valid(context.unit) else null
	if not Unit.is_valid(draugr): return

	await Infection.apply(activation, attacked_unit, INFECTION_APPLIED)
	if activation.abort_without_units([draugr, attacked_unit]): return
	# apply() refuses tech-immune and dead targets, so there may be no Infection to bind to.
	if not Infection.is_infected(attacked_unit): return

	var bindable := bindable_effects(draugr, attacked_unit)
	if bindable.is_empty(): return

	var chosen = await choose_effect(draugr, attacked_unit, bindable)
	if activation.abort_without_units([draugr, attacked_unit]): return
	if chosen == null: return
	InfectionLinks.link(attacked_unit, chosen)

## Every tech effect on the target that is due to expire at the end of its NEXT turn.
##
## Face Thy Judgement's enumeration (action_face_thy_judgement.gd:78-96) with two changes: the window
## is the next turn rather than this one (InfectionLinks.expires_at_end_of_next_turn), and effects
## already bound to this Infection are dropped so a second Symptom cannot "bind" the same thing twice.
##
## Statuses and buffs both count. "The effect of a tech action" covers both, and most of what tech
## gear does lands as a buff rather than a status.
func bindable_effects(draugr:Unit, target:Unit) -> Array:
	var bindable:Array = []

	for status:StatusCondition in target.state.statuses:
		if status.type == Lancer.STATUS.STUNNED: continue # the one exclusion the rules name
		if not InfectionLinks.expires_at_end_of_next_turn(status): continue
		if InfectionLinks.is_linked(target, status): continue
		if not came_from_a_tech_action(draugr, status.source): continue
		bindable.append(status)

	for buff:BuffCore in target.state.buffs:
		if buff.base.applies_statuses.has(Lancer.STATUS.STUNNED): continue # would bind STUNNED by proxy
		if not InfectionLinks.expires_at_end_of_next_turn(buff): continue
		if InfectionLinks.is_linked(target, buff): continue
		if not came_from_a_tech_action(draugr, buff.from_gear): continue
		bindable.append(buff)

	return bindable

## A status or buff records the persistent id of the GEAR behind it, not the action, so this is a
## gear-level approximation - the same one the Erinyes makes and documents at
## action_face_thy_judgement.gd:170-184. UnitAction.is_tech is delegated to rather than hand-rolled
## because "a tech action" has two shapes in the engine and testing for ActionSystem alone misses
## Fragment Signal, the commonest tech in the game.
func came_from_a_tech_action(draugr:Unit, source_id:StringName) -> bool:
	if source_id.is_empty(): return false
	if not is_instance_valid(draugr.map): return false
	var source_gear:GearCore = draugr.map.get_gear_by_id(source_id)
	if not GearCore.is_valid(source_gear): return false
	return UnitAction.is_tech(source_gear)

func effect_name(effect) -> String:
	if effect is StatusCondition: return X.tr(StatusType.name(effect.type))
	return effect.name_text()

## "Choose one" is mandatory, not a "you may" - so this is a menu with no cancel rather than a
## confirm, and it opens even for a single option so the player learns WHICH effect got bound
## (plan decision D3). The AI is never prompted and takes the first, the way this mod's own
## onhit_spreading_stain.gd:89-96 does.
func choose_effect(draugr:Unit, target:Unit, bindable:Array):
	if not draugr.is_player_controlled(): return bindable.front()
	var names:Array[String] = []
	for effect in bindable: names.append(effect_name(effect))
	var specific := SpecificAction.create(draugr, draugr.get_gear(&'ms_disease'), self)
	var chosen_index:int = await Compat.multiple_choice(
		specific,
		names,
		Translate.gear('ms_disease', 'action_symptom.name'),
		Translate.gear('ms_disease', 'action_symptom.effect'),
		'',
		false, # can_cancel: the rules say "choose one"
	)
	if chosen_index < 0 or chosen_index >= bindable.size(): return null
	return bindable[chosen_index]

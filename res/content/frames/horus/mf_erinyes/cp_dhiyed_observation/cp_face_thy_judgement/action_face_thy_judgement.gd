# Face Thy Judgement - the basic half of DHIYED Observation.
#
#   "When the effect of a tech action expires at the end of a chained character's turn within
#    SENSORS, you may extend its duration to the end of that character's next turn instead. This
#    cannot be used to extend the duration of STUNNED. An effect cannot be extended more than once."
#
# Reacts to END_TURN at PRE timing rather than to the status being removed. That is what makes the
# whole thing tractable:
#
#   - event_turn_end.gd fires END_TURN/PRE at line 17, and only clears expiring statuses at line 40,
#     so at PRE the effects that are about to expire are still on the unit and inspectable.
#   - A StatusCondition records its own `until`, so "expires at the end of this turn" is exactly
#     until == END_OF_THIS_TURN. No guessing.
#
# The alternative - reacting to STATUSES_CHANGED when the status is removed - cannot work: the
# virtual event reactions receive (unit_condition.gd:216) omits the `until` that on_status_clear
# knows, so a reaction there cannot tell an effect that expired from one somebody deliberately
# cleared. That gap is why the ability's wording was moved to "expires at the end of ... turn".
#
# "The effect of a tech action" covers BOTH statuses and buffs. Most of what tech gear does lands as
# a buff rather than a status - the Erinyes' own Viral Logic Suite included - and by the same reading
# a beneficial tech buff on a chained ally is extendable too. The two are tracked and expired
# differently, so see extendable_effects and extend for how each is handled.
extends ActionReaction

const CHAIN_BUFF_ID := &'buff_bind_thy_flesh'
const ANCHOR_KEY := 'anchor'
## Effects we already extended, as "<key>@<round>" where key is "<unit id>|status|<type>" or
## "<unit id>|buff|<instance id>". See keys_already_extended for why the round rides along.
const EXTENDED_KEY := 'ftj_extended'

func get_required_triggering_context() -> Array[Context.PROP]:
	return [Context.PROP.unit]

func triggers_on_event(unit:Unit, gear:GearCore, triggering_event:EventCore) -> bool:
	var ending_unit:Unit = triggering_event.context.unit
	if not Unit.is_valid(ending_unit) or ending_unit == unit: return false
	if not is_chained_to_us(ending_unit, unit): return false
	if not is_in_sensors(unit, ending_unit): return false
	return not extendable_effects(unit, gear, ending_unit).is_empty()

## Chained to a shackle of ours that is still standing - the same test Know Thy Sins makes.
func is_chained_to_us(chained_unit:Unit, erinyes:Unit) -> bool:
	if not is_instance_valid(erinyes.map): return false
	for buff:BuffCore in chained_unit.state.buffs:
		if buff.base.compcon_id != CHAIN_BUFF_ID: continue
		var anchor := erinyes.map.get_unit_by_id(StringName(buff.get_state(ANCHOR_KEY, '')))
		if not Unit.is_valid(anchor): continue
		if anchor.get_owner_unit() == erinyes: return true
	return false

func is_in_sensors(erinyes:Unit, other:Unit) -> bool:
	return UnitRelation.distance_between(erinyes, other) <= erinyes.get_sensor_range()

func extension_key(unit:Unit, effect) -> String:
	if effect is StatusCondition: return '%s|status|%s' % [unit.core.persistent_id, effect.type]
	return '%s|buff|%s' % [unit.core.persistent_id, effect.persistent_id]

func effect_name(effect) -> String:
	if effect is StatusCondition: return X.tr(StatusType.name(effect.type))
	return effect.name_text()

## Everything on this unit that is about to expire and that we are allowed to extend.
##
## Entries are StatusCondition OR BuffCore. The engine tracks the two separately and expires them by
## different rules, but "the effect of a tech action" covers both - most of what tech gear actually
## does lands as a buff, the Erinyes' own Viral Logic Suite included, and a beneficial tech buff on a
## chained ally is extendable by the same reading.
func extendable_effects(erinyes:Unit, gear:GearCore, ending_unit:Unit) -> Array:
	var extendable:Array = []
	var already_extended := keys_already_extended(erinyes, gear)

	for status:StatusCondition in ending_unit.state.statuses:
		if status.until != Lancer.UNTIL.END_OF_THIS_TURN: continue # not expiring now
		if status.type == Lancer.STATUS.STUNNED: continue # explicitly excluded by the ability
		if already_extended.has(extension_key(ending_unit, status)): continue
		if not came_from_a_tech_action(erinyes, status.source): continue
		extendable.append(status)

	for buff:BuffCore in ending_unit.state.buffs:
		if not is_expiring_now(buff): continue
		if buff.base.applies_statuses.has(Lancer.STATUS.STUNNED): continue # would extend STUNNED by proxy
		if already_extended.has(extension_key(ending_unit, buff)): continue
		if not came_from_a_tech_action(erinyes, buff.from_gear): continue
		extendable.append(buff)

	return extendable

## "An effect cannot be extended more than once" means one EFFECT - not one status type forever.
##
## A StatusCondition carries nothing that tells one application apart from the next, so a status key
## can only be "<unit>|status|<type>" and a LATER, unrelated application of that status collides with
## it. Left alone, an Erinyes that extended Impaired on a target in round 1 could never extend
## Impaired on that target again for the rest of the scene, and the ability just stopped offering.
## Reported from play.
##
## Records therefore carry the round they were made in, and a record is dropped once it cannot
## possibly still describe a live effect. An extension buys exactly one more turn, so the effect is
## gone by the end of the character's next turn - one round later at the outside. A record older than
## that is stale by construction, whatever is on the unit now.
##
## Both halves are needed. The round bound alone would keep blocking a re-application inside the same
## round; the "is it still there" test alone never fires, because it is only ever reached for a
## chained unit in sensors and by then the NEW status of the same type is already on the unit, which
## reads as the old one still being alive. That is the bug this replaced.
##
## Known gap, and small enough to accept: a status cleared early and re-applied to the same character
## within one round of an extension still reads as the same effect, and is not offered.
func keys_already_extended(erinyes:Unit, gear:GearCore) -> Array[String]:
	var this_round := current_round(erinyes)
	var kept_records:Array[String] = []
	var kept_keys:Array[String] = []
	for record:String in gear.get_state_string_array(EXTENDED_KEY):
		var split := record.rsplit('@', true, 1)
		if split.size() != 2: continue # malformed; drop it
		if this_round - int(split[1]) > 1: continue # cannot still be the same effect
		if not is_effect_still_present(erinyes, split[0]): continue
		kept_records.append(record)
		kept_keys.append(split[0])
	gear.set_state(EXTENDED_KEY, kept_records)
	return kept_keys

func current_round(erinyes:Unit) -> int:
	if not is_instance_valid(erinyes.map): return 0
	if not GamemasterCore.is_valid(erinyes.map.game_core): return 0
	return erinyes.map.game_core.round_count

func is_effect_still_present(erinyes:Unit, key:String) -> bool:
	var parts := key.split('|')
	if parts.size() != 3: return false
	if not is_instance_valid(erinyes.map): return false
	var unit := erinyes.map.get_unit_by_id(StringName(parts[0]))
	if not Unit.is_valid(unit): return false
	if parts[1] == 'status':
		for status:StatusCondition in unit.state.statuses:
			if String(status.type) == parts[2]: return true
		return false
	for buff:BuffCore in unit.state.buffs:
		if String(buff.persistent_id) == parts[2]: return true
	return false

## Mirrors end_turn_for_statuses: a buff's duration is the shared resource's `until` combined with
## the per-instance turn_count, not a value of its own.
func is_expiring_now(buff:BuffCore) -> bool:
	match buff.base.until:
		Lancer.UNTIL.END_OF_THIS_TURN: return buff.turn_count >= 0
		Lancer.UNTIL.END_OF_NEXT_TURN: return buff.turn_count >= 1
	return false

## Buy the effect exactly one more turn.
##
## A status carries its own `until`, so it is set forward to END_OF_NEXT_TURN. A buff's `until` lives
## on the shared resource and must not be touched - every other copy of that buff in the game reads
## it - so the per-instance turn_count is walked back one instead. Either way end_turn_for_statuses
## then lets it through this turn, new_turn_for_statuses ticks it on, and it expires at the end of the
## character's next turn.
func extend(effect) -> void:
	if effect is StatusCondition: effect.until = Lancer.UNTIL.END_OF_NEXT_TURN
	else: effect.turn_count -= 1

## A status or buff records the persistent id of the GEAR behind it, not the action, so this is a
## gear-level approximation: a piece of gear carrying both a tech action and a non-tech one would
## read as tech either way. Rare enough to accept, and noted rather than hidden.
##
## Delegates to UnitAction.is_tech rather than testing the actions here, because "a tech action" has
## TWO shapes in the engine and hand-rolling the check caught only one. A tech ATTACK is an
## ActionAttackTech, which descends from ActionAttack, not from ActionSystem - so an
## `action is ActionSystem and action.is_tech` test reads Fragment Signal, the commonest tech in the
## game, as non-tech. Reported from play: a chained enemy hit with Fragment Signal ended its turn and
## the reaction was never offered.
func came_from_a_tech_action(erinyes:Unit, source_id:StringName) -> bool:
	if source_id.is_empty(): return false
	var source_gear:GearCore = erinyes.map.get_gear_by_id(source_id)
	if not GearCore.is_valid(source_gear): return false
	return UnitAction.is_tech(source_gear)

func activate(context:Context, activation:EventCore) -> void:
	var erinyes:Unit = context.unit
	var gear:GearCore = context.gear
	var ending_unit:Unit = context.event.context.unit
	var extendable := extendable_effects(erinyes, gear, ending_unit)
	if activation.abort_when(extendable.is_empty()): return

	var chosen = await choose_effect(context, ending_unit, extendable)
	if activation.abort_when(chosen == null): return

	spend_actions(activation)

	extend(chosen)
	gear.append_to_array_state(EXTENDED_KEY, '%s@%d' % [extension_key(ending_unit, chosen), current_round(erinyes)])

## The ability extends "the effect", singular, and is a 1/round reaction - so when several tech
## effects expire at once the player picks which one. Cancelling is how "you may" is declined.
func choose_effect(context:Context, ending_unit:Unit, extendable:Array):
	if extendable.size() == 1:
		var confirmed:bool = await CommonActionUtil.confirm_use(context, [ending_unit], [])
		return extendable.front() if confirmed else null

	var names:Array[String] = []
	for effect in extendable: names.append(effect_name(effect))
	var specific := SpecificAction.from_context(context)
	var chosen_index:int = await choice_bus.choose_from_multiple_choice(
		names,
		specific.action.name(specific),
		specific.action.effect_text(specific),
	)
	if chosen_index < 0 or chosen_index >= extendable.size(): return null
	return extendable[chosen_index]

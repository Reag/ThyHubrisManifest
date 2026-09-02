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
# Extending is a one-line mutation of the status, which is precisely how the engine itself handles
# durations: new_turn_for_statuses walks a unit's statuses at turn start and rewrites
# END_OF_NEXT_TURN to END_OF_THIS_TURN. Setting it back to END_OF_NEXT_TURN here means it survives
# this turn's clear, becomes END_OF_THIS_TURN at the start of the character's next turn, and expires
# at the end of it - which is the duration the ability asks for.
extends ActionReaction

const CHAIN_BUFF_ID := &'buff_bind_thy_flesh'
const ANCHOR_KEY := 'anchor'
## Effects we have already extended, as "<unit id>|<status>" - "cannot be extended more than once".
const EXTENDED_KEY := 'ftj_extended'

func get_required_triggering_context() -> Array[Context.PROP]:
	return [Context.PROP.unit]

func triggers_on_event(unit:Unit, gear:GearCore, triggering_event:EventCore) -> bool:
	var ending_unit:Unit = triggering_event.context.unit
	if not Unit.is_valid(ending_unit) or ending_unit == unit: return false
	if not is_chained_to_us(ending_unit, unit): return false
	if not is_in_sensors(unit, ending_unit): return false
	return not extendable_statuses(unit, gear, ending_unit).is_empty()

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

func extension_key(unit:Unit, status:StatusCondition) -> String:
	return '%s|%s' % [unit.core.persistent_id, status.type]

## Everything on this unit that is about to expire and that we are allowed to extend.
func extendable_statuses(erinyes:Unit, gear:GearCore, ending_unit:Unit) -> Array[StatusCondition]:
	var extendable:Array[StatusCondition] = []
	var already_extended := gear.get_state_string_array(EXTENDED_KEY)
	for status:StatusCondition in ending_unit.state.statuses:
		if status.until != Lancer.UNTIL.END_OF_THIS_TURN: continue # not expiring now
		if status.type == Lancer.STATUS.STUNNED: continue # explicitly excluded by the ability
		if already_extended.has(extension_key(ending_unit, status)): continue
		if not came_from_a_tech_action(erinyes, status): continue
		extendable.append(status)
	return extendable

## A status records the persistent id of the GEAR that applied it, not the action, so this is a
## gear-level approximation: a piece of gear carrying both a tech action and a non-tech one would
## read as tech either way. Rare enough to accept, and noted rather than hidden.
func came_from_a_tech_action(erinyes:Unit, status:StatusCondition) -> bool:
	if status.source.is_empty(): return false
	var source_gear:GearCore = erinyes.map.get_gear_by_id(status.source)
	if not GearCore.is_valid(source_gear): return false
	for action:Action in source_gear.kit.actions:
		if action is ActionSystem and action.is_tech: return true
	return false

func activate(context:Context, activation:EventCore) -> void:
	var erinyes:Unit = context.unit
	var gear:GearCore = context.gear
	var ending_unit:Unit = context.event.context.unit
	var extendable := extendable_statuses(erinyes, gear, ending_unit)
	if activation.abort_when(extendable.is_empty()): return

	var chosen := await choose_effect(context, ending_unit, extendable)
	if activation.abort_when(chosen == null): return

	spend_actions(activation)

	chosen.until = Lancer.UNTIL.END_OF_NEXT_TURN
	gear.append_to_array_state(EXTENDED_KEY, extension_key(ending_unit, chosen))

## The ability extends "the effect", singular, and is a 1/round reaction - so when several tech
## effects expire at once the player picks which one. Cancelling is how "you may" is declined.
func choose_effect(context:Context, ending_unit:Unit, extendable:Array[StatusCondition]) -> StatusCondition:
	if extendable.size() == 1:
		var confirmed:bool = await CommonActionUtil.confirm_use(context, [ending_unit], [])
		return extendable.front() if confirmed else null

	var names:Array[String] = []
	for status:StatusCondition in extendable: names.append(X.tr(StatusType.name(status.type)))
	var specific := SpecificAction.from_context(context)
	var chosen_index:int = await choice_bus.choose_from_multiple_choice(
		names,
		specific.action.name(specific),
		specific.action.effect_text(specific),
	)
	if chosen_index < 0 or chosen_index >= extendable.size(): return null
	return extendable[chosen_index]

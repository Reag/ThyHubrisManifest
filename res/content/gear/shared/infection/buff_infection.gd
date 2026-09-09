# The Infection buff. Its state holds the count (COUNT_KEY); infection.gd is the only writer.
#
# Reactive, PRE timing, on the holder's own events only:
#   end_turn - Systems check against 10, carrying Infection.CHECK_FLAG so other buffs can tell
#              this check apart. Pass clears everything; fail is heat equal to the count and the
#              count stays. Mirrors burn in event_turn_end.gd:92-107 (which is an Engineering
#              check; the rules make this one Systems). The victim owns none of the Draugr's gear,
#              which is why this is a buff reaction and not an ActionReaction on a kit.
#   clear_burn - 1.4.0 only (event_unit_clear_burn; the trigger never fires on 1.3.3): an ACTION
#                that clears Burn clears Infection - Whitewash Sealant Spray and the Sealant Gun
#                reach us only this way. The same event also fires from the end-of-turn Burn save
#                (event_turn_end.gd:99 on 1.4.0); that is the Burn mechanic, not an action, so it is
#                ignored (is_inside_event below), which keeps 1.4.0 in step with 1.3.3. The event
#                aborts itself on burn <= 0, so it is never the path for a unit with Infection and
#                no Burn.
#   stabilize  - both engines: Stabilize's burn variant, read off the composed action. This is the
#                primary path on BOTH engines: Stabilize fires STABILIZE PRE before it queues
#                event_unit_clear_burn, so on 1.4.0 the buff is already gone when clear_burn would
#                arrive. It is also the only path for the no-Burn case; the variant is offered to
#                infected units by action_stabilize.gd_ext.gd.
# Keep the trigger names in the .tres, not here: ReactionBus.TRIGGER.CLEAR_BURN exists only on
# 1.4.0 and naming it would not parse on 1.3.3.
extends Buff

const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')

func name_text(core:BuffCore) -> String:
	return Translate.buff(core, 'name.count').format({count = core.get_state(Infection.COUNT_KEY, 0)})

func get_required_triggering_context() -> Array[Context.PROP]:
	return [Context.PROP.unit]

func triggers_on_event(core:BuffCore, unit:Unit, triggering_event:EventCore) -> bool:
	var context := triggering_event.context
	if context.unit != unit: return false # only the holder's own turn, burn clear, or Stabilize
	if context.action != null: return context.action.modified_by_variants.has(&'burn') # a Stabilize: only its burn variant
	if triggering_event.base.event_type == &'event_unit_clear_burn':
		return not is_inside_event(triggering_event, &'event_turn_end') # the Burn save is not an action
	return true # end_turn

## True when the event is executing inside an event of the given type. Event blocks are nodes
## nested under the block that spawned them, and each block lists the events it runs; context.event
## is not set for children run through execute_event, so the block tree is the only link.
static func is_inside_event(event:EventCore, event_type:StringName) -> bool:
	var block:Node = event.block
	var depth := 0
	while block is EventBlock and depth < EventBlock.MAXIMUM_EVENT_DEPTH:
		for other:EventCore in block.event_cores:
			if other != event and other.base.event_type == event_type: return true
		block = block.get_parent()
		depth += 1
	return false

func activate(core:BuffCore, activation:EventCore) -> void:
	var unit:Unit = activation.context.unit
	var triggering:EventCore = activation.context.event
	if not triggering.base.owns_trigger_types().has(ReactionBus.TRIGGER.END_TURN):
		Infection.clear(activation, unit) # a burn clear, or a burn-clearing Stabilize
		return
	var passed:bool = await UnitHasecheck.make_systems_check(activation, unit, 10, null, false, [Infection.CHECK_FLAG])
	if activation.abort_without_unit(unit): return
	if passed:
		Infection.clear(activation, unit)
		return
	await activation.execute_event(&'event_unit_damage', {
		unit = unit,
		number = Infection.count(unit),
		category = Lancer.DAMAGE_TYPE.HEAT,
	})

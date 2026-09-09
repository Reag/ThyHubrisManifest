# The Infection buff. Its state holds the count (COUNT_KEY); infection.gd is the only writer.
#
# Reactive, PRE timing, on the holder's own events only:
#   end_turn - Systems check against 10, carrying Infection.CHECK_FLAG so other buffs can tell
#              this check apart. Pass clears everything; fail is heat equal to the count and the
#              count stays. Mirrors burn in event_turn_end.gd:92-107 (which is an Engineering
#              check; the rules make this one Systems). The victim owns none of the Draugr's gear,
#              which is why this is a buff reaction and not an ActionReaction on a kit.
#   clear_burn - 1.4.0 only (event_unit_clear_burn; the trigger never fires on 1.3.3): anything
#                that clears Burn clears Infection. The event aborts itself on burn <= 0, so it is
#                never the path for a unit with Infection and no Burn.
#   stabilize  - both engines: Stabilize's burn variant, read off the composed action. On 1.4.0
#                clear_burn has usually already cleared us; harmless. On 1.3.3 and for the no-Burn
#                case this is the only path. The variant is offered to infected units by
#                action_stabilize.gd_ext.gd.
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
	if context.action == null: return true # end_turn, clear_burn
	return context.action.modified_by_variants.has(&'burn') # a Stabilize: only its burn variant

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

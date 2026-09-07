# Copyright (c) 2026 Wickworks ♡ Lancer Tactics v1.3.3
# Clause 7: "if this damage destroys the target, they leave behind no wreckage."
#
# WHOSE UNIT THIS SITS ON: the BANSHEE's (via mt_mourning_call_wreckless, a permanent trait added to
# mf_banshee.tres's traits, same as cp_the_keening itself), NOT the dying unit's. A reaction can only
# ever run for a unit that has it equipped, and the target of Mourning Call is an arbitrary enemy
# that will never carry Reag-ThyHubris gear -- so "on the target" was never actually available as an
# option here, whatever the wording in the task brief. That leaves the Banshee, reacting to ANY
# unit's death and checking the DYING unit for buff_mourning_call_mark, which is why this extends
# ActionReaction directly instead of ActionReactionSelf: ActionReactionSelf.triggers_on_event
# requires `triggering_context.unit == unit` (the reaction's OWNER), which would only ever match the
# Banshee's own death, never the target's.
#
# It's buff_mourning_call_mark -- applied to the target for exactly the span of Mourning Call's own
# damage -- that scopes this to ONE specific kill instead of to the unit generally. Without that
# check, this would strip LEAVES_WRECK from every death the Banshee could see, whoever or whatever
# caused it: see spec/test_mourning_call.gd's "killed by anything else still leaves a wreck" test.
#
# Trigger shape mirrors action_castigate.gd / action_unstable_system.gd (both TRIGGER.DEATH /
# TIMING.PRE). The strip itself is exactly what spec/test_mourning_call_probe.gd's probe 2 proved
# works: context.event is the triggering event_unit_die EventCore, still mid execute_preblock, so
# its own execute() has not read .flags yet.
extends ActionReaction

const MARK_BUFF_ID := &'buff_mourning_call_mark'

func get_required_triggering_context() -> Array[Context.PROP]:
	return [Context.PROP.unit]

func triggers_on_event(unit:Unit, gear:GearCore, triggering_event:EventCore) -> bool:
	if not super.triggers_on_event(unit, gear, triggering_event): return false
	var triggering_context:Context = triggering_event.context
	var dying_unit:Unit = triggering_context.unit
	if not Unit.is_valid(dying_unit): return false
	if not triggering_context.flags.has(EventService.DIE_FLAG.LEAVES_WRECK): return false
	# the mark, not this reaction's location, is what makes it THIS kill's business
	return UnitCondition.has_buff(dying_unit, MARK_BUFF_ID)

func activate(context:Context, activation:EventCore) -> void:
	spend_actions(activation)
	context.event.context.flags.erase(EventService.DIE_FLAG.LEAVES_WRECK)

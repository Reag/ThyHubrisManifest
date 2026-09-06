# PROBE -- throwaway, deleted after the real Mourning Call build.
# PROBE 2: can a DEATH:PRE reaction strip LEAVES_WRECK from the death
# context's flags before event_unit_die.execute() reads it, thereby
# preventing the wreck from spawning? See "The gauntlet" in
# D:\DEV\lancer-tactics-claude\specs\2026-09-06-banshee-mourning-call-design.md
extends ActionReactionSelf

const FIRED_META_KEY := &'probe_strip_wreck_reaction_fired'

func triggers_on_event(unit:Unit, gear:GearCore, triggering_event:EventCore) -> bool:
	if not super.triggers_on_event(unit, gear, triggering_event): return false
	var triggering_context:Context = triggering_event.context
	if not triggering_context.flags.has(EventService.DIE_FLAG.LEAVES_WRECK): return false
	return true

func activate(context:Context, activation:EventCore) -> void:
	spend_actions(activation)
	Engine.set_meta(FIRED_META_KEY, true)
	# context.event is the triggering event_unit_die EventCore (still mid execute_preblock,
	# so its own execute() has not read .flags yet).
	context.event.context.flags.erase(EventService.DIE_FLAG.LEAVES_WRECK)

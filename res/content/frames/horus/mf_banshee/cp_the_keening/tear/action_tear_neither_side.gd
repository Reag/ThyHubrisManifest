# A tear is NEITHER tangible nor intangible.
#
# Clause 2 calls a tear "a window between tangible and intangible space" - the thing both sides look
# THROUGH, not an object standing on one side of the line. The engine only has a binary, so the
# closest expressible form of "neither" is: the tear never carries Lancer.STATUS.INTANGIBLE, and
# nothing in this mod judges it by tangibility. Author decision, 2026-09-08.
#
# THE BUG THIS FIXES. event_unit_spawn.gd:97-100 hands a freshly spawned deployable its owner's
# intangibility:
#
#     var owner_unit := unit.get_owner_unit()
#     # we shouldn't be able to deploy stuff while intangible, but just in case we somehow did, ...
#     if Unit.is_valid(owner_unit) and owner_unit.has_status(Lancer.STATUS.INTANGIBLE):
#         core.queue_event(&'event_unit_intangible', {unit = unit, flags = [Lancer.UNTIL.MANUAL]})
#
# Its own comment says the branch should be unreachable, and in vanilla it is:
# ActionSystemDeploy.is_available_to_activate refuses to deploy at all while INTANGIBLE
# (action_system_deploy.gd:21). action_tear.gd deliberately drops that refusal - playtest fix 8.3,
# because Whispering is the Banshee's main route into intangibility and the vanilla gate locked the
# frame out of its own core power - which walks straight into the "just in case" branch.
#
# UNTIL.MANUAL never expires. The only thing that ever clears it is
# UnitCondition.handle_intangibilty_changing (unit_condition.gd:275-279), when the OWNER becomes
# tangible again. So before this fix a tear's tangibility depended permanently on which side of a
# Whispering it happened to be opened on: two tears side by side, one of them phased forever. It was
# visible on the live board as an fxe_intangible ChromaticAbberation stacked on top of the tear's own
# fx.
#
# THAT SEAM IS THE ONLY ONE THAT GRANTS IT, verified rather than assumed:
# handle_intangibilty_changing CLEARS intangible from a unit's deployables and never grants it
# (unit_condition.gd:275-279), so a Banshee phasing AFTER opening a tear does not infect it, and
# nothing else in engine/ or content/ applies INTANGIBLE to a deployable on its owner's behalf.
#
# WHY A REACTION, AND WHY ON THE BANSHEE.
#
#   Not on the tear. A reaction only ever runs for a unit that has it equipped, and a tear is
#   Frame.ENTITY.MARKER: ReactionBus.trigger_occurred gates every candidate on
#   UnitAction.can_activate_gear, and can_be_activated_for_faction (unit_action.gd:405-408) requires
#   is_actor() -> is_character(), which a marker never is. This is the same trap that made the first
#   version of Close Tear unreachable; see action_tear_close.gd's header.
#
#   ActionReaction directly, not ActionReactionSelf, for the same reason
#   action_mourning_call_wreckless.gd does: ActionReactionSelf.triggers_on_event requires
#   triggering_context.unit == the reaction's OWNER, which would only ever match the Banshee's own
#   spawn - never its tear's.
#
#   Not action_tear.gd's place_deployable_followup, which is where clause 6's buff hand-out lives and
#   is the obvious place to try. That hook runs at QUEUE time: place_deployable queues the spawn as an
#   event and returns (action_system_deploy.gd:125-127), so the tear is not on the map yet and the
#   inherit has not happened. Clearing there is undone moments later by event_unit_spawn itself.
#
# TIMING IS WHY POST WORKS. Within event_unit_spawn.execute, line 100 queues event_unit_intangible
# and line 107 queues the UNIT_SPAWN/POST reactions, both onto the same block in that order - so the
# inherit lands before this reaction runs.
#
# ...WHICH IS ALSO WHY THE TRIGGER TEST CANNOT ASK THE TEAR. ReactionBus.trigger_occurred is called
# BY queue_reaction_events (event_core.gd:59-68), i.e. at line 107, while event_unit_intangible is
# still merely queued. At that instant the tear does NOT yet have the status, so a
# `spawned.has_status(INTANGIBLE)` gate would refuse to queue the reaction at all - and
# recheck_trigger_before_execution cannot rescue it, since rechecking only ever CANCELS an
# already-queued reaction, never adds one. The trigger therefore asks the OWNER, which is exactly the
# condition event_unit_spawn:99 itself tests, and is true at queue time. (The tear is checked too, as
# a belt-and-braces clause for any future seam that lands the status earlier.)
#
# NO spend_actions(), DELIBERATELY. There is nothing to spend - the reaction is bookkeeping, not an
# ability - and UnitAction.spend consumes the first free-action buff it finds
# (unit_action.gd:257-259) whether or not the action needed one. action_tear_move.gd declined
# spend_actions for that same reason. consumes_rxn = false already keeps it off the reaction economy
# and, via ActionReaction.get_per_round_hard_limit, raises the naturally-free 1/round cap
# (action.gd:156-158) to 99 - so every tear opened in a round gets cleaned up, not just the first.
# The explicit usage_group on the .tres keeps it off Tear's and Mourning Call's round allowances,
# which a blank one would silently share (gear_core.gd:166-168).
extends ActionReaction

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')

## Invisible plumbing, not an ability. The Keening reads as two abilities and must keep doing so.
func show_in_tooltip(_kit:Kit) -> bool: return false

func get_required_triggering_context() -> Array[Context.PROP]:
	return [Context.PROP.unit]

func triggers_on_event(unit:Unit, gear:GearCore, triggering_event:EventCore) -> bool:
	if not super.triggers_on_event(unit, gear, triggering_event): return false
	var spawned:Unit = triggering_event.context.unit
	if not Unit.is_valid(spawned): return false
	# Our own tear, nobody else's - another Banshee's tear is its own owner's business, and that
	# owner has this same reaction.
	if not TearRouting.is_tear(spawned): return false
	if not spawned.state.is_owned_by(unit): return false
	# Only when there is something to clear. The owner test is the live one at queue time (see the
	# header); the tear test covers a status that somehow arrived earlier.
	return unit.has_status(Lancer.STATUS.INTANGIBLE) or spawned.has_status(Lancer.STATUS.INTANGIBLE)

func activate(context:Context, activation:EventCore) -> void:
	# The tear is the SPAWNING event's unit, not this reaction's - context.unit is the Banshee.
	var triggering_event:EventCore = context.event
	if activation.abort_when(triggering_event == null): return
	var tear:Unit = triggering_event.context.unit
	if activation.abort_without_unit(tear): return
	# An empty source clears every source of the status (unit_condition.gd:309-323), and the call is
	# a no-op when the status is absent - on_status_clear only runs if something actually went.
	UnitCondition.clear_status(activation, tear, Lancer.STATUS.INTANGIBLE)

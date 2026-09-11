# Dig In - Root's whole content.
#
#   "1/turn, ignore the forced movement and take AP KINETIC equal to the number of spaces ignored."
#   Trigger: "You would be moved involuntarily"
#
# ActionReactionSelf on entire_movement at PRE. The base archetype already refuses any event whose
# triggering unit is not us (action_reaction_self.gd:11-15), which is the whole of "you would be
# moved"; everything below filters what KIND of move it was, following Flash Anchor
# (action_flash_lock.gd:34-48) - the same trigger, the same two exclusions, the same declined guard.
#
# ==================== WHY set_aborted() STOPS THE MOVE ====================
# ENTIRE_MOVEMENT/PRE fires inside event_unit_move.execute (:71), not in a preblock, so EventBlock's
# own aborted-check (event_block.gd:99-103) has long since run. What saves us is the very next line:
#   :72   if core.abort_without_unit(unit): return
# abort_without_unit -> abort_when(false) -> event_core.gd:26-29, which returns the core's EXISTING
# `aborted` flag ("if we aborted some other way, also return that it's time to pull the cord"). So a
# PRE reaction that sets it is honoured one line later and undergo_move never runs.
#
# ==================== WHERE THE NUMBER COMES FROM ====================
# event_unit_pick_move - the event that turns a knockback into a move - fires no reaction trigger at
# all, so the raw knockback distance is invisible. The planned path is not: Pathfinder.generate_events
# puts it in `array` (pathfinder.gd:896-913) and event_unit_move reads it back at :137-138. For the
# primary moving unit the reaction is handed that same event core (:313-314), so context.array.size()
# is exactly "the number of spaces ignored". A katamari passenger gets a virtual event with NO array
# (:316-324) - hence the zero guard.
#
# ==================== 1/TURN ====================
# The engine's own per-turn usage counter, not gear state. every_new_turn_refresh clears
# uses_this_turn AND restores the reaction point for EVERY unit at EVERY turn start
# (unit_action.gd:67-72, from event_turn_start.gd:43-44), so get_per_turn_soft_limit -> 1 plus a
# private usage_group plus spend_actions says "1/turn" precisely. The per-ROUND cap must be lifted to
# 99: ActionReaction caps any consumes_rxn reaction at 1/round (action_reaction.gd:69) and
# reset_per_round_usage only runs on our OWN turn (unit_action.gd:75-87), so leaving it would forbid
# digging in during a second enemy's turn in the same round.
extends ActionReactionSelf

## No Compat shim here: the prompt goes through CommonActionUtil.confirm_use directly (see activate
## below), which is identical on both engines.

## Gear state: the id of the triggering event whose prompt we already declined.
const DENIED_KEY := 'dig_in_denied'

func get_per_turn_soft_limit(specific:SpecificAction) -> int: return 1
func get_per_round_hard_limit(specific:SpecificAction) -> int: return 99

func triggers_on_event(unit:Unit, gear:GearCore, triggering_event:EventCore) -> bool:
	if not super.triggers_on_event(unit, gear, triggering_event): return false
	var triggering_context:Context = triggering_event.context
	# only involuntary movement
	if not MovementType.is_valid(triggering_context.resource): return false
	if triggering_context.resource.voluntary: return false
	# ...and only FORCED movement in the core rulebook's sense (knockback, pull, drag, harpoon, ram).
	# The engine tags more than that as "not voluntary" - the Goblin's Puppet System
	# (action_puppet_system.gd:8 "counts as involuntary!!"), teleports (event_unit_teleport.gd:26),
	# mounting up (action_mount_up.gd:56) - but the rulebook does not call those forced movement, and
	# the author ruled (2026-09-10) that they never prompt. The discriminator is the raw ignore_rxns
	# flag: MovementType.create_for_involuntary (movement_type.gd:63-71) sets it, and every content
	# caller that pushes, pulls or drags a unit goes through that constructor; the three above do not.
	# Friendly forced movement DOES prompt (same ruling; Flash Anchor's hostile-only filter is not
	# copied). The raw flag, not ignores_reactions(): that method is true for ALL involuntary movement
	# (movement_type.gd:101-102), which is exactly what the engine and the rulebook disagree on.
	if not triggering_context.resource.ignore_rxns: return false
	# mandatory movement cannot be dug in against. NOTE: deliberately NOT
	# MovementType.is_contextual_move_reactable (movement_type.gd:124-126) - ignores_reactions() is
	# true for ALL involuntary movement (:101-102), which is precisely what this reacts to. That
	# helper is for overwatch-shaped reactions; Flash Anchor does not consult it either.
	if triggering_context.flags.has(EventUnitMove.FLAG.NO_RXNS): return false
	# already said no to this exact shove
	if gear.get_state(DENIED_KEY, &'') == triggering_event.id: return false
	# nothing to ignore, nothing to pay: a katamari passenger's virtual event carries no path
	return spaces_ignored(triggering_context) > 0

## "the number of spaces ignored" - the planned path, which is the only number a reaction can see.
func spaces_ignored(triggering_context:Context) -> int:
	return triggering_context.array.size()

func activate(context:Context, activation:EventCore) -> void:
	var unit:Unit = context.unit
	var triggering:EventCore = context.event
	if activation.abort_when(not Unit.is_valid(unit) or triggering == null): return
	var spaces := spaces_ignored(triggering.context)
	if activation.abort_when(spaces <= 0): return

	# Reactions to one move are collected first and run after (event_unit_move.gd:295-333); if an
	# earlier one already cancelled it (Flash Anchor, action_flash_lock.gd:66), there is nothing to
	# dig in against - no prompt, no reaction spent, no damage.
	if activation.abort_when(triggering.aborted): return

	# CommonActionUtil.confirm_use rather than a raw prompt (plan decision D4): it is Flash Anchor's
	# own line (action_flash_lock.gd:56), it reaches choice_bus.quick_yesno_for on 1.4.0
	# (common_action_util.gd:362-371) so the shim would add nothing, and - decisively - it answers for
	# an AI unit without opening a request at all (:304-310).
	var confirmed:bool = await CommonActionUtil.confirm_use(context, [unit], [])
	if activation.abort_when(not confirmed):
		context.gear.set_state(DENIED_KEY, triggering.id)
		return
	spend_actions(activation)

	# Abort the move FIRST, so the damage lands on a unit that is standing still - and so that a
	# lethal Dig In still cancels the movement it was refusing.
	triggering.set_aborted()

	# No NO_REDUCE: the author's ruling is that a Draugr's own Resilience capping this to 1 (and
	# costing a point) is intended, not an oversight - memory draugr-build-state, 2026-09-10.
	await activation.execute_event(&'event_unit_damage', {
		unit = unit,
		number = spaces,
		category = Lancer.DAMAGE_TYPE.KINETIC,
		flags = [EventService.DAMAGE_FLAG.AP, EventService.DAMAGE_FLAG.SELF_INFLICTED],
	})

# Copyright (c) 2026 Wickworks ♡ Lancer Tactics v1.3.3
# Clauses 1-2's hand-off target: onhit_mourning_call.gd offers this via CommonActionUtil.choose_and_use
# after a ranged hit. Task 2: teleport adjacent to the target (3), become tangible (4), deal 4 AP
# KINETIC (6 on a crit) (5), all of it even while IMMOBILIZED (6). Task 3: no wreckage and INTANGIBLE
# on a kill (7, 8). The tear relocation and core-point refund are Task 4. Do not build ahead.
extends ActionSystem

const MARK_BUFF_ID := &'buff_mourning_call_mark'

func activate(context:Context, activation:EventCore) -> void:
	# mirrors action_castigate.gd / action_unstable_system.gd: call spend_actions() ourselves so the
	# deferred_spend chain from choose_and_use actually runs before we're done.
	spend_actions(activation)

	var unit:Unit = context.unit
	if not Unit.is_valid(unit): return

	# This action's OWN context (a fresh event_gear_activate created by choose_and_use) never gets a
	# target_unit or a DeclaredAttackSummary of its own -- CommonActionUtil.choose_and_use only
	# threads `event` through (set to the activation it was called with), so both live on the OUTER
	# activation: the event_unit_attack core that onhit_mourning_call.gd's OnHitEffect was handed.
	# Confirmed empirically via the test suite below rather than assumed.
	var outer:EventCore = context.event
	if outer == null: return
	var target:Unit = outer.context.target_unit
	if not Unit.is_valid(target): return

	# clause 5: read the crit off the attack summary. NEVER implement on_crit here -- event_unit_attack.gd
	# calls apply_on_hits AND THEN apply_on_crits on a critical hit (event_unit_attack.gd:85-93), so a
	# 4-in-on_hit / 6-in-on_crit split would deal 10, not 6.
	var summary = outer.context.resource # DeclaredAttackSummary
	var crit:bool = DeclaredAttackSummary.is_valid(summary) and summary.get_all_crit_units().has(target)
	var amount:int = 6 if crit else 4

	# clauses 3, 6: teleport to a free space adjacent to the target, even while IMMOBILIZED (or
	# GRAPPLED/SHUTDOWN -- UnitCondition.is_immobilized covers those too; flagged, not trimmed).
	# voluntary = false is the escape hatch: every gate in the engine reads
	# `movement_type.voluntary and UnitCondition.is_immobilized(unit)` (pathfinder.gd:330,
	# action_system_movement.gd:26, action_reaction_movement.gd:48). MovementType.new()'s own default
	# (which create_for_involuntary never overrides) is voluntary = false, so this is automatic --
	# proven by spec/test_mourning_call_probe.gd's probe 3, including its voluntary=true control.
	var movement_type := MovementType.create_for_involuntary(unit)
	movement_type.teleport = true

	var free_tile := Tile.INVALID
	var katamari := Katamari.create(unit)
	for tile:Vector2i in UnitTile.get_adjacent_tiles(target):
		if Pathfinder.is_tile_standable(unit, tile, movement_type, katamari):
			free_tile = tile
			break
	# onhit_mourning_call.gd already checked for a free adjacent tile before offering the prompt, so
	# this should never come up empty in play -- but don't teleport into a wall if it somehow does.
	if free_tile != Tile.INVALID:
		await activation.execute_event(&'event_unit_move', {
			unit = unit,
			target_tiles = [free_tile],
			resource = movement_type,
		})
		if not Unit.is_valid(unit): return

	# clause 4: become tangible.
	UnitCondition.clear_status(activation, unit, Lancer.STATUS.INTANGIBLE)

	# clause 7: mark the target immediately before dealing the damage. mt_mourning_call_wreckless
	# (a permanent trait on the Banshee, see action_mourning_call_wreckless.gd for why it isn't on
	# the target) checks the dying unit for this mark during DEATH:PRE and strips LEAVES_WRECK only
	# when it's present -- that's what scopes "no wreckage" to THIS kill instead of to the target
	# generally. from_gear = context.gear (cp_the_keening) since that's also where the wreckless
	# trait's sibling Kit lives.
	var mark_buff:Buff = ContentLibrary.get_buff(MARK_BUFF_ID)
	var mark:BuffCore = UnitCondition.apply_buff(activation, target, mark_buff, context.gear)

	# clause 5: deal the damage. AP KINETIC, straight to the target. AWAITED (execute_events), NOT
	# queued -- unlike a normal queue_damage_events call, we need to know RIGHT HERE, synchronously,
	# whether this specific blow killed the target, because clauses 7 and 8 both hang off that. This
	# also means Mourning Call's own damage (and any death it causes) resolves before the weapon's
	# own on-hit damage does, since that is still only QUEUED at this point (event_unit_attack.gd
	# runs the weapon's own on_hit_effects, then the buff's -- ours -- and neither has actually
	# applied yet when this runs); see spec/test_mourning_call.gd's kill tests for why that ordering
	# is exactly what makes "killed by Mourning Call, not by anything else" testable at all.
	var damage_events:Array[EventCore] = CommonActionUtil.generate_damage_events(
		unit, [target], amount, Lancer.DAMAGE_TYPE.KINETIC, [EventService.DAMAGE_FLAG.AP]
	)
	await activation.execute_events(damage_events)

	if Unit.is_valid(target):
		# survived -- take the mark back off so it can't outlive this kill and taint a later, unrelated death.
		if BuffCore.is_valid(mark): UnitCondition.clear_buff(activation, target, mark)
	else:
		# clause 8: a kill phases the Banshee out. Via the event (not UnitCondition.apply_status
		# directly) so reactions get a PRE hook, same as every other intangibility change in this
		# engine. Task 2 already CLEARED intangible above, so this activation runs
		# UnitCondition.handle_intangibilty_changing twice -- once for each change. Both calls are
		# independently correct (each recomputes has_status fresh when it runs), so the Banshee still
		# ends up intangible; see spec/test_mourning_call.gd's "ends intangible" test, which asserts
		# the final state rather than merely that the status was applied at some point.
		if not Unit.is_valid(unit): return
		await activation.execute_event(&'event_unit_intangible', {
			unit = unit,
			flags = [Lancer.UNTIL.MANUAL],
		})

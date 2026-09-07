# Copyright (c) 2026 Wickworks ♡ Lancer Tactics v1.3.3
# Clauses 1-2's hand-off target: onhit_mourning_call.gd offers this via CommonActionUtil.choose_and_use
# after a ranged attack resolves (on_resolution -- after the weapon's own damage has landed). Task 2: teleport adjacent to the target (3), become tangible (4), deal 4 AP
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

	# onhit_mourning_call.gd now fires from OnHitEffect.on_resolution, not on_hit (see that file's
	# header for why), and passes the target it picked explicitly as choose_and_use's
	# target_unit_or_tiles. decompose_variant_targets turns that into context.target_unit on THIS
	# action's own event_gear_activate (common_action_util.gd:595-598, 606-607, 714-715) -- read it
	# directly rather than reaching outward.
	#
	# This replaces the old outer.context.target_unit lookup, which relied on `activation` (=
	# context.event) being the PER-TARGET event_unit_attack core -- that core has its own target_unit
	# prop, which is where the old on_hit-stage trigger got its target from. At on_resolution's
	# altitude, `activation` is the event_unit_attack_declared core instead, which has no target_unit
	# of its own; that old lookup would now read null. Verified against the new call chain rather than
	# assumed to still hold.
	var target:Unit = context.target_unit
	if not Unit.is_valid(target): return

	# clause 5: read the crit off the attack summary. NEVER implement on_crit here -- event_unit_attack.gd
	# calls apply_on_hits AND THEN apply_on_crits on a critical hit (event_unit_attack.gd:85-93), so a
	# 4-in-on_hit / 6-in-on_crit split would deal 10, not 6. context.event (the event_unit_attack_declared
	# core) still carries the DeclaredAttackSummary directly on its own context.resource -- see
	# EventUnitAttackDeclared.execute(), which reads `context.resource` into `declared_summary` -- so
	# this half of the lookup is unchanged by the on_resolution move.
	var outer:EventCore = context.event
	var summary = outer.context.resource if outer != null else null # DeclaredAttackSummary
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
	# whether THIS specific blow killed the target, because clauses 7 and 8 both hang off that
	# specifically, not off the target simply having died during this attack.
	#
	# Now that Mourning Call fires from on_resolution (onhit_mourning_call.gd), the weapon's own
	# damage has ALREADY landed by the time this runs (core.execute_events(damage_events) at
	# event_unit_attack_declared.gd:199 happens before on_resolution at :211) -- the opposite of the
	# old on_hit-stage ordering, where the weapon's damage was still only queued. That's the whole
	# point of the move: Mourning Call is meant to finish off a target the weapon has already
	# wounded, not strike first at full health. See spec/test_mourning_call.gd's kill tests, which
	# size the target so the weapon's hit alone does not kill and Mourning Call's own damage has to
	# land the actual killing blow for clauses 7/8 to have anything to prove.
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

# Copyright (c) 2026 Wickworks ♡ Lancer Tactics v1.3.3
# Clauses 1-2's hand-off target: onhit_mourning_call.gd offers this via CommonActionUtil.choose_and_use
# after a ranged attack resolves (on_resolution -- after the weapon's own damage has landed). Task 2: teleport adjacent to the target (3), become tangible (4), deal 4 AP
# KINETIC (6 on a crit) (5), all of it even while IMMOBILIZED (6). Task 3: no wreckage and INTANGIBLE
# on a kill (7, 8). Task 4: relocate a void tear anywhere within SENSORS (9) and, once per scene,
# regain the core point (10).
extends ActionSystem

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')

const MARK_BUFF_ID := &'buff_mourning_call_mark'

## Clause 10's counter lives on THIS gear (cp_the_keening -- context.gear, same as the mark buff
## above) but under its OWN usage_group, distinct from action_mourning_call.tres's own
## (&"action_mourning_call", which _mourning_call_ran in the spec reads via get_uses_this_round_alt).
## Spending the core point to activate and refunding it on a kill must count separately, or the two
## would corrupt each other's tallies the instant both existed on the same group.
const REFUND_USAGE_GROUP := &'action_mourning_call_refund'

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

		# Task 4. Both re-check Unit.is_valid(unit) -- the intangibility event above just awaited, and
		# _maybe_relocate_tear awaits several more choices before returning, any of which could see the
		# Banshee removed from the map (destroyed by a reaction, etc.) in the meantime.
		if not Unit.is_valid(unit): return
		await _maybe_relocate_tear(context, activation, unit) # clause 9
		if not Unit.is_valid(unit): return
		_maybe_refund_core_point(context.gear, unit) # clause 10

## Clause 9: "you may move a void tear anywhere within SENSORS." Optional -- declining, or having no
## tear on the map at all, costs nothing beyond what the kill already spent.
##
## WIDER than Tear's own move verb (clause 8, action_tear_move.gd), which is capped at the Banshee's
## speed and walks a path there tile by tile via Pathfinder. This is a straight relocation instead --
## the same shape as this file's own clause-3 teleport further up, just aimed at a tear instead of the
## Banshee -- so it does NOT reuse action_tear_move.gd's movement loop; a speed-limited walked path is
## a different mechanic from an unlimited sensor-range jump, and forcing the two to share a loop would
## either cap this clause at the Banshee's speed (wrong -- the text says SENSORS) or let clause 8 walk
## further than its own speed (also wrong). What IS shared, so the two verbs can never disagree about
## "which tears are mine": TearRouting.owned_tears, extracted from action_tear_move.gd's own
## (formerly private) _movable_tears for exactly this reason -- see that file's history.
func _maybe_relocate_tear(context:Context, activation:EventCore, unit:Unit) -> void:
	var tears:Array[Unit] = TearRouting.owned_tears(unit)
	if tears.is_empty(): return # nothing to move -- do not prompt at all.

	var confirmed:bool = await choice_bus.quick_yesno(
		unit.tile(),
		tr('gear.cp_the_keening.action_mourning_call.name'),
		tr('gear.cp_the_keening.action_mourning_call.relocate_tear_prompt'),
	)
	if not confirmed or not Unit.is_valid(unit): return

	# Multiple tears (MAX_TEARS = 15 in tear_routing.gd) are possible; pick one the same way clause 8
	# does -- highlight the candidates, then ask -- rather than silently grabbing the first.
	var chosen:Unit = tears.front()
	if tears.size() > 1:
		camera_bus.show_all_tiles(UnitTile.collect_all_occupied_tiles(tears), true)
		chosen = await choice_bus.choose_unit(tears)
	if not Unit.is_valid(chosen) or not Unit.is_valid(unit): return

	# "within SENSORS" is exactly the set TILE_GROUP.SENSORS resolves to
	# (content/fetchers/fetcher_unit_tiles.gd:22) -- not a walking budget. Filtered down to tiles the
	# tear can actually stand on, same standability check this file's own clause-3 teleport uses above,
	# just run against the TEAR's own size/movement rather than the Banshee's.
	var sensor_tiles:Array[Vector2i] = UnitTile.get_tiles_within(unit, unit.get_sensor_range())
	var movement_type := MovementType.create_for_involuntary(chosen)
	movement_type.teleport = true
	var katamari := Katamari.create(chosen)
	var standable_tiles:Array[Vector2i] = []
	for tile:Vector2i in sensor_tiles:
		if Pathfinder.is_tile_standable(chosen, tile, movement_type, katamari): standable_tiles.append(tile)
	if standable_tiles.is_empty(): return

	var plan:CompconPlan = await choice_bus.choose_target_tiles(SpecificAction.from_context(context), standable_tiles)
	if plan == null or plan.target_tiles.is_empty(): return
	if not Unit.is_valid(chosen) or not Unit.is_valid(unit): return

	await activation.execute_event(&'event_unit_move', {
		unit = chosen,
		target_tiles = [plan.target_tiles.front()],
		resource = movement_type,
	})
	# The tear changed tile, and every cache in tear_routing is keyed on tile -- see action_tear.gd
	# and action_tear_move.gd, which invalidate for the identical reason.
	if Unit.is_valid(chosen) and is_instance_valid(chosen.map): TearRouting.invalidate(chosen.map)

## Clause 10: "1/scene after destroying a target this way, regain your core point." unit.core.
## has_core_power = true is the whole refund (confirmed against a neighbouring mod's own use of the
## same field); the gate is what needs care:
##
## - REFUND_USAGE_GROUP, not MOURNING_CALL_USAGE_GROUP (action_mourning_call.tres's own
##   &"action_mourning_call") -- spending the core point to activate and refunding it on a kill are
##   counted separately, so a second kill this scene still reads "1 use" here even though the action
##   itself has run twice.
## - uses_this_scene, not uses_this_round: get_uses_this_scene_alt persists across the whole scene
##   (unit_action.gd's reset_per_round_usage/new_turn_refresh clears uses_this_round every turn but
##   never touches uses_this_scene -- reset_per_scene_usage is unused outside short repair), which is
##   what "1/scene" actually means, as opposed to "1/turn".
## - Checked BEFORE incrementing, so the first kill of the scene still sees a count of 0 and refunds,
##   and a second kill in the same scene sees 1 and does not.
## - Only ever called from the kill branch of activate(), once per call -- never on a survived hit,
##   and never when Mourning Call itself was declined (declining means activate() never runs at all).
func _maybe_refund_core_point(gear:GearCore, unit:Unit) -> void:
	if not GearCore.is_valid(gear): return
	if gear.get_uses_this_scene_alt(REFUND_USAGE_GROUP) > 0: return
	gear.increment_action_usage(REFUND_USAGE_GROUP)
	unit.core.has_core_power = true

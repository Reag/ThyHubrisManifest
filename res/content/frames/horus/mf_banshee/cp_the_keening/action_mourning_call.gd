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


## PLAYTEST FIX 8.2: Mourning Call is not a button. It is only ever reached from
## onhit_mourning_call.gd, after a ranged attack has hit and with that attack's target in hand.
## Clicked cold off the gear bar it has no target at all, so activate() falls straight out of its
## first guard -- a live, clickable, silent no-op sitting next to Tear.
##
## It cannot simply be removed from cp_the_keening.tres's actions: SpecificAction.from_id is how
## onhit_mourning_call.gd finds it, and that searches the kit's action list. So it stays listed and
## is refused UNLESS THE OFFER WINDOW IS OPEN. Paired with hide_if_disabled = true on
## action_mourning_call.tres, which is what actually takes the button off the bar (gear_bar.gd:147).
##
## ------------------------------------------------------------------------------------------------
## WHY A WINDOW AND NOT A FLAT `return false`, which is what this was first written as.
##
## A flat false ALSO kills the on-hit path, and the reason is not where you would look for it.
## is_available_to_activate is reached through UnitAction.can_activate_gear (unit_action.gd:156), and
## it is true that CommonActionUtil.choose_and_use never calls can_activate_gear itself -- but the
## event it BUILDS does: event_gear_activate.check_specific_context ends with
## `return UnitAction.can_activate_gear(specific, as_freebie)` (content/events/event_gear_activate.gd:50),
## and AS_FREEBIE does not exempt it (can_activate_gear runs is_gear_available BEFORE its
## `if as_freebie: return true`). So a flat false aborts every activation of this action, from any
## caller, with `[ Gear not available ] reason : specific`. Measured: 24 red tests.
##
## The window is opened by onhit_mourning_call.gd immediately before it hands off and closed
## immediately after, so the action is activatable for exactly the span in which it is legitimate.
## It lives on the GEAR rather than in a static so two Banshees on one map cannot open each other's.
##
## Preferred over is_situationally_activated = true, which would ALSO strip the effect text out of
## the core power's tooltip (kit.gd:229) -- the player would stop being told what Mourning Call does.
## ------------------------------------------------------------------------------------------------
const OFFER_WINDOW_KEY := 'mourning_call_offer_open'

static func open_offer_window(gear:GearCore) -> void:
	if GearCore.is_valid(gear): gear.set_state(OFFER_WINDOW_KEY, true)

static func close_offer_window(gear:GearCore) -> void:
	if GearCore.is_valid(gear): gear.set_state(OFFER_WINDOW_KEY, false)

static func is_offer_window_open(gear:GearCore) -> bool:
	return GearCore.is_valid(gear) and bool(gear.get_state(OFFER_WINDOW_KEY, false))

func is_available_to_activate(unit:Unit, gear:GearCore) -> bool:
	if not super.is_available_to_activate(unit, gear): return false
	return is_offer_window_open(gear)

func activate(context:Context, activation:EventCore) -> void:
	# Mirrors action_castigate.gd / action_unstable_system.gd in spending our own cost from inside
	# activate() -- but NOT through Action.spend_actions(), and that difference is the whole of
	# playtest fix 6.1.
	#
	# THE DOUBLE BILLING. onhit_mourning_call.gd hands choose_and_use the same SpecificAction as both
	# `using` and `chosen`. choose_and_use always stamps Action.FLAG.AS_FREEBIE onto the CHILD
	# activation (common_action_util.gd:666-670) and installs a deferred_spend that spends the PARENT,
	# so under the default choose_and_use_spend_action this one action was billed twice:
	# UnitAction.spend_actions_gain_heat ran once for the parent (NON-freebie, reached via
	# context.run_deferred_spend() at unit_action.gd:219) and again for the child (freebie).
	# unit.state.actions sits inside spend()'s `if not as_freebie` guard (unit_action.gd:242), so the
	# QUICK was charged exactly once -- which is why the action-economy spec stayed green and hid
	# this through a whole build cycle -- but everything OUTSIDE that guard ran twice:
	# spend_core_power (two "-CP" popups and two core_power barks), increment_action_usage_for_action,
	# log_usage and popcorn_usage.
	#
	# The fix has two halves. onhit_mourning_call.gd now passes
	# CommonActionUtil.choose_and_use_no_spend, so the deferred parent spend is a no-op and the
	# billing happens exactly once -- here. But `no_spend` on its own would leave only the CHILD
	# spend, which choose_and_use has already flagged AS_FREEBIE, and a freebie never touches
	# unit.state.actions: the QUICK the author deliberately chose would have silently become free.
	# So spend explicitly with AS_FREEBIE stripped, instead of calling spend_actions() and inheriting
	# the flag. spec/test_mourning_call.gd counts both halves -- one "-CP" popup, one recorded use.
	var specific := SpecificAction.from_context(activation.context)
	if not SpecificAction.is_valid(specific): return
	# duplicate(): spend() appends SPENT_OVERCHARGE to the REAL activation.context.flags, which must
	# keep its AS_FREEBIE for everything downstream that reads it.
	var spend_flags:Array = activation.context.flags.duplicate()
	spend_flags.erase(Action.FLAG.AS_FREEBIE)
	UnitAction.spend_actions_gain_heat(specific, activation, spend_flags)

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

	# clauses 3, 6: teleport to a free space adjacent to the target, even while IMMOBILIZED. See
	# landing_tiles() / is_teleport_blocked() below for how far that waiver reaches and where it
	# deliberately stops (playtest fix 6.5 -- GRAPPLED is NOT licensed by the prose).
	var movement_type := teleport_movement_type(unit)
	var free_tiles:Array[Vector2i] = landing_tiles(unit, target)

	# PLAYTEST FIX 6.6: which side of the target the Banshee lands on is a real tactical decision --
	# cover, engagement, what it can reach next turn -- and the old code simply took the first
	# standable tile in UnitTile.get_adjacent_tiles order without asking. Offer the choice.
	#
	# The old comment here claimed that a Banshee ALREADY adjacent to its target "stays put" because
	# its own tile reads as standable. That was wrong on both counts, and the reviewer who flagged it
	# was right: its own tile does read as standable (Occupation never lets a unit block itself), but
	# the loop took the FIRST standable tile in direction order, which is almost never the tile the
	# Banshee is standing on -- so an already-adjacent Banshee was silently shuffled sideways. Its
	# current tile is still in this list, so staying put is now something the player can actually
	# choose.
	var free_tile:Vector2i = free_tiles.front() if not free_tiles.is_empty() else Tile.INVALID
	if free_tiles.size() > 1 and unit.is_player_controlled():
		camera_bus.show_all_tiles(free_tiles, true)
		var landing_plan:CompconPlan = await choice_bus.choose_target_tiles(SpecificAction.from_context(context), free_tiles)
		if not Unit.is_valid(unit) or not Unit.is_valid(target): return
		# Cancelling the pick must NOT cancel the whole activation -- the core point and the quick
		# action are already spent by this point, so bailing here would eat both for nothing. Fall
		# back to the same tile the old code would have taken.
		if landing_plan != null and not landing_plan.target_tiles.is_empty():
			free_tile = landing_plan.target_tiles.front()

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

	# clause 7: mark the target immediately before dealing the damage. action_mourning_call_wreckless
	# (a DEATH:PRE reaction on the Banshee, sharing this very Kit since 2026-09-08 -- see that file
	# for why it isn't on the target) checks the dying unit for this mark and strips LEAVES_WRECK only
	# when it's present -- that's what scopes "no wreckage" to THIS kill instead of to the target
	# generally. from_gear = context.gear (cp_the_keening), which is now also the reaction's own gear.
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
		#
		# PLAYTEST FIX 6.2: START_OF_TURN, not MANUAL. MANUAL never expires on its own --
		# event_unit_intangible.get_until() clamps the first flag and hands it straight to
		# UnitCondition.apply_status -- so a single kill left the Banshee permanently intangible,
		# which nothing in the prose promises. Author decision (2026-09-08): it lasts until the start
		# of the Banshee's next turn, matching Whispering's own apply_until = START_OF_TURN. The enum
		# index was checked against engine/utils/lancer.gd rather than taken on trust: UNTIL reads
		# MANUAL, END_OF_NEXT_TURN, END_OF_THIS_TURN, START_OF_TURN, so START_OF_TURN is 3.
		if not Unit.is_valid(unit): return
		await activation.execute_event(&'event_unit_intangible', {
			unit = unit,
			flags = [Lancer.UNTIL.START_OF_TURN],
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

	# PLAYTEST FIX 6.4 (same defect as the offer prompt in onhit_mourning_call.gd, one clause later):
	# an AI Banshee was raising ITS decisions as human dialogs -- the player was asked whether the
	# enemy should relocate its own tear, and then which tear, and then to where. Vanilla always
	# guards a quick_yesno on is_player_controlled and gives the AI a straight default
	# (action_blinkspace_jump.gd:14, action_mag_parry.gd:29, action_consume_lock_on.gd:52-56); the
	# default here is yes, as it is there. Everything below is likewise gated so the AI decides for
	# itself instead of borrowing the player's hands.
	var player_decides:bool = unit.is_player_controlled()
	var confirmed:bool = true # AI always takes the free relocation
	if player_decides:
		confirmed = await choice_bus.quick_yesno(
			unit.tile(),
			tr('gear.cp_the_keening.action_mourning_call.name'),
			tr('gear.cp_the_keening.action_mourning_call.relocate_tear_prompt'),
		)
	if not confirmed or not Unit.is_valid(unit): return

	# Multiple tears (MAX_TEARS = 15 in tear_routing.gd) are possible; pick one the same way clause 8
	# does -- highlight the candidates, then ask -- rather than silently grabbing the first.
	var chosen:Unit = tears.front()
	if tears.size() > 1 and player_decides:
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

	var destination:Vector2i = standable_tiles.front() # the AI's default; see player_decides above
	if player_decides:
		var plan:CompconPlan = await choice_bus.choose_target_tiles(SpecificAction.from_context(context), standable_tiles)
		if plan == null or plan.target_tiles.is_empty(): return
		destination = plan.target_tiles.front()
	if not Unit.is_valid(chosen) or not Unit.is_valid(unit): return

	await activation.execute_event(&'event_unit_move', {
		unit = chosen,
		target_tiles = [destination],
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


# ============================================================================
# The teleport's shared vocabulary. onhit_mourning_call.gd has to answer "can this even happen?"
# BEFORE it prompts, and activate() has to answer "where exactly?" after. Those two answers must
# never disagree -- an offer for a teleport that then cannot run costs the player a core point for
# nothing -- so both live here, as statics, and onhit preloads this script rather than keeping its
# own copy. (It used to keep its own copy, and the copies had already drifted: onhit's built the
# MovementType inline while activate() built a second one a few lines later.)
# ============================================================================

## The involuntary teleport, and the ONE thing it is not allowed to escape.
##
## PLAYTEST FIX 6.5. `voluntary = false` (MovementType.new()'s default, which create_for_involuntary
## never overrides) waives every immobility gate in the engine, because they all read
## `movement_type.voluntary and UnitCondition.is_immobilized(unit)` -- pathfinder.gd:330,
## action_system_movement.gd:26, action_reaction_movement.gd:48. That is exactly what clause 6 wants
## for IMMOBILIZED. But UnitCondition.is_immobilized (unit_condition.gd:412-417) is a THREE-status
## predicate: IMMOBILIZED, GRAPPLED (unless this unit is the larger party) and SHUTDOWN. The prose
## licenses one of those -- "You may do so even while IMMOBILIZED" -- and says nothing about slipping
## a grapple, which in this engine is a contested hold another unit is actively maintaining.
##
## So the waiver is kept and then narrowed by hand: the movement itself stays involuntary (that is
## what makes it a teleport rather than a walk, and what makes it ignore reactions and engagement),
## and the two statuses the prose does not cover are refused here instead. A GRAPPLED or SHUTDOWN
## Banshee is simply not offered Mourning Call -- onhit_mourning_call.gd calls landing_tiles() before
## it prompts, so nothing is spent.
##
## SHUTDOWN is in scope only for completeness: a SHUTDOWN unit cannot take the attack that triggers
## Mourning Call in the first place, so in play this gate is about GRAPPLED.
static func is_teleport_blocked(unit:Unit) -> bool:
	if not Unit.is_valid(unit): return true
	return (
		(UnitCondition.has_status(unit, Lancer.STATUS.GRAPPLED) and not unit.state.is_larger_in_grapple) or
		UnitCondition.has_status(unit, Lancer.STATUS.SHUTDOWN)
	)

static func teleport_movement_type(unit:Unit) -> MovementType:
	var movement_type := MovementType.create_for_involuntary(unit)
	movement_type.teleport = true
	return movement_type

## Every tile adjacent to the TARGET that the Banshee could actually land on -- the offer in
## activate(), and the "is this worth prompting for?" test in onhit_mourning_call.gd.
##
## The target's neighbours, not the Banshee's: the teleport lands next to the target. (That was
## Defect 1 of the original build -- the old check walked the teleporting unit's own neighbours,
## which are nearly always free at ranged distance and so validated nothing.)
##
## If the Banshee is ALREADY adjacent to the target, one of these tiles is the Banshee's own current
## tile, and it correctly reads as standable: Pathfinder's Occupation explicitly refuses to let a
## unit block itself. So staying exactly where it is remains one of the offered options rather than
## being treated as impossible. Occupying_size (2+ frames) is handled inside is_tile_standable, so
## no size-specific logic is needed here.
static func landing_tiles(teleporting_unit:Unit, target_unit:Unit) -> Array[Vector2i]:
	var tiles:Array[Vector2i] = []
	if not Unit.is_valid(teleporting_unit) or not Unit.is_valid(target_unit): return tiles
	if is_teleport_blocked(teleporting_unit): return tiles
	var movement_type := teleport_movement_type(teleporting_unit)
	var katamari := Katamari.create(teleporting_unit)
	for tile:Vector2i in UnitTile.get_adjacent_tiles(target_unit):
		if Pathfinder.is_tile_standable(teleporting_unit, tile, movement_type, katamari): tiles.append(tile)
	return tiles

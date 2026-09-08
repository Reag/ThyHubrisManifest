# Clause 8, move half: "You may expend your base movement to move the tear up to your speed. This
# does not count as taking an action."
#
# Modelled directly on vanilla's Shepherd Drone
# (content/talents/support/t_drone_commander/rank_1/action_shepherd_drone.gd), which is the
# established pattern for "pick one of my deployables, then drive it around": choice_bus.choose_unit
# for the pick, a temporary speed budget on the chosen unit, then the ordinary movement-plan loop.
# The timing differs - Shepherd is a PROTOCOL and so is start-of-turn only, while this is available
# for as long as the base movement is untouched - but the picking is deliberately identical, so it
# feels like a verb the game already has.
#
# THE MOVEMENT MODEL, and the one thing worth understanding before editing this. Base and boost
# movement are POOLED into a single number: current.speed starts at get_speed_max() and BOOST ADDS to
# it (event_unit_boost.gd:37). There is no separate boost tracker to consult.
#
# The rule "you may take this as long as you have not used the movement you get as part of your turn"
# therefore comes out as `current.speed >= get_speed_max()`. If you boosted and then moved only
# within the boost surplus, you are still at or above your full base allowance; the instant you dip
# below it you have eaten into base movement. Spending is the mirror: subtract get_speed_max(), which
# leaves any boost surplus untouched and still lets you BOOST afterwards for more.
#
# THE POOL CANNOT BE THE ONLY TEST, and that was playtest fix 8.4. Because boost ADDS to the same
# number this action subtracts from, the pool test is restored by boosting: move tear (pool drops by
# base) -> BOOST (pool rises by base) -> `current.speed >= get_speed_max()` is true again -> move
# tear again, and again for every boost the player can afford. The prose gives one base movement per
# turn, not one per boost. So the expenditure is now RECORDED rather than only inferred: activate()
# increments this action's own usage counters, and both the check below and vanilla's own
# per-round limit for naturally-free actions (action.gd:156-158 caps them at 1/round, enforced by
# UnitAction.is_under_per_round_limit) then refuse a second one.
#
# The pool test STAYS alongside it. The two answer different questions and neither subsumes the
# other: the counter catches "you already spent your base movement on a tear", the pool catches "you
# already spent it walking".
extends ActionSystem

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')

## Not a third mode of the core power. Clause 8 is a verb of Tear, described in Tear's own effect
## text, so it stays out of the gear tooltip - which lists The Keening's two parts - while remaining
## perfectly usable from the hotbar. show_in_tooltip governs the tooltip listing, not availability.
func show_in_tooltip(kit:Kit = null) -> bool: return false

func is_available_to_activate(unit:Unit, gear:GearCore) -> bool:
	if not super.is_available_to_activate(unit, gear): return false
	if not Unit.is_valid(unit): return false
	# Nothing to move.
	if TearRouting.owned_tears(unit).is_empty(): return false
	# Already spent the base movement on a tear this round - see the note at the top of this file
	# about why boosting would otherwise hand it back.
	if GearCore.is_valid(gear) and gear.get_uses_this_round(self) > 0: return false
	# A unit with no base movement cannot spend base movement.
	var base:int = unit.core.get_speed_max()
	if base <= 0: return false
	# The base allowance is untouched - see the movement model note at the top of this file.
	return unit.core.current.speed >= base

func activate(context:Context, activation:EventCore) -> void:
	var unit:Unit = context.unit
	if activation.abort_without_unit(unit): return

	var tears := TearRouting.owned_tears(unit)
	if activation.abort_when(tears.is_empty()): return

	# The pick. NOT Shepherd's choice_bus.choose_unit, which this used to copy verbatim and which is
	# an unanswerable prompt for a MARKER - see TearRouting.choose_tear for the full story. It picks
	# by tile, and skips the prompt entirely when there is only one tear.
	var chosen:Unit = await TearRouting.choose_tear(SpecificAction.from_context(context), tears)
	if activation.abort_when(not Unit.is_valid(chosen)): return

	# "up to your speed" - the BANSHEE's speed, not the tear's. A tear is a marker with no speed of
	# its own, so it is lent a budget for the duration exactly as Shepherd lends one to a drone.
	var base:int = unit.core.get_speed_max()
	var pre_speed := chosen.core.current.speed
	chosen.core.current.speed = base

	var moved:bool = await _move_the_tear(SpecificAction.from_context(context), chosen, activation)

	if Unit.is_valid(chosen): chosen.core.current.speed = pre_speed

	# NOTHING MOVED, NOTHING IS CHARGED. _move_the_tear returns normally when the player cancels the
	# movement plan (abort_without_movement_plan), and until 2026-09-08 the two lines below ran
	# anyway: cancelling the plan still ate the base movement, and once the expenditure started being
	# RECORDED (playtest fix 8.4, above) it also burned the once-per-round allowance permanently, for
	# a tear that had not budged. The abort guards inside the loop cannot cover this - the whole point
	# of them is to leave activate() running so the lent speed gets handed back on the line above.
	if not moved: return

	# Spend the base movement, leaving any boost surplus. Done AFTER the move rather than before so
	# an aborted pick costs nothing - the player who opens the menu and changes their mind has not
	# spent their turn's movement.
	if Unit.is_valid(unit):
		unit.core.current.speed = maxi(0, unit.core.current.speed - base)
		# RECORD the expenditure, so it survives a boost topping the pool back up. This is the whole
		# of playtest fix 8.4 - see the header. Deliberately NOT spend_actions(): that would also run
		# the self-heat, logging and popcorn path AND consume any ACTION_FREE buff the Banshee is
		# holding (unit_action.gd:260-262), which a naturally-free action has no business eating.
		# increment_action_usage is the narrow half that only writes the counters, and this action
		# has its own usage_group (action_tear_move) so nothing else on The Keening is billed.
		if GearCore.is_valid(context.gear):
			context.gear.increment_action_usage(context.gear.get_usage_group_for_action(self))

## The movement loop, following Shepherd's shape. Repeats until the lent budget runs out or the
## player declines a further leg, so "up to your speed" can be spent in pieces.
##
## Returns whether the tear actually MOVED - which is what activate() bills on, and the distinction
## every exit below is careful about. Cancelling the very first leg returns false (nothing happened,
## charge nothing); declining a SECOND leg after a successful first returns true (the base movement
## was genuinely spent, and the player got what they paid for).
func _move_the_tear(specific:SpecificAction, chosen:Unit, activation:EventCore) -> bool:
	var map:MapState = chosen.map
	var moved := false
	while Unit.is_valid(chosen) and chosen.core.current.speed > 0:
		var movement_type := MovementType.create_for_involuntary(specific.unit)
		movement_type.spend_move = true
		var pathfinder:Pathfinder = await Pathfinder.generate_for_movement_budget(chosen, chosen.core.current.speed, movement_type)
		if activation.abort_without_units([chosen, specific.unit]): return moved

		var plan:CompconPlan = await TargetActionUtil.ask_for_movement_alt(chosen, pathfinder, specific)
		if activation.abort_without_movement_plan(plan, specific.unit): return moved

		await run_system_fxgs(specific.unit)
		if activation.abort_without_units([chosen, specific.unit]): return moved

		var move_events := pathfinder.generate_events(chosen, plan.move_path, [], specific)
		if move_events.is_empty(): break
		await activation.execute_events(move_events)
		if move_events[0].aborted: break
		moved = true

		# The tear has changed tile, and every cache in tear_routing is keyed on tile. Invalidating
		# inside the loop rather than once at the end keeps each leg's routing answers honest for the
		# next leg's pathfinding.
		TearRouting.invalidate(map)
	return moved

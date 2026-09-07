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

	# The Shepherd pick, verbatim in shape: highlight the candidates, then ask.
	camera_bus.show_all_tiles(UnitTile.collect_all_occupied_tiles(tears), true)
	var chosen:Unit = await choice_bus.choose_unit(tears)
	if activation.abort_when(not Unit.is_valid(chosen)): return

	# "up to your speed" - the BANSHEE's speed, not the tear's. A tear is a marker with no speed of
	# its own, so it is lent a budget for the duration exactly as Shepherd lends one to a drone.
	var base:int = unit.core.get_speed_max()
	var pre_speed := chosen.core.current.speed
	chosen.core.current.speed = base

	await _move_the_tear(SpecificAction.from_context(context), chosen, activation)

	if Unit.is_valid(chosen): chosen.core.current.speed = pre_speed

	# Spend the base movement, leaving any boost surplus. Done AFTER the move rather than before so
	# an aborted pick costs nothing - the player who opens the menu and changes their mind has not
	# spent their turn's movement.
	if Unit.is_valid(unit):
		unit.core.current.speed = maxi(0, unit.core.current.speed - base)

## The movement loop, following Shepherd's shape. Repeats until the lent budget runs out or the
## player declines a further leg, so "up to your speed" can be spent in pieces.
func _move_the_tear(specific:SpecificAction, chosen:Unit, activation:EventCore) -> void:
	var map:MapState = chosen.map
	while Unit.is_valid(chosen) and chosen.core.current.speed > 0:
		var movement_type := MovementType.create_for_involuntary(specific.unit)
		movement_type.spend_move = true
		var pathfinder:Pathfinder = await Pathfinder.generate_for_movement_budget(chosen, chosen.core.current.speed, movement_type)
		if activation.abort_without_units([chosen, specific.unit]): return

		var plan:CompconPlan = await TargetActionUtil.ask_for_movement_alt(chosen, pathfinder, specific)
		if activation.abort_without_movement_plan(plan, specific.unit): return

		await run_system_fxgs(specific.unit)
		if activation.abort_without_units([chosen, specific.unit]): return

		var move_events := pathfinder.generate_events(chosen, plan.move_path, [], specific)
		if move_events.is_empty(): break
		await activation.execute_events(move_events)
		if move_events[0].aborted: break

		# The tear has changed tile, and every cache in tear_routing is keyed on tile. Invalidating
		# inside the loop rather than once at the end keeps each leg's routing answers honest for the
		# next leg's pathfinding.
		TearRouting.invalidate(map)

# Clause 8, close half: "You can close the tear as a quick action."
#
# WHY THIS LIVES ON THE BANSHEE AND NOT ON THE TEAR. The obvious reading of the prose is that the
# action belongs to the tear - select it, dismiss it, exactly as vanilla's
# content/gear/shared/action_recall/ dismisses a deployable. That is how this was first built, and it
# was UNREACHABLE: a tear is Frame.ENTITY.MARKER, and UnitAction.can_be_activated_for_faction
# (unit_action.gd:405-408) requires is_actor(), which requires is_character(). A marker never takes a
# turn, so its action bar never renders, and the action set no is_situationally_activated either - so
# neither route to it existed and every tear opened was permanent. The spec suite did not notice
# because SpecFactory.use_solo fires event_gear_activate directly, bypassing availability entirely;
# hence test_it_is_reachable_from_the_banshees_own_gear below, which is the assertion whose absence
# hid the bug.
#
# Making it situational is NOT the fix: situational actions build the SpecificAction with the
# ACTIVATING unit, so context.unit would be the Banshee and event_unit_die would kill the Banshee.
# The prose does not require the verb to live on the tear, so it lives here, on the core power,
# alongside its sibling verb Move Tear - which already had to solve the same "which of my tears?"
# problem and solved it with a choice_bus pick. The two now share a shape.
extends ActionSystem

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')

## Not a third mode of the core power. Like Move Tear, clause 8 is a verb of Tear and is described in
## Tear's own effect text, so it stays out of the gear tooltip - which lists The Keening's two parts -
## while remaining perfectly usable from the hotbar.
func show_in_tooltip(kit:Kit = null) -> bool: return false

func is_available_to_activate(unit:Unit, gear:GearCore) -> bool:
	if not super.is_available_to_activate(unit, gear): return false
	if not Unit.is_valid(unit): return false
	# Nothing to close. Without this the action sits on the bar as a click that opens an empty pick.
	return not TearRouting.owned_tears(unit).is_empty()

func activate(context:Context, activation:EventCore) -> void:
	var unit:Unit = context.unit
	if activation.abort_without_unit(unit): return

	var tears := TearRouting.owned_tears(unit)
	if activation.abort_when(tears.is_empty()): return

	# The pick, in the same shape as action_tear_move's - literally so, since both now call the one
	# shared helper. It picks by TILE: choice_bus.choose_unit, which this used until 2026-09-08, is
	# an unanswerable prompt for a MARKER, so this fix's own predecessor traded one unreachable route
	# for another. See TearRouting.choose_tear. It also skips the prompt for a single tear.
	var chosen:Unit = await TearRouting.choose_tear(SpecificAction.from_context(context), tears)
	# Cancelling costs nothing: spend_actions is below this line, not above it.
	if activation.abort_when(not Unit.is_valid(chosen)): return

	# Grabbed BEFORE the removal: once the tear is gone, chosen.map may no longer be reachable, and
	# the cache still needs dropping against the map the tear was on.
	var map:MapState = chosen.map

	# Committed. Vanilla's order for a system action is pick -> spend -> fx -> effect
	# (action_system_deploy.gd:66-75); the old tear-side version never spent anything at all, so the
	# "quick action" the prose promises was free.
	spend_actions(activation)
	await run_system_fxgs(unit, [chosen])
	if activation.abort_without_unit(chosen): return

	# The event is `event_unit_die`. Two wrong guesses were made before this one, and both failed in
	# ways that read as broken CONTENT rather than a bad call, so they are worth recording:
	#
	#   event_unit_death - does not exist. Fails with `Assertion failed: Could not create event type`
	#     and then a null-base error assigning to the resulting Nil. The action silently does nothing.
	#   event_unit_extract - exists, and is what vanilla's action_recall uses, but it is for RECALLING
	#     a deployable to its owner: it walks the roster and dies on `Nonexistent function
	#     get_lancer_by_id in base Nil` for a marker that has no lancer behind it.
	#
	# event_unit_die is what vanilla's own content/gear/shared/die_when_expires/ uses to take an
	# expiring deployable off the board, which is exactly this situation. "Die" is a blunt word for
	# closing a hole in reality, but it is the engine's verb for "this thing leaves the map".
	await activation.execute_event(&'event_unit_die', {unit = chosen})

	# The caches are keyed on tile, so a closed tear must be evicted or its visibility lingers and
	# every routed query keeps answering as though the window were still open.
	TearRouting.invalidate(map)

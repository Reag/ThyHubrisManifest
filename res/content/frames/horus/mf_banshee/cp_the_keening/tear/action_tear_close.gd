# Clause 8: "You can close the tear as a quick action."
#
# Modelled on vanilla's content/gear/shared/action_recall/, which is the existing pattern for
# dismissing a deployable as a QUICK action.
#
# The action lives on the TEAR, not on the Banshee, because the player picks which tear to close by
# selecting it. That also means the tear needs no targeting of its own - the selected unit IS the
# target, which is why context.unit rather than context.target_unit is the tear being closed.
extends ActionSystem

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')

func activate(context:Context, activation:EventCore) -> void:
	var tear:Unit = context.unit
	if not Unit.is_valid(tear): return
	# Grabbed BEFORE the removal: once the tear is gone, tear.map may no longer be reachable, and the
	# cache still needs dropping against the map the tear was on.
	var map:MapState = tear.map

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
	await activation.execute_event(&'event_unit_die', {unit = tear})

	# The caches are keyed on tile, so a closed tear must be evicted or its visibility lingers and
	# every routed query keeps answering as though the window were still open.
	TearRouting.invalidate(map)

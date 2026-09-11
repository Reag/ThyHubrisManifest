# Reinstates 1.3.3's tilepicker_ability for 1.4.0: "here is a list of tiles, pick one".
#
# 1.4.0-ONLY. This extends the 1.4.0 TilePicker contract (handle_activate(request) etc.), which does
# not parse against the 1.3.3 base class - so nothing that also runs on 1.3.3 may preload() this
# file. choice_controller.tscn_ext.gd load()s the .tscn behind a version check instead.
#
# Lifecycle (tilepicker.gd:4-16): our %ChoiceRequestReceiver (required_type = reag_tile_set, set in
# the .tscn) hears every request of that type, asks has_required_parameters, then calls
# handle_activate; a press on an offered tile answers through pick_tile(); a right-click cancels
# through the base class. Everything vanilla filters on its own type, so we never see theirs and
# they never see ours.
extends TilePicker

var given_tiles:Array[Vector2i] = []

# WHY THIS OVERRIDES _ready()/initialize() INSTEAD OF LEAVING THEM TO THE BASE CLASS.
#
# TilePicker.initialize(map_state) is what wires %ChoiceRequestReceiver up to the choice bus
# (choice_request_receiver.initialize(handle_activate, ...) -> connects on_choice_request), and the
# ONLY caller of that, for every vanilla TilePicker, is ChoiceController.initialize(map) --
# gamemaster.gd:211 and :236, called from initiate_first_round() / finish_loading_saved_game().
# SpecFactory.setup_gamemaster calls NEITHER (gamemaster.gd:209's own comment: "we don't want these
# primed when we're running tests") -- confirmed 2026-09-09, and matches test/gear/test_ms_overwatch.gd
# and test/ui/test_tilepicker_launch.gd, both of which work around the same gap by calling a picker's
# initialize() directly rather than through ChoiceController. Left as the base class wires it, our
# receiver would simply never connect in any spec, including this file's own -- test 1 (which only
# checks the NODE and its required_type, not that it actually answers) would stay green while every
# other test hung forever on an unanswered request.
#
# Wiring in _ready() instead of initialize() sidesteps that gap in BOTH contexts. This picker never
# reads `map` (handle_activate/handle_pressed_tile/has_required_parameters below use only the request's
# own params and the static effect/camera buses), so nothing is lost by wiring before a MapState
# exists. initialize(map_state) is still overridden, but ONLY to store `map` and run the base
# lifecycle hooks -- it deliberately does NOT call super.initialize(), which would wire the receiver a
# SECOND time (ChoiceRequestReceiver.initialize() connects unconditionally, with no re-entry guard) on
# any real game that still calls ChoiceController.initialize() normally.
func _ready() -> void:
	super._ready() # cursor signal connections, hide()
	choice_request_receiver.initialize(handle_activate, deactivate, has_required_parameters)

func initialize(map_state:MapState) -> void:
	map = map_state
	handle_initialize()
	hide()

func has_required_parameters(params:ChoiceRequestParams) -> bool:
	return not params.tiles.is_empty() and SpecificAction.is_valid(params.using)

func handle_activate(request:ChoiceRequest) -> void:
	given_tiles.assign(request.params.tiles)
	var style := ShrinkwrapStyle.style_for_action_flavor(request.params.using.action.get_flavor())
	effect_bus.show_range(given_tiles, Rangemesh.TYPE.ACTIVATE, style)
	camera_bus.show_all_tiles(given_tiles, true)
	activate(request)

func handle_deactivate() -> void:
	given_tiles.clear()
	effect_bus.hide_range(Rangemesh.TYPE.ACTIVATE)

func handle_pressed_tile(tile:Vector2i) -> void:
	if given_tiles.has(tile): pick_tile(tile) # -> {target_tiles = [tile]}
	# a press outside the set is ignored; a right-click cancels via TilePicker.pressed_tile

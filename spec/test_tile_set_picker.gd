# The reinstated "pick one of these tiles" prompt on 1.4.0. 1.4.0 deleted choose_target_tiles and
# tilepicker_ability; Reag-ThyHubris ships its own TilePicker for a mod-private request type,
# installed into ChoiceController by choice_controller.tscn_ext.gd. On 1.3.3 the engine's own
# tilepicker_ability still handles the prompt, so these tests pass trivially there.
#
# The open risk this file exists to settle: whether %ChoiceRequestReceiver resolves inside an
# INSTANCED sub-scene after the scene extension re-packs choice_controller.tscn.
extends GutTest

const Compat := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/reag_compat.gd')
const TestCompat := preload('res://testkit/modkit_compat.gd')

var game:Gamemaster
var unit:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	unit = SpecFactory.create_unit(game.map, Vector2i(3, 3))

func _picker() -> Node:
	return game.get_node('ChoiceController').find_child('ReagTileSetPicker', false, false)

func test_the_picker_is_installed_and_its_receiver_resolves():
	if not TestCompat.is_140():
		pass_test('1.3.3 keeps tilepicker_ability; nothing of ours to install.')
		return
	var picker := _picker()
	assert_not_null(picker, 'choice_controller.tscn_ext.gd added ReagTileSetPicker to ChoiceController.')
	if picker == null: return
	var receiver = picker.get('choice_request_receiver')
	assert_not_null(receiver, '%ChoiceRequestReceiver resolved inside the instanced sub-scene after the re-pack.')
	if receiver == null: return
	assert_eq(receiver.required_type, Compat.TILE_SET_TYPE, 'The receiver listens for our private type only.')

func test_a_press_on_an_offered_tile_answers_the_request():
	if not TestCompat.is_140():
		pass_test('1.3.3 keeps tilepicker_ability; nothing of ours to exercise.')
		return
	SpecFactory.current_responder.choose_misc_targets = false # the picker, not the responder, must answer
	var gear:GearCore = unit.get_gear(&'ms_stabilize')
	var specific := SpecificAction.create(unit, gear, gear.get_solo_action())
	var tiles:Array[Vector2i] = [Vector2i(4, 4), Vector2i(5, 5), Vector2i(6, 6)]

	var picked:Array[Vector2i] = []
	var ask := func() -> void: picked.append(await Compat.pick_tile_from(specific, tiles))
	ask.call() # runs up to the await inside pick_tile_from
	await wait_frames(2)

	var picker := _picker()
	assert_not_null(picker, 'sanity: the picker is installed.')
	if picker == null: return
	assert_true(picker.is_picking, 'The picker activated for our request.')

	picker.handle_pressed_tile(Vector2i(9, 9)) # not offered: ignored
	await wait_frames(1)
	assert_true(picked.is_empty(), 'A press outside the offered set does not answer.')

	picker.handle_pressed_tile(tiles[1])
	await wait_frames(2)
	assert_eq(picked, [tiles[1]], 'The pressed tile came back through the shim.')
	assert_false(picker.is_picking, 'The picker deactivated after answering.')

func test_cancelling_returns_invalid():
	if not TestCompat.is_140():
		pass_test('1.3.3 keeps tilepicker_ability; nothing of ours to exercise.')
		return
	SpecFactory.current_responder.choose_misc_targets = false
	var gear:GearCore = unit.get_gear(&'ms_stabilize')
	var specific := SpecificAction.create(unit, gear, gear.get_solo_action())
	var tiles:Array[Vector2i] = [Vector2i(4, 4), Vector2i(5, 5)]

	var picked:Array[Vector2i] = []
	var ask := func() -> void: picked.append(await Compat.pick_tile_from(specific, tiles))
	ask.call()
	await wait_frames(2)

	var picker := _picker()
	if picker == null: fail_test('sanity: the picker is installed.'); return
	picker.cancel()
	await wait_frames(2)
	assert_eq(picked, [Tile.INVALID], 'Cancelling resolves the request as Tile.INVALID.')

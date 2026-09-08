# "Which of my tears?" -- the pick shared by clause 8's two verbs and clause 9's relocation.
#
# THE BUG THIS FILE EXISTS FOR, reported from play as "I can't seem to move the void tears when I
# select the option that expends my base movement to change their location."
#
# All three sites asked with choice_bus.choose_unit(tears). That is served by
# ui/choice_controller/unit/tilepicker_unit.gd, which builds its clickable set straight from each
# candidate's occupied_tiles() (lines 26-28) -- so the tear's tile HIGHLIGHTS and looks pickable --
# but resolves the click through get_pickable_units_at_tile (lines 87-90), i.e.
# map.get_all_units_at_tile(tile) with include_markers defaulting to FALSE (map_state.gd:314-318). A
# tear is Frame.ENTITY.MARKER, so that list is always empty, and line 78-79 is a bare
# `if units_at_tile.is_empty(): pass`. No pick, no cancel, no feedback: the action hangs forever
# waiting for an answer that cannot arrive.
#
# WHY 569 GREEN TESTS MISSED IT, and the thing to keep in mind when adding to this file.
# SpecFactory's ChoiceBusResponder answers on_choose_unit by handing back from_units.front(). It
# never touches the tilepicker, so a prompt that is IMPOSSIBLE in the real UI is trivially
# answerable in a spec. Every test below is therefore written against the PROPERTY the UI needs --
# that the thing the player is asked to click is something the engine's own pick path can actually
# resolve -- rather than against the outcome, which was always fine.
#
# The three sites are action_tear_move.gd, action_tear_close.gd and action_mourning_call.gd's
# _maybe_relocate_tear; the first two are driven here, and the third has its own coverage in
# test_mourning_call.gd (test_the_relocation_pick_is_not_an_unanswerable_unit_pick) because it needs
# that file's kill fixture to reach clause 9 at all.
extends GutTest

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')
const BANSHEE_FRAME := 'res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/mf_banshee.tres'
const KEENING_KIT_ID := &'cp_the_keening'

var game:Gamemaster
var banshee:Unit

## Every tile set offered to a TILE pick during the test, in order. Snapshotted with duplicate(),
## since the picker hands out the live array.
var offered_tile_sets:Array = []
## Every candidate list offered to a UNIT pick. Must stay empty of tears -- that is the regression.
var offered_unit_sets:Array = []

var _capture_tiles:Callable
var _capture_units:Callable

func before_each():
	# Same fixture as test_tear_move.gd, including the campaign_core assignment that
	# setup_gamemaster's fresh-gamemaster path skips (see test_tear_object.gd's before_each for why
	# event_unit_die needs it).
	game = SpecFactory.setup_gamemaster(self, true, SpecFactory.create_combat(Landscape.create_default(Vector2i(14,14))))
	game.campaign_core = CampaignCore.create(SpecFactory.create_campaign_base())
	game.map.campaign_core = game.campaign_core

	banshee = SpecFactory.create_unit(game.map, Vector2i(1,1))
	banshee.core.change_mech_frame(load(BANSHEE_FRAME))
	banshee.state.overcharge_actions = 99 # several tear actions in one turn
	banshee.update_cached_values_and_token(SpecFactory.dummy_event())
	banshee.core.current.speed = banshee.core.get_speed_max()

	offered_tile_sets = []
	offered_unit_sets = []
	# Listening ALONGSIDE SpecFactory's responder rather than replacing it: it still answers, so the
	# actions run to completion and the outcome assertions below stay meaningful.
	_capture_tiles = func(_request, _specific, from_tiles): offered_tile_sets.append(from_tiles.duplicate())
	_capture_units = func(_request, from_units, _can_cancel, _specific, _secondary): offered_unit_sets.append(from_units.duplicate())
	SpecFactory.choice_bus.on_choose_target_tiles.connect(_capture_tiles)
	SpecFactory.choice_bus.on_choose_unit.connect(_capture_units)

func after_each():
	SpecFactory.choice_bus.on_choose_target_tiles.disconnect(_capture_tiles)
	SpecFactory.choice_bus.on_choose_unit.disconnect(_capture_units)
	TearRouting.invalidate(game.map)

# ---------------------------------------------------------------------------- helpers

func _place_tear(tile:Vector2i) -> void:
	await SpecFactory.use(game, banshee, KEENING_KIT_ID, &'action_tear', [tile])

func _tears() -> Array[Unit]:
	return TearRouting.open_tears(game.map)

## Any unit pick that was offered a tear. A unit pick for something else would be fine; a unit pick
## for a MARKER is the dead click.
func _unit_picks_offering_a_tear() -> int:
	var count := 0
	for candidates:Array in offered_unit_sets:
		for candidate in candidates:
			if candidate is Unit and TearRouting.is_tear(candidate):
				count += 1
				break
	return count

# ---------------------------------------------------------------------------- the predicate

func test_the_engines_unit_pick_path_cannot_see_a_tear():
	# THE WHOLE BUG IN ONE ASSERTION, and the predicate every other test in this file is protecting.
	# This is exactly the call tilepicker_unit.get_pickable_units_at_tile makes to turn a click into
	# a chosen unit. If it ever starts returning the tear, choose_unit becomes usable and the tile
	# indirection below could be reconsidered -- until then, a unit pick over tears is dead code that
	# hangs the game.
	await _place_tear(Vector2i(4,4))
	var tears := _tears()
	if tears.size() != 1: return fail_test('Fixture: exactly one tear.')
	var tear:Unit = tears.front()

	assert_false(
		game.map.get_all_units_at_tile(tear.tile()).has(tear),
		'A click on a tear resolves to nothing: include_markers defaults to false and a tear is a MARKER.'
	)
	assert_true(
		game.map.get_all_units_at_tile(tear.tile(), null, true).has(tear),
		'Sanity: the tear IS on that tile - only the marker filter hides it, so this is not a fixture problem.'
	)

func test_a_picked_tile_resolves_back_to_its_tear_without_asking_the_map():
	# The other half: the resolution the helper actually uses. It matches against the candidate list
	# it already holds, so it works on exactly the tiles the map lookup above cannot answer for.
	await _place_tear(Vector2i(4,4))
	await _place_tear(Vector2i(6,6))
	var tears := _tears()
	if tears.size() != 2: return fail_test('Fixture: two tears.')

	for tear:Unit in tears:
		assert_eq(TearRouting.tear_at_tile(tears, tear.tile()), tear,
			'Each tear tile resolves back to the tear standing on it.')
	assert_null(TearRouting.tear_at_tile(tears, Vector2i(9,9)),
		'And a tile with no tear on it resolves to nothing rather than to the first candidate.')

func test_a_tear_outside_the_candidate_list_is_not_resolvable():
	# Ownership is enforced by WHICH LIST is passed in, so the resolver must never widen it. The
	# tempting map.get_all_units_at_tile(tile, null, true) would happily hand back somebody else's
	# tear standing on a clicked tile.
	await _place_tear(Vector2i(4,4))
	var tears := _tears()
	if tears.size() != 1: return fail_test('Fixture: one tear.')
	var nobodys:Array[Unit] = [] # typed, so the call is the real signature rather than a coerced literal
	assert_null(TearRouting.tear_at_tile(nobodys, tears.front().tile()),
		'An empty candidate list resolves nothing, whatever is standing there.')

# ---------------------------------------------------------------------------- clause 8: move

func test_moving_a_tear_never_opens_a_unit_pick():
	# THE REGRESSION TEST. Before 2026-09-08 this action asked choice_bus.choose_unit(tears), which
	# the player could not answer.
	await _place_tear(Vector2i(4,4))
	await _place_tear(Vector2i(6,6))
	if _tears().size() != 2: return fail_test('Fixture: two tears, so a pick is genuinely needed.')

	await SpecFactory.use(game, banshee, KEENING_KIT_ID, &'action_tear_move')
	assert_eq(_unit_picks_offering_a_tear(), 0,
		'Move Tear asks by tile. A unit pick over MARKERs is an unanswerable prompt.')

func test_moving_a_tear_offers_exactly_the_tear_tiles():
	await _place_tear(Vector2i(4,4))
	await _place_tear(Vector2i(6,6))
	var tears := _tears()
	if tears.size() != 2: return fail_test('Fixture: two tears.')
	var tear_tiles:Array[Vector2i] = [tears[0].tile(), tears[1].tile()]

	await SpecFactory.use(game, banshee, KEENING_KIT_ID, &'action_tear_move')
	if offered_tile_sets.is_empty(): return fail_test('The player was offered a tile pick at all.')

	var pick:Array = offered_tile_sets.front()
	assert_eq(pick.size(), tear_tiles.size(), 'One offered tile per tear, and nothing else.')
	for tile:Vector2i in pick:
		assert_true(tear_tiles.has(tile), 'Every offered tile has a tear on it: %s' % tile)
	for tile:Vector2i in tear_tiles:
		assert_true(pick.has(tile), 'And every tear is offered: %s' % tile)

func test_the_tear_that_moves_is_the_one_whose_tile_was_picked():
	# End to end: the tile the player clicked, resolved back to a unit, is the unit that moved. This
	# is what the dead unit pick could never do.
	await _place_tear(Vector2i(4,4))
	await _place_tear(Vector2i(6,6))
	var tears := _tears()
	if tears.size() != 2: return fail_test('Fixture: two tears.')
	var before:Dictionary = {}
	for tear:Unit in tears: before[tear] = tear.tile()

	await SpecFactory.use(game, banshee, KEENING_KIT_ID, &'action_tear_move')
	if offered_tile_sets.is_empty(): return fail_test('A tile pick was offered.')

	# SpecFactory's responder answers a tile pick with the front of the offered list, so there is
	# exactly one thing "the chosen tile" can mean here.
	#
	# Resolved against the PRE-MOVE tiles, deliberately: TearRouting.tear_at_tile reads
	# occupied_tiles() live, and the whole point of this test is that the picked tear is no longer
	# standing where it was picked.
	var chosen_tile:Vector2i = offered_tile_sets.front().front()
	var chosen:Unit = null
	for tear:Unit in tears:
		if before[tear] == chosen_tile: chosen = tear
	if not Unit.is_valid(chosen): return fail_test('The chosen tile was one of the tear tiles offered.')

	assert_ne(chosen.tile(), before[chosen], 'The picked tear moved.')
	for tear:Unit in tears:
		if tear == chosen: continue
		assert_eq(tear.tile(), before[tear], 'And no other tear did.')

func test_moving_a_single_tear_asks_nothing():
	# There is nothing to decide with one candidate, and until this rewrite the prompt was not merely
	# friction but unanswerable - which is how the commonest case reproduced the bug every time.
	await _place_tear(Vector2i(4,4))
	if _tears().size() != 1: return fail_test('Fixture: exactly one tear.')

	await SpecFactory.use(game, banshee, KEENING_KIT_ID, &'action_tear_move')
	assert_eq(_unit_picks_offering_a_tear(), 0, 'No unit pick.')
	assert_eq(offered_tile_sets.size(), 0, 'And no tile pick either - the lone tear is simply taken.')

# ---------------------------------------------------------------------------- clause 8: close

func test_closing_a_tear_never_opens_a_unit_pick():
	# action_tear_close was itself a fix, landed the same day, for a DIFFERENT unreachability bug:
	# the action used to live on the tear's own kit, where a marker's action bar never renders. It
	# replaced one unreachable route with another.
	await _place_tear(Vector2i(4,4))
	await _place_tear(Vector2i(6,6))
	if _tears().size() != 2: return fail_test('Fixture: two tears.')

	await SpecFactory.use(game, banshee, KEENING_KIT_ID, &'action_tear_close')
	assert_eq(_unit_picks_offering_a_tear(), 0,
		'Close Tear asks by tile. A unit pick over MARKERs is an unanswerable prompt.')

func test_the_tear_that_closes_is_the_one_whose_tile_was_picked():
	await _place_tear(Vector2i(4,4))
	await _place_tear(Vector2i(6,6))
	var tears := _tears()
	if tears.size() != 2: return fail_test('Fixture: two tears.')

	await SpecFactory.use(game, banshee, KEENING_KIT_ID, &'action_tear_close')
	if offered_tile_sets.is_empty(): return fail_test('A tile pick was offered.')
	var chosen_tile:Vector2i = offered_tile_sets.front().front()

	var survivors := _tears()
	assert_eq(survivors.size(), 1, 'Exactly one tear closed.')
	if survivors.is_empty(): return
	assert_ne(survivors.front().tile(), chosen_tile,
		'The tear that closed is the one standing on the picked tile, not the other one.')

func test_closing_a_single_tear_asks_nothing():
	await _place_tear(Vector2i(4,4))
	if _tears().size() != 1: return fail_test('Fixture: exactly one tear.')

	await SpecFactory.use(game, banshee, KEENING_KIT_ID, &'action_tear_close')
	assert_eq(_unit_picks_offering_a_tear(), 0, 'No unit pick.')
	assert_eq(offered_tile_sets.size(), 0, 'And no tile pick either.')
	assert_eq(_tears().size(), 0, 'The lone tear is simply closed.')

# ---------------------------------------------------------------------------- cancelling the move

func test_cancelling_the_movement_plan_costs_no_base_movement():
	# THE SECOND BUG, separate from the pick. _move_the_tear returns NORMALLY when the player cancels
	# the movement plan (abort_without_movement_plan), and activate() used to spend the base movement
	# and bump the usage counter regardless. Cancelling therefore cost a turn's movement for a tear
	# that had not budged.
	#
	# abort_all makes the responder abort every request, which is what the cancel button does. It is
	# safe to leave on for the whole activation here precisely BECAUSE the single-tear case now skips
	# the pick: the only request left to abort is the movement plan itself.
	await _place_tear(Vector2i(4,4))
	var tears := _tears()
	if tears.size() != 1: return fail_test('Fixture: exactly one tear.')
	var tear_tile:Vector2i = tears.front().tile()
	var base:int = banshee.core.get_speed_max()
	var gear:GearCore = banshee.get_gear(KEENING_KIT_ID)
	if not GearCore.is_valid(gear): return fail_test('The Banshee carries The Keening.')

	SpecFactory.current_responder.abort_all = true
	await SpecFactory.use(game, banshee, KEENING_KIT_ID, &'action_tear_move')
	SpecFactory.current_responder.abort_all = false

	assert_eq(_tears().front().tile(), tear_tile, 'Sanity: the tear did not move.')
	assert_eq(banshee.core.current.speed, base, 'So the base movement is still there to spend.')
	assert_eq(gear.get_uses_this_round_alt(&'action_tear_move'), 0,
		'And the once-per-round allowance was not burned - which, since playtest fix 8.4 records it, would have been permanent.')

func test_cancelling_leaves_the_verb_still_available():
	# The user-visible consequence of the above, asked the way the UI asks it.
	await _place_tear(Vector2i(4,4))
	if _tears().size() != 1: return fail_test('Fixture: exactly one tear.')

	SpecFactory.current_responder.abort_all = true
	await SpecFactory.use(game, banshee, KEENING_KIT_ID, &'action_tear_move')
	SpecFactory.current_responder.abort_all = false

	var specific := SpecificAction.from_id(banshee, KEENING_KIT_ID, &'action_tear_move')
	if not SpecificAction.is_valid(specific): return fail_test('The action exists on the gear.')
	assert_true(specific.action.is_available_to_activate(banshee, specific.gear),
		'A cancelled move changes nothing, so Move Tear is still on offer.')

func test_a_completed_move_does_still_charge():
	# The other side of the same line - the fix must not turn the charge off altogether.
	await _place_tear(Vector2i(4,4))
	if _tears().size() != 1: return fail_test('Fixture: exactly one tear.')
	var base:int = banshee.core.get_speed_max()
	var gear:GearCore = banshee.get_gear(KEENING_KIT_ID)
	if not GearCore.is_valid(gear): return fail_test('The Banshee carries The Keening.')

	await SpecFactory.use(game, banshee, KEENING_KIT_ID, &'action_tear_move')
	assert_lt(banshee.core.current.speed, base, 'A move that happened spends the base movement.')
	assert_eq(gear.get_uses_this_round_alt(&'action_tear_move'), 1, 'And is recorded once.')

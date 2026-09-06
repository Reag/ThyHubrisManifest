# Integration: does tear routing actually reach the engine?
#
# test_tear_routing.gd proves the RULES with no extension involved. This file proves the SEAMS. If
# this is red while that is green, an extension is not firing - which is a precise signal, and the
# reason the brain lives in plain script.
extends GutTest

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')

var game:Gamemaster
var banshee:Unit
var ghost:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self, true, SpecFactory.create_combat(Landscape.create_default(Vector2i(12,12))))
	banshee = SpecFactory.create_unit(game.map, Vector2i(1,1))
	ghost = SpecFactory.create_unit(game.map, Vector2i(10,10), Faction.AI_ENEMY)
	SpecFactory.apply(ghost, Lancer.STATUS.INTANGIBLE)

func after_each():
	TearRouting.invalidate(game.map)

func test_line_of_sight_is_widened_through_a_tear():
	# The seam assertion. A tile the tear can see must appear in the viewer's line of sight.
	#
	# CANNOT be tested on the bare create_default map used elsewhere in this file: that landscape is
	# flat with zero blockers, so get_tiles_in_los already returns every tile on the board with no
	# range cap (confirmed against unit_tile.gd:525-543 and the permissive-visibility sightline
	# layer, which caps nothing but elevation). A tear placed at (6,6) can only contribute tiles that
	# are ALREADY in that total, so before == after regardless of whether the seam fires - the
	# original form of this test could never go red even with a dead extension. A real obstruction is
	# required to make "not yet visible" a meaningful state.
	#
	# The wall geometry is from test/gamemaster/test_map_sightlines.gd
	# (test_elevation_blocks_los_in_abstract): a blocker at (2,1)-(2,3), with (4,0) visible around its
	# open end and (4,1) shadowed behind it.
	#
	# The HEIGHT is deliberately 4 rather than that test's 2. That test queries can_tile_see with an
	# explicit layer of 1, whereas get_tiles_in_los derives its height from
	# UnitTile.effective_height(unit, ...) and then takes maxi(from_height, to_height) - and a unit
	# standing on flat ground is tall enough to see straight over a height-2 wall. Vanilla says so
	# itself two lines later: at layer 2 the same wall stops blocking. A wall the viewer can see over
	# makes the sanity check below fail and the whole test meaningless, so it has to out-top the unit.
	SpecFactory.set_tiles_elevation(game.map, 4, [Vector2i(2,1), Vector2i(2,2), Vector2i(2,3)])
	game.map.calculate_los_blockers()

	var hidden_tile := Vector2i(4,1)
	var before := UnitTile.get_tiles_in_los(banshee)
	assert_false(Tile.in_bitwise_array(before, hidden_tile),
		'Sanity check: the wall genuinely blocks direct sight to the hidden tile.')

	# Placed around the open end of the wall: visible to the Banshee directly (same spot vanilla
	# proves visible from (1,1)), and with a plain, unobstructed line of its own to the hidden tile.
	_place_tear(Vector2i(4,0))
	var after := UnitTile.get_tiles_in_los(banshee)
	assert_true(Tile.in_bitwise_array(after, hidden_tile),
		'Opening a tear changes what the Banshee can see. If this is red the unit_tile seam is dead.')

func test_get_tiles_within_falls_back_through_a_tear():
	# THE OTHER SEAM. unit_tile.gd_ext.gd overrides two functions: get_tiles_in_los (tested above) and
	# is_tile_in_los. UnitTile.get_tiles_within uses a precalculated_los array when the caller passes
	# one, and otherwise falls back to calling is_tile_in_los directly per-tile (unit_tile.gd:560-602)
	# - and WHICH of those two happens is decided entirely by the caller, not by anything in this mod.
	# The nine producers in engine/ai/, gear_action/action.gd:275 and the ui/ tilepickers all go
	# through the fallback with no precalculated array. A broken is_tile_in_los override would ship
	# green forever if only get_tiles_in_los were ever exercised - which is exactly what this file did
	# before this test.
	#
	# Same wall fixture as test_line_of_sight_is_widened_through_a_tear, for the same reason: a flat,
	# blocker-free map has nothing hidden to reveal, so "not otherwise visible" needs to be a real
	# state or a broken override could ship green here too.
	SpecFactory.set_tiles_elevation(game.map, 4, [Vector2i(2,1), Vector2i(2,2), Vector2i(2,3)])
	game.map.calculate_los_blockers()
	var hidden_tile := Vector2i(4,1)

	# No precalculated_los argument: use_precalculated_los is false inside get_tiles_within, so it
	# calls UnitTile.is_tile_in_los itself - the fallback path, not the sweep test_line_of_sight_is
	# _widened_through_a_tear already covers. The range is comfortably above Tile.MAX_MAP_HEIGHT (13)
	# so the elevation-reach filter (unit_tile.gd:274) never disqualifies the target on its own,
	# leaving line of sight as the only thing gating whether the tile comes back.
	var before := UnitTile.get_tiles_within(banshee, 20, true)
	assert_false(before.has(hidden_tile),
		'Sanity check: the wall blocks the fallback path too, before any tear is open.')

	_place_tear(Vector2i(4,0))
	var after := UnitTile.get_tiles_within(banshee, 20, true)
	assert_true(after.has(hidden_tile),
		'Opening a tear reaches the hidden tile through get_tiles_within too. If this is red, ' +
		'is_tile_in_los is dead even though get_tiles_in_los works.')

func test_the_seam_is_inert_when_no_tear_is_open():
	# Guards the other direction: the override must be inert when no tear is on the map, or every
	# other frame in the game inherits the Banshee's optics.
	#
	# Asserted against the ROUTING CONTRIBUTION, not by calling get_tiles_in_los twice and comparing
	# - two identical calls are equal whether or not the override does anything, so that form would
	# pass on a completely broken seam.
	#
	# The old second assertion compared this against UnitTile.get_tiles_in_los_alt(game.map,
	# banshee.tile()) directly - NOT an equivalent computation. get_tiles_in_los derives origin height
	# from UnitTile.effective_height(unit, ...) (ground plus the unit's own body height);
	# get_tiles_in_los_alt derives it from raw map.elevation(from_tile), with no unit term at all. On
	# the flat, blocker-free map used elsewhere in this file the two coincidentally agree, because both
	# trivially return every tile - so the comparison passed without ever exercising the terms it
	# claimed to check, and would have quietly misfired the moment either side saw an obstruction.
	#
	# Replaced with a genuine, single-function, non-trivial check: the same wall fixture as
	# test_line_of_sight_is_widened_through_a_tear, asserting the override does not spuriously grant
	# sight to the tile the wall hides when no tear is open. A flat map has nothing hidden to guard, so
	# this needs real terrain to mean anything.
	SpecFactory.set_tiles_elevation(game.map, 4, [Vector2i(2,1), Vector2i(2,2), Vector2i(2,3)])
	game.map.calculate_los_blockers()
	var hidden_tile := Vector2i(4,1)

	var contribution := TearRouting.tiles_visible_via_tears(game.map, banshee.tile())
	assert_true(Tile.is_bitwise_array_empty(contribution), 'Routing adds nothing with no tears open.')

	var los := UnitTile.get_tiles_in_los(banshee)
	assert_false(Tile.in_bitwise_array(los, hidden_tile),
		'With no tear open, the wall still blocks - the override adds no sight of its own on real terrain.')

func _place_tear(tile:Vector2i) -> Unit:
	var tear := SpecFactory.create_unit(game.map, tile)
	tear.core.frame = load('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/dep_tear_banshee.tres')
	tear.update_cached_values_and_token(SpecFactory.dummy_event())
	TearRouting.invalidate(game.map)
	return tear

func test_a_tear_opens_the_window_between_tangible_and_intangible():
	assert_false(UnitRelation.can_affect(banshee, ghost), 'No window before the tear.')
	_place_tear(Vector2i(6,6))
	assert_true(UnitRelation.can_affect(banshee, ghost),
		'Clause 3: a tear is a window between tangible and intangible space.')

func test_the_window_is_symmetric():
	_place_tear(Vector2i(6,6))
	assert_true(UnitRelation.can_affect(ghost, banshee),
		'And the intangible can reach back. can_affect is asked from both sides.')

func test_the_window_is_universal():
	# The agreed reading: tears are terrain, not a personal periscope. Two characters who are not
	# the Banshee route through the Banshee's tear, including enemies shooting back through it.
	var solid := SpecFactory.create_unit(game.map, Vector2i(2,2), Faction.AI_ENEMY)
	_place_tear(Vector2i(6,6))
	assert_true(UnitRelation.can_affect(solid, ghost),
		'Any character routes through any tear.')

func test_the_kraken_tide_still_works():
	# This file also carries the Kraken's tangibility workaround. Adding to it must not disturb that.
	# The Tide's own suite is the real guard; this is a smoke check that both rules coexist.
	assert_false(UnitRelation.can_affect(banshee, ghost),
		'With no tear, vanilla tangibility still refuses - the Banshee rule is not always-on.')

# The Banshee's tear routing, tested WITHOUT any engine extension.
#
# This is the point of keeping the brain in plain script: these specs stay meaningful even if an
# extension seam turns out dead, and a dead seam then shows up as one failing integration spec in
# test_tear_window.gd rather than as "the engine just does not do that".
extends GutTest

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')

var game:Gamemaster

func before_each():
	# A real landscape, NOT SpecFactory.create_map_state - routing calls line of sight, and a bare
	# MapState has no sightline layer, so every can_tile_see fails inside the GDExtension.
	game = SpecFactory.setup_gamemaster(self, true, SpecFactory.create_combat(Landscape.create_default(Vector2i(12,12))))

func after_each():
	TearRouting.invalidate(game.map)

func test_no_tears_means_no_routing():
	assert_false(TearRouting.routes_between(game.map, Vector2i(0,0), Vector2i(11,11)),
		'With no tear on the map, nothing routes.')

func test_the_cap_is_fifteen():
	# Lowered from 99 on the Probe 3 measurements. One constant, one place.
	assert_eq(TearRouting.MAX_TEARS, 15, 'MAX_TEARS is 15.')

func test_a_tear_routes_between_two_tiles_that_can_both_see_it():
	var tear := _place_tear(Vector2i(6,6))
	assert_true(TearRouting.open_tears(game.map).has(tear), 'The tear is open.')
	assert_true(TearRouting.routes_between(game.map, Vector2i(1,1), Vector2i(11,11)),
		'Both ends see the tear on an open map, so the route exists.')

func test_routing_is_symmetric():
	# can_affect is asked from both sides at different call sites. An asymmetric answer would let a
	# character shoot something that could not shoot back.
	_place_tear(Vector2i(6,6))
	assert_eq(
		TearRouting.routes_between(game.map, Vector2i(1,1), Vector2i(11,11)),
		TearRouting.routes_between(game.map, Vector2i(11,11), Vector2i(1,1)),
		'Routing gives the same answer in both directions.')

func test_tiles_visible_via_tears_includes_what_the_tear_can_see():
	_place_tear(Vector2i(6,6))
	var via := TearRouting.tiles_visible_via_tears(game.map, Vector2i(1,1))
	assert_true(Tile.in_bitwise_array(via, Vector2i(11,11)),
		'A tile the tear can see is reachable through it.')

func test_an_unobstructed_viewer_routes_through_the_tear():
	# The first leg is ordinary line of sight and terrain blocks it normally - the agreed relaxation
	# removed the terrain-ignoring clauses, so this is the whole rule.
	_place_tear(Vector2i(6,6))
	var via := TearRouting.tiles_visible_via_tears(game.map, Vector2i(1,1))
	assert_false(Tile.is_bitwise_array_empty(via), 'An unobstructed viewer routes.')

func test_routing_contributes_nothing_when_no_tear_is_open():
	# Inertness, asserted directly rather than by comparing two identical calls. Every other frame in
	# the game runs through this code path, so "contributes nothing" is the load-bearing property.
	assert_true(Tile.is_bitwise_array_empty(TearRouting.tiles_visible_via_tears(game.map, Vector2i(1,1))),
		'With no tears open, routing adds no tiles at all.')

func test_routing_terminates_when_the_los_seam_calls_back_into_it():
	# THE RECURSION GUARD. unit_tile.gd_ext.gd overrides is_tile_in_los to consult this library, and
	# this library computes visibility with get_tiles_in_los_alt, which calls is_tile_in_los. Without
	# the _computing flag that is unbounded recursion and the spec run hangs rather than failing.
	#
	# This test exists because a hang is the worst possible failure mode here: it looks like a slow
	# suite, not a bug, and Probe 3 already trained everyone to expect tear work to be slow.
	_place_tear(Vector2i(6,6))
	var start := Time.get_ticks_msec()
	for i:int in 50:
		TearRouting.routes_between(game.map, Vector2i(1,1), Vector2i(11,11))
	assert_lt(Time.get_ticks_msec() - start, 5000,
		'Fifty routing queries finish promptly - no runaway reentry.')

## Place a tear-frame deployable at a tile. Task 3 builds the real resource; until then this spec
## fails at load, which is the correct RED.
func _place_tear(tile:Vector2i) -> Unit:
	var tear := SpecFactory.create_unit(game.map, tile)
	tear.core.frame = load('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/dep_tear_banshee.tres')
	tear.update_cached_values_and_token(SpecFactory.dummy_event())
	TearRouting.invalidate(game.map)
	return tear

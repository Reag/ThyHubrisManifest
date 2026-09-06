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

func test_tiles_visible_via_tears_reaches_a_cross_tangible_unit():
	# tiles_visible_via_tears returns the tiles of units the viewer may LEGITIMATELY route to, not
	# every tile a tear happens to see. Clauses 4 and 5 both require a tangibility mismatch, so a
	# cross-tangible occupant is what makes a tile reachable at all.
	var viewer := SpecFactory.create_unit(game.map, Vector2i(1,1))
	var ghost := SpecFactory.create_unit(game.map, Vector2i(11,11), Faction.AI_ENEMY)
	SpecFactory.apply(ghost, Lancer.STATUS.INTANGIBLE)
	_place_tear(Vector2i(6,6))

	var via := TearRouting.tiles_visible_via_tears(game.map, viewer, viewer.tile())
	assert_true(Tile.in_bitwise_array(via, ghost.tile()),
		'An intangible character on the far side of a tear is reachable through it.')

func test_a_same_tangibility_unit_is_never_reachable_through_a_tear():
	# THE PERISCOPE REGRESSION. Before this gate existed, an open tear widened line of sight for
	# every unit on the map towards every tile - so two ordinary tangible mechs, neither of them a
	# Banshee, could shoot each other around a corner. No clause grants that: clause 4 is intangible
	# to tangible, clause 5 is tangible to intangible, and both require a MISMATCH.
	var viewer := SpecFactory.create_unit(game.map, Vector2i(1,1))
	var solid := SpecFactory.create_unit(game.map, Vector2i(11,11), Faction.AI_ENEMY)
	_place_tear(Vector2i(6,6))

	var via := TearRouting.tiles_visible_via_tears(game.map, viewer, viewer.tile())
	assert_false(Tile.in_bitwise_array(via, solid.tile()),
		'A tangible pair gets nothing from a tear - it is a window, not a periscope.')

func test_routing_contributes_nothing_when_no_tear_is_open():
	# Inertness, asserted directly rather than by comparing two identical calls. Every other frame in
	# the game runs through this code path, so "contributes nothing" is the load-bearing property.
	var viewer := SpecFactory.create_unit(game.map, Vector2i(1,1))
	var ghost := SpecFactory.create_unit(game.map, Vector2i(11,11), Faction.AI_ENEMY)
	SpecFactory.apply(ghost, Lancer.STATUS.INTANGIBLE)
	assert_true(Tile.is_bitwise_array_empty(TearRouting.tiles_visible_via_tears(game.map, viewer, viewer.tile())),
		'With no tears open, routing adds no tiles at all - even for a pair that would qualify.')

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

func test_visibility_cache_is_scoped_per_map():
	# Regression for the pre-fix cache: it was a flat Dictionary keyed on Vector2i tile alone, with
	# nothing tying an entry to the MapState it was computed against. A single GUT run creates many
	# maps across spec files, and tile (6,6) on one map is not tile (6,6) on another - so whichever
	# map populated that tile's entry first would silently answer for every other map afterward.
	#
	# This does not need a real tear (and so does not need dep_tear_banshee.tres, which Task 3 has
	# not built yet): the bug lives in the cache underneath routing, in _visibility_of, so it can be
	# exercised directly without going through open_tears at all.
	var map_a:MapState = game.map
	var game_b:Gamemaster = SpecFactory.setup_gamemaster(self, true, SpecFactory.create_combat(Landscape.create_default(Vector2i(12,12))))
	var map_b:MapState = game_b.map
	assert_ne(map_a.get_instance_id(), map_b.get_instance_id(), 'Sanity: the two maps are distinct instances.')

	# Populate map A's cache for (6,6), then poison that entry with the blank bitwise array - a value
	# no real sweep of an open, unobstructed 12x12 map would ever produce for its center tile. Against
	# the OLD tile-only cache this poisoned entry IS the entry for (6,6), full stop, on any map.
	TearRouting._visibility_of(map_a, Vector2i(6,6))
	TearRouting._visibility_cache[map_a.get_instance_id()][Vector2i(6,6)] = Tile.create_blank_bitwise_array()

	# Map B has never been queried before. If the cache were still tile-only, this call would return
	# map A's poisoned entry instead of doing a real sweep.
	var visible_b := TearRouting._visibility_of(map_b, Vector2i(6,6))
	assert_false(Tile.is_bitwise_array_empty(visible_b),
		'Map B computes its own visibility for (6,6) rather than inheriting map A\'s poisoned entry.')

	# invalidate(map) honouring its argument: dropping map A must not touch map B.
	TearRouting.invalidate(map_a)
	assert_false(TearRouting._visibility_cache.has(map_a.get_instance_id()),
		'invalidate(map_a) drops map A\'s entries.')
	assert_true(TearRouting._visibility_cache.has(map_b.get_instance_id()),
		'invalidate(map_a) must leave map B\'s entries untouched.')

	TearRouting.invalidate(map_b)

## Place a tear-frame deployable at a tile. Task 3 builds the real resource; until then this spec
## fails at load, which is the correct RED.
func _place_tear(tile:Vector2i) -> Unit:
	var tear := SpecFactory.create_unit(game.map, tile)
	tear.core.frame = load('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/dep_tear_banshee.tres')
	tear.update_cached_values_and_token(SpecFactory.dummy_event())
	TearRouting.invalidate(game.map)
	return tear

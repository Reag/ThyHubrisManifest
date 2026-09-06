# Tear routing for the Banshee. The brain behind clauses 3, 4 and 5.
#
# DELIBERATELY NOT A SCRIPT EXTENSION. The two .gd_ext.gd shims on unit_relation.gd and unit_tile.gd
# do nothing but delegate here, so every rule below is testable without an extension having to fire.
# This project has three confirmed cases of extensions that install cleanly and never run, so a
# testable brain is worth the indirection.
#
# HARD CONSTRAINT: nothing here may consult buffs. can_affect delegates to this file, and aura buff
# delivery is itself gated on can_affect (passive_aura.gd:68), so a buff lookup here closes a real
# cycle. Ask about tears and geometry, nothing else.
#
# THE RULE, after the agreed terrain relaxation:
#
#     routes(a, b) = los(a -> tear) AND los(tear -> b)   for some open tear
#
# Both legs are ordinary line of sight with ordinary terrain blocking, so the two directions are the
# same computation and there is no asymmetry to get wrong.
extends RefCounted

## Lowered from 99 on the 2026-09-06 measurements: 99 tears on a 30x30 map is 370 ms of sweep.
## Cached, that is a one-off rebuild when a tear moves rather than a per-query cost, but the
## per-viewer union still grows with tear count. Tunable - this is a starting value, not a ceiling.
const MAX_TEARS := 15

const TEAR_FRAME_ID := &'dep_tear_banshee'

## map instance id -> (tile -> the tiles visible from it). Keyed by TILE within a map, not by unit,
## because get_tiles_in_los_alt depends only on the tile and the map - never on who is looking. That
## is what makes the cache collapse the units x tears multiplier to a bitwise OR.
##
## The outer level exists because a single GUT run creates many MapStates across spec files, and
## tile (2,2) on one map is not tile (2,2) on another - a bare tile-keyed dictionary would let a
## stale entry from an earlier map answer a query against a later one. Keying on
## map.get_instance_id() ties every cached entry to the exact map it was computed against, so two
## maps sharing a coordinate never collide.
static var _visibility_cache:Dictionary = {}

## map instance id -> Array[Vector2i] of every open tear's tile on that map. routes_between calls
## tear_tiles on every query - once per candidate tile in is_tile_in_los, once per is_tile_in_los
## call, in every spec in the mod whether or not a tear exists - and unlike _visibility_of it was
## never cached, so it paid a full map.get_all_units() scan every time. Same per-map keying as
## _visibility_cache and for the same reason: two maps can share a tile, never an instance id.
static var _tear_tile_cache:Dictionary = {}

## REENTRANCY GUARD, and it is load-bearing rather than defensive.
##
## unit_tile.gd_ext.gd overrides is_tile_in_los to consult this file. This file computes visibility
## with UnitTile.get_tiles_in_los_alt, which calls UnitTile.is_tile_in_los (unit_tile.gd:553 -> :483)
## - the overridden one. Without this flag that is unbounded recursion: routing -> sweep -> override
## -> routing.
##
## While a sweep is in flight, routing answers "no tear route". That is the correct answer, not a
## compromise: the sweep is computing ORDINARY line of sight from a tile, which is exactly the input
## the routing rule is built on top of. Letting a tear widen its own input would make the geometry
## self-referential.
static var _computing := false

static func open_tears(map:MapState) -> Array[Unit]:
	if not is_instance_valid(map): return []
	var tears:Array[Unit] = []
	for unit:Unit in map.get_all_units():
		if not Unit.is_valid(unit): continue
		if unit.core.frame.compcon_id == TEAR_FRAME_ID: tears.append(unit)
	return tears

## Cached per map - see _tear_tile_cache. Invalidated the same way and by the same callers as the
## visibility cache, since both go stale exactly when a tear is created, moved or closed.
static func tear_tiles(map:MapState) -> Array[Vector2i]:
	if not is_instance_valid(map): return []
	var map_id := map.get_instance_id()
	if _tear_tile_cache.has(map_id): return _tear_tile_cache[map_id]
	var tiles:Array[Vector2i] = []
	for tear:Unit in open_tears(map): tiles.append(tear.tile())
	_tear_tile_cache[map_id] = tiles
	return tiles

## Does some open tear bridge these two tiles? Symmetric by construction.
static func routes_between(map:MapState, from_tile:Vector2i, to_tile:Vector2i) -> bool:
	if _computing: return false # see _computing
	var tiles := tear_tiles(map)
	if tiles.is_empty(): return false # fast path: no open tear, no route - skip the sweep entirely.
	for tear_tile:Vector2i in tiles:
		if not _sees(map, from_tile, tear_tile): continue
		if _sees(map, tear_tile, to_tile): return true
	return false

## Every tile reachable from from_tile through any tear it can see. Returned as a bitwise array so
## the caller can merge it straight into an existing line-of-sight result.
static func tiles_visible_via_tears(map:MapState, from_tile:Vector2i) -> PackedInt64Array:
	var reachable := Tile.create_blank_bitwise_array()
	if _computing: return reachable # see _computing
	for tear_tile:Vector2i in tear_tiles(map):
		if not _sees(map, from_tile, tear_tile): continue
		Tile.add_bitwise_array(reachable, _visibility_of(map, tear_tile))
	return reachable

## Drop the cache for one map. Call whenever a tear moves, opens or closes, or terrain changes on
## that map. Scoped to `map` rather than a blanket clear, so invalidating one map's tear in the
## middle of a run (or a spec's after_each) never throws away another map's still-valid entries.
##
## If `map` is no longer valid there is nothing to key on, so fall back to clearing everything -
## better to recompute than to leak a dead map's instance id forever.
static func invalidate(map:MapState) -> void:
	if not is_instance_valid(map):
		_visibility_cache.clear()
		_tear_tile_cache.clear()
		return
	_visibility_cache.erase(map.get_instance_id())
	_tear_tile_cache.erase(map.get_instance_id())

static func _visibility_of(map:MapState, tile:Vector2i) -> PackedInt64Array:
	var map_id := map.get_instance_id()
	var by_tile:Dictionary = _visibility_cache.get(map_id, {})
	if by_tile.has(tile): return by_tile[tile]
	# The guard must wrap the sweep, because get_tiles_in_los_alt re-enters our own is_tile_in_los
	# override. Restored in a defer-equivalent below rather than at every early return.
	_computing = true
	var visible := UnitTile.get_tiles_in_los_alt(map, tile)
	_computing = false
	by_tile[tile] = visible
	_visibility_cache[map_id] = by_tile
	return visible

static func _sees(map:MapState, from_tile:Vector2i, to_tile:Vector2i) -> bool:
	return Tile.in_bitwise_array(_visibility_of(map, from_tile), to_tile)

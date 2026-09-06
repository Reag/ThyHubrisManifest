# Tear routing for the Banshee. The brain behind clauses 3, 4 and 5.
#
# DELIBERATELY NOT A SCRIPT EXTENSION. The two .gd_ext.gd shims on unit_relation.gd and unit_tile.gd
# do nothing but delegate here, so every rule below is testable without an extension having to fire.
# This project has three confirmed cases of extensions that install cleanly and never run, so a
# testable brain is worth the indirection.
#
# HARD CONSTRAINT: nothing here may consult buffs. can_affect delegates to this file, and aura buff
# delivery is itself gated on can_affect (passive_aura.gd:68), so a buff lookup here closes a real
# cycle. Ask about tears, geometry and tangibility STATUS - nothing else.
#
# THE RULE, after the agreed terrain relaxation:
#
#     routes(a, b) = los(a -> tear) AND los(tear -> b)   for some open tear
#         AND exactly one of a, b is INTANGIBLE
#
# That second line was missing until the final review, and its absence was a real bug rather than a
# technicality. Clause 4 is "INTANGIBLE characters can draw line of sight to TANGIBLE targets if the
# line passes through a tear"; clause 5 is the mirror. BOTH require a tangibility mismatch, and
# nothing in the text grants a tangible pair anything. Without the check, an open tear was a free
# corner-peek for every unit on the map, on both teams - proven with a failing spec before this fix.
#
# The design's claim that "direction matters only to can_affect, which is a permission question, not
# a geometric one" was wrong. can_affect only ever REFUSES across the tangibility line, so a
# same-tangibility pair was never gated by it, and widening the geometry universally handed them
# sight that nothing took back. The rule is about PAIRS, and the gate has to live wherever the pair
# is known.
extends RefCounted

## Lowered from 99 on the 2026-09-06 measurements: 99 tears on a 30x30 map is 370 ms of sweep.
## Tunable - a starting value, not a ceiling.
const MAX_TEARS := 15

const TEAR_FRAME_ID := &'dep_tear_banshee'

## Sentinel for "no explicit eye height given, fall back to the cached terrain-level sweep".
const NO_HEIGHT := -1

## map instance id -> (tile -> the tiles visible from it), at TERRAIN height.
##
## The outer level exists because a single GUT run creates many MapStates, and tile (2,2) on one map
## is not tile (2,2) on another - a bare tile-keyed dictionary would let a stale entry from an
## earlier map answer a query against a later one.
##
## STALENESS: entries depend on map.elevation_with_units and map.does_dynamic_zone_block_sight, both
## of which change when units move or smoke is laid. unit_tile.gd_ext.gd therefore invalidates on
## UnitTile.update_tracking_and_statuses, which the engine runs after moves, spawns and deaths. See
## that override for what is still not covered.
static var _visibility_cache:Dictionary = {}

## map instance id -> Array[Vector2i] of every open tear's tile on that map.
static var _tear_tile_cache:Dictionary = {}

## map instance id -> (persistent_id -> Unit). is_tile_in_los receives only a `whos_asking` id, but
## the pair rule needs the viewer's tangibility, so the id has to be resolved back to a unit. Doing
## that with a linear scan per call would be O(units) on a path the engine already calls a
## bottleneck; this makes it O(1) after the first miss.
static var _unit_by_id_cache:Dictionary = {}

## REENTRANCY GUARD, and it is load-bearing rather than defensive.
##
## unit_tile.gd_ext.gd overrides is_tile_in_los to consult this file. This file computes visibility
## with UnitTile.get_tiles_in_los_alt, which calls UnitTile.is_tile_in_los - the overridden one.
## Without this flag that is unbounded recursion: routing -> sweep -> override -> routing.
##
## While a sweep is in flight, routing answers "no tear route". That is correct, not a compromise:
## the sweep computes the ORDINARY line of sight the routing rule is built on top of, and letting a
## tear widen its own input would make the geometry self-referential.
##
## GDScript has no try/finally, so a throw inside the sweep would strand this true and silently kill
## all tear routing for the rest of the session. invalidate() resets it for that reason.
static var _computing := false

# ---------------------------------------------------------------------------- the pair rule

## Exactly one of the two is INTANGIBLE. The whole of clauses 4 and 5's precondition, in one place so
## both seams and any later caller ask the same question.
static func is_cross_tangible(a:Unit, b:Unit) -> bool:
	if not Unit.is_valid(a) or not Unit.is_valid(b): return false
	return a.has_status(Lancer.STATUS.INTANGIBLE) != b.has_status(Lancer.STATUS.INTANGIBLE)

## Every unit on the map whose tangibility differs from the viewer's - i.e. everyone this viewer
## could legitimately reach through a tear. Tears themselves are excluded: a tear is scenery, not
## something you route sight TO.
static func cross_tangible_units(map:MapState, viewer:Unit) -> Array[Unit]:
	var found:Array[Unit] = []
	if not is_instance_valid(map) or not Unit.is_valid(viewer): return found
	for unit:Unit in map.get_all_units():
		if not Unit.is_valid(unit): continue
		if unit == viewer: continue
		if _frame_id(unit) == TEAR_FRAME_ID: continue
		if is_cross_tangible(viewer, unit): found.append(unit)
	return found

# ---------------------------------------------------------------------------- tears

static func open_tears(map:MapState) -> Array[Unit]:
	if not is_instance_valid(map): return []
	var tears:Array[Unit] = []
	for unit:Unit in map.get_all_units():
		if not Unit.is_valid(unit): continue
		if _frame_id(unit) == TEAR_FRAME_ID: tears.append(unit)
	return tears

static func tear_tiles(map:MapState) -> Array[Vector2i]:
	if not is_instance_valid(map): return []
	var map_id := map.get_instance_id()
	if _tear_tile_cache.has(map_id): return _tear_tile_cache[map_id]
	var tiles:Array[Vector2i] = []
	for tear:Unit in open_tears(map): tiles.append(tear.tile())
	_tear_tile_cache[map_id] = tiles
	return tiles

# ---------------------------------------------------------------------------- routing

## Does some open tear bridge these two tiles? PURE GEOMETRY - it asks nothing about tangibility, so
## every caller must apply the pair rule itself. unit_relation.gd_ext.gd's tear_bridges already does;
## unit_tile.gd_ext.gd does it by only ever asking about cross-tangible units' tiles.
##
## `from_height` is the VIEWER's eye height. Vanilla line of sight measures from
## UnitTile.effective_height (floor plus the unit's own body), while the cached sweep below is
## computed at raw terrain elevation - so passing NO_HEIGHT here quietly measures the first leg from
## the ground and makes routing under-permissive over low walls. Pass the real height when you have
## it; is_tile_in_los is handed one, and get_tiles_in_los can compute one.
static func routes_between(map:MapState, from_tile:Vector2i, to_tile:Vector2i, from_height:int = NO_HEIGHT) -> bool:
	if _computing: return false # see _computing
	if not is_instance_valid(map): return false
	var tiles := tear_tiles(map)
	if tiles.is_empty(): return false # fast path: no open tear, no route, no sweep.
	for tear_tile:Vector2i in tiles:
		if not _sees_from(map, from_tile, tear_tile, from_height): continue
		# The second leg is measured from the TEAR, whose own eye height is the terrain it sits on -
		# so the cached terrain-level sweep is the right answer here, not an approximation.
		if _sees(map, tear_tile, to_tile): return true
	return false

## The tiles this viewer may see through a tear: the occupied tiles of cross-tangible units it can
## route to, and nothing else.
##
## Deliberately NOT "every tile any tear can see". That was the periscope bug - it granted sight of
## empty ground and of same-tangibility units alike. It is also cheaper this way: the work is
## O(cross-tangible units) rather than O(map area).
static func tiles_visible_via_tears(map:MapState, viewer:Unit, from_tile:Vector2i, from_height:int = NO_HEIGHT) -> PackedInt64Array:
	var reachable := Tile.create_blank_bitwise_array()
	if _computing: return reachable # see _computing
	if not is_instance_valid(map) or not Unit.is_valid(viewer): return reachable
	if tear_tiles(map).is_empty(): return reachable
	for other:Unit in cross_tangible_units(map, viewer):
		for tile:Vector2i in other.occupied_tiles():
			if routes_between(map, from_tile, tile, from_height):
				Tile.add_to_bitwise_array(reachable, tile)
	return reachable

## CLAUSE 6's predicate: "Attacks that pass through a tear treat targets as INVISIBLE."
##
## Deliberately the SAME question clauses 4 and 5 ask, so the two can never drift apart. That is not
## just tidiness - it is the reason the predicate is correct. A cross-tangible pair has NO ordinary
## interaction at all: can_affect refuses them outright unless a tear bridges the pair. So for any
## pair this returns true for, the attack is necessarily going through the tear; there is no second
## route it could have taken instead.
##
## The eye height is the ATTACKER's, matching how the seam measures the viewer's leg.
static func attack_routes_through_tear(attacker:Unit, target:Unit) -> bool:
	if not is_cross_tangible(attacker, target): return false
	if not is_instance_valid(attacker.map): return false
	var from_tile:Vector2i = attacker.tile()
	var height:int = UnitTile.effective_height(attacker, true, from_tile)
	return routes_between(attacker.map, from_tile, target.tile(), height)

## Resolve a `whos_asking` persistent id back to its unit. See _unit_by_id_cache.
static func unit_with_persistent_id(map:MapState, persistent_id:StringName) -> Unit:
	if not is_instance_valid(map) or persistent_id == &'': return null
	var map_id := map.get_instance_id()
	var by_id:Dictionary = _unit_by_id_cache.get(map_id, {})
	var cached = by_id.get(persistent_id)
	if Unit.is_valid(cached): return cached
	for unit:Unit in map.get_all_units():
		if not Unit.is_valid(unit): continue
		by_id[unit.core.persistent_id] = unit
	_unit_by_id_cache[map_id] = by_id
	cached = by_id.get(persistent_id)
	return cached if Unit.is_valid(cached) else null

# ---------------------------------------------------------------------------- cache

## Drop every cache for one map. Call whenever a tear opens, moves or closes, when terrain changes,
## or when units move - see the staleness note on _visibility_cache.
##
## Also resets _computing. A throw inside the sweep would otherwise strand that flag true and
## silently disable all tear routing for the rest of the session, with nothing to indicate why;
## GDScript has no try/finally to do it at the throw site.
static func invalidate(map:MapState) -> void:
	_computing = false
	if not is_instance_valid(map):
		_visibility_cache.clear()
		_tear_tile_cache.clear()
		_unit_by_id_cache.clear()
		return
	var map_id := map.get_instance_id()
	_visibility_cache.erase(map_id)
	_tear_tile_cache.erase(map_id)
	_unit_by_id_cache.erase(map_id)

static func _frame_id(unit:Unit) -> StringName:
	if not Unit.is_valid(unit): return &''
	if unit.core == null or unit.core.frame == null: return &''
	return unit.core.frame.compcon_id

static func _visibility_of(map:MapState, tile:Vector2i) -> PackedInt64Array:
	var map_id := map.get_instance_id()
	var by_tile:Dictionary = _visibility_cache.get(map_id, {})
	if by_tile.has(tile): return by_tile[tile]
	_computing = true
	var visible := UnitTile.get_tiles_in_los_alt(map, tile)
	_computing = false
	by_tile[tile] = visible
	_visibility_cache[map_id] = by_tile
	return visible

static func _sees(map:MapState, from_tile:Vector2i, to_tile:Vector2i) -> bool:
	return Tile.in_bitwise_array(_visibility_of(map, from_tile), to_tile)

## Like _sees, but measured from a specific eye height rather than from the terrain. Uncached by
## design: it runs once per tear for the viewer's leg only, and caching per (tile, height) pair would
## cost more to key than the call saves.
static func _sees_from(map:MapState, from_tile:Vector2i, to_tile:Vector2i, from_height:int) -> bool:
	if from_height == NO_HEIGHT: return _sees(map, from_tile, to_tile)
	_computing = true
	var seen := UnitTile.is_tile_in_los_alt(map, from_height, to_tile, from_tile)
	_computing = false
	return seen

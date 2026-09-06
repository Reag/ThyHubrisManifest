# Clauses 4 and 5 - the geometry half of the tear window.
#
# TWO FUNCTIONS, NOT ONE. Probe 2 measured this: UnitTile.get_tiles_within reads a precalculated_los
# array when one is passed and otherwise falls back to is_tile_in_los, and which happens is decided
# by the CALLER. A direct targeting query never consults the sweep at all, while the nine producers
# in engine/ai/, gear_action/action.gd:275 and the ui/ tilepickers all go through it. Overriding
# only one leaves half the game seeing vanilla geometry.
#
# THE PAIR RULE. Both clauses require a tangibility MISMATCH - clause 4 is intangible viewer to
# tangible target, clause 5 the mirror - so routing is only ever offered towards units of the
# opposite tangibility to the viewer. An earlier version widened sight for everyone whenever any
# tear was open, which made every tear a free corner-peek for both teams; nothing in the rules text
# grants that. The gate lives in tear_routing.is_cross_tangible and is applied on both paths here.
#
# Everything real lives in tear_routing.gd. This file is a shim on purpose - see that file's header.
#
# Note gavstarb-talents_1st_party also extends unit_tile.gd. Both install and both fire; ours calls
# super, so the composition holds.
extends "res://engine/character/unit/service/unit_tile.gd"

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')

## The sweep. Adds the tiles held by cross-tangible units this viewer can reach through a tear.
static func get_tiles_in_los(unit:Unit, from_tile := Tile.INVALID, ignore_blinded := false) -> PackedInt64Array:
	var tiles := super.get_tiles_in_los(unit, from_tile, ignore_blinded)
	if not Unit.is_valid(unit) or not is_instance_valid(unit.map): return tiles
	# BLINDED is handled by super, which returns only adjacent tiles. Widening that through a tear
	# would let a blinded character see across the map. Checked BEFORE any other work so the blinded
	# path costs nothing.
	if unit.has_status(Lancer.STATUS.BLINDED) and not ignore_blinded: return tiles

	var viewer_tile:Vector2i = unit.tile() if from_tile == Tile.INVALID else from_tile
	# Vanilla measures line of sight from effective_height - floor plus the unit's own body - so the
	# viewer's leg must use it too. The cached sweep inside tear_routing is computed at raw terrain
	# elevation, which silently under-permits a viewer standing tall enough to see over a low wall.
	var from_height:int = UnitTile.effective_height(unit, true, viewer_tile)
	Tile.add_bitwise_array(tiles, TearRouting.tiles_visible_via_tears(unit.map, unit, viewer_tile, from_height))
	return tiles

## The point query, used by the fallback path inside get_tiles_within.
##
## `whos_asking` is the viewer's persistent id and is the only handle on the viewer here, so it has
## to be resolved back to a unit before the pair rule can be applied. When it is absent - some
## callers pass nothing - there is no viewer to compare tangibility against, so routing is declined
## rather than guessed at. Declining is the safe direction: it falls back to vanilla geometry.
static func is_tile_in_los(map:MapState, occupied_tiles:Array[Vector2i], from_height:int, target_tile:Vector2i, whos_asking:StringName = &'') -> bool:
	if super.is_tile_in_los(map, occupied_tiles, from_height, target_tile, whos_asking): return true
	if not is_instance_valid(map) or whos_asking == &'': return false

	var viewer:Unit = TearRouting.unit_with_persistent_id(map, whos_asking)
	if not Unit.is_valid(viewer): return false

	# The pair rule, applied against whoever is actually standing on the target tile. An empty tile
	# has no one to be cross-tangible with, so it never routes - which is the point: a tear shows you
	# things on the other side, not the ground behind a wall.
	var qualifies := false
	for occupant:Unit in map.get_all_units_at_tile(target_tile):
		if TearRouting.is_cross_tangible(viewer, occupant):
			qualifies = true
			break
	if not qualifies: return false

	for occupied_tile:Vector2i in occupied_tiles:
		if TearRouting.routes_between(map, occupied_tile, target_tile, from_height): return true
	return false

## Cache invalidation hook, NOT a behaviour change - super is called unmodified and its result is
## untouched.
##
## tear_routing's visibility cache stores get_tiles_in_los_alt results, and those depend on
## map.elevation_with_units and map.does_dynamic_zone_block_sight - both of which move when units do.
## Invalidating only on tear open/close left a mech that parked between tear and target, or smoke
## laid across the line, being seen straight through for the rest of the mission.
##
## This is the engine's own "occupancy or statuses changed" callback, with 30 call sites covering
## moves, spawns and deaths, so it is the closest thing to a general invalidation signal available
## without touching the base game.
##
## STILL NOT COVERED, and worth knowing: a dynamic sight zone (smoke) created or expiring without a
## unit moving. Nothing routes through that path today, but a mod that lays smoke as a free action
## could stale the cache until the next unit moves.
static func update_tracking_and_statuses(map:MapState, event:EventCore = null) -> void:
	super.update_tracking_and_statuses(map, event)
	TearRouting.invalidate(map)

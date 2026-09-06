# Clauses 4 and 5 - the geometry half of the tear window.
#
# TWO FUNCTIONS, NOT ONE. Probe 2 measured this: UnitTile.get_tiles_within reads a precalculated_los
# array when one is passed and otherwise falls back to is_tile_in_los, and which happens is decided
# by the CALLER. A direct targeting query never consults the sweep at all, while the nine producers
# in engine/ai/, gear_action/action.gd:275 and the ui/ tilepickers all go through it. Overriding
# only one leaves half the game seeing vanilla geometry.
#
# Everything real lives in tear_routing.gd. This file is a shim on purpose - see that file's header.
#
# Note gavstarb-talents_1st_party also extends unit_tile.gd. Both install and both fire; ours calls
# super, so the composition holds.
extends "res://engine/character/unit/service/unit_tile.gd"

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')

## The sweep. Merges in everything reachable through a tear this viewer can see.
static func get_tiles_in_los(unit:Unit, from_tile := Tile.INVALID, ignore_blinded := false) -> PackedInt64Array:
	var tiles := super.get_tiles_in_los(unit, from_tile, ignore_blinded)
	if not Unit.is_valid(unit) or not is_instance_valid(unit.map): return tiles
	var viewer_tile:Vector2i = unit.tile() if from_tile == Tile.INVALID else from_tile
	# BLINDED is handled by super, which returns only adjacent tiles. Widening that through a tear
	# would let a blinded character see across the map, so leave it alone.
	if unit.has_status(Lancer.STATUS.BLINDED) and not ignore_blinded: return tiles
	Tile.add_bitwise_array(tiles, TearRouting.tiles_visible_via_tears(unit.map, viewer_tile))
	return tiles

## The point query, used by the fallback path inside get_tiles_within.
static func is_tile_in_los(map:MapState, occupied_tiles:Array[Vector2i], from_height:int, target_tile:Vector2i, whos_asking:StringName = &'') -> bool:
	if super.is_tile_in_los(map, occupied_tiles, from_height, target_tile, whos_asking): return true
	if not is_instance_valid(map): return false
	for occupied_tile:Vector2i in occupied_tiles:
		if TearRouting.routes_between(map, occupied_tile, target_tile): return true
	return false

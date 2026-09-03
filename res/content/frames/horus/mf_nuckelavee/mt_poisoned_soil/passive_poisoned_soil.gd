# The terrain half of Poisoned Soil: the tiles the Nuckelavee has fouled.
#
# A PassiveTerrainZone normally projects a RangePattern around its owner - that is how the
# Barbarossa's rail crater (mt_apocalypse_difficult.tres) works. This one instead reports an
# arbitrary set of remembered tiles, because a boost path is not a shape.
#
# MapState.add_dynamic_terrain_and_zones_from_unit (map_state.gd:427-434) calls
# get_voxels_to_apply_terrain for every terrain zone on every gear of every unit, and
# Loadout.get_all_gear includes traits - so this needs no deployable to carry it. It also means the
# trail vanishes if the Nuckelavee dies, is EXILED or goes INTANGIBLE, which is the intended
# behaviour, not an oversight.
#
# This is an ordinary subclass of a class_name script used by our own resource, NOT a .gd_ext.gd
# engine extension, so Godot bug #83542 does not apply here.
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-03-poisoned-soil-design.md
extends PassiveTerrainZone

const TRAIT_ID := &'mt_poisoned_soil'

## The terrain currently on the map.
const TRAIL_KEY := 'poisoned_soil_trail'
## Tiles crossed since the last BOOST, not yet committed. Becomes TRAIL_KEY if the player accepts.
const PENDING_KEY := 'poisoned_soil_pending'
const ARMED_KEY := 'poisoned_soil_armed'

# ============================== the terrain zone ==============================

## The remembered trail, as surface voxels. Overrides the base class's pattern-around-the-owner.
func get_voxels_to_apply_terrain(gear:GearCore, _unit_core:UnitCore, _state:UnitBattleState) -> Array[Vector3i]:
	var voxels:Array[Vector3i] = []
	var map:MapState = X.map()
	if map == null: return voxels
	for tile:Vector2i in read_trail(gear):
		if not Tile.within_bounds(tile, map.size): continue
		voxels.append(Tile.to_voxel_at_surface(tile, map))
	return voxels

# ============================== the state contract ==============================
#
# GearCore.state is an exported Dictionary, so all of this serializes into saves for free. Tiles go
# in as a flat [x, y, x, y, ...] Array[int] because get_state_int_array is the only typed array
# helper GearCore offers, and the assert in get_state guards against reading arrays any other way.

static func read_trail(gear:GearCore) -> Array[Vector2i]:
	return _tiles_from_flat(gear.get_state_int_array(TRAIL_KEY))

static func write_trail(gear:GearCore, tiles:Array[Vector2i]) -> void:
	gear.set_state(TRAIL_KEY, _flat_from_tiles(tiles))

static func read_pending(gear:GearCore) -> Array[Vector2i]:
	return _tiles_from_flat(gear.get_state_int_array(PENDING_KEY))

static func write_pending(gear:GearCore, tiles:Array[Vector2i]) -> void:
	gear.set_state(PENDING_KEY, _flat_from_tiles(tiles))

static func is_armed(gear:GearCore) -> bool:
	return bool(gear.get_state(ARMED_KEY, false))

static func set_armed(gear:GearCore, armed:bool) -> void:
	gear.set_state(ARMED_KEY, armed)

static func _flat_from_tiles(tiles:Array[Vector2i]) -> Array[int]:
	var flat:Array[int] = []
	for tile:Vector2i in tiles:
		flat.append(tile.x)
		flat.append(tile.y)
	return flat

static func _tiles_from_flat(flat:Array[int]) -> Array[Vector2i]:
	var tiles:Array[Vector2i] = []
	# Step by two and stop before a trailing odd value; a half-written pair is not a tile.
	var index:int = 0
	while index + 1 < flat.size():
		tiles.append(Vector2i(flat[index], flat[index + 1]))
		index += 2
	return tiles

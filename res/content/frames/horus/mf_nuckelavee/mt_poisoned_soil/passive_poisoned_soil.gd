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

## The terrain currently on the map.
const TRAIL_KEY := 'poisoned_soil_trail'
## Tiles crossed since the last BOOST, not yet committed. Becomes TRAIL_KEY if the player accepts.
const PENDING_KEY := 'poisoned_soil_pending'
const ARMED_KEY := 'poisoned_soil_armed'
## The round the boost that set ARMED_KEY happened in. An arm is only live for the rest of that same
## round - see is_armed below.
const ARMED_ROUND_KEY := 'poisoned_soil_armed_round'

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

## `for_round` is whatever action_poisoned_soil_track / _lay are reacting to right now
## (triggering_event.context.map.game_core.round_count). Named for_round, not round, so it does not
## shadow GDScript's built-in round().
##
## An arm stamped in an earlier round is stale and reads as unarmed - but this is belt and braces,
## not the primary defense. The primary defense is action_poisoned_soil_disarm.gd, which clears
## ARMED_KEY unconditionally at the end of the arming unit's own turn: a round is the wrong grain for
## a turn-scoped effect, because content/frames/horus/mf_goblin/cp_instinct_rig/
## action_symbiosis_shared_turn.gd can grant a second, LINKED turn within the SAME round (a Nuckelavee
## fused to a Goblin), and the round stamp alone would still read "armed" across that boundary. The
## round stamp still matters for anything that disarms outside the normal turn cycle (e.g. death
## mid-turn skipping END_TURN entirely), and as a second line of defense generally - nothing else
## clears ARMED_KEY at a turn or round boundary otherwise (GearCore.state.clear() only runs on a
## repair).
static func is_armed(gear:GearCore, for_round:int) -> bool:
	if not bool(gear.get_state(ARMED_KEY, false)): return false
	return gear.get_state(ARMED_ROUND_KEY, -1) == for_round

## `for_round` is required when arming (stamps the round the arm is live for) and ignored when
## disarming, since a stale stamp on a disarmed gear can never make is_armed return true again.
static func set_armed(gear:GearCore, armed:bool, for_round:int = -1) -> void:
	gear.set_state(ARMED_KEY, armed)
	if armed: gear.set_state(ARMED_ROUND_KEY, for_round)

## "the spaces it moves through" is the Nuckelavee's OWN movement - the designer's ruling is that
## being knocked back or pulled after boosting does not foul the ground it gets thrown across, and
## must not prompt the player mid-enemy-turn either. A move/step event's triggering context carries
## the MovementType behind it as context.resource (see event_unit_move.gd's get_optional_context
## and execute_reaction_events_for_entire_katamari, which is what actually populates it for STEP and
## ENTIRE_MOVEMENT reactions).
##
## Defaults to TRUE when no MovementType is attached at all, deliberately the opposite of
## MovementType.is_contextual_move_voluntary. Every real call site that queues event_unit_move sets
## an explicit MovementType (pathfinder.gd:908 for ordinary moves and boosts, common_action_util.gd
## for knockback/pulls/mounting) - so a missing one here means "we could not tell", not "known
## involuntary". Defaulting to false would silently disable the trait on any such gap; defaulting to
## true costs at most a false trail on a case that, as far as this codebase shows, cannot happen.
static func is_voluntary_movement(triggering_event:EventCore) -> bool:
	var movement_type = triggering_event.context.resource
	if not MovementType.is_valid(movement_type): return true
	return movement_type.voluntary

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

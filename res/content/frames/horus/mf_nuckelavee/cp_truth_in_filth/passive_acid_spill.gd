# Acid Spill's terrain patch, and the whole state contract behind the weapon.
#
# A PassiveTerrainZone normally projects a RangePattern around its owner. This one reports an
# arbitrary remembered set instead, exactly as passive_poisoned_soil.gd does - see that file's
# header for why MapState.add_dynamic_terrain_and_zones_from_unit picks this up off a trait with no
# deployable involved, and for the consequences (the patch dies with the frame).
#
# This is a SECOND, INDEPENDENT patch. Poisoned Soil's trail and this one replace only themselves.
# Both fire on the same entire_movement, so sharing storage was a live option and was rejected -
# see the design doc.
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-04-acid-spill-design.md
extends PassiveTerrainZone

## The terrain currently on the map.
const TRAIL_KEY := 'acid_spill_trail'
## Tiles stepped through since the BOOST. DUPLICATES ARE KEPT - see write_pending.
const PENDING_KEY := 'acid_spill_pending'
const ARMED_KEY := 'acid_spill_armed'
## The round the arming boost happened in; an arm is only live for the rest of that round.
const ARMED_ROUND_KEY := 'acid_spill_armed_round'
## The tile the frame boosted out of. Stored separately from PENDING_KEY on purpose - see below.
const ORIGIN_KEY := 'acid_spill_origin'
## UnitAction.get_boost_speed at the moment of the boost, so Ramjet's +2 is honoured.
const BOOST_SPEED_KEY := 'acid_spill_boost_speed'

# ============================== the terrain zone ==============================

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
# helper GearCore offers.

static func read_trail(gear:GearCore) -> Array[Vector2i]:
	return _tiles_from_flat(gear.get_state_int_array(TRAIL_KEY))

static func write_trail(gear:GearCore, tiles:Array[Vector2i]) -> void:
	gear.set_state(TRAIL_KEY, _flat_from_tiles(tiles))

## The path stepped since the boost, EXCLUDING the tile boosted out of.
##
## Duplicates are deliberately preserved, which is the one place this differs in shape from
## passive_poisoned_soil.gd. That file de-dupes because it is building a SET of tiles to foul; this
## one needs a COUNT of steps for the damage, so a path that crosses itself has to count twice.
static func read_pending(gear:GearCore) -> Array[Vector2i]:
	return _tiles_from_flat(gear.get_state_int_array(PENDING_KEY))

static func write_pending(gear:GearCore, tiles:Array[Vector2i]) -> void:
	gear.set_state(PENDING_KEY, _flat_from_tiles(tiles))

## The origin lives OUTSIDE the pending buffer because AoeCalculator.line returns rings 1..length and
## so excludes its own origin (aoe_calculator.gd:140-158). Seeding the buffer with the start tile the
## way Poisoned Soil does would make is_straight_full_speed unable to match, ever.
static func read_origin(gear:GearCore) -> Vector2i:
	var flat:Array[Vector2i] = _tiles_from_flat(gear.get_state_int_array(ORIGIN_KEY))
	if flat.is_empty(): return Tile.INVALID
	return flat[0]

static func write_origin(gear:GearCore, tile:Vector2i) -> void:
	gear.set_state(ORIGIN_KEY, _flat_from_tiles([tile] as Array[Vector2i]))

## Recorded at arm time rather than read back later, so a buff that expires mid-move (Ramjet's
## buff_ramjet_boost is UNTIL 3) cannot move the goalposts after the charge has begun.
static func read_boost_speed(gear:GearCore) -> int:
	return int(gear.get_state(BOOST_SPEED_KEY, 0))

static func write_boost_speed(gear:GearCore, speed:int) -> void:
	gear.set_state(BOOST_SPEED_KEY, speed)

## See passive_poisoned_soil.is_armed - same reasoning, same two-part stamp. The round stamp is the
## backstop; action_acid_spill_disarm.gd clearing at END_TURN is the primary defense, because a
## Goblin's cp_instinct_rig can grant a second LINKED turn inside one round.
static func is_armed(gear:GearCore, for_round:int) -> bool:
	if not bool(gear.get_state(ARMED_KEY, false)): return false
	return gear.get_state(ARMED_ROUND_KEY, -1) == for_round

static func set_armed(gear:GearCore, armed:bool, for_round:int = -1) -> void:
	gear.set_state(ARMED_KEY, armed)
	if armed: gear.set_state(ARMED_ROUND_KEY, for_round)

## "the spaces it moves through" is the Nuckelavee's OWN movement. Identical to Poisoned Soil's, and
## deliberately defaults to TRUE when no MovementType is attached - a missing one means "we could not
## tell", not "known involuntary". See passive_poisoned_soil.is_voluntary_movement for the full note.
static func is_voluntary_movement(triggering_event:EventCore) -> bool:
	var movement_type = triggering_event.context.resource
	if not MovementType.is_valid(movement_type): return true
	return movement_type.voluntary

# ============================== the derived questions ==============================

## "damage equal to half the distance moved", rounded DOWN. Integer division on a non-negative size
## floors, which is what we want.
static func damage_for(gear:GearCore) -> int:
	return read_pending(gear).size() / 2

## "If you BOOST your full speed in a straight line..."
##
## Straightness is tested against AoeCalculator.line, which is the SAME function the pathfinder uses
## to enforce Ramjet's straight_line/must_move_max_possible movement (pathfinder.gd:493 via
## calculate_step_path_for_line, and :667 in is_path_the_max_unit_can_move). Copying it rather than
## writing a fresh "all steps in one direction" test is deliberate: Ramjet is the intended pairing
## for this frame, and a second definition of "straight" would eventually disagree with the first.
##
## Diagonals qualify, and that falls out of line() being angle-based rather than cardinal-only.
static func is_straight_full_speed(gear:GearCore, map_shape:MapShape) -> bool:
	var path:Array[Vector2i] = read_pending(gear)
	if path.is_empty(): return false
	if path.size() < read_boost_speed(gear): return false
	var origin:Vector2i = read_origin(gear)
	if origin == Tile.INVALID: return false
	return AoeCalculator.line(origin, path.back(), path.size(), map_shape) == path

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

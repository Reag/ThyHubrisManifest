# Undulating Form: the Kraken pours itself around other characters.
#
#   "The Kraken may move through other characters, and may end its movement overlapping them, so
#    long as at least one space it occupies is free."
#
# Rides Buff.TO.CAN_SHARE_SPACE, which the pathfinder consults twice per candidate tile
# (pathfinder.gd:115-120) and which clears both occupation.invalid_endpoint - someone standing on
# the tile itself - and bigunit_invalid_endpoint - someone under any tile our footprint covers.
#
# NOTE ON SCOPE. The trait as originally written also let the Kraken squeeze through terrain gaps
# narrower than itself. That half is not buildable: the decision lives in Pathfinder.Occupation,
# and Pathfinder carries a class_name so it cannot be script-extended (Godot #83542), while
# UnitTile's occupancy helpers - which ARE extendable - take a size rather than a unit and so cannot
# single out this frame. Spiked and rejected 2026-09-02; see the design doc. What survives here is
# the half that vanilla already exposes, and the wording was changed to match rather than promise
# something that does not happen.
extends Buff

## Only when the Kraken is the one MOVING.
##
## The engine asks this question from both sides: once with the mover as context.unit, and once with
## the mover as target_unit and the buff's holder as the thing being stood on. Answering the second
## would let anything in the game end its move on top of the Kraken, which the trait does not say.
## core.is_unit_owner rather than get_holder_unit: the latter needs a map (defaulting to X.map(),
## which is not set under the spec harness) and scans every unit on it. This runs for every
## candidate tile of every path, so it wants to be cheap - is_unit_owner just asks whether that
## unit's loadout holds the gear this buff came from.
func check_if_passive_applies(core:BuffCore, context:Context) -> bool:
	if not Unit.is_valid(context.unit): return false
	if not core.is_unit_owner(context.unit): return false
	if context.target_tiles.is_empty(): return false
	return has_a_free_space(context.unit, context.target_tiles[0])

## "so long as at least one space it occupies is free" - of the tiles the Kraken would cover from
## here, is any one of them clear of things that would block it?
##
## A size 1 unit can never satisfy this, since its only space is the one it is trying to share. That
## is correct rather than an oversight: the trait is about a big body flowing around a small one.
static func has_a_free_space(unit:Unit, tile:Vector2i) -> bool:
	var map:MapState = unit.map
	if not is_instance_valid(map): return false

	var occupied := UnitTile.get_occupied(tile, unit.state.occupying_size, map.size)
	# Part of the footprint hanging off the map is a separate rule (bigunit_offmap_point) and this
	# trait does not waive it.
	if occupied.size() != unit.state.occupying_size * unit.state.occupying_size: return false

	# Built once rather than per tile - this runs for every candidate tile of every path.
	var katamari := Katamari.create(unit)
	for candidate:Vector2i in occupied:
		if is_free_for(unit, candidate, map, katamari): return true
	return false

## Mirrors the pathfinder's own idea of who occupies a tile (pathfinder.gd:106-113): your own
## katamari, exiled units and markers do not count, and neither does anything that is not flagged as
## an obstruction.
static func is_free_for(unit:Unit, tile:Vector2i, map:MapState, katamari:Katamari) -> bool:
	for other:Unit in map.get_all_units_at_tile(tile, null, true):
		if other == unit: continue
		if katamari.all_units.has(other): continue
		if other.has_status(Lancer.STATUS.EXILED): continue
		if other.is_marker(): continue
		if not other.core.frame.is_obstruction: continue
		return false
	return true

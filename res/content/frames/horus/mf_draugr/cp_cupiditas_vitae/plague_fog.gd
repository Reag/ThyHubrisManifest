# Everything the rest of the mod needs to ask about the Draugr's plague fog.
#
# The fog is dep_plague_fog, a MARKER deployable (Frame.ENTITY.MARKER, like every vanilla smoke
# cloud) placed by Plague-Vent Dispersal and owned by the Draugr that placed it. "Inside the fog" is
# distance <= RADIUS from the cloud's own tile, matching the BLAST 2 range pattern on its terrain
# zone - the zone paints voxels for cover and fx, but distance is what every rules question here is
# actually about, and it is what ActionReactionOnComingWithin uses too, so the reaction and these
# helpers cannot disagree.
#
# Markers are invisible to UnitRelation.get_units_within, which drops them unless asked for
# (unit_relation.gd:45-57), so the search below goes through map.get_all_units(), which includes them
# (map_state.gd:222-229).
#
# is_on_map() is the liveness test rather than Unit.is_valid: a fog that has been killed by
# mt_expiration is removed from the map by EventService.remove_unit_from_game but the object may
# still be referenced from an in-flight event.
extends RefCounted

const FRAME_ID := &'dep_plague_fog'
const KIT_ID := &'mt_plague_fog'
## Matches the BLAST 2 range_pattern on mt_plague_fog's PassiveTerrainZone. Keep the two in step.
const RADIUS := 2

static func all_on(map:MapState) -> Array[Unit]:
	var fogs:Array[Unit] = []
	if map == null: return fogs
	for unit:Unit in map.get_all_units():
		if not Unit.is_valid(unit) or not unit.is_on_map(): continue
		if unit.core.frame.compcon_id == FRAME_ID: fogs.append(unit)
	return fogs

static func covers(fog:Unit, unit:Unit) -> bool:
	if not Unit.is_valid(fog) or not Unit.is_valid(unit): return false
	if not fog.is_on_map() or not unit.is_on_map(): return false
	return UnitRelation.distance_between(fog, unit) <= RADIUS

## Every live fog this unit is standing in, whoever owns them.
static func covering(unit:Unit) -> Array[Unit]:
	var fogs:Array[Unit] = []
	if not Unit.is_valid(unit) or not unit.is_on_map(): return fogs
	for fog:Unit in all_on(unit.map):
		if covers(fog, unit): fogs.append(fog)
	return fogs

## "While you are inside the fog" - the gate on all three of the fog's ongoing effects.
static func owner_is_inside(fog:Unit) -> bool:
	if not Unit.is_valid(fog): return false
	return covers(fog, fog.get_owner_unit())

## A fog whose owner is inside it and which also covers `other`, or null. This is the shape both the
## accuracy buff and the Infection auto-fail want: "the Draugr is in its fog, and so are you".
static func shared_by(fog_owner:Unit, other:Unit) -> Unit:
	if not Unit.is_valid(fog_owner) or not Unit.is_valid(other): return null
	for fog:Unit in covering(fog_owner):
		if fog.get_owner_unit() != fog_owner: continue # somebody else's cloud does nothing for us
		if covers(fog, other): return fog
	return null

## "Hostile characters automatically fail SYSTEMS checks to remove INFECTION at the end of their
## turn." Read by buff_infection.gd, which is the only caller.
##
## Hostility is measured against the fog's OWNER, not the fog: a Draugr does not sabotage its own
## allies' recovery, and the fog inherits the deployer's faction anyway (ActionSystemDeploy's
## UnitCore.create(unit.get_faction(), frame), action_system_deploy.gd:117).
static func auto_fails_infection_check(unit:Unit) -> bool:
	if not Unit.is_valid(unit) or not unit.is_on_map(): return false
	for fog:Unit in covering(unit):
		var fog_owner := fog.get_owner_unit()
		if not Unit.is_valid(fog_owner): continue
		if not covers(fog, fog_owner): continue          # "while you are inside the fog"
		if UnitRelation.are_enemies(fog_owner, unit): return true
	return false

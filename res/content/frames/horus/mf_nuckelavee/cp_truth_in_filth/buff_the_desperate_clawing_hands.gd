# The Desperate Clawing Hands Of The Dead - the scene-long switch the whole core power hangs off.
#
#   "For the rest of the scene, something terrible lurks in the cracks."
#
# Everything else in the power asks UnitCondition.has_buff(unit, 'buff_the_desperate_clawing_hands'),
# so this resource is the single switch: clearing it turns all three bullets off at once. Modelled on
# the Kraken's buff_the_all_consuming_tide, so the mod has one answer for "how do our scene-long
# powers work".
#
# until = MANUAL is "rest of the scene". Buff.is_cleared_on_owner_death() defaults true (buff.gd:184),
# which is what stops the hands outliving the Nuckelavee - pinned by a spec rather than trusted,
# because the failure would be silent and would last the whole scene.
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-04-clawing-hands-design.md
extends Buff

## Is this tile difficult GROUND - a property of the terrain, not of whoever is standing on it?
##
## Deliberately NOT Pathfinder.Occupation.calculate_for's definition (pathfinder.gd:92-96), which is
## `terrain.is_difficult() or unit.has_status(PRONE) or underwater`. That PRONE clause is about the
## character: a prone unit pays difficult-terrain costs everywhere. Bullet 1 of this power fires when
## a hostile is knocked PRONE in difficult terrain, so borrowing that definition would make every
## knockdown on the map qualify, and the clause would mean nothing.
##
## Water IS included: the pathfinder charges for it, so it reads as difficult ground to a player. The
## EVA exemption is left out on purpose - that is a property of the character too, and Caustic Earth
## already has its own character-level exemption in is_exempt().
static func is_difficult_ground(map:MapState, tile:Vector2i) -> bool:
	if map == null: return false
	if not Tile.within_bounds(tile, map.size): return false
	if map.get_surface_terrain_at(tile).is_difficult(): return true
	return map.elevation(tile) < map.water_level()

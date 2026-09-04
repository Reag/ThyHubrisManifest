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

# ============================== BULLET 2: THE COST OF LEAVING ==============================
#
#   "Hostile characters must spend two movement to exit |difficult terrain|."
#
# NOT buildable as written, and we have hit this exact wall before. Movement cost is set only inside
# Pathfinder.Occupation.calculate_for (pathfinder.gd:92-98), which consults no buff and prices the
# tile being ENTERED rather than the one being left; calculate_step_cost_alt is a static that
# receives `from` and uses it solely for elevation. No Buff.TO member affects cost. Pathfinder carries
# a class_name, so it cannot be reliably script-extended (Godot #83542). The Kraken's
# buff_the_all_consuming_tide.gd records the same finding for its own clause.
#
# What ships is a BUDGET PENALTY: a hostile that BEGINS its movement standing on difficult ground may
# end no further than one tile short of where it otherwise could. Faithful about the cost - one extra
# point of movement, paid by the character the clause names - and approximate about frequency, since
# it charges once for the whole move rather than once per exit step. That is the permissive direction,
# matching every other liberty taken here.
#
# Rides Buff.TO.MOVEMENT_RESTRICTION's subtractive mode: the pathfinder loops EVERY character's
# restriction buffs against whoever is moving (pathfinder.gd:340-350), so this buff sits on the
# Nuckelavee and restrains other units.

## Only hostile characters, only while they stand on difficult ground, and only for movement that
## difficult terrain would actually have taxed. Note context.unit is the unit MOVING, not the buff's
## holder.
func check_if_passive_applies(core:BuffCore, context:Context) -> bool:
	var mover:Unit = context.unit
	var nuckelavee := core.get_holder_unit(context.map)
	if not Unit.is_valid(mover) or not Unit.is_valid(nuckelavee): return false
	if mover == nuckelavee: return false
	if not mover.is_actor(): return false
	if Faction.is_ally(nuckelavee.state.faction, mover.state.faction): return false
	if not taxes_this_movement(context.resource): return false
	return is_difficult_ground(context.map, mover.state.tile)

## THE DECLARED BOUNDARY. The pathfinder hands its planned MovementType down in context.resource
## (pathfinder.gd:343) and runs the restriction loop for every one of them, so this is where forced,
## flying, teleporting and INTANGIBLE movement are excluded - vanilla difficult terrain does not tax
## them either (movement_type.gd:107-108, consumed at pathfinder.gd:97).
##
## This is also what keeps the power from fighting its own best pairing: a prisoner being dragged by
## a Kraken moves involuntarily, so it pays no toll here while still taking Caustic Earth per tile.
##
## Untyped parameter and MovementType.is_valid rather than a cast: context.resource is a plain
## Resource and nothing guarantees a caller filled it. A movement we cannot identify is not one this
## clause can speak about, so it declines - erring permissive, like everything else here.
func taxes_this_movement(movement_type) -> bool:
	if not MovementType.is_valid(movement_type): return false
	return not movement_type.ignores_difficult_terrain()

func is_buff_context_valid_for_passive(core:BuffCore, context:Context) -> bool:
	return (
		Unit.is_valid(context.unit) and
		is_instance_valid(context.map) and
		Unit.is_valid(core.get_holder_unit(context.map))
	)

## Every tile this character may still END on: those within one less than its remaining movement.
func get_values(core:BuffCore, context:Context) -> Context:
	var allowed_tiles:PackedInt64Array = Tile.create_blank_bitwise_array()
	var mover:Unit = context.unit
	if not Unit.is_valid(mover): return Context.create({object = allowed_tiles, boolean = true})

	# Remaining, not maximum: the toll is paid out of what the character has left this turn.
	var cap:int = maxi(0, mover.core.current.speed - 1)
	var from:Vector2i = mover.state.tile

	for y:int in context.map.size.y:
		for x:int in context.map.size.x:
			var tile := Vector2i(x, y)
			if Tile.distance(from, tile) <= cap:
				Tile.add_to_bitwise_array_alt(allowed_tiles, x, y)

	return Context.create({
		object = allowed_tiles,
		boolean = false, # ban everything not in this array
	})

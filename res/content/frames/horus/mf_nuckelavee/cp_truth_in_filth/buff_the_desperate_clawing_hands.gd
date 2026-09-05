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

## The id this power is switched on and off by. Derived from the FILENAME of the sibling .tres
## (ContentLibrary.get_compcon_id_from_path), so it is declared ONCE, here, and every consumer asks
## through is_active below rather than retyping the literal - a rename then breaks loudly at the
## resource level instead of silently disabling the two halves that still carried the old string.
const ID:StringName = &'buff_the_desperate_clawing_hands'

## Is the power up on this frame? The single switch the whole core power hangs off.
##
## Same shape as is_difficult_ground below: a static predicate on the buff that owns the concept, so
## action_clawing_hands_prone.gd and action_caustic_earth.gd both ask one question in one way.
static func is_active(unit:Unit) -> bool:
	if not Unit.is_valid(unit): return false
	return UnitCondition.has_buff(unit, ID)

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
# point of movement, paid by the character the clause names.
#
# TWO APPROXIMATIONS, both stated plainly rather than implied to be exact:
#
#  1. FREQUENCY. It charges once for the whole move rather than once per exit step, so a hostile
#     weaving in and out of terrain is taxed once rather than repeatedly. Permissive.
#
#  2. A STRAIGHT-LINE RADIUS MEASURED AGAINST A COST BUDGET. get_values can only ban tiles, and it
#     bans by Chebyshev distance from where the mover stands, while the budget it is derived from
#     (speed, plus boost when the mover can boost) is spent on PATH COST - two per tile of difficult
#     terrain. So the two units do not match, and the error is not uniform:
#       - A mover deep inside a field of difficult terrain is UNDER-charged: cost 2/tile already
#         stops it well inside the radius, so the ring this buff removes was unreachable anyway and
#         the toll costs it nothing.
#       - A mover standing on ONE bad tile surrounded by clean ground is where it bites hardest -
#         there the radius is very nearly the real reach, and the trim really is that last ring.
#     Both errors sit on the permissive side of the clause or exactly on it; neither over-charges.
#
# The budget MUST include boost. The restriction array is intersected at pathfinder.gd:352 BEFORE the
# A* graph is built, whereas generate_for_standard_move sizes its candidate ring at speed_with_boost
# (pathfinder.gd:224-229). Capping at speed - 1 alone therefore does not charge one movement point -
# it deletes the boost outright: a speed-4 hostile that normally reaches 8 with a boost would be held
# to 3. That is a whole-ability nerf in the RESTRICTIVE direction, the one thing this clause committed
# against.
#
# Rides Buff.TO.MOVEMENT_RESTRICTION's subtractive mode: the pathfinder loops EVERY character's
# restriction buffs against whoever is moving (pathfinder.gd:340-350), so this buff sits on the
# Nuckelavee and restrains other units.

## Only hostile characters, only while they stand on difficult ground, and only for movement that
## difficult terrain would actually have taxed. Note context.unit is the unit MOVING, not the buff's
## holder.
##
## UnitRelation.are_enemies, matching action_clawing_hands_prone.gd and action_caustic_earth.gd. NOT
## `not Faction.is_ally(...)`, which is not its complement: Faction.SIDE carries NONE, which is
## neither ally nor enemy, so the negated form taxed neutral characters that bullets 1 and 3 leave
## alone. The clause says "hostile characters" in all three places and now means the same thing in
## all three.
##
## ANY occupied tile, matching those same two files. A size-2 mech whose anchor tile is clean while
## its second tile sits in the muck takes the prone damage and the acid, so it pays the movement toll
## too.
func check_if_passive_applies(core:BuffCore, context:Context) -> bool:
	var mover:Unit = context.unit
	var nuckelavee := core.get_holder_unit(context.map)
	if not Unit.is_valid(mover) or not Unit.is_valid(nuckelavee): return false
	if mover == nuckelavee: return false
	if not mover.is_actor(): return false
	if not UnitRelation.are_enemies(nuckelavee, mover): return false
	if not taxes_this_movement(context.resource): return false
	for tile:Vector2i in mover.occupied_tiles():
		if is_difficult_ground(context.map, tile): return true
	return false

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

## Every tile this character may still END on: those within one less than the movement it could
## actually spend this turn - its remaining speed PLUS the boost it is still able to take.
func get_values(core:BuffCore, context:Context) -> Context:
	var allowed_tiles:PackedInt64Array = Tile.create_blank_bitwise_array()
	var mover:Unit = context.unit
	if not Unit.is_valid(mover): return Context.create({object = allowed_tiles, boolean = true})

	# Remaining, not maximum: the toll is paid out of what the character has left this turn. Boost is
	# folded in with the pathfinder's own two helpers, called exactly as it calls them at
	# pathfinder.gd:225-226 - the restriction is applied before the graph is built, so a cap that
	# ignored boost would not charge a point of movement, it would delete the boost.
	var budget:int = mover.core.current.speed
	if UnitAction.can_boost(mover): budget += UnitAction.get_boost_speed(mover)
	var cap:int = maxi(0, budget - 1)
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

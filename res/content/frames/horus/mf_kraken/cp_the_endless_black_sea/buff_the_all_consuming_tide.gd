# The All-Consuming Tide - the scene-long mark the rest of the core power hangs off.
#
#   "For the rest of the |scene|, ..."
#
# Carries no behaviour of its own yet beyond being detectable. Everything else in the core power asks
# UnitCondition.has_buff(unit, 'buff_the_all_consuming_tide'), so this resource is the single switch
# for the whole ability, and clearing it turns all of it off at once.
#
# until = MANUAL is "rest of the scene". Buff.is_cleared_on_owner_death() defaults true (buff.gd:184),
# which is what stops the Tide outliving the Kraken - pinned by a spec rather than trusted, because
# the failure would be silent and permanent.
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-02-kraken-design.md
extends Buff

# ====== THE REACH CAP ======
#
#   "Hostile characters within your |SENSORS| treat movement away from you as |difficult terrain|."
#
# NOT buildable as written. Movement cost is set only inside Pathfinder.Occupation.calculate_for
# (pathfinder.gd:92-98), which consults no buff, and Pathfinder carries a class_name so it cannot be
# script-extended (Godot #83542). extra_cost is written in no other file in the project.
#
# What ships instead is a REACH CAP: a hostile within SENSORS may not END its move more than half its
# remaining movement further from the Kraken than it started. Faithful about DIRECTION - closing and
# circling stay free, and a straight retreat gets exactly the distance difficult terrain would allow -
# and permissive about COST, since it measures the endpoint rather than charging per step.
#
# Rides Buff.TO.MOVEMENT_RESTRICTION's subtractive mode, the same mechanism as the Erinyes' chain:
# the pathfinder loops EVERY character's restriction buffs against whoever is moving
# (pathfinder.gd:340-350), so this buff sits on the Kraken and restrains other units.

## Only hostile characters, and only inside the Tide. Note context.unit is the unit MOVING, not the
## buff's holder - the opposite of buff_bind_thy_flesh, which restrains the character wearing it.
func check_if_passive_applies(core:BuffCore, context:Context) -> bool:
	var mover:Unit = context.unit
	var kraken := core.get_holder_unit(context.map)
	if not Unit.is_valid(mover) or not Unit.is_valid(kraken): return false
	if mover == kraken: return false
	if not mover.is_actor(): return false
	if Faction.is_ally(kraken.state.faction, mover.state.faction): return false
	return UnitRelation.distance_between(kraken, mover) <= kraken.get_sensor_range()

func is_buff_context_valid_for_passive(core:BuffCore, context:Context) -> bool:
	return (
		Unit.is_valid(context.unit) and
		is_instance_valid(context.map) and
		Unit.is_valid(core.get_holder_unit(context.map))
	)

## Every tile this character may still END on: those no further from the Kraken than it stands now,
## plus half the movement it has left.
func get_values(core:BuffCore, context:Context) -> Context:
	var allowed_tiles:PackedInt64Array = Tile.create_blank_bitwise_array()
	var kraken := core.get_holder_unit(context.map)
	if not Unit.is_valid(kraken): return Context.create({object = allowed_tiles, boolean = true})

	var mover:Unit = context.unit
	var kraken_occupied := kraken.occupied_tiles()
	# Remaining, not maximum: difficult terrain charges against what you have left.
	var cap:int = UnitTile.distance_to_alt(kraken_occupied, mover.state.tile) + Util.half(mover.core.current.speed)

	for y:int in context.map.size.y:
		for x:int in context.map.size.x:
			var tile := Vector2i(x, y)
			var would_occupy := UnitTile.get_occupied(tile, mover.state.occupying_size, context.map.size)
			var closest_pair := Tile.get_closest_pair_between(kraken_occupied, would_occupy)
			if Tile.distance(closest_pair.from, closest_pair.to) <= cap:
				Tile.add_to_bitwise_array_alt(allowed_tiles, x, y)

	return Context.create({
		object = allowed_tiles,
		boolean = false, # ban everything not in this array
	})

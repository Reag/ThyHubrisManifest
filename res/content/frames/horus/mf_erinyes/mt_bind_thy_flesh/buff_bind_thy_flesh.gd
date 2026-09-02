# The chain itself: a movement restriction tethering a character to the Erinyes' chain object.
#
#   "The targeted character cannot move away from the chain."
#
# Read as a FROZEN DISTANCE. The character may never end up further from the anchor than it was at
# the moment it was chained, so it can circle the anchor or close in, but never retreat. Each
# chained character records its own leash, because one area pattern catches them at different
# ranges - hence the value lives on the BuffCore instance rather than on the Buff resource.
#
# Modelled on buff_cable_winch_system_move_restriction.gd. The pathfinder intersects a unit's
# reachable tiles with whatever get_values returns (pathfinder.gd:344-349), so returning
# boolean = false here means "these are the only tiles allowed".
extends Buff

const ANCHOR_KEY := 'anchor' ## persistent id of the chain object we are tethered to
const LEASH_KEY := 'leash' ## how far from it this character may remain

## Distance measured the same way the restriction checks it, so "no further than when chained" is
## exact rather than off by one. UnitRelation.distance_between uses a different convention; do not
## mix the two.
static func measure(anchor:Unit, chained:Unit) -> int:
	return measure_from_tiles(anchor.occupied_tiles(), chained)

static func measure_from_tiles(anchor_tiles:Array[Vector2i], chained:Unit) -> int:
	var closest_pair := Tile.get_closest_pair_between(anchor_tiles, chained.occupied_tiles())
	return Tile.distance(closest_pair.from, closest_pair.to)

## Called when the chain is made, to record what this particular character is tethered to and how far
## away it was at that moment.
func bind(core:BuffCore, anchor:Unit, chained:Unit) -> void:
	bind_to_tile(core, anchor.core.persistent_id, anchor.tile(), chained)

## As bind, for when the anchor is spawning from a queued event and so is not on the map yet: its
## UnitCore already has the persistent id, and the tile it is about to occupy is enough to measure.
func bind_to_tile(core:BuffCore, anchor_id:StringName, anchor_tile:Vector2i, chained:Unit) -> void:
	core.set_state(ANCHOR_KEY, String(anchor_id))
	core.set_state(LEASH_KEY, measure_from_tiles([anchor_tile] as Array[Vector2i], chained))

## The chain itself, drawn from the character it binds to the anchor holding it.
##
## Deliberately drawn from the CHARACTER end. The anchor holds every chain it made, and the engine's
## attached-fx map keys by (local tile, fx id) - unit_token.update_attached_fx feeds every ticket to
## one controller per token - so two identical lines on one token collapse into a single instance. A
## shackle holding two prisoners drew one chain, which read in play as only one of them being
## tethered. Each chained character holds exactly one chain buff, so from this end there is nothing
## to collide with.
func get_attached_fx(core:BuffCore, unit:Unit) -> Array[FxEndless.Ticket]:
	var fxe_id := get_fxe_id()
	if fxe_id == &'': return []
	if not is_instance_valid(unit.map): return []
	var anchor := get_anchor(core, unit.map)
	if not Unit.is_valid(anchor): return []
	return [FxEndless.Ticket.create(fxe_id, Vector2i.ZERO, {unit = unit, target_unit = anchor})]

func get_anchor(core:BuffCore, map:MapState) -> Unit:
	return map.get_unit_by_id(StringName(core.get_state(ANCHOR_KEY, '')))

## When the last chain to an anchor goes, the anchor has nothing left to hold and goes with it -
## otherwise a shackle sits on the battlefield as scenery for the rest of the mission.
##
## on_clear fires BEFORE the buff is erased from the unit (unit_condition.gd:933), so the buff being
## cleared right now is still in the list and has to be excluded by identity.
func on_clear(event:EventCore, core:BuffCore, unit:Unit) -> void:
	var map:MapState = event.context.map if is_instance_valid(event) and event.context else X.map()
	if not is_instance_valid(map): return

	var anchor := get_anchor(core, map)
	if not Unit.is_valid(anchor): return # already destroyed, which is one of the ways this ends
	if is_still_binding_anyone(anchor, map, core): return

	event.queue_event(&'event_unit_die', {unit = anchor})

func is_still_binding_anyone(anchor:Unit, map:MapState, ignoring:BuffCore) -> bool:
	var anchor_id := String(anchor.core.persistent_id)
	for check_unit:Unit in map.get_all_units():
		for buff:BuffCore in check_unit.state.buffs:
			if buff == ignoring: continue
			if buff.base.compcon_id != compcon_id: continue
			if buff.get_state(ANCHOR_KEY, '') == anchor_id: return true
	return false

# ====== PASSIVE BUFFS ======
func is_buff_context_valid_for_passive(core:BuffCore, context:Context) -> bool:
	# No anchor means the chain object was destroyed, which the book says ends the effect. Reporting
	# the context as invalid simply stops the restriction applying.
	return (
		Unit.is_valid(context.unit) and
		is_instance_valid(context.map) and
		Unit.is_valid(get_anchor(core, context.map))
	)

func check_if_passive_applies(core:BuffCore, context:Context) -> bool:
	return context.unit == core.get_holder_unit(context.map)

## Every tile this character may still stand on: those no further from the anchor than it already was.
func get_values(core:BuffCore, context:Context) -> Context:
	var allowed_tiles:PackedInt64Array = Tile.create_blank_bitwise_array()
	var anchor := get_anchor(core, context.map)
	if not Unit.is_valid(anchor): return Context.create({object = allowed_tiles, boolean = true})

	var leash:int = core.get_state(LEASH_KEY, 0)
	var anchor_occupied := anchor.occupied_tiles()

	for y:int in context.map.size.y:
		for x:int in context.map.size.x:
			var tile := Vector2i(x, y)
			if UnitTile.distance_to_alt(anchor_occupied, tile) > leash + 4:
				continue # obviously out of range; skip the expensive comparison
			var would_occupy := UnitTile.get_occupied(tile, context.unit.state.occupying_size, context.map.size)
			var closest_pair := Tile.get_closest_pair_between(anchor_occupied, would_occupy)
			if Tile.distance(closest_pair.from, closest_pair.to) <= leash:
				Tile.add_to_bitwise_array_alt(allowed_tiles, x, y)

	return Context.create({
		object = allowed_tiles,
		boolean = false, # ban everything not in this array
	})

# The visible tether between the Kraken and someone it has pulled into its domain.
#
# Purely cosmetic - the grapple itself is a Katamari attachment, and adjacency comes from the
# unit_relation extension. This buff exists only so the line has somewhere to be drawn FROM.
#
# Deliberately drawn from the GRAPPLED character's end, not the Kraken's. The engine's attached-fx
# map keys on (local tile, fx id), and unit_token.gd:230-237 tickets every outgoing grapple with the
# same &'fxe_outgoing_grapple' id at Vector2i.ZERO - so several tethers on one token are competing
# for one key. My Domain grapples a whole burst at once, which is exactly the case that breaks. Each
# grappled character holds one tether buff, so from this end there is nothing to collide with. The
# Erinyes' chains are drawn the same way for the same reason, see buff_bind_thy_flesh.gd.
#
# A separate scene rather than vanilla's fxe_outgoing_grapple because recolouring that one would
# turn every grapple in the game blue, including other frames'.
extends Buff

const GRAPPLER_KEY := 'grappler' ## persistent id of the Kraken holding this character

func bind(core:BuffCore, grappler:Unit) -> void:
	core.set_state(GRAPPLER_KEY, String(grappler.core.persistent_id))

func get_grappler(core:BuffCore, map:MapState) -> Unit:
	if not is_instance_valid(map): return null
	return map.get_unit_by_id(StringName(core.get_state(GRAPPLER_KEY, '')))

## The tether, drawn from this character back to the Kraken.
##
## Checks the grapple is still real before drawing. The buff and the attachment are applied together
## but can be ended apart - grapple release, a death, a forced move - and a line still hanging off a
## character nothing is holding reads as a bug.
func get_attached_fx(core:BuffCore, unit:Unit) -> Array[FxEndless.Ticket]:
	var fxe_id := get_fxe_id()
	if fxe_id == &'': return []
	if not Unit.is_valid(unit) or not is_instance_valid(unit.map): return []

	var grappler := get_grappler(core, unit.map)
	if not Unit.is_valid(grappler): return []
	if not is_still_grappled(unit, grappler): return []

	return [FxEndless.Ticket.create(fxe_id, Vector2i.ZERO, {unit = unit, target_unit = grappler})]

## Is the Kraken still actually holding this character?
static func is_still_grappled(unit:Unit, grappler:Unit) -> bool:
	for grapple:SpecificAction in UnitCondition.get_outgoing_grapples(grappler):
		if grapple.unit == unit: return true
	return false

# Draws one chain from this anchor to every character bound to it.
#
# PassiveFxLine can already draw several lines - its HAS_BUFF mode loops and makes a ticket per
# target - but it matches on the buff having been applied by the gear holding the passive, and our
# chains are applied by the Erinyes' trait rather than by the anchor. Matching on the anchor id the
# buff recorded is also simply more exact: with two anchors on the field each draws only its own
# chains, which HAS_BUFF could not tell apart.
extends Passive

const CHAIN_BUFF_ID := &'buff_bind_thy_flesh'
const ANCHOR_KEY := 'anchor'

func get_attached_fx(gear:GearCore, unit:Unit) -> Array[FxEndless.Ticket]:
	var tickets:Array[FxEndless.Ticket] = []
	var fxe_id := get_fxe_id()
	if fxe_id == &'' or not should_show_attached_fx(gear, unit): return tickets
	if not is_instance_valid(unit.map): return tickets

	var our_id := String(unit.core.persistent_id)
	for check_unit:Unit in unit.map.get_all_units():
		if check_unit == unit or not Unit.is_valid(check_unit): continue
		if not is_bound_to_us(check_unit, our_id): continue
		if not UnitRelation.can_affect(unit, check_unit): continue # parity with PassiveFxLine
		tickets.append(FxEndless.Ticket.create(fxe_id, Vector2i.ZERO, {
			unit = unit,
			target_unit = check_unit,
		}))
	return tickets

func is_bound_to_us(check_unit:Unit, our_id:String) -> bool:
	for buff:BuffCore in check_unit.state.buffs:
		if buff.base.compcon_id != CHAIN_BUFF_ID: continue
		if buff.get_state(ANCHOR_KEY, '') == our_id: return true
	return false

# Know Thy Sins.
#
#   "When a chained character starts their turn, they take |1 BURN| for each condition and status
#    they have."
#
# All the hard work is already done by Bind Thy Flesh: the condition is just "is this character
# chained to one of our anchors", so this is a plain new_turn reaction with no machinery of its own.
#
# It asks for a STANDING anchor rather than merely for the chain buff to be present. Destroying the
# shackle ends the chain - buff_bind_thy_flesh stops restricting movement the moment its anchor is
# gone - and a character should not keep burning for a shackle that is no longer there.
extends ActionReaction

const CHAIN_BUFF_ID := &'buff_bind_thy_flesh'
const ANCHOR_KEY := 'anchor'

func get_required_triggering_context() -> Array[Context.PROP]:
	return [Context.PROP.unit]

func triggers_on_event(unit:Unit, gear:GearCore, triggering_event:EventCore) -> bool:
	var starting_unit:Unit = triggering_event.context.unit
	if not Unit.is_valid(starting_unit) or starting_unit == unit: return false
	if not is_chained_to_us(starting_unit, unit): return false
	return count_sins(starting_unit) > 0

## Chained, and chained to a shackle of ours that is still standing. Checking ownership rather than
## just the buff keeps two Erinyes on the same map from burning each other's prisoners.
func is_chained_to_us(chained_unit:Unit, erinyes:Unit) -> bool:
	if not is_instance_valid(erinyes.map): return false
	for buff:BuffCore in chained_unit.state.buffs:
		if buff.base.compcon_id != CHAIN_BUFF_ID: continue
		var anchor := erinyes.map.get_unit_by_id(StringName(buff.get_state(ANCHOR_KEY, '')))
		if not Unit.is_valid(anchor): continue
		if anchor.get_owner_unit() == erinyes: return true
	return false

## "each condition and status they have" - this engine keeps both in one list on the unit.
func count_sins(unit:Unit) -> int:
	return unit.current_statuses().size()

func activate(context:Context, activation:EventCore) -> void:
	var starting_unit:Unit = context.event.context.unit
	var sins := count_sins(starting_unit)
	if activation.abort_when(sins <= 0): return

	CommonActionUtil.queue_damage_events(
		activation, SpecificAction.from_context(context), [starting_unit],
		sins, Lancer.DAMAGE_TYPE.BURN,
	)

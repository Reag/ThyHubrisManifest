# Breaking free of a chain: a quick action and a HULL check.
#
# This action lives on the ANCHOR's kit, so that whoever is chained is offered it (unit_action.gd
# offers any unit's situational gear to whoever can_be_used_situationally_by accepts). That has one
# consequence worth spelling out: the usage limits Action enforces are recorded against the gear,
# and every character chained to the same anchor shares that one gear.
#
# Left at the defaults, a QUICK action is 1/turn and the FIRST character to break free would spend
# the anchor's whole allowance, leaving everyone else chained with no way out until the next round.
# Each character spends its own quick action from its own action economy - that part is per unit and
# still applies - so the shared limit is meaningless here and is lifted.
extends ActionSystemClearBuff

const CHAIN_BUFF_ID := &'buff_bind_thy_flesh'
const ANCHOR_KEY := 'anchor'

func get_per_turn_soft_limit(specific:SpecificAction) -> int: return 99
func get_per_round_hard_limit(specific:SpecificAction) -> int: return 99

## Only the anchor a character is actually chained to offers it a way out.
##
## ActionSystemClearBuff matches the buff by id alone (and optionally by the gear that applied it,
## which is no help here - our chains are applied by the Erinyes' trait, not by any anchor). With
## three anchors standing, a character chained to one was being offered three identical escape
## actions, one from each. Seen in play: a Blackbeard tethered once with three break-free buttons.
func can_be_used_situationally_by(unit:Unit, situational_unit:Unit, situational_gear:GearCore) -> bool:
	if not super.can_be_used_situationally_by(unit, situational_unit, situational_gear): return false
	return is_bound_to(unit, situational_unit)

func is_bound_to(unit:Unit, anchor:Unit) -> bool:
	if not Unit.is_valid(anchor): return false
	var anchor_id := String(anchor.core.persistent_id)
	for buff:BuffCore in unit.state.buffs:
		if buff.base.compcon_id != CHAIN_BUFF_ID: continue
		if buff.get_state(ANCHOR_KEY, '') == anchor_id: return true
	return false

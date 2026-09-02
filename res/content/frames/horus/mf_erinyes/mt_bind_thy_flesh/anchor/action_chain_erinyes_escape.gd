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

func get_per_turn_soft_limit(specific:SpecificAction) -> int: return 99
func get_per_round_hard_limit(specific:SpecificAction) -> int: return 99

# "Gain +1 ACCURACY on attacks against targets in the fog" - while the Draugr is inside it too.
#
# A BuffBonus (to = attack_roll, ACCURACY, +1) handed to the Draugr by cp_cupiditas_vitae's
# PassiveBuffApplicator and gated per attack by check_if_passive_applies.
#
# THE MAGNITUDE CANNOT DEPEND ON POSITION, WHICH IS WHY THE GATE HAS TO. attack_roll.gd:134 collects
# Buff.TO.ATTACK_ROLL buffs off the attacker WITH the attack context - which does carry target_unit,
# since event_unit_attack.gd:53 builds the PreAttack from its own context - so the gate below sees
# both units. But :182-189 then reads each buff's value with buff_core.get_values() and NO CONTEXT
# AT ALL, so bonus_value has to be a constant. A flat +1 is what the rules ask for, so this is not a
# compromise, but it is why the "in the fog" test lives in the gate and not in get_values.
#
# core.get_owner_unit(map) rather than context.unit: attack_roll.gd:121-122 fetches the buffs off
# relay.get_attacker(context), so context.unit may be a targeting relay (a Throughbolt round, a ghast
# nexus) rather than the Draugr. The buff's owner gear is the Draugr's own core power, so its owner
# unit is always the Draugr - and get_owner_unit is a single map lookup by source id
# (buff_core.gd:102-105), where get_holder_unit walks every unit on the map (:129-133).
#
# PlagueFog.shared_by insists the fog is one the ATTACKER owns and that the attacker is standing in
# it, so an enemy Draugr's cloud never sharpens our aim.
extends BuffBonus

const PlagueFog := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/cp_cupiditas_vitae/plague_fog.gd')

func is_buff_context_valid_for_passive(core:BuffCore, context:Context) -> bool:
	return context != null and Unit.is_valid(context.target_unit)

func check_if_passive_applies(core:BuffCore, context:Context) -> bool:
	var draugr := core.get_owner_unit(context.map)
	if not Unit.is_valid(draugr): return false
	return PlagueFog.shared_by(draugr, context.target_unit) != null

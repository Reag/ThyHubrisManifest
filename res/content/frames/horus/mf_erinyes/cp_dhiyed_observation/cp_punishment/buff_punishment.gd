# Punishment, the spendable half of DHIYED Observation.
#
#   "You may spend your core (no action required) for one of the following effects:
#    • Before rolling an attack, spend your core to cause the attack to automatically critically hit.
#    • Before forcing a target to make a save, spend your core to force the target to fail the save."
#
# Both bullets are one mechanism. Dice.roll_d20_with_player_interventions is called from BOTH
# attack_roll.gd:67 and unit_hasecheck.gd, and a Buff.TO.CHEAT_D20_ROLL buff gets to replace that
# d20 - so the ability does not need a menu asking which effect you want. Which one applies is
# decided by what is being rolled: 20 when the Erinyes is the one attacking, 1 when the roll is a
# save the Erinyes forced. That is closer to how the ability reads at the table than a choice prompt.
#
# The engine spends the action for us when the offer is accepted (dice.gd:200 calls
# spend_actions_gain_heat on whatever `object` we hand back), and action_punishment carries
# consumes_cp, so accepting is what costs the core power.
#
# Caveat worth knowing: a forced 20 crits because attack_roll.gd computes
# `crit = (total_roll >= 20) and hit`. Against a defence above 20 even a forced 20 could miss, so
# "automatically" is true in every realistic case rather than guaranteed. 20 is the highest honest
# value to put on a d20.
extends Buff

const CORE_POWER_ID := &'cp_dhiyed_observation'
const PUNISHMENT_ACTION := &'action_punishment'
const AUTO_CRIT_ROLL := 20
const FORCED_FAILURE_ROLL := 1
const NOT_OUR_BUSINESS := -1

## The action the engine spends when the player accepts. Also what makes this cost the core power.
func get_punishment(core:BuffCore, map:MapState) -> SpecificAction:
	var erinyes := core.get_holder_unit(map)
	if not Unit.is_valid(erinyes): return null
	var gear := erinyes.get_gear(CORE_POWER_ID)
	if not GearCore.is_valid(gear): return null
	return SpecificAction.create(erinyes, gear, gear.get_action(PUNISHMENT_ACTION))

## Attack rolls carry a DeclaredAttackSummary; checks and saves do not.
##
## The obvious-looking test - "does the context have a HASE category" - is WRONG and cost a debug
## cycle: an attack context carries `category` too, as the damage type, so it read every attack as a
## save and forced our own attacks to roll a 1.
func is_an_attack(context:Context) -> bool:
	if not context.is_property_present(Context.PROP.resource): return false
	return DeclaredAttackSummary.is_valid(context.resource)

## What to offer for this roll, or NOT_OUR_BUSINESS. Every d20 in the game passes through here, so
## the overwhelmingly common answer is "nothing".
func offered_roll(core:BuffCore, context:Context) -> int:
	var erinyes := core.get_holder_unit(context.map)
	if not Unit.is_valid(erinyes): return NOT_OUR_BUSINESS
	if not erinyes.core.has_core_power: return NOT_OUR_BUSINESS
	if not Unit.is_valid(context.unit): return NOT_OUR_BUSINESS

	if is_an_attack(context):
		return AUTO_CRIT_ROLL if context.unit.get_attacker(context) == erinyes else NOT_OUR_BUSINESS

	# A check or a save. Only meddle when WE forced it on somebody else - context.unit is the unit
	# forcing it and context.target_unit is the one rolling. Without the second half of this the
	# Erinyes would force a 1 on its own skill checks.
	if context.unit != erinyes: return NOT_OUR_BUSINESS
	var roller:Unit = context.target_unit
	if not Unit.is_valid(roller) or roller == erinyes: return NOT_OUR_BUSINESS
	return FORCED_FAILURE_ROLL

func is_buff_context_valid_for_passive(core:BuffCore, context:Context) -> bool:
	if not is_instance_valid(context.map): return false
	return SpecificAction.is_valid(get_punishment(core, context.map))

func check_if_passive_applies(core:BuffCore, context:Context) -> bool:
	return offered_roll(core, context) != NOT_OUR_BUSINESS

## The prompt the player is shown. dice.gd renders the CHOICES from the roll values themselves, so
## the button reads "20" or "1" and there is nothing content-side that can change that - the meaning
## has to live in the title (the action's name) and this description. Hence a line per effect saying
## what accepting does, rather than the ability's full two-bullet text, half of which never applies
## to the roll being offered.
func prompt_key(core:BuffCore, context:Context) -> String:
	var which := 'crit' if offered_roll(core, context) == AUTO_CRIT_ROLL else 'save'
	return 'gear.%s.%s.prompt.%s' % [CORE_POWER_ID, PUNISHMENT_ACTION, which]

func get_values(core:BuffCore, context:Context) -> Context:
	return Context.create({
		array = [offered_roll(core, context)],
		string = prompt_key(core, context),
		object = get_punishment(core, context.map),
	})

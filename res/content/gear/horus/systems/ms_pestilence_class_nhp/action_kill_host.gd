# Kill Host - the PESTILENCE-class NHP's protocol.
#
#   "Take 2 heat. All targets with INFECTION within RANGE 5 of you take AP ENERGY equal to 2 + twice
#    their current INFECTION. Then choose one of the following:
#    - Targets become IMPAIRED until the end of their next turn, or JAMMED if they have at least 3
#      INFECTION.
#    - Targets become SLOWED until the end of their next turn, or PRONE and IMMOBILIZED if they have
#      at least 3 INFECTION.
#    Targets then clear all INFECTION."
#
# "TAKE 2 HEAT" IS ONE .tres FIELD. Action.self_heat_dice (action.gd:39) is read by
# UnitAction.gain_self_heat (:291-295) from spend_actions_gain_heat, which spend_actions() below
# calls - so the heat is not written anywhere in this file. It is QUEUED rather than awaited
# (:299-302), so it lands after the damage; nothing in the rules depends on the order of the
# Draugr's own heat.
#
# THE PROTOCOL IS 1/ROUND WITH NO OVERRIDE. Lancer.ACTION_COST[PROTOCOL] is 0, and
# Action.get_per_round_hard_limit returns 1 for any naturally free action (action.gd:155-158). A
# protocol also does not close the protocol phase (unit_action.gd:309-314), so the Draugr can still
# take another one.
#
# ================== ORDER OF OPERATIONS (plan decision D8) ==================
#   1. SNAPSHOT the counts. The damage arithmetic and the ">= 3" escalation must read the SAME
#      number; reading Infection.count twice would let anything that reacts to the damage change the
#      escalation underneath us.
#   2. spend_actions - the usage record and the 2 heat.
#   3. DAMAGE, awaited one target at a time, so a death resolves before the next.
#   4. Recollect the SURVIVORS. A target the damage killed is not a target for anything after it.
#   5. The CHOICE, once, for all of them - and only if somebody survived. Asking the player to pick
#      an effect for a pile of wrecks is a bug report waiting to happen.
#   6. The STATUSES, then the CLEAR. The rules put the clear last and it matters: clearing first
#      would zero the counts the escalation is still reading.
#
# ALLIES ARE TARGETS (design decision D5, "as written"). UnitRelation.get_characters_within does no
# faction filtering, so this is the default rather than something arranged here. LOS is not required
# either (plan decision D12): Kill Host detonates a plague already inside the target rather than
# projecting anything at it, and every other Draugr area effect in this mod ignores LOS.
#
# NOT is_tech. It should not be stopped by JAMMED or by the mod's own Lockdown, and
# ActionSystem.get_flavor returns PROTOCOL before it ever consults is_tech (action_system.gd:63-68),
# so the tooltip reads correctly either way.
extends ActionSystem

const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')
const Compat := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/reag_compat.gd')

const KIT_ID := &'ms_pestilence_class_nhp'
const REACH := 5
const BASE_DAMAGE := 2
const PER_INFECTION := 2
const ESCALATION_AT := 3

enum OPTION {IMPAIR, SLOW}

func activate(context:Context, activation:EventCore) -> void:
	var draugr:Unit = context.unit
	if activation.abort_when(not Unit.is_valid(draugr)): return

	var victims:Array[Unit] = kill_host_targets(draugr)
	var counts:Dictionary[Unit, int] = {}
	for victim:Unit in victims: counts[victim] = Infection.count(victim)

	spend_actions(activation) # records the usage and takes the 2 self heat
	await run_system_fxgs(draugr, victims)
	if activation.abort_without_unit(draugr): return

	for victim:Unit in victims:
		if activation.abort_if_level_exited(): return
		if not Unit.is_valid(victim) or not victim.is_on_map(): continue
		await activation.execute_event(&'event_unit_damage', {
			unit = victim,
			number = BASE_DAMAGE + PER_INFECTION * counts.get(victim, 0),
			category = Lancer.DAMAGE_TYPE.ENERGY,
			flags = [EventService.DAMAGE_FLAG.AP],
			target_unit = draugr, # who did this, for the damage event's own logging
		})

	var survivors:Array[Unit] = []
	for victim:Unit in victims:
		if Unit.is_valid(victim) and victim.is_on_map(): survivors.append(victim)
	if survivors.is_empty(): return
	if activation.abort_without_unit(draugr): return

	var option:int = await choose_option(draugr, survivors)
	if option < 0: return # the request was aborted; the damage stands, nothing else happens
	if activation.abort_without_unit(draugr): return

	var source:StringName = context.gear.persistent_id if GearCore.is_valid(context.gear) else &''
	for victim:Unit in survivors:
		if not Unit.is_valid(victim) or not victim.is_on_map(): continue
		for status:StringName in statuses_for(option, counts.get(victim, 0)):
			UnitCondition.apply_status(activation, victim, status, Lancer.UNTIL.END_OF_NEXT_TURN, source)

	for victim:Unit in survivors:
		if not Unit.is_valid(victim) or not victim.is_on_map(): continue
		Infection.clear(activation, victim)

## "All targets with INFECTION within RANGE 5 of you" - allies included (design decision D5).
##
## get_characters_within (unit_relation.gd:34-43) already drops the Draugr itself, drops MARKERS
## (:48, :57) and keeps only is_character(). require_los is false: see the file header.
static func kill_host_targets(draugr:Unit) -> Array[Unit]:
	var found:Array[Unit] = []
	if not Unit.is_valid(draugr) or not is_instance_valid(draugr.map): return found
	found = UnitRelation.get_characters_within(
		draugr, REACH, false,
		func(other:Unit) -> bool: return Infection.is_infected(other)
	)
	return found

## The statuses one option lands on a target holding `infection` INFECTION. Static and pure, so the
## escalation is testable without firing the protocol.
static func statuses_for(option:int, infection:int) -> Array[StringName]:
	var applied:Array[StringName] = []
	var escalated:bool = infection >= ESCALATION_AT
	if option == OPTION.SLOW:
		if escalated:
			applied.append(Lancer.STATUS.PRONE)
			applied.append(Lancer.STATUS.IMMOBILIZED)
		else:
			applied.append(Lancer.STATUS.SLOWED)
	else:
		if escalated: applied.append(Lancer.STATUS.JAMMED)
		else: applied.append(Lancer.STATUS.IMPAIRED)
	return applied

## "Choose one of the following" - mandatory, so no cancel. The AI takes a die, exactly as Snow Crash
## does (action_snow_crash.gd:32); vanilla never prompts an AI for an optional flourish, and this mod
## does the same at onhit_spreading_stain.gd:89-96.
##
## Through reag_compat, never choice_bus directly (CLAUDE.md). BrochureCore does NOT translate its
## choice entries (brochure_core.gd:26-29), so the already-translated text is passed, the way
## action_symptom.gd:97-107 does.
func choose_option(draugr:Unit, survivors:Array[Unit]) -> int:
	if not draugr.is_player_controlled(): return OPTION.IMPAIR if Dice.roll_d6() > 3 else OPTION.SLOW
	var specific := SpecificAction.create(draugr, draugr.get_gear(KIT_ID), self)
	return await Compat.multiple_choice(
		specific,
		[
			Translate.gear(KIT_ID, 'action_kill_host.option_impair'),
			Translate.gear(KIT_ID, 'action_kill_host.option_slow'),
		],
		Translate.gear(KIT_ID, 'action_kill_host.name'),
		'battle.multiple_choice.prompt',
		'',
		false, # can_cancel: the rules say "choose one"
	)

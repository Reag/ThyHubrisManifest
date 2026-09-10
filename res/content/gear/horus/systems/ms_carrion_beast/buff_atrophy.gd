# Atrophy. "1/turn, reduce the target's INFECTION by 1. The target takes +1 DIFFICULTY on the
# triggering roll." Trigger: "A character with INFECTION within SENSORS is about to roll a save or
# check."
#
# AUTOMATIC (design 2026-09-09-draugr-design.md, decision D4). A plain check never fires a reaction
# trigger at all - make_*_check bypasses event_unit_save entirely - and the modifier hook is
# synchronous and runs before the roll, so there is nowhere to prompt. This is therefore not an
# ActionReaction: it is a marker planted on every character in reach by passive_atrophy, which
# decides at roll time whether it applies and pays the reaction itself.
#
# ONE `to = save` BUFF COVERS "A SAVE OR CHECK". UnitHasecheck.roll_check (unit_hasecheck.gd:161-256)
# is the only place Buff.TO.SAVE is read, and both roads lead there: handle_check calls it at :133,
# and a forced save arrives at the same handle_check via event_unit_save.gd:54-63 with is_save = true
# (which changes only the battle-log key). The Infection end-of-turn check comes through as well -
# that is the designed combo, not a coincidence.
#
# READ context.target_unit, NEVER context.unit. roll_check builds its buff context at :174-179 with
# target_unit = the ROLLER, and only fills `unit` from a forcing_action when there is one (:180-184).
# On a plain check - the Infection check included - context.unit is NULL. A gate reading context.unit
# would work on saves and silently do nothing on checks, which is half the rules row.
#
# EVERY GATE IS HERE, BECAUSE on_consumption HAS NO CONTEXT. The engine hands on_consumption only
# (event, core, holder) - no roll, no target, no action (buff.gd:173). So "infected", "in reach",
# "the Draugr is alive", "a reaction is available" and "unused this turn" are all decided in
# check_if_passive_applies, which runs per roll and cannot go stale.
#
# THE BUFF SURVIVES ITS OWN CONSUMPTION. consume_buffs only offers is_onetime buffs to on_consumption
# and clears them unless it returns false (unit_condition.gd:936-949). is_onetime is therefore
# mandatory just to be called, and returning false keeps the marker in place so nothing depends on an
# aura refresh to restore it. The engine logs "Buff aborted its own consumption!" at printv level;
# that line is expected. The real 1/turn limit is the gear counter below.
#
# 1/TURN IS THE ENGINE'S OWN PER-TURN COUNTER, under a private usage group. uses_this_turn is cleared
# for EVERY unit on the map at EVERY turn start (UnitAction.every_new_turn_refresh ->
# reset_per_turn_usage, unit_action.gd:66-70, from content/events/event_turn_start.gd:43-44), which is
# exactly what "1/turn" means for a reaction here - the same shape action_ceaseless_death.gd uses. The
# group is private so nothing else on the Carrion Beast ever shares the allowance (gear_core.gd:166-168).
extends BuffSkillSave

const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')
const DraugrReach := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/draugr_reach.gd')

## Private per-turn usage group on the Carrion Beast's own GearCore.
const USAGE_GROUP := &'carrion_beast_atrophy'

func is_buff_context_valid_for_passive(core:BuffCore, context:Context) -> bool:
	return context != null and Unit.is_valid(context.target_unit)

func check_if_passive_applies(core:BuffCore, context:Context) -> bool:
	if not super.check_if_passive_applies(core, context): return false # the save_type filter; all_save_types = true makes it true
	var holder:Unit = context.target_unit
	if not Unit.is_valid(holder) or not Infection.is_infected(holder): return false

	var draugr:Unit = core.get_owner_unit(context.map)
	if not Unit.is_valid(draugr) or not draugr.is_on_map(): return false
	if draugr == holder: return false # the aura sets applies_to_self = false; belt and braces
	if not DraugrReach.within_sensors(draugr, holder): return false

	# "Gain the Atrophy REACTION": it costs one, so it needs one. can_take_reactions
	# (unit_action.gd:378-386) is the engine's own answer - reactions remaining, not JAMMED, not
	# GRAPPLED without a permitting buff.
	if not UnitAction.can_take_reactions(draugr): return false

	var gear:GearCore = draugr.get_gear(DraugrReach.KIT_ID)
	if not GearCore.is_valid(gear) or not gear.is_intact(): return false

	# TASK 3B: can_take_reactions above does not know Isolation exists. Isolation's "cannot take
	# reactions" is UnitAction.get_gear_unavailable_reason's REASON.FORBIDDEN clause
	# (unit_action.gd:157), which needs a context.action that IS an ActionReaction requiring a
	# reaction point (buff_isolation.gd:22-23) - can_take_reactions is never handed one. action_atrophy
	# exists purely so this question can be asked; it never activates on its own (see its own header).
	# get_gear_unavailable_reason also re-checks intactness/PER_ROUND/etc for this action, all of which
	# are harmlessly redundant with the checks already on this line, because action_atrophy never
	# actually activates and so never advances its own counters.
	var atrophy_action:Action = gear.get_action(&'action_atrophy')
	if not Action.is_valid(atrophy_action): return false # fixture/content gap; fail closed
	var atrophy_specific := SpecificAction.create(draugr, gear, atrophy_action)
	if UnitAction.get_gear_unavailable_reason(atrophy_specific) != UnitAction.REASON.NONE: return false

	return gear.get_uses_this_turn_alt(USAGE_GROUP) < 1

## The whole effect, minus the difficulty die that get_values already handed over. Runs from
## UnitCondition.consume_buffs at unit_hasecheck.gd:195 - BEFORE the d20 at :200 - so the reduction
## is in place by the time a failed Infection check burns what is left.
##
## Returns FALSE on purpose: that keeps this marker on the holder (see the header).
func on_consumption(event:EventCore, core:BuffCore, unit:Unit) -> bool:
	var draugr:Unit = core.get_owner_unit(event.context.map)
	if not Unit.is_valid(draugr): return false
	var gear:GearCore = draugr.get_gear(DraugrReach.KIT_ID)
	if not GearCore.is_valid(gear): return false

	gear.increment_action_usage(USAGE_GROUP, true) # the 1/turn record
	UnitAction.spend_reaction(draugr)
	Infection.reduce(event, unit, 1)
	return false

# PROBE -- throwaway, deleted after the real Mourning Call build.
# PROBE 1: fires on a ranged hit, prompts "use Mourning Call?" (auto-answered
# yes by SpecFactory.current_responder in specs), then hands off to the
# probe QUICK action via CommonActionUtil.choose_and_use -- the same
# hand-off shape action_flank.gd uses.
extends OnHitEffect

const MOURNING_CALL_KIT_ID := &'cp_probe_mourning_call'

func on_hit(activation:EventCore, attacked_unit:Unit) -> void:
	var unit:Unit = activation.context.unit
	if not Unit.is_valid(unit): return
	var gear:GearCore = unit.get_gear(MOURNING_CALL_KIT_ID)
	if not GearCore.is_valid(gear): return

	var confirmed:bool = await choice_bus.quick_yesno(unit.tile(), 'PROBE: use Mourning Call?')
	if not Unit.is_valid(unit) or not confirmed: return

	var mourning_call := SpecificAction.create(unit, gear, gear.get_solo_action())
	await CommonActionUtil.choose_and_use(activation, mourning_call, [mourning_call])

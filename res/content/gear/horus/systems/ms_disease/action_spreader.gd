# Spreader - Disease's second Invade option.
#
#   "Your target takes 1 INFECTION and is SLOWED for as long as they have INFECTION. ..."
#
# Its own usage_group, and a 1/round hard limit, for the same reason Symptom has them: per-round
# counters key on the usage group, which defaults to the KIT id (gear_core.gd:166-168), so without
# one Symptom and Spreader would share a single allowance.
#
# NO get_damage_dice OVERRIDE, on purpose (plan decision D2). Symptom's rules text says "instead of
# Invade's normal heat" and Spreader's does not, so the standard 2 heat
# (action_attack_tech.gd:17) still lands, on top of the 1 heat the Infection itself deals.
#
# The buff is applied AFTER the Infection, because InfectionLinks.link needs an Infection buff to
# record against - and then linked, so "for as long as they have INFECTION" needs no clock of its own.
extends ActionAttackTech

const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')
const InfectionLinks := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection_links.gd')

const SPREADER_BUFF := &'buff_spreader'
const INFECTION_APPLIED:int = 1

func get_per_round_hard_limit(specific:SpecificAction) -> int: return 1

func on_hit(activation:EventCore, attacked_unit:Unit) -> void:
	if not Unit.is_valid(attacked_unit): return
	await Infection.apply(activation, attacked_unit, INFECTION_APPLIED)
	if activation.abort_without_unit(attacked_unit): return
	# apply() refuses tech-immune targets; with no Infection there is nothing to hang the slow on.
	if not Infection.is_infected(attacked_unit): return
	if not UnitCondition.get_buffs(attacked_unit, SPREADER_BUFF).is_empty(): return # already spreading

	# No from_gear: see buff_spreader.gd's header. The slow must outlive the Draugr, as Infection does.
	var spreader := UnitCondition.apply_buff_id(activation, attacked_unit, SPREADER_BUFF)
	if BuffCore.is_valid(spreader): InfectionLinks.link(attacked_unit, spreader)

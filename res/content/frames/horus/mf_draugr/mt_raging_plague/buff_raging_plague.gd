# The Raging Plague. "The Draugr's melee attacks gain OVERKILL against targets with INFECTION."
#
# A BuffWeaponTypeTag (weapon_types = [MELEE], added_tag = overkill) that mt_raging_plague hands to
# the Draugr through a PassiveBuffApplicator. All this subclass adds is the "against targets with
# INFECTION" clause.
#
# WHY THIS DOES NOT SIMPLY READ context.target_unit. OVERKILL is consulted in exactly two places and
# both pass the event_unit_attack_declared context:
#   action_attack_weapon.gd:257-265  is_overkill / apply_overkill, bound as
#                                    action.apply_overkill.bind(core) at
#                                    event_unit_attack_declared.gd:88, :91 and :278
#   event_unit_attack_declared.gd:174 the gate on the event_unit_overkill heat event
# That context is built at action_attack.gd:266-272 as {unit, gear, action, resource, flags} and
# nothing else, and Context.target_unit is just target_units[0] (context.gd:12-16) - so it is NULL
# whenever overkill is being decided. (The AP/IRREDUCIBLE path DOES carry a target: it builds its own
# tag_buff_context at event_unit_attack_declared.gd:239-242. Overkill never takes that path, and the
# UI preview's virtual event at attack_preview.gd:135-141 omits it too.)
#
# So the targets are read off the DeclaredAttackSummary the declared context does carry
# (declared_attack_summary.gd:9, re-filtered for validity at event_unit_attack_declared.gd:71). Base
# damage is rolled ONCE for the whole declared attack, so one overkill decision covers every target
# and "any attacked character is infected" is the only granularity the engine offers. For the
# single-target melee attack this trait is written for, that is exactly the target.
#
# target_unit is still preferred when a caller supplies one - get_glossary_tags
# (action_attack_weapon.gd:113) and the AP/IRREDUCIBLE path both ask per target, and answering those
# off the summary would be wrong.
extends BuffWeaponTypeTag

const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')

func check_if_passive_applies(core:BuffCore, context:Context) -> bool:
	if not super.check_if_passive_applies(core, context): return false
	if Unit.is_valid(context.target_unit): return Infection.is_infected(context.target_unit)
	if not DeclaredAttackSummary.is_valid(context.resource): return false
	var declared:DeclaredAttackSummary = context.resource
	for attacked:Unit in declared.all_attacked_units:
		if Unit.is_valid(attacked) and Infection.is_infected(attacked): return true
	return false

# The targeting half of "When targeting characters with INFECTION, your SENSORS increase by 5."
#
# A Buff.TO.ACTION_TILES buff on the Draugr, handed out by ms_carrion_beast's PassiveBuffApplicator.
# UnitTargeting.modify_action_tiles_from_buffs (unit_targeting.gd:164-181) is the fifth step of
# get_tiles_in_range and merges every such buff: values.boolean = true ADDS the tiles in
# values.object, false INTERSECTS them. We add. Vanilla's template is the Metahook's
# buff_metahook_range.gd, and the tech filter below is that file's, verbatim.
#
# WHY context.unit IS SAFE HERE and get_attacker is not needed: modify_action_tiles_from_buffs builds
# its context from specific.unit.get_owner_unit_or_self() (:165), so a targeting relay has already
# been resolved to the real attacker before we see it. context.map is populated too, even though the
# caller never sets it - Context.create fills it from context.unit.map (context.gd:77-79).
#
# `action is ActionSystem and action.is_tech`, never a bare `action.is_tech`: is_tech is an export on
# ActionSystem alone (action_system.gd:11) and reading it off any other Action is a runtime error.
#
# THE TILES COME FROM draugr_reach.infected_in_reach, not from a second copy of the rule, so the
# crosshair and every "within SENSORS" test in this mod can never disagree.
#
# KNOWN, ACCEPTED: an ACTION_TILES grant is merged AFTER the mod's own Banshee range cap has policed
# (see res/engine/character/unit/service/unit_tile.gd_ext.gd:137-139). Nothing about the Draugr
# interacts with tears; the note is there so a future reader does not rediscover it as a bug.
extends Buff

const DraugrReach := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/draugr_reach.gd')

func is_buff_context_valid_for_passive(core:BuffCore, context:Context) -> bool:
	return context != null and context.map != null and Action.is_valid(context.action)

## Tech only. "When targeting" in the rules row is the tech crosshair; a weapon gains nothing.
func check_if_passive_applies(core:BuffCore, context:Context) -> bool:
	return (
		(context.action is ActionAttackTech) or
		(context.action is ActionSystem and context.action.is_tech)
	)

## A bitwise tile array in `object`, marked as ADDITIONAL with boolean = true.
func get_values(core:BuffCore, context:Context) -> Context:
	var tiles:Array[Vector2i] = []
	var draugr:Unit = context.unit
	if Unit.is_valid(draugr):
		for other:Unit in DraugrReach.infected_in_reach(draugr):
			tiles.append_array(other.occupied_tiles())
	return Context.create({
		object = Tile.to_bitwise_array(tiles),
		boolean = true, # add, do not intersect
	})

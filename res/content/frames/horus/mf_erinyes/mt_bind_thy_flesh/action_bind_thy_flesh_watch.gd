# Remembers where the Erinyes last aimed an area effect.
#
# Exists because a save event is missing the one thing the chain needs: an origin. It carries the
# action (so the pattern's shape and size are known) but no tiles and no link to the activation that
# forced it, so the save path could only offer a circle around whoever failed - which is why the
# placement area did not line up with the blast a player had just thrown.
#
# UNIT_ACTION fires at PRE from event_gear_activate, before the effect resolves, and its virtual
# event carries target_tiles. Recording the aim there lets the save path rebuild the true pattern
# with UnitTile.get_aoe_tiles_from_specific.
#
# Separate from action_bind_thy_flesh because a reaction has one trigger_timing, and that one needs
# POST to read resolved attacks and saves while this needs PRE to run before them.
extends ActionReaction

const AIM_TILE_KEY := 'bind_aim_tile'
const AIM_ROUND_KEY := 'bind_aim_round'

func get_required_triggering_context() -> Array[Context.PROP]:
	return [Context.PROP.unit, Context.PROP.action]

func triggers_on_event(unit:Unit, gear:GearCore, triggering_event:EventCore) -> bool:
	var triggering := triggering_event.context
	if triggering.unit != unit: return false
	if triggering.target_tiles.is_empty(): return false
	var range_pattern:RangePattern = triggering.action.get_range_pattern_for_targets(SpecificAction.from_context(triggering))
	if not is_instance_valid(range_pattern): return false
	return range_pattern.pattern != Lancer.AOE_TYPE.NONE

func activate(context:Context, activation:EventCore) -> void:
	var triggering := context.event.context
	context.gear.set_state_tile(AIM_TILE_KEY, triggering.target_tiles.front())
	context.gear.set_state(AIM_ROUND_KEY, context.map.game_core.round_count)

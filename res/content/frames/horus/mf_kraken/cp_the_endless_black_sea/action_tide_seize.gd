# The seize - anything that crashes into the Tide gets taken.
#
#   "If a character collides with you, you may expend your |OVERWATCH| to attempt to |Grapple| the
#    character as a |reaction|."
#
# event_unit_collide (content/events/event_unit_collide.gd) carries the moving unit, the TILE it
# collided with, and the move event that caused it - it does NOT carry the unit that was collided
# with. So this asks whether the collided tile is one of ours rather than looking for ourselves in a
# context property.
#
# Collisions on this trigger are forced-movement stops, per ReactionBus.TRIGGER.COLLISION's own
# comment, which is what "collides with you" means rather than any adjacency.
#
# "Expend your OVERWATCH" is the reaction point: Overwatch is itself a reaction in this engine, so
# consumes_rxn = true is the faithful cost. Irrepressible is what keeps this usable while the Kraken
# is itself GRAPPLED, which under the Tide it usually is.
#
# The grapple routes through the unit's own action_grapple via CommonActionUtil.choose_and_use rather
# than being reimplemented - the same route Drag To The Depths' Grapple takes - so it is a genuine
# contested roll and inherits the katamari filter and jam immunity for free.
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-02-kraken-design.md
extends ActionReaction

const TIDE_BUFF_ID := &'buff_the_all_consuming_tide'
const GRAPPLE_KIT := &'mw_grapple'
const GRAPPLE_ACTION := &'action_grapple'

func get_required_triggering_context() -> Array[Context.PROP]:
	return [Context.PROP.unit, Context.PROP.target_tiles]

func triggers_on_event(unit:Unit, gear:GearCore, triggering_event:EventCore) -> bool:
	if not UnitCondition.has_buff(unit, TIDE_BUFF_ID): return false
	if not collided_with_us(unit, triggering_event): return false
	var mover:Unit = triggering_event.context.unit
	if not UnitRelation.can_affect(unit, mover): return false
	return SpecificAction.is_valid(grapple_for(unit))

## Did this collision happen against one of our own tiles?
func collided_with_us(unit:Unit, triggering_event:EventCore) -> bool:
	var mover:Unit = triggering_event.context.unit
	if not Unit.is_valid(mover) or mover == unit: return false
	if not mover.is_actor(): return false
	var collided_tiles:Array[Vector2i] = triggering_event.context.target_tiles
	var ours := unit.occupied_tiles()
	return collided_tiles.any(func(tile:Vector2i) -> bool: return ours.has(tile))

func grapple_for(unit:Unit) -> SpecificAction:
	if not Unit.is_valid(unit): return null
	return SpecificAction.from_id(unit, GRAPPLE_KIT, GRAPPLE_ACTION)

func activate(context:Context, activation:EventCore) -> void:
	var kraken:Unit = context.unit
	var mover:Unit = context.event.context.unit
	var grapple := grapple_for(kraken)
	if activation.abort_when(not SpecificAction.is_valid(grapple)): return
	if activation.abort_without_units([kraken, mover]): return

	await CommonActionUtil.choose_and_use(
		activation,
		SpecificAction.from_context(context),
		[grapple],
		CommonActionUtil.choose_and_use_spend_action,
		mover,
	)

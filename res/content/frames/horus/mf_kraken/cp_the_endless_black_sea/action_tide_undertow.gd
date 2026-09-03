# The undertow - the Tide drags at whoever tries to begin a turn inside it.
#
#   "Characters of your choice are pulled 1 space toward you at the beginning of their turn."
#
# Scoped to hostiles within SENSORS. The clause names no range, but the sentence immediately after it
# establishes SENSORS as the Tide's zone, so an unbounded map-wide drag reads as the wrong inference.
#
# Prompted per character rather than configured once at activation, matching My Domain, and for the
# same reason: each pull changes the board, so it is a per-target judgement. A future pass may
# replace the per-character yes/no with one three-way choice per round - pull everything, pick which,
# or nothing - which would touch this file and nothing else. See the design doc.
#
# No save. Drag To The Depths' Pull grants a HULL save because its rules text says so; this clause
# does not.
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-02-kraken-design.md
extends ActionReaction

const TIDE_BUFF_ID := &'buff_the_all_consuming_tide'
const PULL_DISTANCE:int = 1

func get_required_triggering_context() -> Array[Context.PROP]:
	return [Context.PROP.unit]

func triggers_on_event(unit:Unit, gear:GearCore, triggering_event:EventCore) -> bool:
	if not UnitCondition.has_buff(unit, TIDE_BUFF_ID): return false
	return hostiles_caught(unit, triggering_event.context.unit)

## Is this somebody the Tide has a grip on? A hostile character, not the Kraken itself, standing
## within the Kraken's sensors and far enough out that a pull would move it at all.
func hostiles_caught(unit:Unit, starting_unit:Unit) -> bool:
	if not Unit.is_valid(starting_unit) or starting_unit == unit: return false
	if not starting_unit.is_actor(): return false
	if Faction.is_ally(unit.state.faction, starting_unit.state.faction): return false
	if not UnitRelation.can_affect(unit, starting_unit): return false

	var distance := UnitRelation.distance_between(unit, starting_unit)
	# Already up against us, so there is nowhere closer to go: generate_pull_events finds no path and
	# moves nobody (common_action_util.gd:159-187). This is the immunity check's argument above applied
	# to the far commoner case - under the Tide every prisoner the Kraken holds at close range is one
	# of these, and without this the player is asked "drag it deeper?" every round forever and yes does
	# nothing.
	#
	# Footprint distance, the same measure the sensor check uses - deliberately NOT
	# UnitRelation.is_adjacent, which this mod widens so a character grappled at range counts as
	# adjacent (unit_relation.gd_ext.gd). A prisoner held three spaces away by My Domain is exactly the
	# one the undertow SHOULD still be dragging.
	if distance <= PULL_DISTANCE: return false

	return distance <= unit.get_sensor_range()

func activate(context:Context, activation:EventCore) -> void:
	var kraken:Unit = context.unit
	var prey:Unit = context.event.context.unit
	if activation.abort_when(not hostiles_caught(kraken, prey)): return

	var movement_type := MovementType.create_for_involuntary(prey)
	movement_type.must_move_max_possible = true

	# Same gate action_drag_pull.gd applies before its own generate_pull_events call, and for the same
	# reason: that helper performs no immunity check of its own (unlike generate_knockback_events), and
	# event_unit_move.gd exempts the primary mover, so nothing downstream would catch this either. Both
	# pulls share the mechanism; a knockback-immune character should be immune to both.
	#
	# Checked here, before confirm() rather than after: this reaction prompts once per hostile turn,
	# and that friction is already the ability's main cost. An immune character can never be moved by
	# it, so asking anyway would announce the reaction, take the "yes", and then pull nothing - a
	# wasted question with no possible outcome. action_drag_pull.gd never prompts at all, so it had no
	# equivalent ordering to get wrong; putting the check in can_target_unit there is this same rule
	# applied to its own shape.
	if activation.abort_when(UnitCondition.is_immune_to_knockback_from(
		prey, SpecificAction.from_context(context), movement_type)): return

	if activation.abort_when(not await confirm(kraken, prey)): return
	if activation.abort_without_units([kraken, prey]): return

	var pull_events := await CommonActionUtil.generate_pull_events(
		prey, kraken.occupied_tiles(), SpecificAction.from_context(context),
		movement_type, true, PULL_DISTANCE,
	)
	if activation.abort_without_unit(kraken): return

	activation.queue_events(pull_events)

## "Characters of your choice", asked per character. Lifted from mt_my_domain's confirm(), which is
## the working version of this exact prompt on this exact frame - same camera call, same bus call,
## same reason for String.format over %.
func confirm(kraken:Unit, prey:Unit) -> bool:
	if not kraken.is_player_controlled(): return true # the AI always takes it

	# No zoom reset and no rotation: this runs once per character per round, and re-framing the board
	# between each question would be worse than not moving at all.
	camera_bus.focus_on_unit(prey, false, false)

	# String.format rather than %, so an unwritten localization row degrades to the raw key instead
	# of erroring on a format specifier that is not there.
	return await choice_bus.quick_yesno(
		prey.tile(),
		tr('gear.cp_the_endless_black_sea.action_tide_undertow.name'),
		tr('gear.cp_the_endless_black_sea.action_tide_undertow.prompt').format(
			{name = prey.core.get_pilot_or_mech_name()}
		),
	)

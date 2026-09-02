# The trigger half of Bind Thy Flesh.
#
#   "When the Erinyes creates an area pattern (such as a LINE or BURST), and a character is hit by
#    or fails a save against the effect, the Erinyes may create a Chain on an object within the
#    area."
#
# Reacts to the Erinyes' OWN attack, which is what mt_skirmisher (Nelson) does - triggers_on
# attack_declared with consumes_rxn = false. The triggering event carries a DeclaredAttackSummary on
# context.resource, which is where both halves of the condition come from: all_attacked_tiles is the
# real area pattern (targeted tiles plus everything caught in the blast), and attack_rolls says who
# was hit.
#
# We never need to de-duplicate against a second trigger. buff_bind_thy_flesh leaves
# multiple_copies_can_stack at false, so the engine clears an older copy before applying a new one
# (unit_condition.gd:721) - and characters already chained are skipped below, so the first chain's
# leash is the one that sticks rather than being silently re-measured.
extends ActionReaction

const ANCHOR_FRAME_ID := &'dep_chain_erinyes'
const CHAIN_BUFF_ID := &'buff_bind_thy_flesh'

func get_required_triggering_context() -> Array[Context.PROP]:
	return [Context.PROP.unit, Context.PROP.action, Context.PROP.resource]

func triggers_on_event(unit:Unit, gear:GearCore, triggering_event:EventCore) -> bool:
	var triggering := triggering_event.context
	if triggering.unit.get_attacker(triggering) != unit: return false # only our own attacks
	if not is_area_pattern(triggering): return false
	return not characters_to_chain(triggering).is_empty()

## "creates an area pattern" - read off the action's own targeting rather than guessed from how many
## tiles happened to be caught, so a single-target shot at a big mech never counts.
func is_area_pattern(triggering:Context) -> bool:
	var summary:DeclaredAttackSummary = triggering.resource
	if not DeclaredAttackSummary.is_valid(summary): return false
	var range_pattern:RangePattern = triggering.action.get_range_pattern_for_targets(SpecificAction.from_context(triggering))
	if not is_instance_valid(range_pattern): return false
	return range_pattern.pattern != Lancer.AOE_TYPE.NONE

## Everyone the pattern caught who is not already chained.
func characters_to_chain(triggering:Context) -> Array[Unit]:
	var chaining:Array[Unit] = []
	var summary:DeclaredAttackSummary = triggering.resource
	if not DeclaredAttackSummary.is_valid(summary): return chaining

	for attack_roll:AttackRoll in summary.attack_rolls:
		if not AttackRoll.is_valid(attack_roll): continue
		if not attack_roll.hit: continue
		var hit_unit:Unit = attack_roll.target_unit
		if not Unit.is_valid(hit_unit) or not hit_unit.is_actor(): continue # characters, not scenery
		if UnitCondition.has_buff(hit_unit, CHAIN_BUFF_ID): continue # already chained; first chain wins
		if chaining.has(hit_unit): continue
		chaining.append(hit_unit)
	return chaining

## The anchor goes at the middle of the pattern, since every character caught chains to the same
## point. Snapped to a tile the pattern actually covered rather than a bare average, which for a
## CONE or LINE can land outside it.
func anchor_tile_for(summary:DeclaredAttackSummary) -> Vector2i:
	var tiles := summary.all_attacked_tiles
	if tiles.is_empty(): return Tile.INVALID

	var total := Vector2i.ZERO
	for tile:Vector2i in tiles: total += tile
	var average := Vector2(total) / float(tiles.size())

	var closest:Vector2i = tiles.front()
	var closest_distance:float = Vector2(closest).distance_to(average)
	for tile:Vector2i in tiles:
		var distance:float = Vector2(tile).distance_to(average)
		if distance < closest_distance:
			closest = tile
			closest_distance = distance
	return closest

func activate(context:Context, activation:EventCore) -> void:
	var erinyes:Unit = context.unit
	var triggering := context.event.context
	var summary:DeclaredAttackSummary = triggering.resource
	var chaining := characters_to_chain(triggering)
	if activation.abort_when(chaining.is_empty()): return

	var anchor_tile := anchor_tile_for(summary)
	if activation.abort_when(anchor_tile == Tile.INVALID): return

	# "may" - one prompt for the whole pattern, not one per character caught.
	var confirmed:bool = await CommonActionUtil.confirm_use(context, chaining, summary.all_attacked_tiles)
	if activation.abort_when(not confirmed): return

	spend_actions(activation)

	var anchor_core := UnitCore.create(erinyes.get_faction(), ContentLibrary.get_mech_frame(ANCHOR_FRAME_ID))
	var anchor := Unit.create(anchor_core)
	UnitAction.set_deployable_owner(anchor, erinyes, context.gear)
	activation.queue_event(&'event_unit_spawn', {
		unit = anchor,
		target_tile = anchor_tile,
		flags = [EventUnitSpawn.FLAG.SKIP_ANIMATION],
	})

	# The anchor spawns from a queued event, so it is not on the map yet - hence binding by id and a
	# leash measured from the tile it is about to occupy, rather than from the unit.
	var chain_buff:Buff = ContentLibrary.get_buff(CHAIN_BUFF_ID)
	for chained_unit:Unit in chaining:
		var buff_core := UnitCondition.apply_buff(activation, chained_unit, chain_buff, context.gear)
		chain_buff.bind_to_tile(buff_core, anchor_core.persistent_id, anchor_tile, chained_unit)

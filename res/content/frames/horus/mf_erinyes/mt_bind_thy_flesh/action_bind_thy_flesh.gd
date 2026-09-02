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

const SAVE_EVENT := &'event_unit_save'
const ACTIVATION_EVENT := &'event_gear_activate'

## Remembers a "no" so that declining does not re-ask for every other character the blast caught.
## Keyed by round and place because a save event cannot identify the activation it came from.
const DECLINED_ROUND_KEY := 'bind_declined_round'
const DECLINED_TILE_KEY := 'bind_declined_tile'

func get_required_triggering_context() -> Array[Context.PROP]:
	return [Context.PROP.unit]

func triggers_on_event(unit:Unit, gear:GearCore, triggering_event:EventCore) -> bool:
	if triggering_event.base.event_type == SAVE_EVENT:
		return triggers_on_failed_save(unit, gear, triggering_event)
	return triggers_on_attack(unit, triggering_event)

func triggers_on_attack(unit:Unit, triggering_event:EventCore) -> bool:
	var triggering := triggering_event.context
	if not triggering.is_property_present(Context.PROP.resource): return false
	if triggering.unit.get_attacker(triggering) != unit: return false # only our own attacks
	if not is_area_pattern(triggering): return false
	return not characters_to_chain(triggering).is_empty()

## The other half of the condition: "or fails a save against the effect". Grenades and other area
## systems never make an attack roll at all - a frag grenade is an ActionSystemGrenade that damages
## through queue_damage_events_with_save_for_half - so attack_declared never fires for them and this
## is the only path that catches them. One save event is fired per character, hence the grouping by
## activation below.
func triggers_on_failed_save(unit:Unit, gear:GearCore, triggering_event:EventCore) -> bool:
	var triggering := triggering_event.context
	if not Unit.is_valid(triggering.unit): return false
	if triggering.unit.get_attacker(triggering) != unit: return false # we forced the save
	if triggering.boolean: return false # they passed it

	var saving_unit:Unit = triggering.target_unit
	if not Unit.is_valid(saving_unit) or not saving_unit.is_actor(): return false
	if UnitCondition.has_buff(saving_unit, CHAIN_BUFF_ID): return false
	if not is_area_pattern(triggering): return false
	return not declined_here(gear, triggering, saving_unit, area_radius(triggering))

## A save event carries no link to the activation that forced it - context.event is null, unlike an
## attack event which passes `event = core` down explicitly. So saves from one grenade cannot be
## grouped by activation id, and the pattern's tiles are not reachable either. Instead the first
## character to fail drops the anchor at its own feet, and everyone else the same effect catches
## finds that anchor already standing within the blast radius and binds to it.
func nearby_anchor_of_ours(context:Context, near_unit:Unit, radius:int) -> Unit:
	for check_unit:Unit in context.map.get_all_units():
		if not Frame.is_valid(check_unit.core.frame): continue
		if check_unit.core.frame.compcon_id != ANCHOR_FRAME_ID: continue
		if check_unit.get_owner_unit() != context.unit: continue
		if Tile.distance(check_unit.tile(), near_unit.tile()) > radius: continue
		return check_unit
	return null

## The blast/burst size of the effect, used to decide which anchor belongs to it.
func area_radius(triggering:Context) -> int:
	var range_pattern := range_pattern_of(triggering)
	return range_pattern.value if is_instance_valid(range_pattern) else 0

## Did the player already say no for this effect? Remembered by round and place, since that is all a
## save event gives us to identify one effect by.
func declined_here(gear:GearCore, context:Context, near_unit:Unit, radius:int) -> bool:
	if gear.get_state(DECLINED_ROUND_KEY, -1) != context.map.game_core.round_count: return false
	var declined_tile := gear.get_state_tile(DECLINED_TILE_KEY)
	if declined_tile == Tile.INVALID: return false
	return Tile.distance(declined_tile, near_unit.tile()) <= radius

func remember_decline(gear:GearCore, context:Context, near_unit:Unit) -> void:
	gear.set_state(DECLINED_ROUND_KEY, context.map.game_core.round_count)
	gear.set_state_tile(DECLINED_TILE_KEY, near_unit.tile())

## "creates an area pattern" - read off the action's own targeting rather than guessed from how many
## tiles happened to be caught, so a single-target shot at a big mech never counts.
##
## Deliberately asks nothing but the action: this has to answer for a save event too, which carries
## no DeclaredAttackSummary. Requiring one here silently disabled the whole save path.
func is_area_pattern(triggering:Context) -> bool:
	var range_pattern := range_pattern_of(triggering)
	if not is_instance_valid(range_pattern): return false
	return range_pattern.pattern != Lancer.AOE_TYPE.NONE

func range_pattern_of(triggering:Context) -> RangePattern:
	if not triggering.is_property_present(Context.PROP.action): return null
	return triggering.action.get_range_pattern_for_targets(SpecificAction.from_context(triggering))

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
	var triggering_event:EventCore = context.event
	var triggering := triggering_event.context
	var is_save_path:bool = triggering_event.base.event_type == SAVE_EVENT

	var chaining:Array[Unit] = []
	var pattern_tiles:Array[Vector2i] = []
	var anchor_tile := Tile.INVALID
	var anchor:Unit = null

	if is_save_path:
		var saving_unit:Unit = triggering.target_unit
		chaining = [saving_unit] as Array[Unit]
		# Everyone one effect catches shares an anchor. With no way to identify the activation, the
		# anchor already standing within the blast radius IS the one this effect made a moment ago.
		anchor = nearby_anchor_of_ours(context, saving_unit, area_radius(triggering))
		anchor_tile = saving_unit.tile()
		pattern_tiles = [anchor_tile] as Array[Vector2i]
	else:
		var summary:DeclaredAttackSummary = triggering.resource
		chaining = characters_to_chain(triggering)
		anchor_tile = anchor_tile_for(summary)
		pattern_tiles = summary.all_attacked_tiles

	if activation.abort_when(chaining.is_empty()): return
	if activation.abort_when(anchor_tile == Tile.INVALID): return

	var anchor_id:StringName = anchor.core.persistent_id if Unit.is_valid(anchor) else &''
	if Unit.is_valid(anchor):
		anchor_tile = anchor.tile() # bind to where it actually stands
	else:
		# "may" - asked once per effect, not once per character caught.
		var confirmed:bool = await CommonActionUtil.confirm_use(context, chaining, pattern_tiles)
		if not confirmed:
			if is_save_path: remember_decline(context.gear, context, chaining.front())
			activation.abort()
			return

		spend_actions(activation)

		var anchor_core := UnitCore.create(erinyes.get_faction(), ContentLibrary.get_mech_frame(ANCHOR_FRAME_ID))
		var new_anchor := Unit.create(anchor_core)
		UnitAction.set_deployable_owner(new_anchor, erinyes, context.gear)
		activation.queue_event(&'event_unit_spawn', {
			unit = new_anchor,
			target_tile = anchor_tile,
			flags = [EventUnitSpawn.FLAG.SKIP_ANIMATION],
		})
		anchor_id = anchor_core.persistent_id

	# On the first pass the anchor spawns from a queued event and is not on the map yet - hence
	# binding by id and a leash measured from the tile it is about to occupy, not from the unit.
	var chain_buff:Buff = ContentLibrary.get_buff(CHAIN_BUFF_ID)
	for chained_unit:Unit in chaining:
		var buff_core := UnitCondition.apply_buff(activation, chained_unit, chain_buff, context.gear)
		chain_buff.bind_to_tile(buff_core, anchor_id, anchor_tile, chained_unit)

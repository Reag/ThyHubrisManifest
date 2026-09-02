# My Domain.
#
#   "The Kraken can |Grapple| characters at least partially within any |Bursts| centered on itself.
#    Characters grappled this way count as though they are |adjacent| and within |Range 1| of the
#    Kraken."
#
# "Centered on itself" needs no origin check: RangePattern.get_aoe_tiles builds a BURST from
# occupied_tiles[0] - the ACTING unit's own tiles - and ignores target_tiles entirely
# (range_pattern.gd:45). Only BLAST is placed on a point. So in this engine a burst is always
# centered on whoever used it, and "our burst" is the whole condition.
#
# Triggers on UNIT_ACTION rather than attack_declared/forced_save, which is what Bind Thy Flesh
# uses. A burst may be an attack, a save-forcing system, or neither, and only UNIT_ACTION catches
# all three. It can afford to: because a burst is derived entirely from the Kraken's position and
# the pattern's radius, the area is knowable without a DeclaredAttackSummary.
#
# The grapple is automatic - no attack roll. Everyone caught is already inside the effect; the burst
# itself was the cost.
extends ActionReaction

const TETHER_BUFF_ID := &'buff_my_domain_tether'

func get_required_triggering_context() -> Array[Context.PROP]:
	return [Context.PROP.unit, Context.PROP.action]

func triggers_on_event(unit:Unit, gear:GearCore, triggering_event:EventCore) -> bool:
	var triggering := triggering_event.context
	if not Unit.is_valid(triggering.unit): return false
	if triggering.unit != unit: return false # our own bursts only
	if not is_burst(triggering): return false
	return not characters_caught(unit, gear, triggering).is_empty()

## A BURST specifically, not any area pattern - the trait names it, and BLAST is explicitly excluded
## because a blast is placed on a point rather than centred on the Kraken.
func is_burst(triggering:Context) -> bool:
	var range_pattern := range_pattern_of(triggering)
	if not is_instance_valid(range_pattern): return false
	return range_pattern.pattern == Lancer.AOE_TYPE.BURST

func range_pattern_of(triggering:Context) -> RangePattern:
	if not triggering.is_property_present(Context.PROP.action): return null
	return triggering.action.get_range_pattern_for_targets(SpecificAction.from_context(triggering))

## The tiles the burst covered. target_tiles is passed through but a BURST ignores it, so this works
## for a self-centred system that was never aimed at anything.
func burst_tiles(triggering:Context) -> Array[Vector2i]:
	return UnitTile.get_aoe_tiles_from_specific(
		SpecificAction.from_context(triggering), triggering.target_tiles)

## Everyone the burst caught who can still be grabbed.
##
## Hostiles only. The rules text says "characters", but a single confirmation that also grabs your
## own side would be a trap: grappling applies GRAPPLED to the target too, costing an ally its
## reactions and its boost. Narrow it here rather than making the player decline per character.
func characters_caught(unit:Unit, gear:GearCore, triggering:Context) -> Array[Unit]:
	var caught:Array[Unit] = []
	var tiles := burst_tiles(triggering)
	if tiles.is_empty(): return caught

	var already_held := currently_held(unit)
	for other_unit:Unit in triggering.map.get_all_units():
		if not Unit.is_valid(other_unit) or not other_unit.is_actor(): continue
		if other_unit == unit: continue
		if Faction.is_ally(unit.state.faction, other_unit.state.faction): continue
		if already_held.has(other_unit): continue # already in the domain
		if other_unit.occupied_tiles().any(func(tile:Vector2i) -> bool: return tiles.has(tile)):
			caught.append(other_unit)
	return caught

## Who this Kraken is already holding, by any grapple - re-grabbing them would be a no-op that still
## re-applied the tether.
func currently_held(unit:Unit) -> Array[Unit]:
	var held:Array[Unit] = []
	for grapple:SpecificAction in UnitCondition.get_outgoing_grapples(unit):
		if Unit.is_valid(grapple.unit): held.append(grapple.unit)
	return held

func activate(context:Context, activation:EventCore) -> void:
	var kraken:Unit = context.unit
	var triggering := context.event.context
	var caught := characters_caught(kraken, context.gear, triggering)
	if activation.abort_when(caught.is_empty()): return

	if not await confirm(context, kraken, caught):
		activation.abort()
		return

	var tether:Buff = ContentLibrary.get_buff(TETHER_BUFF_ID)
	for target:Unit in caught:
		grapple(activation, context, kraken, target)
		if is_instance_valid(tether):
			var buff_core := UnitCondition.apply_buff(activation, target, tether, context.gear)
			tether.bind(buff_core, kraken)

	kraken.update_attached_fx()
	for target:Unit in caught: target.update_attached_fx()

## "can Grapple" is a may, so it is offered rather than applied. One prompt for the whole burst
## instead of one per character: the burst already chose who is caught, and a per-character walk
## would be several clicks for a free action.
func confirm(context:Context, kraken:Unit, caught:Array[Unit]) -> bool:
	if not kraken.is_player_controlled(): return true # the AI always takes it
	# String.format rather than %, so an unwritten localization row degrades to the raw key instead
	# of erroring on a format specifier that is not there.
	return await choice_bus.quick_yesno(
		kraken.tile(),
		tr('gear.mt_my_domain.name'),
		tr('gear.mt_my_domain.prompt').format({count = caught.size()}),
	)

## The grapple itself, matching what onhit_grapple.gd does for the basic Grapple weapon - the
## attachment first so the katamari knows about it, then the paired statuses, then a recalculation
## to settle who is larger and so who may drag whom.
func grapple(activation:EventCore, context:Context, kraken:Unit, target:Unit) -> void:
	Katamari.attach_units(activation, kraken, target, context.gear.persistent_id)
	Katamari.create(kraken).recalculate_largest_unit(kraken, activation, false)

	UnitCondition.apply_status(activation, kraken, Lancer.STATUS.GRAPPLED, Lancer.UNTIL.MANUAL, target.core.persistent_id)
	UnitCondition.apply_status(activation, target, Lancer.STATUS.GRAPPLED, Lancer.UNTIL.MANUAL, kraken.core.persistent_id)

	Katamari.create(kraken).recalculate_largest_unit(kraken, activation)

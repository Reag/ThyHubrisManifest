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
# "Grapple" is the real thing: one full contested attack per character, which can miss. Each routes
# to the Kraken's OWN action_grapple through CommonActionUtil.choose_and_use, the same way Drag To
# The Depths' grapple and the Tide's seize do. The burst is what earns the attempt, not the hold.
#
# THE REACH. action_grapple is melee, so its reach is threat range, which is 1; a burst is wider.
# buff_my_domain_reach carries the attack out to whoever the burst caught, on the pattern of the
# Blackbeard's buff_grapple_cable_threat - see that file's header for the mechanism. The difference
# is that the Blackbeard's is always on and this one is scoped to the activation: opened when the
# trait resolves, sized to the furthest character the burst actually caught, and closed again the
# moment the last question has been answered. An always-on reach would let the Kraken Grapple across
# a room as an ordinary Quick action, which the trait does not grant.
#
# THE HOLD IS MY DOMAIN'S, not the basic Grapple's - and this is load-bearing, not bookkeeping.
# Both halves of the trait's second sentence read the ATTACHMENT rather than the attack:
# UnitCondition.check_attachments_are_adjacent (unit_condition.gd:598) waives the adjacency
# requirement only for a unit holding an attachment from gear that declares
# ignores_adjacency_requirement, and this mod's unit_relation extension asks the same question of
# the grappling gear before counting a prisoner as adjacent. mw_grapple declares neither, so a
# grapple made through it across a burst is torn off again the instant it lands, and would never
# have counted as adjacent. Measured, not guessed: with the attachment left to mw_grapple alone the
# trait grappled nobody at all.
#
# So the domain holds it in two steps - buff_my_domain_grip keeps the attack's own attachment from
# being dropped while the trait is still resolving, and claim_the_hold then records the landed
# grapple against this trait, which is what "grappled this way" means and is what keeps it held once
# the grip comes off. Releasing is unaffected: action_grapple_release and action_grapple_break both
# iterate get_outgoing/incoming_grapples, which yield one entry per grappling gear, so every record
# of one hold is dropped together.
extends ActionReaction

const TETHER_BUFF_ID := &'buff_my_domain_tether'
const GRAPPLE_KIT := &'mw_grapple'
const GRAPPLE_ACTION := &'action_grapple'

## What is true of the Kraken only while the domain is closing: its Grapple carries out to whoever
## the burst caught, and nothing it takes slips out of its hands for standing too far off. Applied
## together and cleared together; see open_the_domain.
const DOMAIN_BUFF_IDS:Array[StringName] = [&'buff_my_domain_reach', &'buff_my_domain_grip']

func get_required_triggering_context() -> Array[Context.PROP]:
	return [Context.PROP.unit, Context.PROP.action]

func triggers_on_event(unit:Unit, gear:GearCore, triggering_event:EventCore) -> bool:
	var triggering := triggering_event.context
	if not Unit.is_valid(triggering.unit): return false
	if triggering.unit != unit: return false # our own bursts only
	if not is_burst(triggering): return false
	# Nothing to offer without a Grapple to make. Mirrors action_tide_seize, which asks the same
	# question for the same reason.
	if not SpecificAction.is_valid(grapple_for(unit)): return false
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

	# unit.map rather than triggering.map: a unit_action context is a virtual event and carries no
	# guarantee of the map property, and reading a missing one would fail the whole trigger silently.
	if not is_instance_valid(unit.map): return caught
	var already_held := currently_held(unit)
	for other_unit:Unit in unit.map.get_all_units():
		if not Unit.is_valid(other_unit) or not other_unit.is_actor(): continue
		if other_unit == unit: continue
		if Faction.is_ally(unit.state.faction, other_unit.state.faction): continue
		if already_held.has(other_unit): continue # already in the domain
		if other_unit.occupied_tiles().any(func(tile:Vector2i) -> bool: return tiles.has(tile)):
			caught.append(other_unit)
	return caught

## Who this Kraken is already holding, by any grapple - re-grabbing them would be a no-op that still
## re-applied the tether. Also how a landed grapple is told from a missed one; see take_hold.
func currently_held(unit:Unit) -> Array[Unit]:
	var held:Array[Unit] = []
	for outgoing:SpecificAction in UnitCondition.get_outgoing_grapples(unit):
		if Unit.is_valid(outgoing.unit): held.append(outgoing.unit)
	return held

## The Kraken's own basic Grapple, which every mech carries.
func grapple_for(unit:Unit) -> SpecificAction:
	if not Unit.is_valid(unit): return null
	return SpecificAction.from_id(unit, GRAPPLE_KIT, GRAPPLE_ACTION)

func activate(context:Context, activation:EventCore) -> void:
	var kraken:Unit = context.unit
	var triggering := context.event.context
	var caught := characters_caught(kraken, context.gear, triggering)
	if activation.abort_when(caught.is_empty()): return
	if activation.abort_when(not SpecificAction.is_valid(grapple_for(kraken))): return

	# open_the_domain and close_the_domain bracket the whole loop, and take_hold always returns
	# rather than returning early past this line - so a decline, a miss, an empty burst and a Kraken
	# that died somewhere in the middle all leave through the same close. A reach that outlived its
	# activation would be silent and would last the rest of the scene.
	open_the_domain(activation, context, kraken, reach_needed(kraken, caught))
	var taken := await take_hold(activation, context, kraken, caught)
	close_the_domain(activation, kraken)

	# Declining every one of them is declining the trait; nothing has been changed at this point.
	if activation.abort_when(taken.is_empty()): return

	kraken.update_attached_fx()
	for target:Unit in taken: target.update_attached_fx()

## Ask, attack, and keep whoever the attack actually caught.
##
## Asked one at a time, not once for the burst. Every extra character in the katamari raises the
## size it has to beat to stay held (Katamari.recalculate_largest_unit), so grabbing everyone
## available can be strictly worse than grabbing one - that is a per-target judgement and has to be
## a per-target question.
func take_hold(activation:EventCore, context:Context, kraken:Unit, caught:Array[Unit]) -> Array[Unit]:
	var tether:Buff = ContentLibrary.get_buff(TETHER_BUFF_ID)
	var taken:Array[Unit] = []
	for target:Unit in caught:
		if not Unit.is_valid(kraken): break # the sea closed over it partway through
		if not Unit.is_valid(target): continue
		if not await confirm(context, kraken, target): continue

		await grapple(activation, context, kraken, target)

		# choose_and_use's bool does NOT report a hit, whatever its comment says: it returns
		# SpecificAction.is_valid(chosen) (common_action_util.gd:737), and with a single option and a
		# player driving, that option is picked automatically - so it reads true for a clean miss and
		# for a cancelled activation alike. Ask the board who is actually held instead.
		if not currently_held(kraken).has(target): continue

		claim_the_hold(activation, context, kraken, target)
		if is_instance_valid(tether):
			var buff_core := UnitCondition.apply_buff(activation, target, tether, context.gear)
			tether.bind(buff_core, kraken)
		taken.append(target)
	return taken

## "can Grapple" is a may, offered per character.
##
## The camera goes to whoever is being asked about first. With several characters caught, a prompt
## naming one of them is not much use if the player cannot see which one it means - and the answer
## depends on where that character is standing.
func confirm(context:Context, kraken:Unit, target:Unit) -> bool:
	if not kraken.is_player_controlled(): return true # the AI always takes it

	# No zoom reset and no rotation: this runs once per character, and re-framing the board between
	# each question would be worse than not moving at all.
	camera_bus.focus_on_unit(target, false, false)

	# String.format rather than %, so an unwritten localization row degrades to the raw key instead
	# of erroring on a format specifier that is not there.
	return await choice_bus.quick_yesno(
		target.tile(),
		tr('gear.mt_my_domain.name'),
		tr('gear.mt_my_domain.prompt').format({name = target.core.get_pilot_or_mech_name()}),
	)

## The attack: the Kraken's own Grapple, aimed at one character, routed rather than reimplemented.
## A contested roll that can miss, with mw_grapple's own on-hit effect doing the attaching and the
## paired GRAPPLED statuses - which is exactly the code this trait used to keep a copy of.
##
## choose_and_use stamps Action.FLAG.AS_FREEBIE, so the attack costs nothing on its own, and
## choose_and_use_no_spend is what keeps the trait free too: the burst was the cost, and the trait
## can attack several times off one burst.
func grapple(activation:EventCore, context:Context, kraken:Unit, target:Unit) -> void:
	await CommonActionUtil.choose_and_use(
		activation,
		SpecificAction.from_context(context),
		[grapple_for(kraken)],
		CommonActionUtil.choose_and_use_no_spend,
		target,
	)

## Record a landed grapple as this trait's hold as well as the Grapple's - "grappled this way".
## Both halves of the trait's second sentence read the attachment source rather than the attack; see
## the file header for why holding it under mw_grapple alone would silently undo them.
func claim_the_hold(activation:EventCore, context:Context, kraken:Unit, target:Unit) -> void:
	Katamari.attach_units(activation, kraken, target, context.gear.persistent_id)

## How far this activation has to carry: the distance to the furthest character the burst caught.
##
## Not a constant, and deliberately not the burst's radius either - a large character is caught with
## any part of itself inside the burst, so the distance to it can be greater than the radius. Sizing
## it off who was actually caught grants exactly what the burst earned and nothing more.
func reach_needed(kraken:Unit, caught:Array[Unit]) -> int:
	var reach := 0
	for target:Unit in caught: reach = maxi(reach, UnitRelation.distance_between(kraken, target))
	return reach

## Open the domain: the reach, sized to this burst, and the grip that holds what the reach catches.
##
## The grip is buff_my_domain_grip, an ATTACH_AT_DISTANCE buff on the Blackbeard's
## buff_grapple_cable_at_distance pattern, and it is not optional. mw_grapple's own attachment
## passive does not ignore the adjacency requirement, so a grapple landed across a burst is torn off
## again by UnitCondition.check_attachments_are_adjacent before this action gets control back - the
## grapple reads as a clean miss and the trait silently does nothing. The grip holds it just long
## enough for claim_the_hold to record it as My Domain's, whose attachment DOES ignore adjacency and
## keeps it held from then on.
##
## While it is up, the Kraken's other attachments skip that adjacency check too. That is a real
## widening, and the reason this is closed on the very next line rather than left to an UNTIL.
func open_the_domain(activation:EventCore, context:Context, kraken:Unit, reach:int) -> void:
	for buff_id:StringName in DOMAIN_BUFF_IDS:
		var buff:Buff = ContentLibrary.get_buff(buff_id)
		if not is_instance_valid(buff): continue
		var buff_core := UnitCondition.apply_buff(activation, kraken, buff, context.gear)
		if buff.has_method(&'bind'): buff.bind(buff_core, reach)

## Deliberately not guarded on Unit.is_valid, which is false for a dead unit: a Kraken that died
## mid-activation still has to have these taken off it, in case anything brings it back.
## clear_buff_id is a no-op when the buff is not there, so the paranoid call costs nothing.
func close_the_domain(activation:EventCore, kraken:Unit) -> void:
	if not is_instance_valid(kraken) or kraken.state == null: return
	for buff_id:StringName in DOMAIN_BUFF_IDS:
		UnitCondition.clear_buff_id(activation, kraken, buff_id)

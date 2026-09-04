# Caustic Earth: the Nuckelavee's ground bites whoever stands in it.
#
#   "Characters who start their turn in or enter a space of |difficult terrain| created by the
#    Nuckelavee take |1 AP ENERGY|. Characters can take this damage 1/round. Characters who ignore
#    |difficult terrain| ignore this damage"
#
# NOT TerrainData.DANGEROUS_TERRAIN.ENERGY, which looks like an exact fit and is not one: it fires
# at turn END (event_turn_end.gd:81) for Lancer.DANGEROUS_TERRAIN_DAMAGE = 5, only on a FAILED
# engineering check, limited 1/TURN, and TerrainData.base_merge_in spreads it to every zone
# overlapping the voxel.
#
# We extend ActionReactionOnComingWithin for one thing only: its per-character 1/round bookkeeping
# (record_unit_affected_and_abort_if_already_affected, built on buff_track_affection). Its TARGETING
# is distance-based and wrong for us, so triggers_on_event is overridden wholesale - the base hard-
# returns false for the reaction's own owner at :49, and the designer's ruling is that the
# Nuckelavee DOES take its own damage.
#
# Consequence: triggers_on_coming_within_range, triggers_on_allies, triggers_on_enemies,
# triggers_regardless_of_elevation and trigger_blocked_by_skeleton_key are INERT on our .tres. So is
# the base class's own intangibility-status-matching gate (:66, "intangibility status must match") -
# dropped deliberately, since this effect is terrain-mediated rather than proximity-mediated, and an
# intangible Nuckelavee's terrain should not exist for intangible units either. With the core power up,
# get_caustic_tiles is never called at all, so the EXILED/INTANGIBLE guard that enforces this now lives
# at the top of is_victim_on_caustic_ground instead, and is repeated there for exactly that reason.
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-04-caustic-earth-design.md
extends ActionReactionOnComingWithin

## Bookkeeping, not an ability the pilot uses - keep it out of the trait's tooltip.
##
## Action.show_in_tooltip returns TRUE for any trait reaction whose KIT carries a trigger row
## (action.gd:343-344). mt_caustic_earth's trigger row is empty today, so this changes nothing right
## now - it stops one future localization row from silently advertising this reaction as a separate
## ability, which is exactly what happened to all four Poisoned Soil actions and had to be fixed
## after playtest. The kit's own name and effect text are unaffected; they do not come from here.
##
## Same move as vanilla's action_system_clear_buff.gd:21.
func show_in_tooltip(_kit:Kit) -> bool: return false

const DAMAGE:int = 1
## Hoisted to a constant so test_content_integrity.gd can pin it. See that test for why a
## behavioural assertion cannot distinguish ENERGY from KINETIC at 1 damage.
const DAMAGE_TYPE:Lancer.DAMAGE_TYPE = Lancer.DAMAGE_TYPE.ENERGY

const ClawingHands := preload('../cp_truth_in_filth/buff_the_desperate_clawing_hands.gd')

## Is the core power's protocol half awake on this frame?
##
## Delegates rather than re-asking: the buff id is declared once, on the buff script, and both
## consumers go through it - a rename of the .tres cannot leave a stale literal behind here.
func is_clawing_hands_active(nuckelavee:Unit) -> bool:
	return ClawingHands.is_active(nuckelavee)

# ============================== the seams ==============================
#
# The core power (The Desperate Clawing Hands Of The Dead) promises "Caustic Earth loses its 1/round
# limit for hostile characters and applies to all |difficult terrain|". Both halves now ship, and they
# are scoped DIFFERENTLY on purpose - see is_victim_on_caustic_ground and is_capped_for.
#
# The widening lands on SEAM 1b only - SEAM 1 (get_caustic_tiles) is unmodified and simply goes
# unconsulted while the power is up. The uncapping lands on neither: it has to touch BOTH places the
# limiter is enforced - the has_unit_already_been_affected gate in triggers_on_event, and the
# record_unit_affected_and_abort_if_already_affected call in activate. Those two are not redundant -
# see activate's own comment for why - so relaxing one and not the other would leave the limit in
# force, with no error. is_capped_for is the one predicate both consult.

## SEAM 1 - which tiles are caustic. Today: difficult terrain this unit's own gear projects.
##
## Names no specific trait, so Acid Spill's future patch is picked up for free the moment it carries
## a PassiveTerrainZone. The core power does not widen this method - it bypasses it entirely; see
## is_victim_on_caustic_ground's own branch for the map-wide question instead.
func get_caustic_tiles(nuckelavee:Unit) -> Array[Vector2i]:
	var tiles:Array[Vector2i] = []
	# MapState.add_dynamic_terrain_and_zones_from_unit (map_state.gd:423-425) returns BEFORE
	# collecting any terrain zone for an exiled or intangible owner, so that frame contributes no
	# terrain to the map. We call get_voxels_to_apply_terrain directly and bypass that guard, so it
	# has to be repeated here or the acid outlives the frame.
	#
	# EXILED is belt and braces - UnitAction.get_gear_unavailable_reason:138 already stops the
	# reaction dead - but it costs one comparison and keeps this method's answer true on its own
	# terms rather than true only because of a gate somewhere else. A DEAD Nuckelavee needs neither:
	# ReactionBus.trigger_occurred iterates map.get_all_units(), which no longer contains it.
	if nuckelavee.has_status(Lancer.STATUS.EXILED): return tiles
	if nuckelavee.has_status(Lancer.STATUS.INTANGIBLE): return tiles
	for gear:GearCore in nuckelavee.core.loadout.get_all_gear(false):
		for passive:PassiveTerrainZone in gear.kit.get_passives(PassiveTerrainZone):
			if not is_instance_valid(passive.terrain_data): continue
			if not passive.terrain_data.difficult_terrain: continue
			for voxel:Vector3i in passive.get_voxels_to_apply_terrain(gear, nuckelavee.core, nuckelavee.state):
				var tile := Tile.from_voxel(voxel)
				if not tiles.has(tile): tiles.append(tile)
	return tiles

## SEAM 1b - is this victim standing on caustic ground? Wraps get_caustic_tiles so the core power can
## widen the question without the trait having to enumerate anything.
##
##   "Caustic Earth ... applies to all |difficult terrain|"
##
## The widening is UNIVERSAL - allies and the Nuckelavee itself included. Only the 1/round uncapping
## below is hostile-only, and that asymmetry is the whole point of the core power: a dragged prisoner
## takes a hit per tile while your own team takes one.
##
## The map-wide branch is a per-tile predicate rather than an enumeration, so widening does not mean
## scanning the map on every step of every character.
##
## The EXILED/INTANGIBLE guard is repeated here because the widened branch never calls
## get_caustic_tiles - a frame that is not there still projects nothing, power or no power.
func is_victim_on_caustic_ground(nuckelavee:Unit, victim:Unit) -> bool:
	if nuckelavee.has_status(Lancer.STATUS.EXILED): return false
	if nuckelavee.has_status(Lancer.STATUS.INTANGIBLE): return false

	if is_clawing_hands_active(nuckelavee):
		for tile:Vector2i in victim.occupied_tiles():
			if ClawingHands.is_difficult_ground(nuckelavee.map, tile): return true
		return false

	var caustic:Array[Vector2i] = get_caustic_tiles(nuckelavee)
	if caustic.is_empty(): return false
	for tile:Vector2i in victim.occupied_tiles():
		if caustic.has(tile): return true
	return false

## Does the 1/round limit still bind for this victim?
##
##   "Caustic Earth loses its 1/round limit for hostile characters"
##
## Hostile-only, deliberately: allies and the Nuckelavee keep the cap, so crossing the widened ground
## costs the player's own team once per round rather than once per tile.
##
## Consulted in BOTH places the limiter is enforced - see the calls in triggers_on_event and activate.
## It cannot be collapsed into an override of has_unit_already_been_affected(gear, check_unit),
## because that signature carries no reference to the Nuckelavee and so cannot tell whether the power
## is up. Relaxing one place and not the other leaves the cap in force with no error.
func is_capped_for(nuckelavee:Unit, victim:Unit) -> bool:
	if not can_only_affect_a_unit_once_per_round: return false
	if is_clawing_hands_active(nuckelavee) and UnitRelation.are_enemies(nuckelavee, victim): return false
	return true

## SEAM 2 - who walks over it untouched.
##
## Character-level, by the designer's ruling: the clause reads as a property of the CHARACTER, so
## this asks the victim's own inherent MovementType and never the movement that brought them in.
## ignores_difficult_terrain() is `ignore_difficult or teleport or flying or not voluntary`, and
## MovementType.create sets voluntary = true, so in practice this is FLYING, INTANGIBLE
## (movement_type.gd:47), or a Buff.TO.MOVEMENT_TYPE with ignore_difficult - i.e. Bulwark Mods.
##
## Because the step's own MovementType is not consulted, knocking or pulling a character across the
## acid DOES hurt them. That is deliberate and is designed play, not a side effect.
func is_exempt(victim:Unit) -> bool:
	return MovementType.create(victim).ignores_difficult_terrain()

# ============================== the trigger ==============================

func triggers_on_event(unit:Unit, gear:GearCore, triggering_event:EventCore) -> bool:
	var victim:Unit = triggering_event.context.unit
	if not Unit.is_valid(victim): return false

	# The two halves of the clause, kept as live exports rather than implied by triggers_on, so the
	# .tres says which one is on. Copied from the base class's own split at :53-55.
	if triggering_event.base.event_type == &'event_unit_move' and not when_enter_within: return false
	if triggering_event.base.event_type == &'event_turn_start' and not when_start_turn_within: return false

	if triggers_only_on_characters and not victim.is_character(): return false

	# "Characters can take this damage 1/round." The base class stores this as a hidden
	# buff_track_affection on the VICTIM, stamped with our kit's compcon_id and expiring at
	# UNTIL.START_OF_TURN. once_per_round_is_specific_to_gear stays false, matching vanilla and the
	# text's unqualified "1/round" - two Nuckelavees' acid still bites a CAPPED character only once.
	# That cap is exactly what is_capped_for's hostile-only exception below lifts: with the core power
	# up, a hostile is bitten once per tile instead.
	if is_capped_for(unit, victim) and has_unit_already_been_affected(gear, victim): return false
	if is_exempt(victim): return false

	return is_victim_on_caustic_ground(unit, victim)

func activate(context:Context, activation:EventCore) -> void:
	var victim:Unit = activation.context.event.context.unit
	var specific := SpecificAction.from_context(context)

	# Stamps the victim and bails if someone else already did this round. Checked here as well as in
	# triggers_on_event because reactions are queued as a block and resolved later: two units can
	# both pass the gate before either activates.
	#
	# Only stamp the victim when the cap actually binds them. An uncapped hostile takes the damage
	# every tile, and recording it each time would apply a tracking buff nothing ever reads. Skipping
	# the stamp also skips the two revalidation checks record_unit_affected_and_abort_if_already_affected
	# folds in (action_reaction_on_coming_within.gd:98-100): GearCore.is_valid(gear) and
	# abort_without_unit(affected_unit). The event framework re-derives similar validity downstream
	# (event_block.gd:95,103 checks is_context_valid, and event_unit_damage requires a unit in its
	# context), so this is not unsafe - but this path fires once per tile and is therefore the one most
	# likely to resolve after the victim has died, so the unit-validity guard is reinstated here
	# explicitly rather than left entirely to the framework.
	if is_capped_for(context.unit, victim):
		if record_unit_affected_and_abort_if_already_affected(activation, victim): return
	elif activation.abort_without_unit(victim): return

	activation.queue_events([build_damage_event(specific, victim)] as Array[EventCore])

## The acid is TERRAIN, not an attacker, and the damage event has to say so.
##
## Built by hand rather than through CommonActionUtil.queue_damage_events, which always sets
## `target_unit = specific.unit` - "let the damage event know WHO has done this"
## (common_action_util.gd:96). event_unit_damage.gd:83 reads that back as `damaging_unit` and :192
## hands it to UnitBark.handle_damage, which fires friendly_fire_self + friendly_fire_target whenever
## the damager is an ALLY of the damaged unit (unit_bark.gd:76-80). Playtest 2026-09-04: an ally
## stepping into the trail set off the whole apology exchange, as though the Nuckelavee had shot it.
##
## Vanilla's own environmental damage omits the attribution for exactly this reason -
## event_map_dangerous.gd queues event_unit_damage with unit, number and category and nothing else.
## We follow it. No damager means no friendly-fire bark BY CONSTRUCTION, rather than by suppressing a
## symptom.
##
## It also, deliberately, means a DAMAGE-triggered reaction cannot retaliate against the Nuckelavee
## for acid damage, and the acid finishing an enemy earns no destroy_target bark. Both are right:
## there is nothing to shoot back at, and dangerous terrain behaves the same way.
##
## `gear` and `action` are kept - they feed the battle log and damage modifications, and neither
## reaches UnitBark. The one thing worth preserving from the helper is SELF_INFLICTED, which real
## gear keys on (buff_flash_aegis.gd:7, cb_armory_sculpted_chassis, action_weak_grunt.gd:20, and
## buff_resist_damage.gd:44's resist_self_inflicted), so it is re-added by hand.
func build_damage_event(specific:SpecificAction, victim:Unit) -> EventCore:
	var flags:Array = [EventService.DAMAGE_FLAG.AP]
	if victim == specific.unit: flags.append(EventService.DAMAGE_FLAG.SELF_INFLICTED)
	return EventCore.create(&'event_unit_damage', {
		unit = victim,
		number = DAMAGE,
		category = DAMAGE_TYPE,
		gear = specific.gear,
		action = specific.action,
		flags = flags,
	})

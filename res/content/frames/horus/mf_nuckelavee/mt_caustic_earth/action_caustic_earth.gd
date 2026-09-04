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
# triggers_regardless_of_elevation and trigger_blocked_by_skeleton_key are INERT on our .tres.
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-04-caustic-earth-design.md
extends ActionReactionOnComingWithin

const DAMAGE:int = 1
## Hoisted to a constant so test_content_integrity.gd can pin it. See that test for why a
## behavioural assertion cannot distinguish ENERGY from KINETIC at 1 damage.
const DAMAGE_TYPE:Lancer.DAMAGE_TYPE = Lancer.DAMAGE_TYPE.ENERGY

# ============================== the two seams ==============================
#
# The core power (The Desperate Clawing Hands Of The Dead) promises "Caustic Earth loses its 1/round
# limit for hostile characters and applies to all |difficult terrain|". That is a change to exactly
# these two methods and nothing else. Deliberately no flag and no state until it exists.

## SEAM 1 - which tiles are caustic. Today: difficult terrain this unit's own gear projects.
##
## Names no specific trait, so Acid Spill's future patch is picked up for free the moment it carries
## a PassiveTerrainZone. The core power widens this to "ask the map".
func get_caustic_tiles(nuckelavee:Unit) -> Array[Vector2i]:
	var tiles:Array[Vector2i] = []
	for gear:GearCore in nuckelavee.core.loadout.get_all_gear(false):
		for passive:PassiveTerrainZone in gear.kit.get_passives(PassiveTerrainZone):
			if not is_instance_valid(passive.terrain_data): continue
			if not passive.terrain_data.difficult_terrain: continue
			for voxel:Vector3i in passive.get_voxels_to_apply_terrain(gear, nuckelavee.core, nuckelavee.state):
				var tile := Tile.from_voxel(voxel)
				if not tiles.has(tile): tiles.append(tile)
	return tiles

## SEAM 2 - who walks over it untouched.
##
## Character-level, by the designer's ruling: the clause reads as a property of the CHARACTER, so
## this asks the victim's own inherent MovementType and never the movement that brought them in.
## ignores_difficult_terrain() is `ignore_difficult or teleport or flying or not voluntary`, and
## MovementType.create sets voluntary = true, so in practice this is FLYING, INTANGIBLE
## (movement_type.gd:53), or a Buff.TO.MOVEMENT_TYPE with ignore_difficult - i.e. Bulwark Mods.
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
	# text's unqualified "1/round" - two Nuckelavees' acid still bites a given character only once.
	if can_only_affect_a_unit_once_per_round and has_unit_already_been_affected(gear, victim): return false
	if is_exempt(victim): return false

	var caustic:Array[Vector2i] = get_caustic_tiles(unit)
	if caustic.is_empty(): return false
	for tile:Vector2i in victim.occupied_tiles():
		if caustic.has(tile): return true
	return false

func activate(context:Context, activation:EventCore) -> void:
	var victim:Unit = activation.context.event.context.unit
	var specific := SpecificAction.from_context(context)

	# Stamps the victim and bails if someone else already did this round. Checked here as well as in
	# triggers_on_event because reactions are queued as a block and resolved later: two units can
	# both pass the gate before either activates.
	if record_unit_affected_and_abort_if_already_affected(activation, victim): return

	CommonActionUtil.queue_damage_events(
		activation, specific, [victim],
		DAMAGE, DAMAGE_TYPE, [EventService.DAMAGE_FLAG.AP],
	)

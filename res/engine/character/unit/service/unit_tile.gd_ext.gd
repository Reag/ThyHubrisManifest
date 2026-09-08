# Clauses 4 and 5 - the geometry half of the tear window.
#
# TWO FUNCTIONS, NOT ONE. Probe 2 measured this: UnitTile.get_tiles_within reads a precalculated_los
# array when one is passed and otherwise falls back to is_tile_in_los, and which happens is decided
# by the CALLER. A direct targeting query never consults the sweep at all, while the nine producers
# in engine/ai/, gear_action/action.gd:275 and the ui/ tilepickers all go through it. Overriding
# only one leaves half the game seeing vanilla geometry.
#
# THE PAIR RULE. Both clauses require a tangibility MISMATCH - clause 4 is intangible viewer to
# tangible target, clause 5 the mirror - so routing is only ever offered towards units of the
# opposite tangibility to the viewer. An earlier version widened sight for everyone whenever any
# tear was open, which made every tear a free corner-peek for both teams; nothing in the rules text
# grants that. The gate lives in tear_routing.is_cross_tangible and is applied on both paths here.
#
# STRICT COLLINEARITY (2026-09-08). Both clauses say the line PASSES THROUGH a tear, so the tear has
# to be on the line between the pair - not merely visible to both of them. The bent-path reading that
# shipped first is To Bend Reality's rule, and conflating the two erased the difference between the
# frame's core power and its signature trait. The test lives in tear_routing._tears_on_the_line and
# reaches this file through routes_between and routes_within_range; nothing here decides it.
#
# Everything real lives in tear_routing.gd. This file is a shim on purpose - see that file's header.
#
# Note gavstarb-talents_1st_party also extends unit_tile.gd. Both install and both fire; ours calls
# super, so the composition holds.
extends "res://engine/character/unit/service/unit_tile.gd"

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')
const TearInvisibilityGrant := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_invisibility_grant.gd')

## The sweep. Adds the tiles held by cross-tangible units this viewer can reach through a tear.
static func get_tiles_in_los(unit:Unit, from_tile := Tile.INVALID, ignore_blinded := false) -> PackedInt64Array:
	var tiles := super.get_tiles_in_los(unit, from_tile, ignore_blinded)
	if not Unit.is_valid(unit) or not is_instance_valid(unit.map): return tiles
	# BLINDED is handled by super, which returns only adjacent tiles. Widening that through a tear
	# would let a blinded character see across the map. Checked BEFORE any other work so the blinded
	# path costs nothing.
	if unit.has_status(Lancer.STATUS.BLINDED) and not ignore_blinded: return tiles

	var viewer_tile:Vector2i = unit.tile() if from_tile == Tile.INVALID else from_tile
	# Vanilla measures line of sight from effective_height - floor plus the unit's own body - so the
	# viewer's leg must use it too. The cached sweep inside tear_routing is computed at raw terrain
	# elevation, which silently under-permits a viewer standing tall enough to see over a low wall.
	var from_height:int = UnitTile.effective_height(unit, true, viewer_tile)
	Tile.add_bitwise_array(tiles, TearRouting.tiles_visible_via_tears(unit.map, unit, viewer_tile, from_height))
	return tiles

## The point query, used by the fallback path inside get_tiles_within.
##
## `whos_asking` is the viewer's persistent id and is the only handle on the viewer here, so it has
## to be resolved back to a unit before the pair rule can be applied. When it is absent - some
## callers pass nothing - there is no viewer to compare tangibility against, so routing is declined
## rather than guessed at. Declining is the safe direction: it falls back to vanilla geometry.
static func is_tile_in_los(map:MapState, occupied_tiles:Array[Vector2i], from_height:int, target_tile:Vector2i, whos_asking:StringName = &'') -> bool:
	if super.is_tile_in_los(map, occupied_tiles, from_height, target_tile, whos_asking): return true
	if not is_instance_valid(map) or whos_asking == &'': return false

	var viewer:Unit = TearRouting.unit_with_persistent_id(map, whos_asking)
	if not Unit.is_valid(viewer): return false

	# A BEND PROXY IS NOT A WINDOW. To Bend Reality relays an attack through a proxy standing on a
	# tear, governed by the trait's own rule (same tangibility, combined range), not by the tear
	# window's. Without this, a bend proxy (always raw-tangible - it carries no status) reading as
	# cross-tangible against an INTANGIBLE target - the Calendula case this trait exists to permit -
	# would grant sight through ANY open tear, not just the one the player picked.
	# cross_tangible_units already takes this off the LOS sweep above (get_tiles_in_los) and the
	# range policing in get_tiles_within; this is the third seam, reachable directly via
	# tilepicker_compcon.gd:396's unprecalculated LOS query.
	if TearRouting.is_bend_proxy(viewer): return false

	# The pair rule, applied against whoever is actually standing on the target tile. An empty tile
	# has no one to be cross-tangible with, so it never routes - which is the point: a tear shows you
	# things on the other side, not the ground behind a wall.
	var qualifies := false
	for occupant:Unit in map.get_all_units_at_tile(target_tile):
		if TearRouting.is_cross_tangible(viewer, occupant):
			qualifies = true
			break
	if not qualifies: return false

	for occupied_tile:Vector2i in occupied_tiles:
		if TearRouting.routes_between(map, occupied_tile, target_tile, from_height): return true
	return false

## CLAUSE 7: "An attack cannot travel more than half its maximum range after passing through a tear."
##
## Widening sight cannot do this on its own. Range is a BOX around the shooter (unit_tile.gd:580-583),
## so a routed target beyond that box is never even considered however well it can be seen - and a
## routed target inside it is allowed at any post-tear distance, which clause 7 forbids. Both halves
## need fixing, and this is the only function that knows max_range.
##
## EVERY cross-tangible target is governed by it, whether or not vanilla sight happens to reach the
## tile. That is not a shortcut - it follows from the pair rule. A cross-tangible pair has NO
## ordinary interaction at all: can_affect refuses them outright unless a tear bridges them
## (unit_relation.gd:397). So if such an attack is legal, it is legal BECAUSE of a tear, and it is
## therefore "an attack that passes through a tear" even when the target stands in plain view.
##
## An earlier version skipped tiles vanilla sight already granted, reasoning that those attacks were
## not going through the tear. On an open map that is every tile, so clause 7 never applied and an
## over-range routed target stayed targetable. Same argument as clause 6's predicate, which had it
## right; this did not.
##
## Skipped entirely when the caller does not care about sight (`consider_line_of_sight` false), since
## routing is a line-of-sight concept - that caller wants raw reach.
##
## ------------------------------------------------------------------------------------------------
## RANGE-CAP COVERAGE - what clause 7 actually reaches, audited 2026-09-08. Read this before
## believing the cap is universal; it is not, and the gaps are known rather than suspected.
##
## COVERED, because every one of these paths ends up here with the weapon's own range in hand:
##   - ordinary weapon and tech targeting. UnitTargeting.get_tiles_in_range (unit_targeting.gd:33)
##     calls this with specific.action.get_target_range, and every crosshair the player sees is
##     filtered through it.
##   - OVERWATCH AND WEAPON REACTIONS, contrary to what the fix plan assumed. They do not stop at
##     "raw distance + can_see": UnitRelation.can_weapon_hit_target_as_rxn (unit_relation.gd:302-308)
##     also requires UnitTargeting.get_tiles_in_range(specific).has(closest_pair.to), which is this
##     function again. The raw-distance test is an additional filter, not the only one. Pinned by
##     test_tear_range.gd's reaction tests - if those go red, this paragraph is what became false.
##   - the AI's threat model, which reaches the same two functions.
##
## NOT COVERED. Each of these can put an attack through a tear with a post-tear leg longer than half
## its range, and nothing in this mod stops it:
##   - SEEKING and ARCING weapons, and anything else whose action returns requires_line_of_sight
##     false. That makes `consider_line_of_sight` false and this function returns super's answer
##     untouched. It CANNOT simply be policed anyway: the same false is passed by passive_aura.gd:90,
##     action_reaction_aura.gd:101, passive_dynamic_zone.gd:24 and common_action_util.gd:168, none of
##     which are attacks and none of which clause 7 governs - and the signature here carries a unit
##     and a number, with nothing to tell an aura from a seeking missile. Covering this needs a seam
##     that still holds the SpecificAction: UnitTargeting.get_tiles_in_range is that seam, but
##     unit_targeting.gd is an unproven script-extension target (see the dead-seams note in
##     CLAUDE.md's memory) and probing it was out of scope for this pass.
##   - UnitRelation.can_affect, and so everything filtered through it - AoE membership
##     (map_state.gd:320), the AI's score dictionary (ai_action_decider.gd:386), the crosshair list
##     (tilepicker_compcon.gd:379). can_affect has no weapon in scope at all; it answers a question
##     about a PAIR. See tear_bridges' own note in unit_relation.gd_ext.gd.
##   - an action with a `range_tiles_override` (unit_targeting.gd:21-27), which replaces this call
##     wholesale. No vanilla weapon in 1.3.3 pairs one with a normal range budget, but a mod could.
##   - a Buff.TO.ACTION_TILES buff granting extra tiles: modify_action_tiles_from_buffs
##     (unit_targeting.gd:164-181) merges them in AFTER this function has policed, so a granted tile
##     is never re-checked against the cap.
## ------------------------------------------------------------------------------------------------
static func get_tiles_within(
	unit:Unit,
	max_range:int,
	consider_line_of_sight:bool = true,
	consider_elevation:bool = true,
	from_tile := Tile.INVALID,
	precalculated_los:PackedInt64Array = []
) -> Array[Vector2i]:
	var tiles := super.get_tiles_within(unit, max_range, consider_line_of_sight, consider_elevation, from_tile, precalculated_los)
	if not consider_line_of_sight: return tiles
	if not Unit.is_valid(unit) or not is_instance_valid(unit.map): return tiles
	if unit.has_status(Lancer.STATUS.BLINDED): return tiles

	var map:MapState = unit.map
	if TearRouting.tear_tiles(map).is_empty(): return tiles # nothing to police or add

	var viewer_tile:Vector2i = unit.tile() if from_tile == Tile.INVALID else from_tile
	var from_height:int = UnitTile.effective_height(unit, true, viewer_tile)

	for other:Unit in TearRouting.cross_tangible_units(map, unit):
		for tile:Vector2i in other.occupied_tiles():
			var qualifies := TearRouting.routes_within_range(map, viewer_tile, tile, from_height, max_range)
			var present := tiles.has(tile)
			if qualifies and not present: tiles.append(tile)
			elif present and not qualifies: tiles.erase(tile)
	return tiles

## Cache invalidation AND clause 6's re-hand-out. Super is called unmodified and its result is
## untouched - this override adds work after it and changes nothing it did.
##
## tear_routing's visibility cache stores get_tiles_in_los_alt results, and those depend on
## map.elevation_with_units and map.does_dynamic_zone_block_sight - both of which move when units do.
## Invalidating only on tear open/close left a mech that parked between tear and target, or smoke
## laid across the line, being seen straight through for the rest of the mission.
##
## This is the engine's own "occupancy or statuses changed" callback, with 30 call sites covering
## moves, spawns and deaths, so it is the closest thing to a general invalidation signal available
## without touching the base game.
##
## STILL NOT COVERED, and worth knowing: a dynamic sight zone (smoke) created or expiring without a
## unit moving. Nothing routes through that path today, but a mod that lays smoke as a free action
## could stale the cache until the next unit moves.
##
## ------------------------------------------------------------------------------------------------
## SECOND JOB (2026-09-08): CLAUSE 6's RE-HAND-OUT.
##
## action_tear.gd hands the clause 6 predicate to every character on the map when a tear is placed,
## and that used to be the only time it happened - so a unit that arrived AFTERWARDS never carried
## it, and clause 6 silently did not exist for reinforcements, drones or anything deployed mid-scene.
##
## This is the engine's own "occupancy or statuses changed" callback and it already runs for exactly
## the events that matter (spawn, move, death), which is why the hook goes here rather than into a
## new reaction: there is nothing to install and nothing to keep in sync.
##
## The no-tear path must cost essentially nothing, because this runs constantly and in every mission
## in the game, Banshee or no Banshee. hand_out_if_any_tear_is_open leads with tear_tiles(map),
## which is a single cached scan of the unit list, and returns immediately when it is empty.
## ------------------------------------------------------------------------------------------------
static func update_tracking_and_statuses(map:MapState, event:EventCore = null) -> void:
	super.update_tracking_and_statuses(map, event)
	TearRouting.invalidate(map)
	TearInvisibilityGrant.hand_out_if_any_tear_is_open(map, event)

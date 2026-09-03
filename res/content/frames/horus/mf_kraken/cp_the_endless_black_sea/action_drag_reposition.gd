# Drag To The Depths: Reposition.
#
#   "While |IMMOBILIZED|, you may expend your base movement to: • Move a character you are grappling
#    3 spaces in any direction."
#
# AN AIMED THROW. The Kraken picks a prisoner and then a point to hurl it at; the character travels
# toward that point in a straight line, up to 3 spaces, on the same mechanics as knockback, and stops
# against the first thing that will not let it through - a wall, a bystander, or the Kraken itself.
# Hitting something is a COLLISION, which is what the Tide's seize listens for, so a throw is a real
# opening rather than a tidy relocation.
#
# This replaces an earlier reading, "any reachable tile within 3", which asked the player for a
# DESTINATION and pathed the prisoner around obstacles to reach it. That version could not collide by
# construction: it only ever offered tiles the prisoner could already stand on, so it never attempted
# to enter anything. Aiming costs the ability its old party trick - a prisoner can no longer be tucked
# neatly around a corner - and the user has taken that trade deliberately: a throw that cannot slam
# somebody into something is not a throw.
#
# "In any direction" is the aim point, unrestricted: any tile within 3 of the prisoner, occupied,
# walled or empty alike. Aiming at something solid is the entire point of aiming.
#
# MovementType.create_for_involuntary already sets ignore_rxns, ignore_engagement, ignore_difficult
# and jump_downhill, so the throw provokes nothing, ignores terrain, and can drop the target off a
# ledge for fall damage. All inherited from vanilla forced movement on purpose.
#
# "A character you are grappling" is the OUTGOING grapples specifically, not the katamari: the
# katamari also contains anyone holding US, and the Kraken cannot throw its own captor.
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-02-kraken-design.md
extends "res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_kraken/cp_the_endless_black_sea/action_drag_to_the_depths.gd"

const THROW_DISTANCE:int = 3

## The movement the throw actually performs. Shares every flag with Pull's (action_drag_pull.gd) and
## for the same reasons, which are worth restating because either flag alone is inert:
##
##   straight_line + must_move_max_possible are what make event_unit_move.gd:410-414 read a unit in
##   the way as something to CRASH INTO rather than a reason to stop quietly one space short. Without
##   them the throw ends on a silent break and nothing can react to it.
##
##   can_move_through_enemies is what lets the PLANNER draw the line into that unit's space at all.
##   pathfinder.gd:136 prices an occupied tile at INVALID_COST otherwise, so the generated path stops
##   before the obstruction and the move event never gets the chance to call it a collision. Vanilla's
##   nanobot whip puts the same flag on the same kind of pull (action_nanobot_whip.gd:11). It does not
##   let the prisoner pass THROUGH anybody: event_unit_move stops it at the first body regardless.
func movement_type_for(target_unit:Unit) -> MovementType:
	var movement_type := MovementType.create_for_involuntary(target_unit)
	movement_type.straight_line = true
	movement_type.must_move_max_possible = true
	movement_type.can_move_through_enemies = true
	return movement_type

## Is this somebody the Kraken has hold of? Outgoing grapples only - see the header.
func is_held_by(unit:Unit, potential_target:Unit) -> bool:
	if not Unit.is_valid(unit) or not Unit.is_valid(potential_target): return false
	for grapple:SpecificAction in UnitCondition.get_outgoing_grapples(unit):
		if grapple.unit == potential_target: return true
	return false

## Strip out anyone immune to the knockback this throw would deal - nothing downstream of the throw
## checks it, and event_unit_move.gd exempts the primary mover. The movement type mirrors the one the
## throw actually moves the target with, so the check matches the movement.
func can_target_unit(potential_target:Unit, specific:SpecificAction) -> bool:
	if not super.can_target_unit(potential_target, specific): return false
	if not is_held_by(specific.unit, potential_target): return false
	return not UnitCondition.is_immune_to_knockback_from(
		potential_target, specific, movement_type_for(potential_target))

## Holding nobody closes this option, the same way Pull stays gated on the Kraken's own state
## rather than on there being a legal target. Unlike Grapple's and Pull's map scans,
## get_outgoing_grapples is a cheap dictionary lookup, so there is no cost reason to leave it to
## can_target_unit alone - and vanilla gates the same case: action_drag_cables_demolisher_reel.gd
## refuses to activate when its attached unit is gone. (The Goliath's mag gauntlet gates on
## attachments too but the OTHER way round, refusing while it already holds someone - a different
## rule, not a second precedent for this one.) Without this gate a FREE action sits permanently lit
## and opens a dead-end targeting mode with nothing highlighted.
func is_available_to_activate(unit:Unit, gear:GearCore) -> bool:
	if not super(unit, gear): return false
	return not UnitCondition.get_outgoing_grapples(unit).is_empty()

# ============================== targeting ==============================
# Two picks: the prisoner, then the point to throw it at. The Mirage's metafold shove
# (content/frames/npc/npcc_mirage/metafold_shove/action_metafold_shove_mirage.gd) is the vanilla
# precedent for a multi-pick whose second pick means something different from its first.
#
# can_target_empty_tiles is what buys the aim point its freedom: with it set, get_tiles_targetable
# stops filtering down to tiles that hold a legal target (unit_targeting.gd:84-106), so a wall, the
# Kraken's own footprint and open ground are all equally aimable. Everything the first pick needs to
# stay honest is enforced by the tile set below instead.

func get_target_requirements(specific:SpecificAction) -> TargetRequirements:
	var reqs:TargetRequirements = (
		target_requirements_override.duplicate() if target_requirements_override
		else TargetRequirements.new()
	)
	reqs.count = 2
	reqs.can_target_empty_tiles = true
	# Both, not just the targetable set: the range highlight is drawn from get_tiles_in_range, and
	# left alone it would show the Kraken's sensor bubble while the clickable tiles sat around the
	# prisoner instead.
	reqs.range_tiles_override = throw_tiles
	reqs.targetable_tiles_override = throw_tiles
	return reqs

## First pick: the prisoners. Second: everywhere the chosen prisoner can be thrown at.
func throw_tiles(
	specific:SpecificAction,
	picks_so_far:Array[TargetingPick] = [],
	_from_tile := Tile.INVALID,
	_precalculated_los:PackedInt64Array = []
) -> Array[Vector2i]:
	var tiles:Array[Vector2i] = []

	if picks_so_far.is_empty():
		for grapple:SpecificAction in UnitCondition.get_outgoing_grapples(specific.unit):
			if not Unit.is_valid(grapple.unit): continue
			if not can_target_unit(grapple.unit, specific): continue
			Util.append_array_nonduplicate(tiles, grapple.unit.occupied_tiles())
		return tiles

	var prisoner := prisoner_at(specific.unit, TargetingPick.collect_tiles(picks_so_far)[0], specific)
	if not Unit.is_valid(prisoner): return tiles
	# Neither line of sight nor elevation: a throw is aimed, not shot, and the aim point is allowed to
	# be somewhere the prisoner could never walk. Its own tiles are excluded because aiming a throw at
	# where the prisoner already stands is a throw of nothing.
	tiles = UnitTile.get_tiles_within(prisoner, THROW_DISTANCE, false, false)
	var standing_on := prisoner.occupied_tiles()
	Util.filter(tiles, func(tile:Vector2i) -> bool: return not standing_on.has(tile))
	return tiles

## Which prisoner is standing on this tile? Only ever consulted for a tile the pick offered, so a
## miss means the board changed underneath the choice.
func prisoner_at(unit:Unit, tile:Vector2i, specific:SpecificAction) -> Unit:
	for grapple:SpecificAction in UnitCondition.get_outgoing_grapples(unit):
		if not Unit.is_valid(grapple.unit): continue
		if not can_target_unit(grapple.unit, specific): continue
		if grapple.unit.occupied_tiles().has(tile): return grapple.unit
	return null

# ============================== the throw ==============================

func activate(context:Context, activation:EventCore) -> void:
	var kraken:Unit = context.unit
	var specific := SpecificAction.from_context(context)

	# No move-before-targeting: the Kraken is IMMOBILIZED and has to still hold its whole allowance to
	# be here at all, so there is no movement to offer and nothing to re-validate afterwards.
	var plan:CompconPlan = await TargetActionUtil.ask_for_targets(activation, false)
	if activation.abort_when(not CompconPlan.is_valid_with_targets(plan, context)): return

	var prisoner := prisoner_thrown(kraken, plan, specific)
	var aim_tile:Vector2i = plan.target_tiles.back() if not plan.target_tiles.is_empty() else Tile.INVALID
	if activation.abort_when(not Unit.is_valid(prisoner)): return
	if activation.abort_when(not Tile.is_valid(aim_tile, kraken.map)): return
	if activation.abort_when(prisoner.occupied_tiles().has(aim_tile)): return

	spend_actions(activation)
	await run_system_fxgs(kraken, [prisoner])
	if activation.abort_without_units([kraken, prisoner]): return

	# generate_pull_events is the engine's own "travel toward a tile in a straight line, up to N, and
	# stop where you are stopped" - the same helper Pull uses, aimed at a chosen point rather than at
	# the Kraken. force_to_land is false: a thrown flier stays in the air, as it did before.
	var throw_events := await CommonActionUtil.generate_pull_events(
		prisoner,
		[aim_tile] as Array[Vector2i],
		specific,
		movement_type_for(prisoner),
		false,
		THROW_DISTANCE,
		[EventUnitMove.FLAG.IGNORE_BEING_KNOCKED_OFF_COURSE],
	)
	if activation.abort_without_unit(kraken): return

	activation.queue_events(throw_events)

## Who is being thrown. The plan arrives in two shapes that mean the same thing: a player's picks are
## two bare tiles, because the tilepicker attaches no unit to a pick once empty tiles are targetable
## (tilepicker_compcon.gd:194), so the prisoner is whoever we hold at the first of them. A caller that
## already knows who it is throwing - the AI, a spec - names the unit outright and supplies the aim
## point alone.
func prisoner_thrown(unit:Unit, plan:CompconPlan, specific:SpecificAction) -> Unit:
	for target_unit:Unit in plan.target_units:
		if Unit.is_valid(target_unit) and is_held_by(unit, target_unit): return target_unit
	if plan.target_tiles.size() < 2: return null
	return prisoner_at(unit, plan.target_tiles[0], specific)

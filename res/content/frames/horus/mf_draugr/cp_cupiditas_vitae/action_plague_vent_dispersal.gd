# Plague-Vent Dispersal - the Draugr's core active.
#
#   "Flood a BLAST 2 centered within RANGE 2 with sickly fog until the end of your next turn.
#    Hostile characters in the area must make a SYSTEMS save, taking 2 INFECTION on a failure or 1
#    on a success."
#
# A stock ActionSystemDeploy for everything except the save loop: deploy_range = 2, one
# dep_plague_fog at the picked tile, the Blast 2 coming from the deployable's own PassiveTerrainZone
# rather than from deploy_to_every_aoe_space. That is precisely vanilla's smoke grenade
# (action_smoke_grenade.tres), and inheriting it means the targeting, the preview shrinkwrap, the
# AI's tile choice and the "supplied tiles skip the prompt" behaviour all come for free.
#
# THE SAVE LOOP WORKS FROM THE TILE, NOT FROM THE CLOUD. place_deployable QUEUES event_unit_spawn
# (action_system_deploy.gd:120-125) rather than awaiting it, so the fog does not exist yet when this
# function continues - asking "who is within 2 of the cloud" would find nothing. Tile.get_all_within
# (tile.gd:335-345) gives the same square neighbourhood the BLAST pattern will, from the tile we just
# placed at.
#
# super.activate() is not called: it would ask for targets a second time. The three lines it does -
# get_deploy_plan_targets, spend_actions, place_deployables_at_target_tiles - are reproduced here in
# the same order so the plan is validated and the core power is spent before anything else happens,
# and then the saves are appended.
extends ActionSystemDeploy

const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')
const PlagueFog := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/cp_cupiditas_vitae/plague_fog.gd')

const INFECTION_ON_FAIL := 2
const INFECTION_ON_PASS := 1

func activate(context:Context, activation:EventCore) -> void:
	var unit:Unit = context.unit

	var plan:CompconPlan = await get_deploy_plan_targets(context, activation)
	if activation.abort_when(not CompconPlan.is_valid_with_targets(plan, context)): return

	spend_actions(activation) # spends the core power (unit_action.gd:271) and records the usage
	await run_system_fxgs(unit, plan.target_tiles)
	if activation.abort_without_unit(unit): return

	var target_tiles:Array[Vector2i] = plan.target_tiles if not plan.target_tiles.is_empty() else unit.occupied_tiles()
	place_deployables_at_target_tiles(activation, target_tiles)

	await gas_the_area(context, activation, target_tiles)

## One SYSTEMS save per hostile character in the cloud, resolved before this activation ends so the
## Infection heat is attributed to the protocol rather than trailing after it.
##
## UnitHasecheck.make_save(event, unit, forcing_action, type, flags_and_statuses) is
## unit_hasecheck.gd:108-114; the SYS branch routes to make_systems_save (:42-45), which refuses
## non-characters outright and fires FORCED_SAVE through UnitCondition.forced_save. Infection.apply
## is async and must be awaited (infection.gd:52).
func gas_the_area(context:Context, activation:EventCore, target_tiles:Array[Vector2i]) -> void:
	var specific := SpecificAction.from_context(context)
	for victim:Unit in hostiles_in_the_cloud(context.unit, target_tiles):
		if activation.abort_if_level_exited(): return
		if not Unit.is_valid(victim) or not victim.is_on_map(): continue
		var passed:bool = await UnitHasecheck.make_save(activation, victim, specific, Lancer.HASE.SYS, [])
		if not Unit.is_valid(victim): continue
		await Infection.apply(activation, victim, INFECTION_ON_PASS if passed else INFECTION_ON_FAIL)

## "Hostile characters in the area". The area is every tile within PlagueFog.RADIUS of each target
## tile - the same square neighbourhood the deployable's BLAST 2 terrain zone will paint.
##
## map.get_all_units_at_tiles (map_state.gd:323-327) is used rather than
## UnitRelation.get_characters_within because the cloud does not exist yet (see the file header) and
## because it is the tile set, not a unit, that defines the area.
func hostiles_in_the_cloud(unit:Unit, target_tiles:Array[Vector2i]) -> Array[Unit]:
	var victims:Array[Unit] = []
	var map:MapState = unit.map
	if map == null: return victims
	var area:Array[Vector2i] = []
	for tile:Vector2i in target_tiles:
		for covered:Vector2i in Tile.get_all_within(tile, PlagueFog.RADIUS, map):
			if not area.has(covered): area.append(covered)
	for other:Unit in map.get_all_units_at_tiles(area, unit):
		if other == unit or not other.is_character(): continue
		if not UnitRelation.are_enemies(unit, other): continue
		if not victims.has(other): victims.append(other)
	return victims

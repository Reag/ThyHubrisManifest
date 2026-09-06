# TO BEND REALITY - the wrapper. Structurally mirrors content/gear/ipsn/systems/wm_throughbolt_rounds/
# action_throughbolt_line.gd: the variant callable REPLACES the pilot's weapon action with a
# duplicate of this one carrying the original as followup_attack, and this action then runs that
# original inside the same activation.
#
# THE FIRST PICK IS A TEAR, and it is an ordinary map click - TargetActionUtil.ask_for_targets runs
# the tilepicker, not a modal. Cancelling it yields an invalid CompconPlan that
# abort_without_targeting_plan turns into a clean abort, and because the pick happens before the real
# weapon is activated, nothing has been spent.
extends ActionAttackWeapon

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')

@export var followup_attack:ActionAttackWeapon

## The bend's budget is the wrapped weapon's own range. For a LINE weapon get_target_range returns
## range_pattern.value (action_attack_weapon.gd:202-203), so "the weapon's range" and "the line's
## normal length" are the same number and there is no second budget to keep in sync.
func get_target_range(specific:SpecificAction) -> int:
	if not Action.is_valid(followup_attack): return 0
	return followup_attack.get_target_range(specific)

## The tear pick. Overrides the TILE SET rather than filtering units, because tears are MARKERs and
## map_state.gd:314-318 excludes markers from get_all_units_at_tile unless include_markers is set -
## which the targeting path never does. A unit-based pick would highlight nothing, silently.
func get_target_requirements(specific:SpecificAction) -> TargetRequirements:
	var reqs := TargetRequirements.new()
	reqs.count = 1
	reqs.can_target_empty_tiles = true
	reqs.targetable_tiles_override = func(
		override_specific:SpecificAction,
		_picks_so_far:Array[TargetingPick] = [],
		_from_tile := Tile.INVALID,
		_precalculated_los:PackedInt64Array = []
	) -> Array[Vector2i]:
		return bendable_tear_tiles(override_specific)
	return reqs

## Every open tear this attack could bend through: in line of sight from the Banshee, and near enough
## that SOMETHING is still reachable past it. A tear exactly at the range limit leaves a zero-length
## second leg, which is legal but useless, so the bound is `<` rather than `<=`.
func bendable_tear_tiles(specific:SpecificAction) -> Array[Vector2i]:
	var offerable:Array[Vector2i] = []
	if not Unit.is_valid(specific.unit) or not is_instance_valid(specific.unit.map): return offerable
	var map:MapState = specific.unit.map
	var from_tile:Vector2i = specific.unit.tile()
	var from_height:int = UnitTile.effective_height(specific.unit, true, from_tile)
	var max_range:int = get_target_range(specific)
	for tear_tile:Vector2i in TearRouting.tear_tiles(map):
		if Tile.distance(from_tile, tear_tile) >= max_range: continue
		if not TearRouting.bends_within_range(map, from_tile, tear_tile, from_height, max_range): continue
		offerable.append(tear_tile)
	return offerable

func activate(context:Context, activation:EventCore) -> void:
	if activation.abort_when(not Action.is_valid(followup_attack)): return
	# Delegate with a context re-pointed at the FOLLOWUP, not the wrapper. SpecificAction.from_context
	# rebuilds specific.action straight from context.action, and that is what event_unit_attack_declared
	# and friends read damage_dice/aim_range/weapon_size/threat/tags from - not from `self`, even though
	# `self` (the object this activate() runs on) is already the followup. Handing the followup our own
	# (wrapper) context would run its targeting and damage resolution against the wrapper's unset
	# defaults instead of the real weapon. Mirrors action_throughbolt_line.gd's followup_context swap.
	var followup_context := Context.clone(context, { action = followup_attack })
	activation.context = followup_context
	await followup_attack.activate(followup_context, activation)

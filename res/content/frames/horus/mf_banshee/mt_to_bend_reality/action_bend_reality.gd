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
	var tear_tiles_fn := func(
		override_specific:SpecificAction,
		_picks_so_far:Array[TargetingPick] = [],
		_from_tile := Tile.INVALID,
		_precalculated_los:PackedInt64Array = []
	) -> Array[Vector2i]:
		return bendable_tear_tiles(override_specific)
	reqs.targetable_tiles_override = tear_tiles_fn
	# UnitTargeting.get_tiles_targetable (the clickable tiles) reads targetable_tiles_override above,
	# but UnitTargeting.get_tiles_in_range - the ground overlay tilepicker_compcon.gd:431 feeds to
	# show_range_bitwise, i.e. what the player actually SEES highlighted - reads range_tiles_override
	# instead. They are two independent fields read by two different callers. Leaving this one unset
	# meant the player saw the weapon's ordinary range highlighted during the tear pick, while only
	# the tear tiles actually responded to a click. Same callable as above so the two answers can
	# never drift apart.
	reqs.range_tiles_override = tear_tiles_fn
	return reqs

## Every open tear this attack could bend through: in line of sight from the Banshee, and near enough
## that SOMETHING is still reachable past it. A tear exactly at the range limit leaves a zero-length
## second leg, which is legal but useless, so the bound is `<` rather than `<=`.
##
## THE FIRST LEG MUST BE PLAIN SIGHT, NOT ROUTED. TearRouting.sees_between answers "can the Banshee
## plainly see this tile", asking nothing about other open tears. Using TearRouting.bends_within_range
## here instead - the earlier, buggy version of this function did, passing the candidate tear as both
## waypoint and destination - would let a SECOND open tear bridge sight to a candidate the Banshee
## cannot actually see (banshee -> other tear -> candidate), offering a tear that is not really
## visible. See sees_between's docstring for the full story. This also flattens what used to be a
## nested loop - bendable_tear_tiles over every tear, each calling bends_within_range which itself
## loops every tear again, up to 225 evaluations at MAX_TEARS - into one pass.
func bendable_tear_tiles(specific:SpecificAction) -> Array[Vector2i]:
	var offerable:Array[Vector2i] = []
	if not Unit.is_valid(specific.unit) or not is_instance_valid(specific.unit.map): return offerable
	var map:MapState = specific.unit.map
	var from_tile:Vector2i = specific.unit.tile()
	var from_height:int = UnitTile.effective_height(specific.unit, true, from_tile)
	var max_range:int = get_target_range(specific)
	for tear_tile:Vector2i in TearRouting.tear_tiles(map):
		# `>=` here, `>` on bends_within_range's combined-distance check - both correct, deliberately
		# different. There this is the SUM of two legs and a total exactly at max_range still leaves a
		# real (if zero-length-tolerant) second leg from the caller's chosen target. Here there is no
		# second leg yet - this candidate tile IS the tear, not a target beyond it - so a tear sitting
		# exactly at max_range would leave nothing for a follow-up target to reach, and is excluded.
		# Do not "fix" one bound to match the other; they answer different questions.
		if Tile.distance(from_tile, tear_tile) >= max_range: continue
		if not TearRouting.sees_between(map, from_tile, tear_tile, from_height): continue
		offerable.append(tear_tile)
	return offerable

const RELAY_BUFF_ID := &'buff_bend_relay'
const PROXY_KEY := 'proxy_id'

## THE RANGE BUDGET, extracted out of activate() so the arithmetic is directly testable. Nothing on
## the mocked-CompconPlan path a spec normally exercises ever re-derives or checks range (see
## test_to_bend_reality.gd's Gap 2 comment for why), so this needs its own tests rather than relying
## on damage landing as proof. The first leg is spent getting to the tear; whatever is left, clamped
## at zero, is what the weapon has past it for the followup to spend.
func remaining_range_after(specific:SpecificAction, tear_tile:Vector2i) -> int:
	var first_leg:int = Tile.distance(specific.unit.tile(), tear_tile)
	return maxi(get_target_range(specific) - first_leg, 0)

## THE LINE SPLIT, extracted out of activate() for the same reason as remaining_range_after above -
## nothing on the mocked-CompconPlan test path ever re-derives or checks a segment's actual length (see
## test_to_bend_reality.gd's Gap 2 comment), so a test asserting only on damage would pass even if this
## arithmetic were deleted or wrong. x is segment 1's length (Banshee -> tear, full damage); y is
## segment 2's length (tear -> wherever the second pick aims, half damage - remaining_range_after's
## whole contract, reused rather than recomputed so the two functions cannot drift apart). Barring
## remaining_range_after's own clamp at zero, x + y always equals the weapon's full line length, since y
## is defined as "whatever's left of the range budget after x is spent."
func line_segment_lengths(specific:SpecificAction, tear_tile:Vector2i) -> Vector2i:
	var first_leg:int = Tile.distance(specific.unit.tile(), tear_tile)
	var remaining:int = remaining_range_after(specific, tear_tile)
	return Vector2i(first_leg, remaining)

func activate(context:Context, activation:EventCore) -> void:
	if activation.abort_when(not Action.is_valid(followup_attack)): return
	var unit := context.unit

	# No compcon movement on top of all this - Throughbolt does the same at action_throughbolt_line.gd:36.
	context.object = null

	var plan:CompconPlan = await TargetActionUtil.ask_for_targets(activation)
	if activation.abort_without_targeting_plan(plan): return
	var tear_tile:Vector2i = plan.target_tiles[0]

	# ASSIGN a fresh RangePattern - never mutate the existing one. create_duplicate_for_variant is
	# duplicate_deep(DEEP_DUPLICATE_NONE), so subresources are SHARED with the pilot's real weapon and
	# mutating one permanently rewrites their actual gun. This gets reassigned a SECOND time below for a
	# LINE weapon - once per segment - and both assignments must stay assignments, never in-place mutation.
	var specific := SpecificAction.from_context(context)
	var segment_lengths:Vector2i = line_segment_lengths(specific, tear_tile)
	var first_leg:int = segment_lengths.x
	var remaining:int = segment_lengths.y
	var is_line:bool = followup_attack.range_pattern != null and followup_attack.range_pattern.pattern == Lancer.AOE_TYPE.LINE

	var proxy := TargetActionUtil.create_targeting_proxy(tear_tile, unit, 1, TearRouting.BEND_PROXY_FRAME_ID)
	var relay_buff:BuffCore

	if is_line:
		# A LINE weapon bends into two segments instead of one relocated shot: segment 1 from the
		# Banshee to the tear at full damage, segment 2 onward from the tear at half damage.
		#
		# SEGMENT 1 FIRES BEFORE THE RELAY BUFF EXISTS. get_attacker_relay (action_attack.gd:120-128) is
		# called at the very top of every ActionAttackWeapon.activate (action_attack.gd:233) and, the
		# moment it finds a SET_ATTACK_RELAY buff, CONSUMES it (UnitCondition.consume_buffs at :126) -
		# it is one-shot. Applying the relay buff before both activations, as the non-line path does,
		# would relay SEGMENT 1 (the wrong leg - it must originate from the Banshee, not the tear) and
		# leave segment 2 unrelayed. So the buff is applied AFTER segment 1 returns and BEFORE segment 2
		# starts, so only segment 2 ever sees it and consumes it.
		var pattern:Lancer.AOE_TYPE = followup_attack.range_pattern.pattern
		followup_attack.range_pattern = RangePattern.create(pattern, first_leg)
		var segment_one := Context.clone(context, {
			action = followup_attack,
			target_tiles = [tear_tile],
		})
		activation.context = segment_one
		await followup_attack.activate(segment_one, activation)

		relay_buff = UnitCondition.apply_buff_id(activation, unit, RELAY_BUFF_ID, context.gear)
		relay_buff.set_state(PROXY_KEY, proxy.core.persistent_id)

		# SEGMENT 2: from the proxy on the tear (relayed, above), the remaining length, HALF damage.
		# The player's second pick supplies this segment's direction/target. AS_FREEBIE keeps it from
		# charging a second action - the same flag action_attack_weapon.gd:64-79 uses for mounted
		# followups. first_leg + remaining == the line's normal length (remaining_range_after's contract).
		followup_attack.range_pattern = RangePattern.create(pattern, remaining)
		var segment_two := Context.clone(context, {
			action = followup_attack,
			flags = context.flags.duplicate() + [Action.FLAG.HALF_DAMAGE, Action.FLAG.AS_FREEBIE],
		})
		activation.context = segment_two
		await followup_attack.activate(segment_two, activation)
	else:
		if followup_attack.range_pattern:
			followup_attack.range_pattern = RangePattern.create(followup_attack.range_pattern.pattern, remaining)
		else:
			followup_attack.aim_range = remaining

		relay_buff = UnitCondition.apply_buff_id(activation, unit, RELAY_BUFF_ID, context.gear)
		relay_buff.set_state(PROXY_KEY, proxy.core.persistent_id)

		# Delegate with a context re-pointed at the FOLLOWUP, not the wrapper. SpecificAction.from_context
		# rebuilds specific.action straight from context.action, and that is what event_unit_attack_declared
		# and friends read damage_dice/aim_range/weapon_size/threat/tags from - not from `self`, even though
		# `self` (the object this activate() runs on) is already the followup. Handing the followup our own
		# (wrapper) context would run its targeting and damage resolution against the wrapper's unset
		# defaults instead of the real weapon. Mirrors action_throughbolt_line.gd's followup_context swap.
		var followup_context := Context.clone(context, { action = followup_attack })
		activation.context = followup_context
		await followup_attack.activate(followup_context, activation)

	if Unit.is_valid(unit) and BuffCore.is_valid(relay_buff): UnitCondition.clear_buffs(activation, unit, [relay_buff])
	if Unit.is_valid(proxy): proxy.remove_from_game()

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

## Every open tear this attack could bend through: in line of sight from the Banshee, and within the
## weapon's range - INCLUSIVE, matching the prose's "the combined distance must be within the
## weapon's range" and bends_within_range's own `>` boundary.
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
		# `>`, MATCHING bends_within_range's combined-distance check. This used to be `>=`, on the
		# reasoning that a tear exactly at max range leaves a zero-length second leg and so is a
		# useless pick. That reasoning was wrong on both counts. The prose permits it - "the combined
		# distance must be within the weapon's range", and a combined distance of exactly max_range
		# is within it, which is why bends_within_range has always used `>`. And it is not useless:
		# for a LINE weapon a tear at max range still makes segment 1 a full-length line attack, and
		# anything standing ON the tear takes segment 1 and segment 2 both (see the bend-tile
		# machinery in activate()). Keep this comparison and bends_within_range's identical.
		if Tile.distance(from_tile, tear_tile) > max_range: continue
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
## `first_leg` lets a caller that has already computed the distance (line_segment_lengths, below) hand
## it over instead of paying for Tile.distance a second time; -1 (the default) means "not known yet,
## compute it here" so every existing external caller - direct spec calls included - is unaffected.
func remaining_range_after(specific:SpecificAction, tear_tile:Vector2i, first_leg:int = -1) -> int:
	if first_leg < 0: first_leg = Tile.distance(specific.unit.tile(), tear_tile)
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
	var remaining:int = remaining_range_after(specific, tear_tile, first_leg)
	return Vector2i(first_leg, remaining)

## THE POST-TEAR BUDGET, WRITTEN WHERE THE WEAPON ACTUALLY READS IT.
##
## This used to write `aim_range` unconditionally. ActionAttackWeapon.get_target_range
## (action_attack_weapon.gd:197-206) never consults aim_range for a melee weapon: it returns
## threat_distance when threat > 0 and thrown_distance when it is 0 (which is how the engine
## recognises the THROWN variant - see its own comment there). So a bent melee or thrown attack kept
## its FULL reach past the tear: a War Pike (kinetic, threat 3) bending through a tear two tiles away
## still swung three tiles beyond it, a reach of 5 on a range-3 weapon. Nothing caught it, because
## the field that was being written was simply never read.
##
## SUBTRACTING first_leg FROM THE RAW FIELD, rather than assigning remaining_range_after's answer.
## The two are the same number when nothing else is in play, but threat_distance/thrown_distance/
## ranged_distance each add Buff.TO.ACTION_RANGE bonuses on top of the raw member - so assigning the
## already-bonused `remaining` would let the bonus be counted twice. Subtracting the first leg from
## the raw value makes the effective range come out at exactly remaining_range_after's contract for
## a buffed weapon and an unbuffed one alike.
##
## The `thrown = 0` line is not tidiness. get_target_range falls THROUGH to thrown_distance the
## moment threat reaches 0, so a throwable melee weapon whose threat budget was fully spent would
## silently hand itself its entire thrown range past the tear - the same bug this function exists to
## fix, one branch over.
func narrow_range_past_tear(specific:SpecificAction, first_leg:int) -> void:
	if UnitAction.is_melee_weapon(followup_attack, specific.gear):
		if followup_attack.threat > 0:
			followup_attack.threat = maxi(followup_attack.threat - first_leg, 0)
			if followup_attack.threat <= 0: followup_attack.thrown = 0
		else:
			followup_attack.thrown = maxi(followup_attack.thrown - first_leg, 0)
		return
	followup_attack.aim_range = maxi(followup_attack.aim_range - first_leg, 0)

## "A character standing on the bend is hit by both."
##
## Tile.get_rings (tile.gd:347-349) starts at ring 1, so AoeCalculator.line NEVER contains its own
## origin. Segment 1 runs Banshee -> tear and its last ring IS the tear tile, so the bend-tile
## occupant is caught by it. Segment 2's origin is the tear itself, so the same tile is the one tile
## its line cannot reach - the occupant took full damage and nothing else, while the variant's prose
## promises both halves.
##
## This is the only seam that reaches it. Segment 2 is resolved by followup_attack - the pilot's own
## weapon action - so there is no method of ours to override, and get_attacked_tiles_and_units_from_plan
## has already run by the time any code we control is reached. on_hit_effects, though, is an ordinary
## @export on ActionAttack (action_attack.gd:9) that we can append to on the DUPLICATE, and
## event_unit_attack_declared.execute runs OnHitEffect.apply_on_targeted_tiles over it AFTER the
## declared summary exists and BEFORE the per-target attack rolls are built from
## declared_summary.all_attacked_units. A unit appended here gets its own attack roll in segment 2,
## which is precisely "hit by the second segment too", separate roll and all.
##
## get_all_units_at_tile with whos_asking set does the two exclusions that matter: markers are
## dropped unless include_markers (both the tear and the bend proxy are Frame.ENTITY.MARKER, so
## neither can shoot itself), and the rest are filtered through UnitRelation.can_affect from the
## proxy, the same relation segment 2's own targeting used. append_nonduplicate is the guard against
## the double hit: a size-2 unit straddling the tear and an adjacent tile is already in the list via
## that adjacent tile, and appending it again would deal segment 2's damage to it twice.
class BendTileAlsoTakesSegmentTwo extends OnHitEffect:
	var tear_tile:Vector2i = Tile.INVALID

	func on_targeted_tiles(activation:EventCore, _direct_target_tiles:Array[Vector2i], _all_target_tiles:Array[Vector2i]) -> void:
		if tear_tile == Tile.INVALID: return
		if not DeclaredAttackSummary.is_valid(activation.context.resource): return
		var attacker:Unit = activation.context.unit # the proxy standing on the tear
		if not Unit.is_valid(attacker) or not is_instance_valid(attacker.map): return
		var declared_attack:DeclaredAttackSummary = activation.context.resource
		var specific := SpecificAction.from_context(activation.context)
		for occupant:Unit in attacker.map.get_all_units_at_tile(tear_tile, attacker):
			if not specific.action.can_target_unit(occupant, specific): continue
			Util.append_nonduplicate(declared_attack.all_attacked_units, occupant)

## WHY THE PROXY NEEDS BUFFS AT ALL, given get_attacker exists.
##
## UnitCondition.get_invisibility_summary (unit_condition.gd:446-469) is the ONLY consumer of
## invisibility, and it enumerates buffs off exactly two units: `for unit in [context.unit,
## context.target_unit]`. On a bend context.unit is the proxy (action_attack.gd:233 swapped it), so
## the Banshee is not in that list at all and its IGNORE_INVISIBLE buffs are never even looked at -
## To Twist Truth stopped existing the moment To Bend Reality was used. No amount of get_attacker
## inside a buff's predicate fixes that: the predicate is not reached, because the buff is not found.
## And there is nowhere else to stand - AttackUtil.check_if_invisibility_forces_miss is the sole call
## site and attack_util.gd is a confirmed-dead script-extension seam in this project (see
## buff_to_twist_truth.gd's banner). So the buffs have to be ON the proxy before the attack starts.
##
## from_gear is COPIED VERBATIM, which is what makes the mirrored copy behave like the original:
## BuffCore.get_owner_unit resolves the gear id back to whoever holds that gear
## (buff_core.gd:102-105), so the mirror on the proxy still reports the BANSHEE as its owner, and
## buff_to_twist_truth's `owner == get_attacker(context.unit)` gate still answers correctly. Copying
## the base Buff with a blank from_gear instead would silently disarm that gate.
##
## GENERIC OVER Buff.TO.IGNORE_INVISIBLE rather than hardcoding buff_to_twist_truth: To Bend Reality
## has no business knowing which of the Banshee's other traits happens to grant it, and a later
## source (a pilot talent, a mod's system) would otherwise break in the same silent way.
##
## Only IGNORE_INVISIBLE is mirrored, deliberately. TREAT_AS_INVISIBLE does NOT need mirroring -
## clause 6's buff is handed to every character on the map, so the TARGET carries it and
## get_invisibility_summary finds it there (buff_tear_invisibility.gd recognises the bend from the
## proxy itself). Copying the whole buff list across would drag statuses, auras and one-shot state
## onto a unit that lives for one activation.
##
## No cleanup is needed: the proxy is removed from the game at the end of activate().
func _mirror_invisibility_buffs_onto(activation:EventCore, from_unit:Unit, proxy:Unit) -> void:
	if not Unit.is_valid(from_unit) or not Unit.is_valid(proxy): return
	for buff_core:BuffCore in from_unit.state.buffs:
		if not BuffCore.is_valid(buff_core): continue
		if buff_core.base.to != Buff.TO.IGNORE_INVISIBLE: continue
		UnitCondition.apply_buff_alt(activation, proxy, BuffCore.create(buff_core.base, buff_core.from_gear))

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
	_mirror_invisibility_buffs_onto(activation, unit, proxy)
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

		# THE ABORT GUARD (finding 3). The codebase's own precedent for this exact pattern checks
		# `not activation.aborted` before continuing (action_attack_weapon.gd:61's mounted-followup
		# gate). Without it: a declined friendly-fire/no-targets confirmation on segment 1 still applied
		# the relay buff and prompted the player for segment 2's direction - a pointless prompt for an
		# attack that can never resolve - before the sticky `aborted` flag finally bailed out inside
		# segment 2's own activate(). Unit.is_valid(unit) covers the other trace: the Banshee dying
		# mid-resolution (e.g. a retaliation reaction) leaves activation.aborted false but the unit gone,
		# and without this check the proxy on the tear would keep firing after its owner was destroyed.
		# Falling straight through to the cleanup below - rather than an early `return` - is deliberate:
		# the one-shot relay buff (never applied on this path, so the clear below is a no-op) and the
		# proxy removal must still run either way.
		if not activation.aborted and Unit.is_valid(unit):
			relay_buff = UnitCondition.apply_buff_id(activation, unit, RELAY_BUFF_ID, context.gear)
			relay_buff.set_state(PROXY_KEY, proxy.core.persistent_id)

			# SEGMENT 2: from the proxy on the tear (relayed, above), the remaining length, HALF damage.
			# The player's second pick supplies this segment's direction/target. AS_FREEBIE keeps it from
			# charging a second action - the same flag action_attack_weapon.gd:64-79 uses for mounted
			# followups. NO_SELF_HEAT keeps it from charging a second dose of self-heat (finding 2):
			# spend_actions_gain_heat runs once per segment and self-heat is only skipped by this flag
			# (unit_action.gd:228-229), so without it a self-heating weapon like mw_rail_rifle cost the
			# Banshee heat twice for one bend. first_leg + remaining == the line's normal length
			# (remaining_range_after's contract).
			#
			# CAN_FOLLOWUP IS STRIPPED, NOT CARRIED FORWARD (finding 1). ActionAttackWeapon.activate
			# queues the mount's opposite weapon as a followup whenever CAN_FOLLOWUP is set and
			# IS_FOLLOWUP is not (action_attack_weapon.gd:59-82) - context.flags.duplicate() would
			# otherwise carry CAN_FOLLOWUP through from the player's original weapon-fire context into
			# BOTH segments, so a paired mount's opposite weapon fired a second time for one bend (free,
			# and at half damage, since HALF_DAMAGE also propagates into the followup's own flags at
			# action_attack_weapon.gd:74). Segment 1 keeps CAN_FOLLOWUP - it is the attack the player
			# actually initiated - so it alone gets to trigger the mount's followup. .erase() over
			# IS_FOLLOWUP: the same idiom already used at common_action_util.gd:683, and IS_FOLLOWUP
			# carries other meaning elsewhere (action_breach_ram_breacher_prone.gd:76 - "hijacked to
			# signify one attack only") that segment 2 has no business claiming.
			followup_attack.range_pattern = RangePattern.create(pattern, remaining)

			# THE BEND TILE ITSELF, which segment 2's line geometrically cannot reach. See
			# BendTileAlsoTakesSegmentTwo above for why this is the only available seam.
			# ASSIGNING a fresh array rather than appending to the existing one: action.gd:95 claims
			# create_duplicate_for_variant duplicates arrays, and it is probably right, but appending
			# to the pilot's real weapon's on_hit_effects would permanently bolt this onto their gun
			# for the rest of the mission if it is ever wrong. An assignment cannot be wrong either way.
			var bend_tile_effect := BendTileAlsoTakesSegmentTwo.new()
			bend_tile_effect.tear_tile = tear_tile
			var segment_two_onhits:Array[OnHitEffect] = []
			segment_two_onhits.assign(followup_attack.on_hit_effects)
			segment_two_onhits.append(bend_tile_effect)
			followup_attack.on_hit_effects = segment_two_onhits

			# RELIABLE IS PRE-DOUBLED SO THE HALVING BELOW LANDS ON THE RIGHT NUMBER.
			# "Characters hit by the second segment take half damage ON A HIT" - but
			# Action.FLAG.HALF_DAMAGE is a whole-activation flag: event_unit_attack_declared.gd:162
			# reads it once per damage event and stamps EventService.DAMAGE_FLAG.HALVED on every one,
			# and a MISS still emits a damage event carrying the weapon's RELIABLE floor
			# (attack_util.gd:126's get_miss). So a reliable-2 weapon dealt 1 on a missed second
			# segment. There is no per-roll seam to fix it at: the flag is read inside
			# content/events/, which is base game and read-only, and it is read before any roll
			# exists. Doubling the raw value here means Util.half (util.gd:12-13, a ceil) hands back
			# exactly the original - exactly, whatever the original's parity, because the input is
			# even by construction. The tier is resolved off the PROXY deliberately:
			# event_unit_attack_declared reads `unit.get_tiered_int(action.reliable_damage)` with
			# context.unit, which on a relayed segment IS the proxy, so resolving it off anything
			# else here would disagree with the value that actually gets halved.
			# COSMETIC COST, ACCEPTED: get_base_value_for_tag (action_attack_weapon.gd:118-125) reads
			# reliable_damage straight, so segment 2's targeting tooltip reads "Reliable 4" for a
			# reliable-2 weapon. The damage it then deals is right; the old build had the tooltip
			# right and the damage wrong.
			var reliable_past_tear:int = proxy.get_tiered_int(followup_attack.reliable_damage)
			if reliable_past_tear > 0: followup_attack.reliable_damage = str(reliable_past_tear * 2)

			var segment_two_flags:Array = context.flags.duplicate()
			segment_two_flags.erase(Action.FLAG.CAN_FOLLOWUP)
			segment_two_flags.append_array([Action.FLAG.HALF_DAMAGE, Action.FLAG.AS_FREEBIE, Action.FLAG.NO_SELF_HEAT])
			# NO-OP deferred_spend, ONCE PER BEND NOT ONCE PER SEGMENT. Context.clone copies
			# deferred_spend from the context it clones (context.gd:86), and run_deferred_spend is
			# NOT one-shot (context.gd:42 - contrast event_unit_move.gd:78, which nulls it after
			# calling). spend_actions_gain_heat calls it unconditionally once per activate()
			# (unit_action.gd:219), and both segments here delegate to their own
			# followup_attack.activate(). Left alone, segment two would inherit the SAME callable
			# segment one already ran it through, and fire it a second time - doubling whatever a
			# parent activation (CommonActionUtil.choose_and_use's child-activation path, reachable
			# through COMP/CON, Scylla NHP, Slave Systems, Overwatch) deferred: its action points,
			# its charge, and - since UnitAction.spend also calls spend_reaction unconditionally -
			# its REACTION. Segment one keeps the parent's real deferred_spend (Context.clone's
			# default); this is the idiom the codebase already uses elsewhere to silence a copied
			# one (event_gear_choose_and_use.gd:59, event_unit_move.gd:78).
			#
			# LATENT, NOT GUARDED: UnitAction.spend (unit_action.gd:271-279) runs
			# gear.spend_charge() and increment_action_usage_for_action for freebies too, so a
			# charge-limited kinetic LINE weapon would ALSO spend two charges for one bend, same
			# double-spend shape as the deferred_spend bug above. No vanilla weapon is both kinetic,
			# LINE and charge-limited, so this cannot happen today - a comment is enough, this does
			# not need its own guard.
			var segment_two := Context.clone(context, {
				action = followup_attack,
				flags = segment_two_flags,
				deferred_spend = func() -> void: pass,
			})
			activation.context = segment_two
			await followup_attack.activate(segment_two, activation)
	else:
		# NARROWED TO CONE, NOT "ANY range_pattern" (finding A). get_target_range reads
		# range_pattern.value as the RANGE only for LINE and CONE (action_attack_weapon.gd:202-203);
		# LINE is handled in the branch above, so CONE is the only pattern left where rewriting
		# .value is correct. For BLAST/BURST/CHAIN, .value is the AoE's RADIUS and the weapon's
		# actual range lives in aim_range instead (ranged_distance, action_attack_weapon.gd:178-185)
		# - rewriting .value for those would shrink the blast/burst/chain RADIUS to the remaining
		# range budget while leaving the weapon's real reach (aim_range) uncapped. No vanilla
		# kinetic BLAST/BURST/CHAIN weapon exists today, so this was unreachable in play, but it is
		# a live trap for this mod's own future weapons.
		if followup_attack.range_pattern and followup_attack.range_pattern.pattern == Lancer.AOE_TYPE.CONE:
			followup_attack.range_pattern = RangePattern.create(followup_attack.range_pattern.pattern, remaining)
		else:
			# The MELEE/THROWN/aim_range split; see narrow_range_past_tear's banner for why writing
			# aim_range unconditionally was wrong.
			narrow_range_past_tear(specific, first_leg)

		# THE BANSHEE FIRES FIRST, THEN THE TEAR. The relay swap on the line below moves the whole
		# activation's origin to the proxy, and ActionAttack.run_attack_effects then plays the
		# weapon's attack FXG from specific.unit (action_attack.gd:222) - so on this path the ONLY
		# muzzle flash in the whole bend came out of the tear, and the shot read as the tear
		# attacking rather than the Banshee shooting through a window. (The LINE path above reads
		# correctly on its own: segment 1 genuinely fires from the Banshee and segment 2 from the
		# tear, which is the sequence this line reconstructs for a single relayed shot.)
		#
		# Awaited so the two flashes read in sequence rather than overlapping. fxg_target is null on
		# purpose: this is the Banshee's muzzle end only - the impact belongs to the real attack, at
		# the real target, and playing a hit effect on the tear would read as the tear being shot.
		#
		# BEFORE THE CONFIRMATIONS, unavoidably. get_attacker_relay is consulted on the first line of
		# ActionAttack.activate, so the relay buff has to exist before we delegate, and this has to
		# precede the buff - which puts it ahead of the friendly-fire / no-targets confirmations
		# inside that activate(). A player who declines one has already seen the Banshee's flash. The
		# alternative is no flash at all, which is the bug being fixed.
		if Unit.is_valid(unit):
			await CommonActionUtil.run_attack_and_target_fx(
				followup_attack.get_attack_fxg(context.gear, followup_attack), unit,
				null, [tear_tile]
			)

		# Guarded, and FALLING THROUGH to the cleanup below rather than returning early - the same
		# shape (and the same reason) as the LINE path's abort guard above: the proxy has to be taken
		# off the map whatever happens. The Banshee dying during the muzzle FX above is the trace
		# this covers.
		if Unit.is_valid(unit):
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

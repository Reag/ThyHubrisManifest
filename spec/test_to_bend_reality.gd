# To Bend Reality. Asserts the RULES, not the mechanism - so a later re-implementation can be checked
# against the same tests. See D:\DEV\lancer-tactics-claude\specs\2026-09-06-banshee-to-bend-reality-design.md
extends GutTest

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')
const TEAR_FRAME := 'res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/dep_tear_banshee.tres'
const PROXY_FRAME := 'res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/mt_to_bend_reality/dep_bend_proxy_banshee.tres'

## The Kraken's Tide, per test_the_all_consuming_tide.gd. Applying it directly is the house pattern
## for a unit standing in for "a Kraken with the Tide up" - counts_as_every_tangibility keys off this
## buff alone, not off the Kraken frame, so it needs no Kraken to test.
const TIDE_BUFF_ID := &'buff_the_all_consuming_tide'

var game:Gamemaster
var banshee:Unit
var target:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self, true, SpecFactory.create_combat(Landscape.create_default(Vector2i(20,20))))
	game.campaign_core = CampaignCore.create(SpecFactory.create_campaign_base())
	game.map.campaign_core = game.campaign_core
	banshee = SpecFactory.create_unit(game.map, Vector2i(1,1))
	target = SpecFactory.create_unit(game.map, Vector2i(10,1), Faction.AI_ENEMY)

func after_each():
	TearRouting.invalidate(game.map)

## Put a unit of the given frame on a tile. Used for both tears and bend proxies.
func _place_frame(frame_path:String, tile:Vector2i, owner_unit:Unit = null) -> Unit:
	var placed := SpecFactory.create_unit(game.map, tile)
	placed.core.frame = load(frame_path)
	if Unit.is_valid(owner_unit): placed.state.set_owner(owner_unit)
	placed.update_cached_values_and_token(SpecFactory.dummy_event())
	TearRouting.invalidate(game.map)
	return placed

func test_a_tear_is_recognised_as_a_tear():
	var tear := _place_frame(TEAR_FRAME, Vector2i(5,1))
	assert_true(TearRouting.is_tear(tear), 'A dep_tear_banshee is a tear.')
	assert_false(TearRouting.is_bend_proxy(tear), 'A tear is not a bend proxy.')

func test_a_bend_proxy_is_recognised_as_a_bend_proxy():
	var proxy := _place_frame(PROXY_FRAME, Vector2i(5,1), banshee)
	assert_true(TearRouting.is_bend_proxy(proxy), 'A dep_bend_proxy_banshee is a bend proxy.')
	assert_false(TearRouting.is_tear(proxy), 'A bend proxy is not a tear.')

func test_an_ordinary_unit_is_neither():
	assert_false(TearRouting.is_tear(banshee), 'A mech is not a tear.')
	assert_false(TearRouting.is_bend_proxy(banshee), 'A mech is not a bend proxy.')

func test_effective_tangibility_of_an_ordinary_unit_is_its_own():
	assert_false(TearRouting.effective_tangibility(banshee), 'A tangible mech reads tangible.')
	SpecFactory.apply(banshee, Lancer.STATUS.INTANGIBLE)
	assert_true(TearRouting.effective_tangibility(banshee), 'An INTANGIBLE mech reads intangible.')

func test_a_bend_proxy_reads_its_owners_tangibility():
	# THE RULE. The proxy itself never carries the status - create_targeting_proxy spawns a unit with
	# none - so reading has_status off it directly would make every bend look tangible.
	SpecFactory.apply(banshee, Lancer.STATUS.INTANGIBLE)
	var proxy := _place_frame(PROXY_FRAME, Vector2i(5,1), banshee)
	assert_false(proxy.has_status(Lancer.STATUS.INTANGIBLE), 'The proxy really has no status of its own.')
	assert_true(TearRouting.effective_tangibility(proxy), 'But it reads through to its INTANGIBLE owner.')

func test_a_bend_proxy_owned_by_tangible_unit_reads_as_tangible():
	# Bug catching test: an implementation that ignored the owner and just returned true for any bend
	# proxy would pass the existing suite, since it only tested intangible owners. This test ensures
	# the owner's tangibility is actually consulted.
	var proxy := _place_frame(PROXY_FRAME, Vector2i(5,1), banshee)
	assert_false(proxy.has_status(Lancer.STATUS.INTANGIBLE), 'The proxy has no status of its own.')
	assert_false(TearRouting.effective_tangibility(proxy), 'It reads through to its tangible owner.')

func test_a_bend_proxy_with_no_owner_reads_its_own_status():
	# The fallback is intentional: effective_tangibility reads the owner if one exists, and falls back
	# to the unit itself if not. This test pins the fallback as deliberate.
	var proxy := _place_frame(PROXY_FRAME, Vector2i(5,1))
	assert_false(proxy.has_status(Lancer.STATUS.INTANGIBLE), 'A freshly-placed proxy has no status.')
	assert_false(TearRouting.effective_tangibility(proxy), 'Without an owner, it reads its own status.')

func test_a_bend_reaches_an_intangible_target_when_the_banshee_is_intangible():
	# THE CALENDULA CASE. Both parties INTANGIBLE - which happens when a Calendula has execrated the
	# target, or Weighing of Inequitable Hearts has caught it. The proxy carries no status, so
	# vanilla can_affect sees tangible-vs-intangible and refuses; effective tangibility rescues it.
	SpecFactory.apply(banshee, Lancer.STATUS.INTANGIBLE)
	SpecFactory.apply(target, Lancer.STATUS.INTANGIBLE)
	var proxy := _place_frame(PROXY_FRAME, Vector2i(5,1), banshee)
	assert_true(UnitRelation.can_affect(proxy, target),
		'An INTANGIBLE Banshee bends at an INTANGIBLE target.')

func test_a_bend_cannot_cross_the_tangibility_line_outward():
	# THE MODE SWITCH. "Instead of changing an attack's tangibility" - a bend never crosses the line.
	# Vanilla can_affect ALLOWS this pair (tangible proxy, tangible target), so only the early
	# refusal can stop it. Without it, a bend would be a strictly better tear window: no INVISIBLE
	# check and no half-range cap.
	SpecFactory.apply(banshee, Lancer.STATUS.INTANGIBLE)
	var proxy := _place_frame(PROXY_FRAME, Vector2i(5,1), banshee)
	assert_false(UnitRelation.can_affect(proxy, target),
		'An INTANGIBLE Banshee cannot bend at a tangible target.')

func test_a_bend_cannot_cross_the_tangibility_line_inward():
	SpecFactory.apply(target, Lancer.STATUS.INTANGIBLE)
	var proxy := _place_frame(PROXY_FRAME, Vector2i(5,1), banshee)
	assert_false(UnitRelation.can_affect(proxy, target),
		'A tangible Banshee cannot bend at an INTANGIBLE target - that is what the window is for.')

func test_a_bend_between_two_tangible_parties_is_ordinary():
	var proxy := _place_frame(PROXY_FRAME, Vector2i(5,1), banshee)
	assert_true(UnitRelation.can_affect(proxy, target),
		'Tangible Banshee, tangible target: nothing special, and nothing broken.')

func test_a_bend_reaches_a_kraken_with_the_tide_up_even_though_it_reads_tangible():
	# THE COMPOSITION CASE. TearRouting.effective_tangibility knows nothing about the Tide - it
	# compares raw INTANGIBLE status, and the Tide never touches the Kraken's real status (see the
	# tangibility workaround banner in unit_relation.gd_ext.gd). So an INTANGIBLE Banshee's proxy
	# reads intangible while a Tide-raised Kraken still reads tangible: exactly the mismatch the mode
	# switch above exists to refuse, unless the refusal is exempted for a party that counts as every
	# tangibility.
	#
	# The SAME Banshee attacking the SAME Kraken DIRECTLY, with no proxy at all, already succeeds -
	# super refuses on the identical raw mismatch, and counts_as_every_tangibility bridges it in the
	# widened branch (test_the_kraken_can_reach_an_intangible_character,
	# test_the_all_consuming_tide.gd). Routing the identical interaction through a bend must not flip
	# the answer: a Kraken with the Tide up counts as every tangibility, so it matches whatever the far
	# end of the bend is, proxy included.
	SpecFactory.apply(banshee, Lancer.STATUS.INTANGIBLE)
	var proxy := _place_frame(PROXY_FRAME, Vector2i(5,1), banshee)
	SpecFactory.apply_buff(target, TIDE_BUFF_ID)
	assert_true(UnitRelation.can_affect(proxy, target),
		'An INTANGIBLE Banshee bends at a Kraken with the Tide up, same as a direct attack would.')

func test_a_bend_inside_the_combined_range_is_allowed():
	# banshee (1,1) -> tear (5,1) is 4; tear -> target (10,1) is 5. Total 9 <= 10.
	_place_frame(TEAR_FRAME, Vector2i(5,1))
	assert_true(TearRouting.bends_within_range(game.map, Vector2i(1,1), Vector2i(10,1), 1, 10),
		'A bend whose two legs sum to within the weapon range is allowed.')

func test_a_bend_over_the_combined_range_is_refused():
	# banshee (1,1) -> tear (5,1) is 4; tear -> target (10,1) is 5. Total 9 > 8.
	_place_frame(TEAR_FRAME, Vector2i(5,1))
	assert_false(TearRouting.bends_within_range(game.map, Vector2i(1,1), Vector2i(10,1), 1, 8),
		'The combined distance must be within the weapon range.')

func test_a_bend_exactly_at_the_combined_range_is_allowed():
	# THE BOUNDARY. bends_within_range rejects with `> max_range`, so a combined distance EXACTLY
	# equal to max_range must still be allowed. test_a_bend_inside_the_combined_range_is_allowed
	# leaves a margin below the boundary and test_a_bend_over_the_combined_range_is_refused sits one
	# past it, but nothing exercises the boundary itself. A later edit that tightened the comparison
	# to `>=` would silently start refusing legal bends, and every other test in this file would stay
	# green. THE EQUALITY IS THE POINT - do not "tidy" this into an unequal distance.
	#
	# banshee (1,1) -> tear (5,1) is 4; tear -> target (10,1) is 5. Total 9 == 9.
	_place_frame(TEAR_FRAME, Vector2i(5,1))
	assert_true(TearRouting.bends_within_range(game.map, Vector2i(1,1), Vector2i(10,1), 1, 9),
		'A combined distance exactly equal to max_range is allowed, not refused.')

func test_a_bend_is_not_capped_at_half_range_after_the_tear():
	# THE DIFFERENCE FROM CLAUSE 7, asserted directly so the two rules cannot drift together.
	# banshee (1,1) -> tear (2,1) is 1; tear -> target (10,1) is 8. Total 9 <= 10, but 8 is well over
	# half of 10 - which routes_within_range refuses and bends_within_range must not.
	_place_frame(TEAR_FRAME, Vector2i(2,1))
	assert_false(TearRouting.routes_within_range(game.map, Vector2i(1,1), Vector2i(10,1), 1, 10),
		'The tear window still caps its post-tear leg at half range.')
	assert_true(TearRouting.bends_within_range(game.map, Vector2i(1,1), Vector2i(10,1), 1, 10),
		'A bend does not - clause 7 does not carry over.')

func test_no_tear_means_no_bend():
	assert_false(TearRouting.bends_within_range(game.map, Vector2i(1,1), Vector2i(3,1), 1, 10),
		'With no tear open nothing bends, whatever the range.')

## Arms the Banshee with the given weapon and gets it fully wired: frame swapped via
## change_mech_frame (not core.frame = load(...), which skips regenerate_derived_gear and leaves the
## trait's passive unreachable), gear equipped, repaired, and passive buffs applied.
##
## THE MOURNING CALL GUARD. change_mech_frame grants the whole frame, not just To Bend Reality - so
## it also grants cp_the_keening's Mourning Call. Mourning Call triggers after any ranged hit, and
## SpecFactory.ChoiceBusResponder auto-answers its "you may" prompt yes (chosen_yesnos starts true).
## On a kill its clause 9 relocates a void tear - which corrupts the bent line's geometry mid-test,
## since this whole file's assertions depend on the tear staying exactly where the test placed it.
## Whether the target dies (and so whether the relocation fires) depends on the damage rolls, so left
## unguarded this fails intermittently, about one run in eight, with segment 2 of a bent line hitting
## nothing. Setting has_core_power = false makes Mourning Call unaffordable (consumes_cp = true on
## action_mourning_call.tres, gated at unit_action.gd:145) regardless of what the dice do, so this
## file tests To Bend Reality in isolation. This is a fixture concern, not a nerf: in real play a
## Banshee firing a bent line SHOULD be offered Mourning Call, same as it should be offered anything
## else the core point allows - see spec/test_mourning_call.gd for that behaviour's own coverage.
func _arm_banshee_with(weapon_id:StringName) -> GearCore:
	banshee.core.change_mech_frame(load('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/mf_banshee.tres'))
	var gear := banshee.core.equip_system(weapon_id)
	banshee.core.full_repair()
	SpecFactory.apply_passive_buffs(banshee) # this ALSO calls full_repair() internally, resetting
	                                          # has_core_power = true (unit_printer.gd:76) - so the
	                                          # guard below must come after this call, not before it
	banshee.core.has_core_power = false # see the Mourning Call guard above
	return gear

func _variant_keys_on(gear:GearCore) -> Array:
	var specific := SpecificAction.create(banshee, gear, gear.get_solo_action())
	var keys:Array = []
	for group:VariantActionGroup in specific.action.get_alternate_actions(specific): keys.append(group.key)
	return keys

func test_a_kinetic_weapon_is_offered_the_bend():
	var gear := _arm_banshee_with(&'mw_assault_rifle')
	_place_frame(TEAR_FRAME, Vector2i(5,1))
	assert_true(_variant_keys_on(gear).has(&'to_bend_reality'),
		'A kinetic weapon offers To Bend Reality when a tear is open.')

func test_a_non_kinetic_weapon_is_not_offered_the_bend():
	var gear := _arm_banshee_with(&'mw_thermal_pistol')
	_place_frame(TEAR_FRAME, Vector2i(5,1))
	assert_false(_variant_keys_on(gear).has(&'to_bend_reality'),
		'An energy weapon is not offered To Bend Reality.')

func test_no_tear_means_no_offer():
	var gear := _arm_banshee_with(&'mw_assault_rifle')
	assert_false(_variant_keys_on(gear).has(&'to_bend_reality'),
		'With no tear open there is nothing to bend through, so the entry is not offered.')

func test_a_bend_is_refused_when_the_second_leg_is_blocked():
	# THE LOS REGRESSION GUARD FOR bends_within_range's SIGHT CHECK - not for anything a player
	# touches. bends_within_range has no production caller (see its docstring in tear_routing.gd):
	# the shipped range budget runs through bendable_tear_tiles plus the narrowed
	# aim_range/range_pattern instead. What this guards is the shared _sees_from/_sees machinery
	# bends_within_range exercises as the rule's reference predicate. Every other test in this file
	# runs on a flat, open map with the tear sitting directly on the line between the two points, so
	# _sees_from and _sees are trivially true in every case - a regression that broke, swapped or
	# short-circuited either sight check would pass the whole suite. This is the one geometry where
	# sight, not distance, is the reason for the refusal.
	#
	# banshee (1,1) -> tear (3,1) is 2; tear (3,1) -> target (10,1) is 7. Total 9, comfortably inside
	# max_range 15 - the distance rule alone would allow this.
	_place_frame(TEAR_FRAME, Vector2i(3,1))

	# Sanity check first: with no wall yet, the same geometry bends fine. This is what proves the
	# eventual refusal below comes from the wall, not from the numbers.
	assert_true(TearRouting.bends_within_range(game.map, Vector2i(1,1), Vector2i(10,1), 1, 15),
		'Sanity check: this geometry bends fine before any wall exists.')

	# A wall between the tear and the target only - the banshee's own leg to the tear (x=1 to x=3)
	# never crosses x=6, so this blocks the SECOND leg exclusively. Height 4, not 2: per the project's
	# known trap, UnitTile.effective_height is floor plus the unit's own body, so a unit standing on
	# flat ground sees straight over a height-2 wall. Three tiles stacked in y, matching the fixture
	# proven to block a straight line in test_tear_window.gd.
	SpecFactory.set_tiles_elevation(game.map, 4, [Vector2i(6,1), Vector2i(6,2), Vector2i(6,3)])
	game.map.calculate_los_blockers()
	TearRouting.invalidate(game.map) # the cached sweep is stale the moment terrain changes underneath it

	assert_false(TearRouting.bends_within_range(game.map, Vector2i(1,1), Vector2i(10,1), 1, 15),
		'The tear -> target leg is blocked by the wall, so the bend fails even though the combined ' +
		'distance is well within range. A broken or short-circuited sight check would miss this.')

func test_activating_the_bend_resolves_damage_from_the_followups_own_weapon():
	# THE CONTEXT-DELEGATION REGRESSION GUARD (finding 2). action_bend_reality.activate used to hand
	# followup_attack.activate() the WRAPPER'S OWN context. SpecificAction.from_context rebuilds
	# specific.action straight from context.action, and that is what event_unit_attack_declared reads
	# damage_dice/reliable_damage/tags from when it rolls base damage - NOT `self`, even though `self`
	# (the object activate() runs on) is already the followup. With the wrapper's context still in
	# play, damage_dice was '' (the wrapper's own unset default from action_bend_reality.tres) and the
	# base d6 roll below would resolve to 0 regardless of what was queued. Once activate() re-points
	# the context at followup_attack before delegating, the roll uses the real mw_assault_rifle
	# (damage_dice "1d6"), and the forced roll of 4 lands as 4 damage.
	#
	# banshee (1,1) -> tear (5,1) is 4, tear -> target (10,1) is 5, total 9 - inside mw_assault_rifle's
	# aim_range of 10, so the bend reaches. Task 8 made activate() actually route through the tear pick
	# (an earlier draft of this test predates that and queued only the target plan, back when the stub
	# didn't route through the tear at all); this now queues the tear pick too so the real flow's second
	# leg is what resolves damage.
	var gear := _arm_banshee_with(&'mw_assault_rifle')
	_place_frame(TEAR_FRAME, Vector2i(5,1))

	target.core.frame.stat.evasion = 0
	target.core.frame.stat.armor = 0
	target.core.full_repair()

	# [to-hit d20, base damage 1d6]. Evasion 0 means any non-fumble roll hits, so 15 is a safe,
	# unambiguous (non-crit, non-fumble) forced hit; 4 is comfortably clear of the rifle's reliable-2
	# floor, so a mis-delegated 0-damage roll can't be mistaken for a reliable minimum kicking in.
	Dice.CHEAT_ROLL_QUEUE.append_array([15, 4])

	SpecFactory.current_responder.chosen_plan_queue = [
		CompconPlan.create([Vector2i(5,1)]), # the tear
		CompconPlan.create([], [], [target]), # the target, from the tear
	]
	await game.execute_event(&'event_gear_activate', {
		action = gear.get_solo_action(),
		gear = gear,
		unit = banshee,
		string = 'to_bend_reality' # force the variant
	})

	assert_eq(target.current_damage(), 4,
		"The bend resolved with the followup's real 1d6, not the wrapper's empty damage_dice.")

## Compose the bend variant onto a weapon and hand back the SpecificAction the player would get.
##
## Must go through generate_composed_action. VariantActionGroup.get_variant_specifics looks like the
## obvious helper and is WRONG for this: at variant_action_group.gd:96 it calls
## `variant_action.modify.call(modified_action)` and DISCARDS the return value, so for a variant that
## REPLACES the action - which ours does, and Throughbolt's does - it hands back the pilot's weapon
## duplicate rather than the wrapper. Tests built on it would exercise the weapon's own targeting and
## never touch the tear pick at all.
##
## Index 1, not 0: get_variant_actions() inserts a blank "no modification" entry at index 0 for any
## blankable group, and ours is blankable so the player can always shoot normally.
func _bend_specific(gear:GearCore) -> SpecificAction:
	var specific := SpecificAction.create(banshee, gear, gear.get_solo_action())
	var groups := specific.action.get_alternate_actions(specific)
	if groups.is_empty(): return null
	var chosen:Dictionary[StringName, int] = { &'to_bend_reality': 1 }
	var composed := VariantActionGroup.generate_composed_action(groups, specific.action, chosen)
	return SpecificAction.create(banshee, gear, composed)

func test_only_tears_are_offerable_for_the_pick():
	var gear := _arm_banshee_with(&'mw_assault_rifle')
	_place_frame(TEAR_FRAME, Vector2i(5,1))
	var bend := _bend_specific(gear)
	assert_not_null(bend, 'The bend variant exists.')
	var tiles := UnitTargeting.get_tiles_targetable(bend)
	assert_true(tiles.has(Vector2i(5,1)), 'The tear tile is offerable.')
	assert_false(tiles.has(Vector2i(10,1)), 'The enemy is NOT offerable - the first pick is a tear.')
	assert_eq(tiles.size(), 1, 'Exactly one tear is offerable. Got: %s' % [tiles])

func test_a_tear_out_of_weapon_range_is_not_offerable():
	# NOT independent evidence the range filter works: "zero tiles offered" is indistinguishable from
	# "the override does nothing at all" - this passed even before bendable_tear_tiles existed. It
	# only means something read alongside test_only_tears_are_offerable_for_the_pick, which proves the
	# override actually offers a tear when one is in range. Together they show the filter includes the
	# in-range tear and excludes the out-of-range one; alone, this test proves nothing.
	var gear := _arm_banshee_with(&'mw_assault_rifle')
	_place_frame(TEAR_FRAME, Vector2i(19,19))
	var bend := _bend_specific(gear)
	assert_eq(UnitTargeting.get_tiles_targetable(bend).size(), 0,
		'A tear further away than the weapon range cannot be bent through.')

func test_a_tear_the_banshee_cannot_see_is_not_offered_even_when_another_tear_bridges_to_it():
	# THE NESTED-ROUTING REGRESSION GUARD (finding 1). Every other test in this file places exactly
	# one tear, which is why they all passed against the buggy implementation: bendable_tear_tiles used
	# to test a candidate tear T by calling TearRouting.bends_within_range(banshee, T), passing T as
	# BOTH waypoint and destination, relying on los(T -> T) being trivially true so only the
	# banshee -> T leg actually mattered. That reasoning breaks with a second tear open, because
	# bends_within_range loops over EVERY open tear as a candidate waypoint - so a second tear W that
	# the Banshee CAN see, and which can itself see T, bridges sight to T (banshee -> W -> T) and gets
	# T incorrectly offered, even though the real first leg (banshee -> T, unrouted) is blocked. The
	# first leg is ordinary weapon sight and must never be tear-routed.
	#
	# Geometry: banshee at (1,1). A height-4 wall at x=6 (y=1..3) blocks the row y=1 - per the
	# project's known trap, UnitTile.effective_height is floor plus the unit's own body, so a unit on
	# flat ground sees straight over a height-2 wall; height 4 is unambiguous. Height-2 pattern matches
	# test_a_bend_is_refused_when_the_second_leg_is_blocked above.
	#
	# T (10,1): banshee -> T is the horizontal line y=1, x 1->10, which crosses the wall at (6,1) and
	# is blocked. Distance 9, under mw_assault_rifle's range of 10, so only sight excludes it.
	#
	# W (5,5): banshee -> W is the diagonal y=x, x maxing out at 5 - it never reaches the wall's
	# column (x=6) at all, so the Banshee sees W directly. W -> T crosses x=6 at y~=4.2, clear of the
	# wall's y=1..3 span, so W can also see T directly. Both legs also stay cheap: dist(banshee,W)=4,
	# dist(W,T)=5, total 9 <= the weapon's range of 10, so bends_within_range's own distance filter
	# does not reject the bridge either. Under the buggy code this is exactly the bridge: banshee sees
	# W, W sees T, so T reads reachable even though banshee can never see it directly.
	var gear := _arm_banshee_with(&'mw_assault_rifle')
	_place_frame(TEAR_FRAME, Vector2i(10,1)) # T - blocked from the banshee directly
	_place_frame(TEAR_FRAME, Vector2i(5,5)) # W - visible, and bridges to T

	SpecFactory.set_tiles_elevation(game.map, 4, [Vector2i(6,1), Vector2i(6,2), Vector2i(6,3)])
	game.map.calculate_los_blockers()
	TearRouting.invalidate(game.map) # the cached sweep is stale the moment terrain changes underneath it

	var bend := _bend_specific(gear)
	var tiles := UnitTargeting.get_tiles_targetable(bend)
	assert_false(tiles.has(Vector2i(10,1)),
		'T is not offered: the Banshee cannot plainly see it, even though W could bridge to it.')
	assert_true(tiles.has(Vector2i(5,5)),
		'W is still offered: the Banshee genuinely sees it directly.')

func test_the_range_highlight_matches_the_pick():
	# THE OVERLAY REGRESSION GUARD (finding 2). get_tiles_targetable (the clickable tiles, asserted by
	# test_only_tears_are_offerable_for_the_pick above) and get_tiles_in_range (the ground highlight
	# tilepicker_compcon.gd feeds to show_range_bitwise - what the player actually SEES) read two
	# DIFFERENT TargetRequirements fields: targetable_tiles_override and range_tiles_override
	# respectively. Setting only the first left the player seeing the weapon's full ordinary range
	# highlighted during the tear pick, while only the tear tile actually responded to a click - a
	# player-visible discrepancy between what looks selectable and what is. This asserts the highlight
	# side directly, so a future edit that sets one override and not the other regresses here even if
	# it never touches the click-target test.
	var gear := _arm_banshee_with(&'mw_assault_rifle')
	_place_frame(TEAR_FRAME, Vector2i(5,1))
	var bend := _bend_specific(gear)
	var tiles := UnitTargeting.get_tiles_in_range(bend)
	assert_eq(tiles, [Vector2i(5,1)] as Array[Vector2i],
		'The range highlight shows only the tear tile, matching the click target exactly.')

func test_an_intangible_banshee_can_still_pick_its_own_tear():
	# Targeting normally filters through can_affect, and an INTANGIBLE Banshee is cross-tangible with
	# its own (tangible) tear. Overriding the tile set sidesteps that filter entirely. Asserted
	# because the failure mode is silent - the tear simply would not highlight.
	var gear := _arm_banshee_with(&'mw_assault_rifle')
	SpecFactory.apply(banshee, Lancer.STATUS.INTANGIBLE)
	_place_frame(TEAR_FRAME, Vector2i(5,1))
	assert_true(UnitTargeting.get_tiles_targetable(_bend_specific(gear)).has(Vector2i(5,1)),
		'An INTANGIBLE Banshee can select its own tear.')

func test_a_bend_hits_a_target_the_banshee_cannot_reach_directly():
	# The target sits behind the range limit from the Banshee but within the remaining budget from
	# the tear. Only a bend puts it in reach.
	var gear := _arm_banshee_with(&'mw_assault_rifle')
	var weapon_range:int = gear.get_solo_action().get_target_range(SpecificAction.create(banshee, gear, gear.get_solo_action()))
	UnitTile.move_to(target, Vector2i(1 + weapon_range + 2, 1))
	_place_frame(TEAR_FRAME, Vector2i(1 + weapon_range - 1, 1))
	target.core.frame.stat.evasion = 0
	target.core.frame.stat.armor = 0
	target.core.full_repair()

	SpecFactory.current_responder.chosen_plan_queue = [
		CompconPlan.create([Vector2i(1 + weapon_range - 1, 1)]), # the tear
		CompconPlan.create([], [], [target]),                    # the target, from the tear
	]
	Dice.CHEAT_ROLL_QUEUE = [20]
	await game.execute_event(&'event_gear_activate', {
		action = gear.get_solo_action(), gear = gear, unit = banshee,
		string = 'to_bend_reality',
	})
	assert_gt(target.current_damage(), 0, 'The bent attack reached a target out of direct range.')

func test_cancelling_the_tear_pick_spends_nothing():
	var gear := _arm_banshee_with(&'mw_assault_rifle')
	_place_frame(TEAR_FRAME, Vector2i(5,1))
	SpecFactory.start_turn(game, banshee)
	var actions_before:int = banshee.state.actions

	SpecFactory.current_responder.chosen_plan_queue = [CompconPlan.create_aborted()]
	await game.execute_event(&'event_gear_activate', {
		action = gear.get_solo_action(), gear = gear, unit = banshee,
		string = 'to_bend_reality',
	})
	assert_eq(banshee.state.actions, actions_before,
		'Cancelling the tear pick spends no action.')
	assert_eq(target.current_damage(), 0, 'And deals no damage.')

func test_no_bend_proxy_survives_the_activation():
	var gear := _arm_banshee_with(&'mw_assault_rifle')
	_place_frame(TEAR_FRAME, Vector2i(5,1))
	SpecFactory.current_responder.chosen_plan_queue = [
		CompconPlan.create([Vector2i(5,1)]),
		CompconPlan.create([], [], [target]),
	]
	Dice.CHEAT_ROLL_QUEUE = [20]
	await game.execute_event(&'event_gear_activate', {
		action = gear.get_solo_action(), gear = gear, unit = banshee,
		string = 'to_bend_reality',
	})
	for unit:Unit in game.map.get_all_units():
		assert_false(TearRouting.is_bend_proxy(unit), 'No bend proxy is left on the map afterwards.')

func test_the_pilots_real_weapon_is_unchanged_after_a_bend():
	# THE SHARED-SUBRESOURCE GUARD. create_duplicate_for_variant is duplicate_deep(DEEP_DUPLICATE_NONE)
	# (action.gd:94-99) - its own comment says subresources are NOT duplicated - so the followup's
	# range_pattern is the SAME RangePattern object as the pilot's real weapon action's. Mutating
	# followup_attack.range_pattern.value in place would permanently rewrite the pilot's actual weapon
	# for the rest of the mission; only assigning a fresh RangePattern avoids that. Every other
	# assertion in this file passes whether activate() mutates in place or assigns fresh - this is the
	# only test that would catch the mistake.
	#
	# THIS ONLY COVERS THE `aim_range` BRANCH. mw_assault_rifle has no range_pattern at all
	# (content/gear/gms/weapons/mw_assault_rifle.tres), so activate() takes the `else` arm and copies
	# an int onto the duplicate - which cannot corrupt anything shared. See
	# test_the_pilots_real_line_weapons_range_pattern_is_unchanged_after_a_bend below for the other
	# arm, the one that actually shares a subresource. Do not delete either as redundant with the
	# other; together they are the only cover for the two branches of that `if`.
	var gear := _arm_banshee_with(&'mw_assault_rifle')
	var real_action:ActionAttackWeapon = gear.get_solo_action()
	var range_before:int = real_action.range_pattern.value if real_action.range_pattern else real_action.aim_range
	_place_frame(TEAR_FRAME, Vector2i(5,1))
	target.core.frame.stat.evasion = 0
	target.core.frame.stat.armor = 0
	target.core.full_repair()

	SpecFactory.current_responder.chosen_plan_queue = [
		CompconPlan.create([Vector2i(5,1)]),
		CompconPlan.create([], [], [target]),
	]
	Dice.CHEAT_ROLL_QUEUE = [20]
	await game.execute_event(&'event_gear_activate', {
		action = gear.get_solo_action(), gear = gear, unit = banshee,
		string = 'to_bend_reality',
	})

	var range_after:int = real_action.range_pattern.value if real_action.range_pattern else real_action.aim_range
	assert_eq(range_after, range_before,
		"The pilot's real weapon range is untouched by the bend's range-budget rewrite.")

func test_the_pilots_real_line_weapons_range_pattern_is_unchanged_after_a_bend():
	# THE OTHER BRANCH OF THE SHARED-SUBRESOURCE GUARD. test_the_pilots_real_weapon_is_unchanged_after_a_bend
	# above only exercises activate()'s `aim_range` branch, because mw_assault_rifle has no
	# range_pattern at all - an int copied onto the duplicate cannot corrupt anything shared.
	# mw_rail_rifle IS a kinetic LINE weapon with a real range_pattern SubResource
	# (content/gear/ssc/weapons/mw_rail_rifle.tres: pattern = 2 [LINE], value = 10), so arming the
	# Banshee with it exercises the OTHER arm: `followup_attack.range_pattern = RangePattern.create(...)`.
	# create_duplicate_for_variant shares subresources with the pilot's real action
	# (action.gd:94-99), so if that arm ever mutated `followup_attack.range_pattern.value` in place
	# instead of assigning a fresh RangePattern, it would permanently rewrite the pilot's real weapon's
	# range - and every other assertion in this file, including the assault-rifle guard above, would
	# still pass. Do not delete this test as redundant with that one; they cover two different arms of
	# the same `if` in activate().
	var gear := _arm_banshee_with(&'mw_rail_rifle')
	var real_action:ActionAttackWeapon = gear.get_solo_action()
	assert_not_null(real_action.range_pattern, 'Sanity check: mw_rail_rifle really has a range_pattern.')
	var range_before:int = real_action.range_pattern.value
	_place_frame(TEAR_FRAME, Vector2i(5,1))
	target.core.frame.stat.evasion = 0
	target.core.frame.stat.armor = 0
	target.core.full_repair()

	SpecFactory.current_responder.chosen_plan_queue = [
		CompconPlan.create([Vector2i(5,1)]),
		CompconPlan.create([], [], [target]),
	]
	Dice.CHEAT_ROLL_QUEUE = [20]
	await game.execute_event(&'event_gear_activate', {
		action = gear.get_solo_action(), gear = gear, unit = banshee,
		string = 'to_bend_reality',
	})

	assert_eq(real_action.range_pattern.value, range_before,
		"The pilot's real LINE weapon's range_pattern is untouched by the bend's range-budget rewrite.")

## GAP 2: THE RANGE-BUDGET ARITHMETIC. test_a_bend_hits_a_target_the_banshee_cannot_reach_directly
## below LOOKS like it proves the budget works, but it does not: SpecFactory's choose_compcon_plan
## pops a queued CompconPlan and returns it with no re-validation, CompconPlan.is_valid_with_targets_alt
## never checks range, and Action.can_target_unit never checks range either - so that test would pass
## unchanged if the entire range-budget block were deleted, or computed with the wrong formula. These
## tests call remaining_range_after directly, which is the only thing that actually exercises the rule.
##
## _bend_specific composes the real variant (needs one real tear open just to pass
## check_if_passive_applies's gate), then remaining_range_after is called with an arbitrary tear_tile
## - it never looks at whether that tile is an actual tear, only at distance and the weapon's range -
## so the composed action can be reused across several hypothetical geometries.
func test_remaining_range_after_a_close_tear_leaves_most_of_the_range():
	var gear := _arm_banshee_with(&'mw_assault_rifle')
	_place_frame(TEAR_FRAME, Vector2i(2,1)) # any open tear satisfies the offer gate
	var bend := _bend_specific(gear)
	var bend_action = bend.action
	var max_range:int = bend_action.get_target_range(bend)

	var close_tear := Vector2i(2,1) # first leg 1
	var remaining:int = bend_action.remaining_range_after(bend, close_tear)
	assert_eq(remaining, max_range - 1,
		'A tear one tile from the Banshee leaves nearly the whole weapon range.')

func test_remaining_range_after_a_far_tear_leaves_little_range():
	var gear := _arm_banshee_with(&'mw_assault_rifle')
	_place_frame(TEAR_FRAME, Vector2i(2,1))
	var bend := _bend_specific(gear)
	var bend_action = bend.action
	var max_range:int = bend_action.get_target_range(bend)

	var far_tear := Vector2i(1 + max_range - 1, 1) # first leg max_range - 1
	var remaining:int = bend_action.remaining_range_after(bend, far_tear)
	assert_eq(remaining, 1,
		'A tear one short of the weapon range leaves only one tile of budget.')

func test_remaining_range_after_a_tear_at_max_range_leaves_zero():
	var gear := _arm_banshee_with(&'mw_assault_rifle')
	_place_frame(TEAR_FRAME, Vector2i(2,1))
	var bend := _bend_specific(gear)
	var bend_action = bend.action
	var max_range:int = bend_action.get_target_range(bend)

	var boundary_tear := Vector2i(1 + max_range, 1) # first leg == max_range exactly
	var remaining:int = bend_action.remaining_range_after(bend, boundary_tear)
	assert_eq(remaining, 0,
		'A tear exactly at the weapon range leaves nothing past it.')

func test_remaining_range_after_a_tear_beyond_max_range_clamps_to_zero_not_negative():
	# THE CLAMP. A tear exactly at max range (above) already lands on 0 with or without maxi() -
	# max_range - max_range is 0 either way. Only a tear PAST the weapon's range actually exercises the
	# clamp: without it this would go negative, and a negative "remaining range" assigned onto
	# aim_range or a RangePattern is nonsense the engine has never been asked to handle.
	var gear := _arm_banshee_with(&'mw_assault_rifle')
	_place_frame(TEAR_FRAME, Vector2i(2,1))
	var bend := _bend_specific(gear)
	var bend_action = bend.action
	var max_range:int = bend_action.get_target_range(bend)

	var beyond_tear := Vector2i(1 + max_range + 3, 1) # first leg max_range + 3
	var remaining:int = bend_action.remaining_range_after(bend, beyond_tear)
	assert_eq(remaining, 0,
		'A tear past the weapon range still clamps to zero, not a negative budget.')

func test_remaining_range_after_first_leg_plus_remaining_equals_full_range():
	# THE INVARIANT. Whatever the geometry (short of the clamp kicking in), the first leg plus what's
	# left over must add back up to the weapon's whole range - an off-by-one in either direction breaks
	# this even though the individual close/far cases above might still look plausible in isolation.
	var gear := _arm_banshee_with(&'mw_assault_rifle')
	_place_frame(TEAR_FRAME, Vector2i(2,1))
	var bend := _bend_specific(gear)
	var bend_action = bend.action
	var max_range:int = bend_action.get_target_range(bend)

	for first_leg:int in [1, 3, max_range - 1]:
		var tear_tile := Vector2i(1 + first_leg, 1)
		var remaining:int = bend_action.remaining_range_after(bend, tear_tile)
		assert_eq(first_leg + remaining, max_range,
			'First leg %d + remaining %d must equal the full range %d.' % [first_leg, remaining, max_range])

## THE LINE SPLIT ARITHMETIC. Same rationale as Gap 2 above, for line_segment_lengths instead of
## remaining_range_after: nothing on the mocked-CompconPlan end-to-end path
## (test_a_bent_line_hits_both_segments_and_halves_the_second below) re-derives or checks a segment's
## actual length - CompconPlan.is_valid_with_targets_alt never checks range and neither does
## Action.can_target_unit - so a test that only asserts damage would pass even if both segments were
## sized wrong, or the split were deleted outright. These call line_segment_lengths directly, which is
## the only thing that actually exercises the split.
##
## mw_rail_rifle, not mw_assault_rifle like Gap 2's block: it is a real kinetic LINE weapon
## (content/gear/ssc/weapons/mw_rail_rifle.tres: pattern = 2 [LINE], value = 10), so get_target_range
## here returns the line's own length rather than a plain aim_range - the actual budget the split
## divides in the real activate() flow.
func test_line_segment_lengths_x_is_the_distance_to_the_tear():
	var gear := _arm_banshee_with(&'mw_rail_rifle')
	_place_frame(TEAR_FRAME, Vector2i(2,1)) # any open tear satisfies the offer gate
	var bend := _bend_specific(gear)
	var bend_action = bend.action

	var tear_tile := Vector2i(4,1) # first leg 3
	var lengths:Vector2i = bend_action.line_segment_lengths(bend, tear_tile)
	assert_eq(lengths.x, 3, "Segment 1's length is exactly the distance from the Banshee to the tear.")

func test_line_segment_lengths_y_matches_remaining_range_after():
	# THE REUSE CHECK. line_segment_lengths.y is documented as remaining_range_after's own result,
	# reused rather than recomputed so the two functions cannot drift apart. Assert that directly, not
	# just its value, so a future edit that inlines a SEPARATE (and possibly different) formula for y
	# is caught even if it happens to agree with remaining_range_after for this one geometry.
	var gear := _arm_banshee_with(&'mw_rail_rifle')
	_place_frame(TEAR_FRAME, Vector2i(2,1))
	var bend := _bend_specific(gear)
	var bend_action = bend.action

	var tear_tile := Vector2i(4,1)
	var lengths:Vector2i = bend_action.line_segment_lengths(bend, tear_tile)
	assert_eq(lengths.y, bend_action.remaining_range_after(bend, tear_tile),
		"Segment 2's length equals remaining_range_after's answer for the same tear.")

func test_line_segment_lengths_at_the_range_boundary_leaves_a_zero_length_second_segment():
	# THE BOUNDARY. A tear exactly at the weapon's full range leaves segment 2 legal but zero-length -
	# mirroring test_remaining_range_after_a_tear_at_max_range_leaves_zero above, through the pair now.
	var gear := _arm_banshee_with(&'mw_rail_rifle')
	_place_frame(TEAR_FRAME, Vector2i(2,1))
	var bend := _bend_specific(gear)
	var bend_action = bend.action
	var max_range:int = bend_action.get_target_range(bend)

	var boundary_tear := Vector2i(1 + max_range, 1) # first leg == max_range exactly
	var lengths:Vector2i = bend_action.line_segment_lengths(bend, boundary_tear)
	assert_eq(lengths.x, max_range, 'Segment 1 spans the whole weapon range up to the boundary tear.')
	assert_eq(lengths.y, 0, 'Segment 2 is left with nothing past a tear sitting at the range limit.')

func test_line_segment_lengths_always_sum_to_the_full_line_length():
	# THE INVARIANT THE BRIEF ASKS FOR BY NAME. Whatever the geometry (short of the clamp kicking in),
	# segment 1 plus segment 2 must add back up to the weapon's whole line length - an off-by-one in
	# either direction breaks this even though the individual x/y checks above might still look
	# plausible in isolation. Mirrors test_remaining_range_after_first_leg_plus_remaining_equals_full_range,
	# through the pair rather than through remaining_range_after alone.
	var gear := _arm_banshee_with(&'mw_rail_rifle')
	_place_frame(TEAR_FRAME, Vector2i(2,1))
	var bend := _bend_specific(gear)
	var bend_action = bend.action
	var max_range:int = bend_action.get_target_range(bend)

	for first_leg:int in [1, 3, max_range - 1]:
		var tear_tile := Vector2i(1 + first_leg, 1)
		var lengths:Vector2i = bend_action.line_segment_lengths(bend, tear_tile)
		assert_eq(lengths.x + lengths.y, max_range,
			'Segment 1 %d + segment 2 %d must equal the full line length %d.' % [lengths.x, lengths.y, max_range])

func test_activation_narrows_the_followups_range_to_the_computed_budget():
	# THE END-TO-END CHECK. The direct tests above prove remaining_range_after's arithmetic in
	# isolation; this proves activate() actually calls it and applies the result to the followup that
	# damage resolution delegates to - the real path a mocked CompconPlan travels, which per the Gap 2
	# analysis above never touches range on its own.
	#
	# game.execute_event (Level.execute_event, level.gd:97) returns void - every other test in this
	# file discards it - so there is no handle on the finished EventCore to read context.action back
	# from. Level.execute_event_block (level.gd:100-109) is what it calls, and does nothing more than
	# add an EventBlock under Events and await block.execute(); this reproduces exactly that, but keeps
	# the block instead of discarding it, so event_cores[0].context - which action_bend_reality.activate
	# re-points at the followup before delegating (activation.context = followup_context) - is still
	# readable right after the await, before the block is freed the same way execute_event_block does.
	var gear := _arm_banshee_with(&'mw_assault_rifle')
	var weapon_range:int = gear.get_solo_action().get_target_range(SpecificAction.create(banshee, gear, gear.get_solo_action()))
	var tear_tile := Vector2i(5,1) # first leg 4 from banshee (1,1)
	var first_leg:int = Tile.distance(banshee.tile(), tear_tile)
	_place_frame(TEAR_FRAME, tear_tile)
	target.core.frame.stat.evasion = 0
	target.core.frame.stat.armor = 0
	target.core.full_repair()

	SpecFactory.current_responder.chosen_plan_queue = [
		CompconPlan.create([tear_tile]),
		CompconPlan.create([], [], [target]),
	]
	Dice.CHEAT_ROLL_QUEUE = [20]

	var block := EventBlock.create(&'event_gear_activate', {
		action = gear.get_solo_action(), gear = gear, unit = banshee,
		string = 'to_bend_reality',
	})
	game.Events.add_child(block)
	await block.execute()

	var followup:ActionAttackWeapon = block.event_cores[0].context.action
	if is_instance_valid(block) and not block.is_queued_for_deletion(): block.queue_free()

	assert_not_null(followup, 'The finished event core still carries the followup as its context action.')
	assert_eq(followup.aim_range, weapon_range - first_leg,
		"The followup's narrowed aim_range equals the weapon's range minus the first leg to the tear.")

## THE LINE-SPLIT END-TO-END PLUMBING. The direct line_segment_lengths tests above prove the split
## arithmetic in isolation; this proves activate() actually branches on it for a LINE weapon and fires
## TWO real attacks - one from the Banshee to the tear, one onward from the tear at half damage - not
## just narrowing a single followup's range as the non-line path does. Per the Gap 2/line-split-Gap
## analysis, damage landing at all does not prove the segments were sized correctly - only
## line_segment_lengths's own tests do that - so this is plumbing cover, not geometry cover.
func test_a_bent_line_hits_both_segments_and_halves_the_second():
	# Rail Rifle: LINE, length 10. Banshee at (1,1), tear at (4,1) - so segment 1 is 3 long and
	# segment 2 is 7, and 3 + 7 == 10, the line's normal length.
	var gear := _arm_banshee_with(&'mw_rail_rifle')
	var near := SpecFactory.create_unit(game.map, Vector2i(3,1), Faction.AI_ENEMY)
	var far := SpecFactory.create_unit(game.map, Vector2i(9,1), Faction.AI_ENEMY)
	for victim:Unit in [near, far]:
		victim.core.frame.stat.evasion = 0
		victim.core.frame.stat.armor = 0
		victim.core.full_repair()
	_place_frame(TEAR_FRAME, Vector2i(4,1))

	SpecFactory.current_responder.chosen_plan_queue = [
		CompconPlan.create([Vector2i(4,1)]),  # the tear
		CompconPlan.create([Vector2i(9,1)]),  # segment 2's direction
	]
	Dice.CHEAT_ROLL_QUEUE = [20, 20, 4, 4] # both attacks hit; both damage rolls fixed
	await game.execute_event(&'event_gear_activate', {
		action = gear.get_solo_action(), gear = gear, unit = banshee,
		string = 'to_bend_reality',
	})
	assert_gt(near.current_damage(), 0, 'Segment 1 hit the character before the tear.')
	assert_gt(far.current_damage(), 0, 'Segment 2 hit the character past the tear.')
	assert_lt(far.current_damage(), near.current_damage(),
		'Segment 2 dealt HALF damage; segment 1 dealt full.')

func test_the_pilots_real_weapon_is_not_rewritten_by_a_bend():
	# THE SUBRESOURCE TRAP, for the LINE path specifically. create_duplicate_for_variant does not
	# duplicate subresources, so a line bend that MUTATED range_pattern.value - on EITHER of its two
	# reassignments, segment 1's or segment 2's - would permanently shorten the player's actual
	# railgun. Every other assertion in this file, including the end-to-end test above, would still
	# pass; only reading the real action's own range_pattern.value back catches it.
	var gear := _arm_banshee_with(&'mw_rail_rifle')
	var real_action:ActionAttackWeapon = gear.get_solo_action()
	var length_before:int = real_action.range_pattern.value
	_place_frame(TEAR_FRAME, Vector2i(4,1))

	SpecFactory.current_responder.chosen_plan_queue = [
		CompconPlan.create([Vector2i(4,1)]),
		CompconPlan.create([Vector2i(9,1)]),
	]
	Dice.CHEAT_ROLL_QUEUE = [20, 20, 4, 4]
	await game.execute_event(&'event_gear_activate', {
		action = gear.get_solo_action(), gear = gear, unit = banshee,
		string = 'to_bend_reality',
	})
	assert_eq(real_action.range_pattern.value, length_before,
		'The pilot\'s real weapon still has its original line length after a bend.')

## THE SELF-HEAT GUARD (finding 2). spend_actions_gain_heat runs once per followup_attack.activate()
## call (unit_action.gd:214-229), and self-heat is gated only by Action.FLAG.NO_SELF_HEAT - AS_FREEBIE
## (unit_action.gd:242) does not touch it. Segment 2 is AS_FREEBIE (so it doesn't cost a second
## action) but, before this fix, was NOT NO_SELF_HEAT - so a self-heating LINE weapon charged the
## Banshee heat once for segment 1 and AGAIN for segment 2, for one bend that should cost one weapon's
## worth of heat.
func test_a_bend_costs_self_heat_once_not_once_per_segment():
	var gear := _arm_banshee_with(&'mw_rail_rifle') # self_heat_dice "1" (content/gear/ssc/weapons/mw_rail_rifle.tres)
	var near := SpecFactory.create_unit(game.map, Vector2i(3,1), Faction.AI_ENEMY)
	var far := SpecFactory.create_unit(game.map, Vector2i(9,1), Faction.AI_ENEMY)
	for victim:Unit in [near, far]:
		victim.core.frame.stat.evasion = 0
		victim.core.frame.stat.armor = 0
		victim.core.full_repair()
	_place_frame(TEAR_FRAME, Vector2i(4,1))

	assert_eq(banshee.core.current.heat, 0, 'Sanity check: the Banshee starts at zero heat.')

	SpecFactory.current_responder.chosen_plan_queue = [
		CompconPlan.create([Vector2i(4,1)]),  # the tear
		CompconPlan.create([Vector2i(9,1)]),  # segment 2's direction
	]
	Dice.CHEAT_ROLL_QUEUE = [20, 20, 4, 4] # both attacks hit; both damage rolls fixed
	await game.execute_event(&'event_gear_activate', {
		action = gear.get_solo_action(), gear = gear, unit = banshee,
		string = 'to_bend_reality',
	})

	assert_eq(banshee.core.current.heat, 1,
		"One bend with mw_rail_rifle's self_heat_dice \"1\" costs exactly 1 heat, not 2.")

## THE ABORT GUARD (finding 3). Segment 1 travels from the Banshee straight to an EMPTY tear tile with
## nothing standing on that line, so ActionAttack.activate's own "attack anyway with no targets?"
## confirmation (TargetActionUtil.confirm_aoe_no_targets, action_attack.gd:247) prompts the player
## before committing. Declining it sets activation.aborted and returns before spend_actions ever runs -
## segment 1 never happened. Without the abort guard, activate() sails on regardless: it applies the
## relay buff to a Banshee that never fired, and prompts the player AGAIN for segment 2's direction,
## for an attack that can never resolve - only the sticky aborted flag inside segment 2's own
## delegated activate() finally bails out.
##
## CompconPlan.create_aborted() (the lever the brief suggested) does not reach segment 1: its own
## target_tiles are PRE-FILLED by the wrapper (Context.clone(..., {target_tiles = [tear_tile]})), so
## TargetActionUtil.ask_for_targets_alt treats it as "was_supplied_a_target" and never consults the
## player/queue at all for segment 1 - only a genuinely-queued CompconPlan for the WRAPPER's own tear
## pick, or segment 2's un-supplied direction pick, ever pop chosen_plan_queue. Declining the
## no-targets confirmation is the lever that actually reaches inside segment 1's own activate().
func test_a_bend_aborts_cleanly_when_segment_one_declines_the_no_targets_confirmation():
	var gear := _arm_banshee_with(&'mw_rail_rifle')
	_place_frame(TEAR_FRAME, Vector2i(4,1)) # empty line (1,1)->(4,1): nothing to hit, nothing to confirm past
	target.core.frame.stat.evasion = 0
	target.core.frame.stat.armor = 0
	target.core.full_repair()

	SpecFactory.current_responder.chosen_plan_queue = [
		CompconPlan.create([Vector2i(4,1)]), # the tear pick - the ONLY plan queued
	]
	SpecFactory.current_responder.chosen_yesnos = false # decline "attack anyway with no targets?"
	Dice.CHEAT_ROLL_QUEUE = [20, 20, 4, 4] # would-be rolls for both segments; untouched if the guard holds

	var choices_before:int = SpecFactory.current_responder.choices_made
	await game.execute_event(&'event_gear_activate', {
		action = gear.get_solo_action(), gear = gear, unit = banshee,
		string = 'to_bend_reality',
	})

	assert_eq(SpecFactory.current_responder.choices_made, choices_before + 2,
		'Exactly two choices were consulted - the tear pick and the decline. No second targeting ' +
		'prompt for segment 2 was ever consumed.')
	assert_eq(target.current_damage(), 0, 'No damage reached the target - the bend never resolved.')

## Finding 1's fixture: a Banshee with a real MAIN+AUX paired mount, a LINE kinetic rifle on the
## primary slot and a pistol on the secondary - so ActionAttackWeapon's own mounted-followup logic
## (action_attack_weapon.gd:59-82, which reads unit.core.loadout.get_mount_for_gear(gear)) actually has
## something to find. _arm_banshee_with's ordinary equip_system path never touches loadout.mounts at
## all - get_mount_for_gear would return null for gear equipped that way - so it cannot exercise this.
##
## Mirrors test_secondary_aux_attack.gd's own setup (append a mount type to the frame, full_repair to
## materialize it, equip both slots directly on the MountCore, full_repair again so charges are real) -
## the base game's own precedent for testing this exact mechanism. The frame is duplicated first (and
## its mount_types array duplicated too, since Resource.duplicate() alone doesn't guarantee that for
## every Godot version) rather than mutating the cached res://.../mf_banshee.tres in place, so this
## doesn't leak an extra mount type into every other test in this file that also loads that path.
func _arm_banshee_with_paired_mount(primary_id:StringName, secondary_id:StringName) -> Dictionary:
	var frame:Frame = load('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/mf_banshee.tres').duplicate()
	frame.mount_types = frame.mount_types.duplicate()
	frame.mount_types.append(ContentLibrary.get_mount(&'mount_main_aux'))
	banshee.core.change_mech_frame(frame)
	var mount:MountCore = banshee.core.loadout.mounts.back()
	var primary_gear := mount.equip_primary(primary_id)
	var secondary_gear := mount.equip_secondary(secondary_id)
	banshee.core.full_repair()
	SpecFactory.apply_passive_buffs(banshee) # also calls full_repair() internally - see the Mourning
	                                          # Call guard on _arm_banshee_with above
	banshee.core.has_core_power = false # same guard as _arm_banshee_with: this also arms the whole
	                                     # frame, including cp_the_keening's Mourning Call
	return { primary = primary_gear, secondary = secondary_gear }

## THE MOUNTED-FOLLOWUP GUARD (finding 1). Normal player weapon fire sets CAN_FOLLOWUP
## (phase_ui_player_action.gd:176). Before this fix, BOTH of a LINE bend's segments could trigger
## ActionAttackWeapon's mounted-followup logic: segment 1 via Context.clone (which carries flags
## through untouched), segment 2 via context.flags.duplicate() plus its own additions - neither
## stripped CAN_FOLLOWUP or set IS_FOLLOWUP. One bend fired the mount's opposite weapon twice.
##
## GearCore.get_uses_this_turn is the observable: increment_action_usage_for_per_turn
## (action_attack_weapon.gd:70) runs unconditionally the instant a followup is QUEUED, before that
## queued attack even rolls to hit - so it counts how many times the followup was triggered,
## independent of what the dice do afterwards. No target is placed on either leg on purpose: the
## "attack anyway with no targets?" confirmation defaults to yes (ChoiceBusResponder.chosen_yesnos
## starts true), and the followup trigger itself does not care whether the main attack connected -
## only whether it aborted (see action_attack_weapon.gd:61's `not activation.aborted` gate).
func test_a_bend_triggers_the_mounted_followup_exactly_once():
	var gears := _arm_banshee_with_paired_mount(&'mw_rail_rifle', &'mw_pistol')
	_place_frame(TEAR_FRAME, Vector2i(4,1))

	SpecFactory.current_responder.chosen_plan_queue = [
		CompconPlan.create([Vector2i(4,1)]), # the tear
		CompconPlan.create([Vector2i(9,1)]), # segment 2's direction
	]
	await game.execute_event(&'event_gear_activate', {
		action = gears.primary.get_solo_action(), gear = gears.primary, unit = banshee,
		string = 'to_bend_reality',
		flags = [Action.FLAG.CAN_FOLLOWUP],
	})

	assert_eq(gears.secondary.get_uses_this_turn(gears.secondary.get_solo_action()), 1,
		"The mount's pistol fired exactly once for one bend, not once per segment.")

## THE DEFERRED_SPEND GUARD (blocker 2). Same class of bug as the self-heat and mounted-followup
## doubles above, in the same place: a LINE bend runs TWO activations (segment 1 and segment 2), and
## anything that survives Context.clone unmodified fires for BOTH unless activate() strips it.
## Context.clone copies deferred_spend (context.gd:86), and run_deferred_spend is NOT one-shot
## (context.gd:42 - contrast event_unit_move.gd:78, which nulls it after calling).
## UnitAction.spend_actions_gain_heat calls it unconditionally once per followup_attack.activate()
## call (unit_action.gd:219). CommonActionUtil.choose_and_use (common_action_util.gd:694-719) sets
## exactly this on a CHILD activation so a parent (e.g. Flank/COMP-CON/Scylla NHP/Slave
## Systems/Overwatch) doesn't spend its own actions until the child commits - so a bent LINE weapon
## fired through one of those doubled the parent's action points, its charge, and its REACTION for
## one bend, before this fix.
##
## Simulated the same way choose_and_use actually wires it: passing `deferred_spend` straight into
## the event_gear_activate params dict (mirroring common_action_util.gd:710-720), which Context.create
## routes to context.deferred_spend via its own special-cased handling (context.gd:99-100).
func test_a_bent_line_runs_the_parent_activations_deferred_spend_once_not_twice():
	var gear := _arm_banshee_with(&'mw_rail_rifle')
	var near := SpecFactory.create_unit(game.map, Vector2i(3,1), Faction.AI_ENEMY)
	var far := SpecFactory.create_unit(game.map, Vector2i(9,1), Faction.AI_ENEMY)
	for victim:Unit in [near, far]:
		victim.core.frame.stat.evasion = 0
		victim.core.frame.stat.armor = 0
		victim.core.full_repair()
	_place_frame(TEAR_FRAME, Vector2i(4,1))

	var deferred_spend_calls := [0]
	var count_deferred_spend:Callable = func() -> void: deferred_spend_calls[0] += 1

	SpecFactory.current_responder.chosen_plan_queue = [
		CompconPlan.create([Vector2i(4,1)]),  # the tear
		CompconPlan.create([Vector2i(9,1)]),  # segment 2's direction
	]
	Dice.CHEAT_ROLL_QUEUE = [20, 20, 4, 4] # both attacks hit; both damage rolls fixed
	await game.execute_event(&'event_gear_activate', {
		action = gear.get_solo_action(), gear = gear, unit = banshee,
		string = 'to_bend_reality',
		deferred_spend = count_deferred_spend,
	})

	assert_eq(deferred_spend_calls[0], 1,
		"A parent activation's deferred_spend runs once per bend, not once per segment.")

## get_values points the VARIANT's title/description at these keys (not the trait's own
## gear.mt_to_bend_reality.name/.effect, which label the group) so the menu states the two-attack
## cost instead of special-casing it. See buff_to_bend_reality.gd:get_values.
func test_the_variant_strings_are_localized():
	assert_ne(tr('gear.mt_to_bend_reality.variant.name'), 'gear.mt_to_bend_reality.variant.name',
		'The variant name resolves. If it does not, a stale mod zip is shadowing the working tree.')
	assert_ne(tr('gear.mt_to_bend_reality.variant.effect'), 'gear.mt_to_bend_reality.variant.effect',
		'The variant description resolves.')

func test_a_bend_proxy_sees_no_cross_tangible_units():
	# One line in cross_tangible_units takes BOTH the tear's LOS widening and its clause-7 range
	# policing off a bend, because tiles_visible_via_tears and the get_tiles_within override both
	# iterate it. A bend sees plain vanilla geometry measured from the tear, which is what the trait
	# text describes.
	SpecFactory.apply(target, Lancer.STATUS.INTANGIBLE)
	_place_frame(TEAR_FRAME, Vector2i(5,1))
	var proxy := _place_frame(PROXY_FRAME, Vector2i(5,1), banshee)

	assert_eq(TearRouting.cross_tangible_units(game.map, banshee).size(), 1,
		'A tangible Banshee still sees the INTANGIBLE target as cross-tangible.')
	assert_eq(TearRouting.cross_tangible_units(game.map, proxy).size(), 0,
		'A bend proxy sees nobody as cross-tangible - the tear window does not apply to a bend.')

func test_a_bend_proxy_gains_no_sight_through_the_third_los_seam():
	# THE THIRD SEAM (blocker 1). test_a_bend_proxy_sees_no_cross_tangible_units above proves
	# cross_tangible_units returns nothing for a bend proxy, which is enough to take the widening off
	# the LOS sweep (get_tiles_in_los) and the clause-7 range policing (get_tiles_within) - both
	# iterate that function. is_tile_in_los is a THIRD seam that does NOT go through
	# cross_tangible_units at all: it calls TearRouting.is_cross_tangible(viewer, occupant) directly
	# on RAW status. A bend proxy always reads raw-tangible - create_targeting_proxy gives it no
	# statuses - so against an INTANGIBLE target it reads as cross-tangible, and without its own
	# bend-proxy exclusion the override grants sight through ANY open tear, not just the one the
	# player actually picked for the bend.
	#
	# Geometry: banshee (1,1) and target (10,1), both INTANGIBLE - the Calendula case this trait
	# exists to permit. A wall at x=6 (y=1..3, height 4) blocks BOTH the direct proxy -> target line
	# and TEAR1 (5,1, where the proxy stands, as it would for a real bend) -> target - so neither
	# ordinary sight nor the "chosen" tear reaches the target. TEAR2 (5,5) is a SECOND open tear that
	# bridges anyway: the proxy sees TEAR2 (straight up column x=5, never crosses the wall), and TEAR2
	# sees the target (crosses x=6 at y~4.2, clear of the wall's y=1..3 span). Only the bug lets TEAR2
	# answer for a pick the player never made.
	SpecFactory.apply(banshee, Lancer.STATUS.INTANGIBLE)
	SpecFactory.apply(target, Lancer.STATUS.INTANGIBLE)
	_place_frame(TEAR_FRAME, Vector2i(5,1)) # TEAR1 - the "chosen" tear, itself blocked from the target
	_place_frame(TEAR_FRAME, Vector2i(5,5)) # TEAR2 - a second open tear that bridges anyway
	var proxy := _place_frame(PROXY_FRAME, Vector2i(5,1), banshee)

	SpecFactory.set_tiles_elevation(game.map, 4, [Vector2i(6,1), Vector2i(6,2), Vector2i(6,3)])
	game.map.calculate_los_blockers()
	TearRouting.invalidate(game.map) # the cached sweep is stale the moment terrain changes underneath it

	var from_height:int = UnitTile.effective_height(proxy, true, proxy.tile())
	assert_false(
		UnitTile.is_tile_in_los(game.map, [proxy.tile()], from_height, target.tile(), proxy.core.persistent_id),
		'A bend proxy gains no sight of an INTANGIBLE target through a tear it was never routed through.')

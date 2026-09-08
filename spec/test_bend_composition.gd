# THE COMPOSITION SUITE. Three of the Banshee's four abilities silently stopped working the moment
# the player used the fourth, and all three failed for the same root cause: To Bend Reality relays
# the attack through a targeting proxy standing on the tear (action_attack.gd:233 assigns
# `specific.unit = get_attacker_relay(...)`), every downstream event then carries that PROXY as
# context.unit, and three of this mod's files read context.unit raw when they meant "the Banshee".
#
# WHY THIS FILE EXISTS AT ALL, given each of those three abilities already had a full spec suite of
# its own. Every one of those suites tested its ability in isolation, against an ordinary unrelayed
# attack, and every one of them was green while the ability was dead in play. The units were tested;
# the COMPOSITION never was. So every test here drives a genuinely BENT attack end to end - through
# event_gear_activate with the to_bend_reality variant forced, the tear pick answered, and the real
# weapon resolving damage - and asserts the other ability fires. Asserting the helper functions in
# isolation is precisely how these three shipped broken; do not "simplify" any of these into a
# direct call to the predicate under test.
#
# HOW THE DICE ASSERTIONS WORK, because they look arbitrary and are not. Dice.CHEAT_ROLL_QUEUE is
# popped one value per die roll, whatever the die type (dice.gd:33-35). The invisibility machinery
# rolls d6s BEFORE the attack's d20 ever happens - buff_to_twist_truth's coin flip, then vanilla's
# AttackUtil.check_if_invisibility_forces_miss (attack_util.gd:74) - so a broken build that skips
# those rolls does not merely behave differently, it CONSUMES A DIFFERENT NUMBER OF VALUES and every
# later roll shifts up the queue. That is what makes these damage assertions sharp: the queues below
# are chosen so the broken build lands on a visibly different damage number rather than an
# ambiguous zero. Each test names its own broken-build outcome.
extends GutTest

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')

const BANSHEE_FRAME := 'res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/mf_banshee.tres'
const TEAR_FRAME := 'res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/dep_tear_banshee.tres'

## mw_assault_rifle: kinetic (no damage_type override) so To Bend Reality offers itself, weapon_type
## unset so it defaults to RIFLE and Mourning Call's ranged gate passes, aim_range 10 so the
## 4 + 5 = 9 tile bend below fits, and damage_dice "1d6" so one queued value is the whole damage roll.
## Its `reliable 2` floor is why the "it missed" assertions below are `< 4` rather than `== 0`.
const WEAPON_ID := &'mw_assault_rifle'
const KEENING_KIT_ID := &'cp_the_keening'
const MOURNING_CALL_USAGE_GROUP := &'action_mourning_call'
const TWIST_TRUTH_BUFF_ID := &'buff_to_twist_truth'
const TEAR_INVIS_BUFF_ID := &'buff_tear_invisibility'

const BANSHEE_TILE := Vector2i(1,1)
const TEAR_TILE := Vector2i(5,1)   # 4 from the Banshee: inside aim_range 10, so it is offerable
const TARGET_TILE := Vector2i(10,1) # 5 past the tear: inside the 10 - 4 = 6 remaining budget

var game:Gamemaster
var banshee:Unit
var target:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self, true, SpecFactory.create_combat(Landscape.create_default(Vector2i(20,20))))
	game.campaign_core = CampaignCore.create(SpecFactory.create_campaign_base())
	game.map.campaign_core = game.campaign_core

	banshee = SpecFactory.create_unit(game.map, BANSHEE_TILE)
	banshee.core.change_mech_frame(load(BANSHEE_FRAME))
	banshee.core.equip_system(WEAPON_ID)
	banshee.core.full_repair()
	# apply_passive_buffs is what actually runs cp_the_keening's and mt_to_twist_truth's
	# PassiveBuffApplicators. Without it buff_mourning_call and buff_to_twist_truth never exist and
	# every test in this file would pass or fail for the wrong reason.
	SpecFactory.apply_passive_buffs(banshee)
	banshee.state.overcharge_actions = 99
	SpecFactory.start_turn(game, banshee)

	target = SpecFactory.create_unit(game.map, TARGET_TILE, Faction.AI_ENEMY)
	target.core.frame.stat.evasion = 0 # any non-fumble d20 hits, so the roll is never the variable
	target.core.frame.stat.armor = 0
	target.core.full_repair()

func after_each():
	TearRouting.invalidate(game.map)
	Dice.CHEAT_ROLL_QUEUE.clear()

# ---------------------------------------------------------------------------- fixtures

## A tear placed as SCENERY. Mirrors test_to_bend_reality.gd's _place_frame: it puts a
## dep_tear_banshee on the map so To Bend Reality has something to bend through, WITHOUT running
## action_tear - so clause 6's buff is never handed out and the tear-invisibility machinery stays
## completely out of the way. Used by every test here that is not about clause 6.
func _place_bare_tear(tile:Vector2i = TEAR_TILE) -> Unit:
	var placed := SpecFactory.create_unit(game.map, tile)
	placed.core.frame = load(TEAR_FRAME)
	placed.state.set_owner(banshee)
	placed.update_cached_values_and_token(SpecFactory.dummy_event())
	TearRouting.invalidate(game.map)
	return placed

## A tear opened the way the player opens one, so _hand_out_tear_invisibility actually runs and every
## character on the map ends up carrying clause 6's predicate buff.
func _open_tear_for_real(tile:Vector2i = TEAR_TILE) -> void:
	await SpecFactory.use(game, banshee, KEENING_KIT_ID, &'action_tear', [tile])

## Fire the equipped weapon WITH THE BEND VARIANT FORCED, answering both picks: the tear first, then
## the target from the tear. `string = 'to_bend_reality'` is the required_variant channel
## event_gear_activate uses, and is how test_to_bend_reality.gd drives the same path.
func _bend_at_target(dice:Array) -> void:
	var weapon:GearCore = banshee.get_gear(WEAPON_ID)
	Dice.CHEAT_ROLL_QUEUE.append_array(dice)
	SpecFactory.current_responder.chosen_plan_queue = [
		CompconPlan.create([TEAR_TILE]),          # pick 1: the tear to bend through
		CompconPlan.create([], [], [target]),     # pick 2: the target, aimed from the tear
	]
	await game.execute_event(&'event_gear_activate', {
		action = weapon.get_solo_action(),
		gear = weapon,
		unit = banshee,
		string = 'to_bend_reality'
	})

## Fire the same weapon with NO bend, as the control for "the ability works normally".
func _shoot_target_plainly(dice:Array) -> void:
	var weapon:GearCore = banshee.get_gear(WEAPON_ID)
	Dice.CHEAT_ROLL_QUEUE.append_array(dice)
	SpecFactory.current_responder.chosen_plan_queue = [CompconPlan.create([], [], [target])]
	await game.execute_event(&'event_gear_activate', {
		action = weapon.get_solo_action(),
		gear = weapon,
		unit = banshee,
	})

func _mourning_call_ran() -> bool:
	var gear:GearCore = banshee.get_gear(KEENING_KIT_ID)
	if not GearCore.is_valid(gear): return false
	return gear.get_uses_this_round_alt(MOURNING_CALL_USAGE_GROUP) > 0

## Take To Twist Truth off the board so a clause 6 test measures clause 6 alone. Clearing it from the
## BANSHEE is enough to clear it from the proxy too: action_bend_reality mirrors whatever
## IGNORE_INVISIBLE buffs the Banshee is carrying at the moment the proxy is created, so a Banshee
## with none hands over none.
func _disarm_to_twist_truth() -> void:
	UnitCondition.clear_buff_id(SpecFactory.dummy_event(), banshee, TWIST_TRUTH_BUFF_ID)

# ---------------------------------------------------------------------------- sanity

func test_the_fixture_actually_bends():
	# Not a rule - a fixture check, and the one every other test in this file rests on. If the bend
	# never happened (variant not offered, tear not offerable, pick queue mismatched) then every
	# "the ability fired on a bend" assertion below would be measuring an ORDINARY attack and would
	# pass while proving nothing. The Banshee cannot see (10,1) any less well than (5,1) on open
	# ground, so this cannot be checked by reach; check the tear is offerable to the variant instead.
	banshee.core.has_core_power = false
	_place_bare_tear()
	var weapon:GearCore = banshee.get_gear(WEAPON_ID)
	var specific := SpecificAction.create(banshee, weapon, weapon.get_solo_action())
	var groups := specific.action.get_alternate_actions(specific)
	var keys:Array = []
	for group:VariantActionGroup in groups: keys.append(group.key)
	assert_true(keys.has(&'to_bend_reality'), 'The bend variant is offered on the kinetic rifle. Got: %s' % [keys])

	var chosen:Dictionary[StringName, int] = { &'to_bend_reality': 1 }
	var composed := VariantActionGroup.generate_composed_action(groups, specific.action, chosen)
	var tiles := UnitTargeting.get_tiles_targetable(SpecificAction.create(banshee, weapon, composed))
	assert_true(tiles.has(TEAR_TILE), 'The tear is offerable as the bend pick. Got: %s' % [tiles])

# ---------------------------------------------------------------------------- Mourning Call

func test_mourning_call_is_offered_after_a_bent_ranged_hit():
	# THE BUG: onhit_mourning_call.on_resolution read activation.context.unit, which on a bend is the
	# dep_bend_proxy_banshee - a unit that owns no cp_the_keening. SpecificAction.from_id came back
	# invalid and the function returned before ever prompting, so a Banshee that bent lost its core
	# power for the rest of the mission. get_attacker resolves the proxy back to its owner.
	#
	# Asserted on the kit's usage counter rather than on damage: this is about whether the ability was
	# REACHED, and the counter only moves when choose_and_use actually runs the action.
	_place_bare_tear()
	banshee.core.has_core_power = true
	# [to-hit, damage, then spares for Mourning Call's own attack roll and damage].
	await _bend_at_target([15, 4, 15, 4, 4, 4])
	assert_true(_mourning_call_ran(), 'A bent ranged hit offers Mourning Call, exactly as an unbent one does.')

func test_mourning_call_is_still_offered_after_an_ordinary_hit():
	# The control that keeps the test above honest: the same fixture, same weapon, no bend. If this
	# ever fails alongside the one above, the fault is in the fixture and not in the relay.
	_place_bare_tear()
	banshee.core.has_core_power = true
	await _shoot_target_plainly([15, 4, 15, 4, 4, 4])
	assert_true(_mourning_call_ran(), 'Sanity: the unbent path - the one that always worked - still works.')

func test_mourning_call_is_not_offered_without_a_core_point_on_a_bend():
	# Guards the assertion above against vacuity: the usage counter must be capable of staying at
	# zero on this exact path. Without this, "the counter moved" could be an artefact of the bend
	# machinery rather than evidence Mourning Call was offered.
	_place_bare_tear()
	banshee.core.has_core_power = false
	await _bend_at_target([15, 4, 4, 4])
	assert_false(_mourning_call_ran(), 'No core point, no Mourning Call - the counter is a real signal.')

# ---------------------------------------------------------------------------- To Twist Truth

func test_to_twist_truth_ignores_invisibility_on_a_bent_attack():
	# THE BUG, IN TWO HALVES. (1) The gate compared the buff's owner against context.unit, which on a
	# bend is the proxy, so it never matched. (2) More fundamentally, get_invisibility_summary only
	# enumerates buffs off [context.unit, context.target_unit] - on a bend NEITHER is the Banshee, so
	# the buff was not even found and no gate could have saved it. action_bend_reality now mirrors the
	# Banshee's IGNORE_INVISIBLE buffs onto the proxy, from_gear intact, and the gate resolves the
	# relay with get_attacker.
	#
	# The target carries a REAL INVISIBLE status here rather than clause 6's buff, so this measures
	# To Twist Truth alone and does not depend on the clause 6 fix in the same file.
	#
	# QUEUE [1, 15, 4]: To Twist Truth's coin flip pops the 1 (<= 3, so invisibility is ignored),
	# vanilla's miss-check is therefore never rolled, the d20 pops 15 (a clean non-crit hit against
	# evasion 0) and the damage 1d6 pops 4.
	# BROKEN BUILD: the buff is absent from the proxy, so no coin flip happens; the 1 is popped by
	# vanilla's miss-check instead, forces a miss, and the target takes only the rifle's reliable
	# floor - a visibly different number, not a coincidental zero.
	_place_bare_tear()
	banshee.core.has_core_power = false # no Mourning Call prompt to disturb the queue
	SpecFactory.apply(target, Lancer.STATUS.INVISIBLE)
	assert_true(UnitCondition.has_buff(banshee, TWIST_TRUTH_BUFF_ID), 'Sanity: the Banshee carries To Twist Truth.')

	await _bend_at_target([1, 15, 4])
	assert_eq(target.current_damage(), 4,
		'To Twist Truth ignored the INVISIBLE target on a BENT attack, so the shot landed its full 1d6.')

func test_a_high_roll_leaves_a_bent_attack_subject_to_invisibility():
	# The other side of the coin flip, and the reason the fix above cannot be "always ignore": on a
	# high roll the ordinary vanilla check still runs and can still force a miss.
	#
	# QUEUE [6, 1, 15, 4]: coin flip 6 (> 3, do not ignore), vanilla miss-check 1 (<= 3, forced miss).
	# The 15 and 4 are never reached.
	_place_bare_tear()
	banshee.core.has_core_power = false
	SpecFactory.apply(target, Lancer.STATUS.INVISIBLE)

	await _bend_at_target([6, 1, 15, 4])
	assert_lt(target.current_damage(), 4,
		'A high coin flip leaves the bent attack subject to invisibility, and this one missed.')

# ---------------------------------------------------------------------------- clause 6

func test_clause_six_treats_the_target_as_invisible_on_a_bend():
	# THE BUG: buff_tear_invisibility asked TearRouting.attack_routes_through_tear(context.unit, ...),
	# and on a bend context.unit is the proxy. is_cross_tangible reads raw INTANGIBLE status and the
	# proxy has none, so an ordinary tangible-on-tangible bend answered "no route" and clause 6 went
	# quiet on the one attack that is guaranteed to pass through a tear.
	#
	# To Twist Truth is disarmed here so this measures clause 6 alone.
	#
	# QUEUE [6, 15, 4]: vanilla's miss-check pops the 6 (> 3, no forced miss), the d20 pops 15, damage
	# pops 4.
	# BROKEN BUILD: clause 6 does not fire, so the target is not invisible, so NO miss-check roll
	# happens at all; the d20 pops the 6 - still a hit against evasion 0 - and the DAMAGE roll pops
	# the 15, landing 15 damage instead of 4. The number is the proof that the extra d6 was consumed.
	await _open_tear_for_real()
	banshee.core.has_core_power = false
	_disarm_to_twist_truth()
	assert_true(UnitCondition.has_buff(target, TEAR_INVIS_BUFF_ID),
		'Sanity: opening the tear for real hands clause 6 predicate buff to every character.')

	await _bend_at_target([6, 15, 4])
	assert_eq(target.current_damage(), 4,
		"Clause 6 made the bent attack roll vanilla's invisibility check, which is what consumed the 6.")

func test_clause_six_can_make_a_bend_miss():
	# The consequence that makes clause 6 cost something on a bend rather than just consume a die.
	# QUEUE [1, 15, 4]: miss-check 1 (<= 3) forces the miss; the 15 and 4 are never reached and the
	# target takes only the rifle's reliable floor.
	await _open_tear_for_real()
	banshee.core.has_core_power = false
	_disarm_to_twist_truth()

	await _bend_at_target([1, 15, 4])
	assert_lt(target.current_damage(), 4, 'A low invisibility roll makes the bent attack miss.')

func test_clause_six_and_to_twist_truth_compose_on_a_bend():
	# ALL THREE PIECES AT ONCE, which is the shape that was never tested and is why the frame shipped
	# with abilities that cancelled each other. The tear is opened for real (clause 6 live), To Twist
	# Truth is left armed, and a bend is fired.
	#
	# QUEUE [1, 15, 4]: clause 6 makes the target count as invisible, To Twist Truth's coin flip pops
	# the 1 and ignores it, so vanilla's miss-check never rolls, the d20 pops 15 and damage pops 4.
	# BROKEN BUILD, EITHER HALF: if clause 6 is dead, nothing is invisible, To Twist Truth declines to
	# roll (its own stray-roll guard), the d20 pops the 1 and the shot fumbles. If To Twist Truth is
	# dead, the 1 is eaten by vanilla's miss-check and forces a miss. Both land under 4 damage; only
	# both fixes together reach exactly 4.
	await _open_tear_for_real()
	banshee.core.has_core_power = false
	assert_true(UnitCondition.has_buff(banshee, TWIST_TRUTH_BUFF_ID), 'Sanity: To Twist Truth is armed.')
	assert_true(UnitCondition.has_buff(target, TEAR_INVIS_BUFF_ID), 'Sanity: clause 6 is armed.')

	await _bend_at_target([1, 15, 4])
	assert_eq(target.current_damage(), 4,
		'Clause 6 made the target invisible and To Twist Truth twisted it away, on one bent attack.')

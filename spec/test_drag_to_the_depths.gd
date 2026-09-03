# Drag To The Depths - the gate and the cost.
#
#   "While |IMMOBILIZED|, you may expend your base movement to: ..."
#
# Design notes live in D:\DEV\lancer-tactics-claude\specs\2026-09-02-kraken-design.md.
#
# The gate is UnitCondition.is_immobilized rather than the bare IMMOBILIZED status, because that is
# the exact predicate pathfinder.gd:330 uses to hand back an empty reachable set - so the Kraken may
# spend the movement precisely when the movement was worthless.
#
# It is opened here with the STATUS rather than with a grapple, deliberately. Grappling only
# immobilizes the Kraken once the katamari outweighs it (a size 2 holding one size 1 is still the
# larger party), so building that state costs three units and a size change for no extra coverage.
extends GutTest

const CORE_POWER_ID := &'cp_the_endless_black_sea'
const DRAG_MODES := [&'action_drag_grapple', &'action_drag_pull', &'action_drag_reposition']
const MY_DOMAIN_ID := &'mt_my_domain'

var game:Gamemaster
var kraken:Unit
var gear:GearCore

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	kraken = SpecFactory.create_unit(game.map, Vector2i(0, 0))
	gear = kraken.core.equip_system(CORE_POWER_ID)
	_refill_movement()

## The turn-start state: speed refilled, none of it spent.
func _refill_movement() -> void:
	kraken.core.current.speed = kraken.core.get_speed_max()

func _pin() -> void:
	SpecFactory.apply(kraken, Lancer.STATUS.IMMOBILIZED)

## Grapple through My Domain's gear, the way the burst trigger does - its attachment passive is what
## lets a grapple hold at range, which Reposition then relies on. Hoisted up here next to the other
## shared setup helpers since the gate test below needs it too, not just Reposition's own tests.
func _hold(prey:Unit) -> GearCore:
	var domain := kraken.core.equip_system(MY_DOMAIN_ID)
	Katamari.attach_units(SpecFactory.dummy_event(), kraken, prey, domain.persistent_id)
	return domain

func _action(action_id:StringName) -> Action:
	return ContentLibrary.get_kit(CORE_POWER_ID).get_action(action_id)

func _available(action_id:StringName) -> bool:
	var action := _action(action_id)
	if not Action.is_valid(action): return false
	return action.is_available_to_activate(kraken, gear)

# ============================== the gate ==============================

func test_a_mobile_kraken_cannot_drag():
	# The clause is "while IMMOBILIZED". A Kraken that can walk has no business reaching.
	assert_false(UnitCondition.is_immobilized(kraken), 'It starts free to move.')
	for action_id:StringName in DRAG_MODES:
		assert_false(_available(action_id), '%s is unavailable while mobile.' % action_id)

func test_a_pinned_kraken_can_drag():
	_pin()
	assert_true(UnitCondition.is_immobilized(kraken), 'It is pinned.')
	# Reposition's own gate additionally requires something held (see its is_available_to_activate),
	# so pinning alone is not enough for it - give the Kraken a prisoner first to keep this test's
	# original meaning (all three modes available) intact.
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	_hold(prey)
	for action_id:StringName in DRAG_MODES:
		assert_true(_available(action_id), '%s is available while pinned.' % action_id)

func test_being_grappled_and_outweighed_opens_the_gate_too():
	# The second route, and the one the frame actually plays: is_immobilized is a disjunction, and
	# GRAPPLED-while-not-larger is a member of it. Guards against someone "simplifying" the gate to
	# has_status(IMMOBILIZED), which would silently kill the interaction with My Domain.
	SpecFactory.apply(kraken, Lancer.STATUS.GRAPPLED)
	kraken.state.is_larger_in_grapple = false
	assert_true(UnitCondition.is_immobilized(kraken), 'Held and outweighed counts as immobilized.')
	assert_true(_available(&'action_drag_pull'), 'So Drag is available.')

func test_a_kraken_that_already_moved_cannot_drag():
	# "expend your BASE MOVEMENT", read strictly: the price is the whole allowance, so there has to
	# be a whole allowance left. Move first and the option is gone for the turn.
	_pin()
	kraken.core.current.speed = kraken.core.get_speed_max() - 1
	for action_id:StringName in DRAG_MODES:
		assert_false(_available(action_id), '%s is unavailable after moving.' % action_id)

# ============================== the cost ==============================

func test_activating_spends_the_whole_allowance():
	_pin()
	var action := _action(&'action_drag_pull')
	if not Action.is_valid(action): return fail_test('action_drag_pull is on the kit.')

	# flags matters: the inherited spend_actions reads activation.context.flags, and a Context
	# without the property would fail the read rather than default.
	var activation := SpecFactory.dummy_event({
		unit = kraken, gear = gear, action = action, flags = [], number = 0,
	})
	action.spend_actions(activation)
	assert_eq(kraken.core.current.speed, 0, 'The base movement is gone.')

func test_the_cost_closes_the_gate_behind_it():
	# One Drag per turn, and it falls out of the cost rather than needing a shared usage_group.
	_pin()
	var action := _action(&'action_drag_pull')
	if not Action.is_valid(action): return fail_test('action_drag_pull is on the kit.')

	assert_true(_available(&'action_drag_pull'), 'Available to begin with.')
	action.spend_actions(SpecFactory.dummy_event({
		unit = kraken, gear = gear, action = action, flags = [], number = 0,
	}))
	for action_id:StringName in DRAG_MODES:
		assert_false(_available(action_id), '%s is spent for the turn.' % action_id)

# ============================== Grapple ==============================
# Routed through the unit's own action_grapple via CommonActionUtil.choose_and_use rather than
# reimplemented, so it is a genuine contested roll. choose_and_use auto-picks when there is exactly
# one option and a player is driving, and it adds Action.FLAG.AS_FREEBIE, which is what makes the
# grapple itself cost no action.

const GRAPPLE_KIT := &'mw_grapple'
const GRAPPLE_ACTION := &'action_grapple'

func test_grapple_points_at_the_units_own_grapple():
	var action := _action(&'action_drag_grapple')
	if not Action.is_valid(action): return fail_test('action_drag_grapple is on the kit.')

	var grapple:SpecificAction = action.grapple_for(kraken)
	assert_true(SpecificAction.is_valid(grapple), 'It found a grapple to route to.')
	if not SpecificAction.is_valid(grapple): return
	assert_eq(grapple.action.get_id(), GRAPPLE_ACTION, 'And it is the real basic Grapple.')
	assert_eq(grapple.unit, kraken, 'Made by the Kraken itself.')

func test_grapple_takes_no_target_of_its_own():
	# The grapple it routes to does the targeting. Asking for a target here would make the player
	# pick twice, and the first pick would be meaningless.
	var action := _action(&'action_drag_grapple')
	if not Action.is_valid(action): return fail_test('action_drag_grapple is on the kit.')
	var reqs:TargetRequirements = action.get_target_requirements(
		SpecificAction.create(kraken, gear, action))
	assert_eq(reqs.count, 0, 'It targets nothing directly.')

func test_grapple_actually_grabs_and_pays_the_movement():
	# CHEAT_ROLL_QUEUE fixes the contested roll high so the grapple lands; the point of the test is
	# that a real roll happened at all and that the movement was the only thing spent.
	_pin()
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	Dice.CHEAT_ROLL_QUEUE.append(20)

	var actions_before := kraken.state.actions
	await SpecFactory.use(game, kraken, CORE_POWER_ID, &'action_drag_grapple')

	var held:Array[StringName] = []
	for grapple:SpecificAction in UnitCondition.get_outgoing_grapples(kraken):
		held.append(grapple.unit.core.persistent_id)
	assert_true(held.has(prey.core.persistent_id), 'The Kraken grabbed it.')
	assert_eq(kraken.core.current.speed, 0, 'And paid with its base movement.')
	assert_eq(kraken.state.actions, actions_before, 'The grapple itself was free.')

func test_grapple_missing_still_pays_the_movement():
	# choose_and_use's deferred spend runs before the roll resolves - that is the whole reason the
	# spend is deferred at all - so a missed grapple still costs the whole base movement. Intended,
	# but nothing pinned it before this test.
	_pin()
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	Dice.CHEAT_ROLL_QUEUE.append(1) # a 1 fails any attack roll worth the name

	await SpecFactory.use(game, kraken, CORE_POWER_ID, &'action_drag_grapple')

	var held:Array[StringName] = []
	for grapple:SpecificAction in UnitCondition.get_outgoing_grapples(kraken):
		held.append(grapple.unit.core.persistent_id)
	assert_false(held.has(prey.core.persistent_id), 'The grapple did not land.')
	assert_eq(kraken.core.current.speed, 0, 'But the movement was spent anyway.')

func test_grapple_does_not_offer_a_character_it_already_holds():
	# Free, from routing rather than reimplementing: action_grapple.can_target_unit strips anyone in
	# the katamari. Worth pinning anyway - it is the kind of thing a future rewrite would lose, and
	# re-grabbing a prisoner would be a no-op that still burned the Kraken's whole movement.
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	var action := _action(&'action_drag_grapple')
	if not Action.is_valid(action): return fail_test('action_drag_grapple is on the kit.')

	var grapple:SpecificAction = action.grapple_for(kraken)
	if not SpecificAction.is_valid(grapple): return fail_test('It found a grapple to route to.')
	assert_true(grapple.action.can_target_unit(prey, grapple), 'A loose character is a target.')

	_hold(prey)
	assert_false(grapple.action.can_target_unit(prey, grapple),
		'One it is already holding is not.')

# ============================== Pull ==============================
# The Goliath's Coercive Force is the template for the pull itself; the difference is one target
# rather than a burst, and a HULL save in front of it. "Resists" is read as no movement at all.
#
# The spec map is 5x5 (SpecFactory.create_map_state default), so every tile used here is inside it.

func test_pull_reaches_as_far_as_sensors():
	# The range is the SENSORS stat, not a literal - target_range_is_sensors on the resource. A
	# hardcoded number would silently stop tracking the statblock.
	var action := _action(&'action_drag_pull')
	if not Action.is_valid(action): return fail_test('action_drag_pull is on the kit.')
	var specific := SpecificAction.create(kraken, gear, action)
	assert_eq(action.get_target_range(specific), kraken.get_sensor_range(),
		'Pull reaches to SENSORS.')

func test_a_failed_save_drags_them_two_spaces_closer():
	_pin()
	var prey := SpecFactory.create_unit(game.map, Vector2i(4, 0), Faction.AI_ENEMY)
	Dice.CHEAT_ROLL_QUEUE.append(1) # a 1 fails any save worth the name

	await SpecFactory.use(game, kraken, CORE_POWER_ID, &'action_drag_pull', [prey])

	assert_eq(prey.tile(), Vector2i(2, 0), 'It was dragged two spaces towards the Kraken.')
	assert_eq(kraken.core.current.speed, 0, 'And the movement was paid.')

func test_a_passed_save_resists_the_pull_entirely():
	# "(HULL save resists)" - resists means nothing happens, not a shorter pull.
	_pin()
	var prey := SpecFactory.create_unit(game.map, Vector2i(4, 0), Faction.AI_ENEMY)
	Dice.CHEAT_ROLL_QUEUE.append(20)

	await SpecFactory.use(game, kraken, CORE_POWER_ID, &'action_drag_pull', [prey])

	assert_eq(prey.tile(), Vector2i(4, 0), 'It held its ground.')

func test_pull_will_take_an_ally():
	# The rules text says "a character", and the user confirmed allies are valid: yanking a wounded
	# teammate clear is a real play, and the save means they can decline. This diverges from My
	# Domain's hostiles-only rule on purpose - see the design doc.
	var action := _action(&'action_drag_pull')
	if not Action.is_valid(action): return fail_test('action_drag_pull is on the kit.')
	var friend := SpecFactory.create_unit(game.map, Vector2i(3, 0), Faction.PLAYER)
	assert_true(UnitRelation.are_allies(kraken, friend), 'They are on the same side.')
	assert_true(action.can_target_unit(friend, SpecificAction.create(kraken, gear, action)),
		'And the ally is a legal target.')

func test_pull_will_not_target_a_knockback_immune_character():
	# generate_pull_events performs no immunity check of its own (unlike generate_knockback_events),
	# and event_unit_move.gd exempts the primary mover, so nothing downstream would catch this -
	# can_target_unit has to filter it directly. buff_fortress_knockback is vanilla's plain,
	# unconditional TO.KNOCKBACK_IMMUNITY buff, applied directly here rather than through its aura so
	# the test does not also have to stand up the Drake's deployed cover.
	var action := _action(&'action_drag_pull')
	if not Action.is_valid(action): return fail_test('action_drag_pull is on the kit.')
	var immune := SpecFactory.create_unit(game.map, Vector2i(3, 0), Faction.AI_ENEMY)
	assert_true(action.can_target_unit(immune, SpecificAction.create(kraken, gear, action)),
		'A target is legal before it has the immunity.')

	UnitCondition.apply_buff_id(SpecFactory.dummy_event(), immune, &'buff_fortress_knockback')
	assert_false(action.can_target_unit(immune, SpecificAction.create(kraken, gear, action)),
		'A knockback-immune character is not a legal target.')

# ============================== Reposition ==============================
# AN AIMED THROW. The Kraken picks a prisoner and a point to hurl it at; the character travels toward
# that point in a straight line, up to three spaces, and stops against the first thing that will not
# let it through. Aiming is allowed at anything - open ground, a wall, a bystander, the Kraken's own
# space - because hitting something is the whole appeal.
#
# This file previously read "3 spaces in any direction" as "any reachable tile within 3": the player
# named a DESTINATION and the prisoner walked around obstacles to reach it. That reading could not
# hit anything, ever, because only tiles the prisoner could already stand on were offered. The trade
# is deliberate and the user made it: a prisoner can no longer be posted neatly around a corner, and
# in exchange a throw is a throw.
#
# MovementType.create_for_involuntary already sets ignore_rxns, ignore_engagement, ignore_difficult
# and jump_downhill, so the throw provokes nothing and can drop the target off a ledge. That is
# inherited from vanilla forced movement rather than reimplemented.

func test_reposition_only_offers_characters_the_kraken_is_holding():
	var action := _action(&'action_drag_reposition')
	if not Action.is_valid(action): return fail_test('action_drag_reposition is on the kit.')
	var specific := SpecificAction.create(kraken, gear, action)

	var loose := SpecFactory.create_unit(game.map, Vector2i(2, 0), Faction.AI_ENEMY)
	assert_false(action.can_target_unit(loose, specific), 'A character it is not holding is not a target.')

	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	_hold(prey)
	assert_true(action.can_target_unit(prey, specific), 'One it is holding is.')

func test_reposition_will_take_a_held_ally():
	# Same divergence from My Domain as Pull, and here it is unconditional: the Kraken already holds
	# them, so nothing new is imposed by moving them.
	var action := _action(&'action_drag_reposition')
	if not Action.is_valid(action): return fail_test('action_drag_reposition is on the kit.')
	var friend := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.PLAYER)
	_hold(friend)
	assert_true(UnitRelation.are_allies(kraken, friend), 'They are on the same side.')
	assert_true(action.can_target_unit(friend, SpecificAction.create(kraken, gear, action)),
		'And a held ally can still be moved.')

func test_reposition_throws_them_and_pays_the_movement():
	_pin()
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	_hold(prey)

	# The aim point is the Kraken's PLAYER's choice, so the spec names it the way the player would -
	# the prisoner, then the tile to throw it at. Given clear ground the throw covers its full three
	# spaces and lands on the aim point exactly.
	await SpecFactory.use(game, kraken, CORE_POWER_ID, &'action_drag_reposition', [prey, Vector2i(4, 0)])

	assert_eq(prey.tile(), Vector2i(4, 0), 'It landed exactly where the Kraken chose, three spaces out.')
	assert_eq(kraken.core.current.speed, 0, 'And the movement was paid.')
	# The immobilized thrower must not go along for the ride - the loudest possible failure of this
	# action would be the Kraken dragging itself while throwing its prisoner.
	assert_eq(kraken.tile(), Vector2i(0, 0), 'The Kraken itself did not move.')

func test_reposition_can_aim_at_a_space_that_is_already_occupied():
	# The whole point of aiming. A destination-picker can only ever offer somewhere the prisoner could
	# stand, which is exactly the set of places where nothing is in the way - so it can never be used
	# to throw anybody AT anything. The Kraken's own footprint is the case that matters most: it is
	# what turns a throw into a collision, and a collision into a seize.
	_pin()
	var prey := SpecFactory.create_unit(game.map, Vector2i(2, 0), Faction.AI_ENEMY)
	var bystander := SpecFactory.create_unit(game.map, Vector2i(4, 0), Faction.AI_ENEMY)
	_hold(prey)

	var action := _action(&'action_drag_reposition')
	if not Action.is_valid(action): return fail_test('action_drag_reposition is on the kit.')
	var specific := SpecificAction.create(kraken, gear, action)
	var picked_prisoner:Array[TargetingPick] = [TargetingPick.create_selection(prey.tile())]
	var aimable:Array[Vector2i] = UnitTargeting.get_tiles_targetable(specific, picked_prisoner)

	assert_true(aimable.has(kraken.tile()), 'The Kraken can be aimed at.')
	assert_true(aimable.has(bystander.tile()), 'So can a bystander two spaces the other way.')
	assert_true(aimable.has(Vector2i(2, 2)), 'And so can open ground.')
	assert_false(aimable.has(prey.tile()), 'Only the prisoner\'s own space is no aim at all.')

func test_reposition_stops_the_throw_against_whatever_is_in_the_way():
	# "3 spaces" is a maximum reached by travelling, not a teleport to the aim point. A body in the
	# line is where the throw ends, and the prisoner is left against it rather than beyond it or on
	# top of it.
	_pin()
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	var bystander := SpecFactory.create_unit(game.map, Vector2i(3, 0), Faction.AI_ENEMY)
	_hold(prey)

	await SpecFactory.use(game, kraken, CORE_POWER_ID, &'action_drag_reposition', [prey, Vector2i(4, 0)])

	assert_eq(prey.tile(), Vector2i(2, 0), 'It got as far as the bystander and no further.')
	assert_eq(bystander.tile(), Vector2i(3, 0), 'Who was not shoved along by it.')

func test_reposition_can_slam_a_prisoner_into_the_kraken_itself():
	# The throw the whole rewrite exists for. Aimed at its own captor, a prisoner is hauled back down
	# the line and stops dead against it - which is a collision, and a collision against the Kraken is
	# what the Tide's seize listens for (see test_the_all_consuming_tide.gd). A destination-picker could
	# never even offer this shot.
	_pin()
	var prey := SpecFactory.create_unit(game.map, Vector2i(3, 0), Faction.AI_ENEMY)
	_hold(prey)

	await SpecFactory.use(game, kraken, CORE_POWER_ID, &'action_drag_reposition', [prey, Vector2i(0, 0)])

	assert_eq(prey.tile(), Vector2i(1, 0), 'It travelled until the Kraken stopped it.')
	# Travelled and was stopped, not routed and parked. Two spaces of movement and then a Kraken - a
	# prisoner that reached the Kraken's space and was tidied back out again would land on the same
	# tile having covered more ground, which is a different thing entirely.
	assert_eq(prey.state.spaces_moved_this_turn, 2, 'Two spaces of it, and then no more.')
	assert_eq(kraken.tile(), Vector2i(0, 0), 'And the Kraken held its ground under the impact.')

func test_reposition_throws_along_the_line_it_was_aimed_down():
	# Aimed, not routed. The old reading let the prisoner walk around a corner to reach a chosen
	# destination; this one sends it in a straight line and lets the line decide where it ends up.
	_pin()
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 1), Faction.AI_ENEMY)
	_hold(prey)

	await SpecFactory.use(game, kraken, CORE_POWER_ID, &'action_drag_reposition', [prey, Vector2i(4, 4)])

	assert_eq(prey.tile(), Vector2i(4, 4), 'Thrown three spaces down the diagonal it was pointed at.')

func test_reposition_will_not_target_a_held_knockback_immune_character():
	# Same filter as Pull, and for the same reason: pathfinder.generate_events is what actually moves
	# the target here, and nothing else along that path checks immunity.
	var action := _action(&'action_drag_reposition')
	if not Action.is_valid(action): return fail_test('action_drag_reposition is on the kit.')
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	_hold(prey)
	assert_true(action.can_target_unit(prey, SpecificAction.create(kraken, gear, action)),
		'A held target is legal before it has the immunity.')

	UnitCondition.apply_buff_id(SpecFactory.dummy_event(), prey, &'buff_fortress_knockback')
	assert_false(action.can_target_unit(prey, SpecificAction.create(kraken, gear, action)),
		'A knockback-immune character it holds is not a legal target either.')

func test_reposition_cannot_target_its_own_captor():
	# The header's specific worry: OUTGOING grapples only, not the whole katamari - the katamari also
	# contains whoever is holding US. This is exactly what would break if get_outgoing_grapples were
	# ever refactored to Katamari.create(unit).all_units, since that set includes both directions.
	var captor := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	var captor_domain := captor.core.equip_system(MY_DOMAIN_ID)
	Katamari.attach_units(SpecFactory.dummy_event(), captor, kraken, captor_domain.persistent_id)
	assert_false(UnitCondition.get_incoming_grapples(kraken).is_empty(), 'The captor is holding the Kraken.')

	var action := _action(&'action_drag_reposition')
	if not Action.is_valid(action): return fail_test('action_drag_reposition is on the kit.')
	assert_false(action.can_target_unit(captor, SpecificAction.create(kraken, gear, action)),
		'The Kraken cannot throw whoever is holding it.')

func test_the_grapple_survives_the_throw():
	# The open question from the design doc. My Domain's ignores_adjacency_requirement is proven to
	# let a grapple FORM at range; whether it keeps one alive after the prisoner is thrown is what
	# this pins. If it fails, the fix is Buff.TO.ATTACH_AT_DISTANCE - the key whose comment reads
	# "grapple doesn't automatically fall off because they're far", carried by the Blackbeard's
	# cable as buff_grapple_cable_at_distance.tres.
	_pin()
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	_hold(prey)

	await SpecFactory.use(game, kraken, CORE_POWER_ID, &'action_drag_reposition', [prey, Vector2i(4, 0)])

	var held:Array[StringName] = []
	for grapple:SpecificAction in UnitCondition.get_outgoing_grapples(kraken):
		held.append(grapple.unit.core.persistent_id)
	assert_true(held.has(prey.core.persistent_id), 'The Kraken is still holding it.')

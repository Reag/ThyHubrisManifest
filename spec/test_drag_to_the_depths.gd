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

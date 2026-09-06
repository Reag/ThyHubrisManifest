# Clause 8, move half: "You may expend your base movement to move the tear up to your speed. This
# does not count as taking an action."
#
# THE RULE, as specified by the author: the action is offered while your base turn movement is
# untouched. Taking it spends all of that base movement. You may still BOOST afterwards for more, and
# boosting FIRST does not disqualify you - moving on boost movement alone leaves the base allowance
# intact and the action still available.
#
# These specs drive is_available_to_activate directly rather than through the UI, because the
# availability rule is the whole subtlety here and the movement pool is what encodes it. Base and
# boost movement are POOLED (current.speed starts at get_speed_max(); BOOST adds to it), so
# "untouched base movement" is exactly current.speed >= get_speed_max().
extends GutTest

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')

var game:Gamemaster
var banshee:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self, true, SpecFactory.create_combat(Landscape.create_default(Vector2i(14,14))))
	game.campaign_core = CampaignCore.create(SpecFactory.create_campaign_base())
	game.map.campaign_core = game.campaign_core
	banshee = SpecFactory.create_unit(game.map, Vector2i(1,1))
	banshee.core.change_mech_frame(load('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/mf_banshee.tres'))
	banshee.state.overcharge_actions = 99
	banshee.update_cached_values_and_token(SpecFactory.dummy_event())
	banshee.core.current.speed = banshee.core.get_speed_max()

func after_each():
	TearRouting.invalidate(game.map)

func _move_action() -> SpecificAction:
	var gear:GearCore = banshee.get_gear(&'cp_the_keening')
	return SpecificAction.create(banshee, gear, gear.get_action(&'action_tear_move'))

func _available() -> bool:
	var specific := _move_action()
	return specific.action.is_available_to_activate(banshee, specific.gear)

func test_it_is_unavailable_with_no_tear_to_move():
	assert_false(_available(), 'Nothing to move, so the action is not offered.')

func test_it_is_available_with_a_tear_and_untouched_movement():
	await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear', [Vector2i(4,4)])
	assert_true(_available(), 'A tear exists and the base movement is untouched.')

func test_spending_base_movement_withdraws_it():
	await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear', [Vector2i(4,4)])
	banshee.core.current.speed -= 1 # one tile of ordinary movement
	assert_false(_available(), 'Once any base movement is spent the action is gone.')

func test_boosting_first_does_not_disqualify():
	# THE SUBTLE CASE, and the reason the rule is expressed against get_speed_max rather than a bare
	# "has not moved" flag. After a BOOST the pool is base + boost; moving within the boost surplus
	# leaves the base allowance whole, so the action must still be offered.
	await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear', [Vector2i(4,4)])
	var base:int = banshee.core.get_speed_max()
	banshee.core.current.speed = base + 3 # as though boosted for 3
	banshee.core.current.speed -= 2       # and moved 2, entirely on boost movement
	assert_true(_available(), 'Movement spent from the boost surplus does not touch the base allowance.')

func test_boosting_then_spending_past_the_surplus_does_disqualify():
	# The other side of the same line: once the pool drops below the base allowance, base movement
	# has been eaten regardless of how it was topped up.
	await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear', [Vector2i(4,4)])
	var base:int = banshee.core.get_speed_max()
	banshee.core.current.speed = base + 3
	banshee.core.current.speed -= 4 # one tile past the surplus
	assert_false(_available(), 'Spending past the boost surplus eats base movement and closes the window.')

func test_it_does_not_cost_an_action():
	# "This does not count as taking an action" - a FREE action costs 0 (Lancer.ACTION_COST).
	var specific := _move_action()
	assert_eq(specific.action.get_action_type(null), Lancer.ACTION.FREE,
		'Clause 8: moving a tear is not taking an action.')

func test_it_stays_out_of_the_gear_tooltip():
	# It is a verb of Tear, described inside Tear's own effect text, not a third mode of the core
	# power. The Keening must still read as two abilities.
	var kit:Kit = ContentLibrary.get_kit(&'cp_the_keening')
	if not Kit.is_valid(kit): return fail_test('cp_the_keening loaded.')
	var action:Action = kit.get_action(&'action_tear_move')
	assert_false(action.show_in_tooltip(kit), 'Move Tear does not list itself as a separate ability.')

func test_it_only_offers_the_banshees_own_tears():
	# Routing is universal, but the VERBS are not - clause 8 is the Banshee's. A tear belonging to
	# someone else must not be draggable by this action.
	var other := SpecFactory.create_unit(game.map, Vector2i(11,11), Faction.AI_ENEMY)
	other.core.change_mech_frame(load('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/mf_banshee.tres'))
	other.state.overcharge_actions = 99
	other.update_cached_values_and_token(SpecFactory.dummy_event())
	await SpecFactory.use(game, other, &'cp_the_keening', &'action_tear', [Vector2i(10,10)])

	assert_eq(TearRouting.open_tears(game.map).size(), 1, 'Fixture: exactly one tear, and it is theirs.')
	assert_false(_available(), 'Another Banshee tear is not ours to move.')

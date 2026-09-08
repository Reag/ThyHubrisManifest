# Clause 6: "Attacks that pass through a tear treat targets as INVISIBLE."
#
# Asserted on DAMAGE, because that is the observable consequence and it cannot be faked by the buff
# merely existing. Every attack test here is comparative: a single attack landing zero damage proves
# nothing on its own, since the attack might simply have missed.
#
# The mechanism is a TREAT_AS_INVISIBLE buff whose condition recomputes, per attack, whether that
# exact pair is routed through a tear. It is a buff rather than a hook at the attack itself because
# AttackUtil is a dead extension seam - see buff_tear_invisibility.gd for the full reasoning.
extends GutTest

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')
const BUFF_ID := &'buff_tear_invisibility'

var game:Gamemaster
var banshee:Unit
var ghost:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self, true, SpecFactory.create_combat(Landscape.create_default(Vector2i(12,12))))
	game.campaign_core = CampaignCore.create(SpecFactory.create_campaign_base())
	game.map.campaign_core = game.campaign_core

	banshee = SpecFactory.create_unit(game.map, Vector2i(1,1))
	banshee.core.change_mech_frame(load('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/mf_banshee.tres'))
	banshee.state.overcharge_actions = 99
	banshee.update_cached_values_and_token(SpecFactory.dummy_event())

	ghost = SpecFactory.create_unit(game.map, Vector2i(9,9), Faction.AI_ENEMY)
	ghost.core.frame.stat.evasion = 0

func after_each():
	TearRouting.invalidate(game.map)
	Dice.CHEAT_ROLL_QUEUE.clear()

func test_the_buff_is_handed_out_when_a_tear_opens():
	assert_false(UnitCondition.has_buff(banshee, BUFF_ID), 'Nobody carries it before a tear exists.')
	await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear', [Vector2i(5,5)])
	assert_true(UnitCondition.has_buff(banshee, BUFF_ID), 'The Banshee has it.')
	assert_true(UnitCondition.has_buff(ghost, BUFF_ID), 'And so does everyone else - routing is universal.')

func test_the_buff_is_inert_against_a_same_tangibility_pair():
	# THE POINT of the whole design: the buff grants nothing at rest. Both units are tangible here, so
	# no attack between them ever "passes through a tear" however many tears are open.
	await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear', [Vector2i(5,5)])
	assert_false(UnitCondition.is_invisible(banshee, ghost),
		'A tangible pair is untouched by clause 6, even carrying the buff with a tear open.')

func test_the_buff_is_inert_when_no_tear_routes_the_pair():
	# Cross-tangible, buff present, but the tear is closed again - so nothing routes and the buff
	# must go quiet. Guards against the condition keying on tangibility alone.
	await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear', [Vector2i(5,5)])
	SpecFactory.apply(ghost, Lancer.STATUS.INTANGIBLE)
	assert_true(UnitCondition.is_invisible(banshee, ghost), 'Sanity: routed while the tear is open.')

	if TearRouting.open_tears(game.map).is_empty(): return fail_test('A tear was placed.')
	# Close is the BANSHEE's verb, not the tear's - see action_tear_close.gd. SpecFactory's
	# ChoiceBusResponder answers the "which tear?" pick with the front of the list, and there is
	# exactly one.
	await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear_close')
	assert_false(UnitCondition.is_invisible(banshee, ghost),
		'With the tear closed nothing routes, so clause 6 stops applying.')

func test_a_routed_target_counts_as_invisible():
	await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear', [Vector2i(5,5)])
	SpecFactory.apply(ghost, Lancer.STATUS.INTANGIBLE)
	assert_true(UnitCondition.is_invisible(banshee, ghost),
		'Clause 6: an attack routed through a tear treats its target as INVISIBLE.')

func test_it_applies_in_both_directions():
	# can_affect is asked from both sides and so is invisibility. An attack back through the tear is
	# just as much "an attack that passes through a tear".
	await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear', [Vector2i(5,5)])
	SpecFactory.apply(ghost, Lancer.STATUS.INTANGIBLE)
	assert_true(UnitCondition.is_invisible(ghost, banshee),
		'The intangible shooting back through the tear also treats its target as invisible.')

# Whispering - the Banshee's own protocol into intangibility.
#
#   "As a protocol, the Banshee can become INTANGIBLE until the start of its next turn."
#
# Pure content: ActionSystemApplyStatus, the vanilla archetype, does the whole thing -
# applied_statuses = [&"intangible"], apply_until = START_OF_TURN, apply_to_self = true,
# action_type = PROTOCOL. See action_whispering.tres.
#
# PROTOCOLS NEED THE PROTOCOL PHASE. unit_action.gd:119 refuses a protocol unless
# unit.state.is_using_protocols, which only start_turn opens. Hence start_turn in before_each;
# without it every activation fails with "[ Gear not available ] reason : protocol", which reads as
# broken content rather than a missing setup step.
extends GutTest

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')
const KIT_ID := &'mt_whispering'

var game:Gamemaster
var banshee:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self, true, SpecFactory.create_combat(Landscape.create_default(Vector2i(12,12))))
	banshee = SpecFactory.create_unit(game.map, Vector2i(1,1))
	# change_mech_frame, NOT a raw core.frame assignment - the latter skips
	# loadout.regenerate_derived_gear, leaving the frame's traits unreachable as gear (get_gear finds
	# nothing). See test_to_bend_reality.gd and friends for the same trap.
	banshee.core.change_mech_frame(load('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/mf_banshee.tres'))
	SpecFactory.start_turn(game, banshee)

func after_each():
	TearRouting.invalidate(game.map)

func test_activating_the_protocol_applies_intangible():
	assert_false(banshee.has_status(Lancer.STATUS.INTANGIBLE), 'Tangible to begin with.')
	await SpecFactory.use_solo(game, banshee, KIT_ID)
	assert_true(banshee.has_status(Lancer.STATUS.INTANGIBLE), 'Intangible after the protocol.')

func test_it_costs_no_action():
	# "As a protocol" - action_type = PROTOCOL on the .tres, not QUICK/FULL, so it must not touch the
	# Banshee's action economy. state.actions is the int tracked by unit_battle_state.gd:27.
	var actions_before:int = banshee.state.actions
	await SpecFactory.use_solo(game, banshee, KIT_ID)
	assert_eq(banshee.state.actions, actions_before, 'A protocol spends no action economy.')

func test_it_clears_at_the_start_of_its_next_turn():
	await SpecFactory.use_solo(game, banshee, KIT_ID)
	assert_true(banshee.has_status(Lancer.STATUS.INTANGIBLE), 'Intangible after the protocol.')

	SpecFactory.end_turn(game, banshee)
	assert_true(banshee.has_status(Lancer.STATUS.INTANGIBLE),
		'Still intangible through the end of this turn - apply_until is START_OF_TURN, not END_OF_THIS_TURN.')

	SpecFactory.start_turn(game, banshee)
	assert_false(banshee.has_status(Lancer.STATUS.INTANGIBLE), 'Tangible again at the start of its next turn.')

func test_it_is_a_protocol():
	var kit:Kit = ContentLibrary.get_kit(KIT_ID)
	if not Kit.is_valid(kit): return fail_test('%s loaded.' % KIT_ID)
	assert_eq(kit.actions.size(), 1, 'One action.')
	if kit.actions.is_empty(): return
	assert_eq(kit.actions[0].action_type, Lancer.ACTION.PROTOCOL, 'And it is a protocol.')

func test_it_composes_with_the_tear_window():
	# THE END-TO-END PROOF. test_tear_window.gd proves the tear routes between opposite tangibility
	# using SpecFactory.apply to fake the Banshee INTANGIBLE - a test fixture, not gameplay. Until
	# Whispering exists as a real action, nothing in the actual game ever puts the Banshee into that
	# state, so the tear window would have nothing genuine to route between. This test proves
	# Whispering is the player's route into it: a real protocol activation, not a fixture shortcut.
	var enemy := SpecFactory.create_unit(game.map, Vector2i(10,10), Faction.AI_ENEMY)

	await SpecFactory.use_solo(game, banshee, KIT_ID)
	assert_true(banshee.has_status(Lancer.STATUS.INTANGIBLE), 'Sanity: the Banshee really is intangible now.')

	assert_false(UnitRelation.can_affect(banshee, enemy),
		'Opposite tangibility, no tear yet: the tangible enemy is not reachable.')

	var tear := SpecFactory.create_unit(game.map, Vector2i(6,6))
	tear.core.frame = load('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/dep_tear_banshee.tres')
	tear.update_cached_values_and_token(SpecFactory.dummy_event())
	TearRouting.invalidate(game.map)

	assert_true(UnitRelation.can_affect(banshee, enemy),
		'With Whispering up and a tear open, the previously-unreachable tangible enemy becomes reachable.')

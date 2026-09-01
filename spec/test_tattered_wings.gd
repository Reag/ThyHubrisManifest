# Tattered Wings - the Erinyes' hover protocol.
#
#   "As a protocol, the Erinyes may take |1 HEAT| to hover until the start of its next turn."
#
# Two things worth knowing before reading these.
#
# HOVER IS NOT FLIGHT in this engine. MovementType.hovering does exactly one thing
# (unit_condition.gd:302): it stops a FLYING unit that did not move from falling at the end of its
# turn. Being airborne is the separate STATUS.FLYING, applied by the shared action_takeoff, which
# the Erinyes does not have. This trait is deliberately implemented to the letter of the book - it
# buys the hover property and eva, and nothing here takes off - so until a flight source is added to
# the frame the hovering half has no observable effect in play. The eva half does.
#
# PROTOCOLS NEED THE PROTOCOL PHASE. unit_action.gd:119 refuses a protocol unless
# unit.state.is_using_protocols, which start_turn opens. Hence start_turn in before_each; without it
# every activation fails with "[ Gear not available ] reason : protocol", which looks exactly like
# broken content.
extends GutTest

const KIT_ID := &'mt_tattered_wings'

var game:Gamemaster
var unit:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	unit = SpecFactory.create_unit(game.map)
	unit.core.equip_system(KIT_ID)
	SpecFactory.start_turn(game, unit)

func test_the_protocol_costs_one_heat():
	unit.core.current.heat = 0
	await SpecFactory.use_solo(game, unit, KIT_ID)
	assert_eq(unit.core.current.heat, 1, 'Hovering cost exactly 1 heat.')

func test_it_grants_hover():
	assert_false(MovementType.create(unit).hovering, 'Not hovering to begin with.')
	await SpecFactory.use_solo(game, unit, KIT_ID)
	assert_true(MovementType.create(unit).hovering, 'Hovering after the protocol.')

func test_it_grants_eva():
	# Mirrors mt_maneuverability_jets, which pairs the same hover buff with eva.
	assert_false(unit.has_status(&'eva'), 'No eva to begin with.')
	await SpecFactory.use_solo(game, unit, KIT_ID)
	assert_true(unit.has_status(&'eva'), 'Eva while hovering.')

func test_hover_lasts_until_the_start_of_its_next_turn():
	await SpecFactory.use_solo(game, unit, KIT_ID)
	assert_true(MovementType.create(unit).hovering, 'Hovering after the protocol.')

	SpecFactory.end_turn(game, unit)
	assert_true(MovementType.create(unit).hovering, 'Still hovering through the end of this turn.')

	SpecFactory.start_turn(game, unit)
	assert_false(MovementType.create(unit).hovering, 'Gone at the start of its next turn.')

func test_it_cannot_be_paid_for_twice_while_already_hovering():
	# can_reapply = false on the action. Using a protocol does not close the protocol phase
	# (unit_action.gd:285), so the action economy would happily allow a second activation - this
	# guards that the player cannot burn a second heat re-buying a buff they already have.
	unit.core.current.heat = 0
	await SpecFactory.use_solo(game, unit, KIT_ID)
	await SpecFactory.use_solo(game, unit, KIT_ID)
	assert_eq(unit.core.current.heat, 1, 'Second activation was not available, so no second heat.')

func test_it_is_a_protocol():
	var kit:Kit = ContentLibrary.get_kit(KIT_ID)
	if not Kit.is_valid(kit): return fail_test('%s loaded.' % KIT_ID)
	assert_eq(kit.actions.size(), 1, 'One action.')
	if kit.actions.is_empty(): return
	assert_eq(kit.actions[0].action_type, Lancer.ACTION.PROTOCOL, 'And it is a protocol.')

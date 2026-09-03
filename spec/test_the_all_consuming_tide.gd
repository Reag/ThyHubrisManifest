# The All-Consuming Tide - the Kraken's core power activation.
#
#   "For the rest of the |scene|, the Kraken counts as both tangible and |INTANGIBLE|, and characters
#    you have |GRAPPLED| are |INTANGIBLE| during their turn. Characters of your choice are pulled 1
#    space toward you at the beginning of their turn. Hostile characters within your |SENSORS| treat
#    movement away from you as |difficult terrain|. If a character collides with you, you may expend
#    your |OVERWATCH| to attempt to |Grapple| the character as a |reaction|."
#
# Design notes live in D:\DEV\lancer-tactics-claude\specs\2026-09-02-kraken-design.md.
#
# THESE SPECS ASSERT THE RULES, NOT THE MECHANISM. The tangibility clauses are a workaround for an
# engine limitation and are meant to be deleted when a future modkit makes the faithful reading
# possible. Every assertion here is phrased as what the ability does - "the Kraken can attack an
# intangible unit" - so a faithful reimplementation passes this file unchanged. Do not rewrite these
# to assert that can_affect returned a particular value.
extends GutTest

const CORE_POWER_ID := &'cp_the_endless_black_sea'
const TIDE_ACTION := &'action_the_all_consuming_tide'
const TIDE_BUFF_ID := &'buff_the_all_consuming_tide'

const KRAKEN_TILE := Vector2i(0, 0)

var game:Gamemaster
var kraken:Unit
var gear:GearCore

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	kraken = SpecFactory.create_unit(game.map, KRAKEN_TILE)
	gear = kraken.core.equip_system(CORE_POWER_ID)
	# A core power action reports itself unavailable without this (unit_action.gd:145).
	kraken.core.has_core_power = true

func _raise_the_tide() -> void:
	await SpecFactory.use(game, kraken, CORE_POWER_ID, TIDE_ACTION)

func _tide_is_up() -> bool:
	return UnitCondition.has_buff(kraken, TIDE_BUFF_ID)

# ============================== raising it ==============================

func test_raising_the_tide_marks_the_kraken_for_the_rest_of_the_scene():
	assert_false(_tide_is_up(), 'It starts down.')
	await _raise_the_tide()
	assert_true(_tide_is_up(), 'The Tide is up.')

func test_raising_the_tide_spends_the_core_power():
	await _raise_the_tide()
	assert_false(kraken.core.has_core_power, 'The core power is spent.')

func test_the_tide_cannot_be_raised_twice():
	await _raise_the_tide()
	var action:Action = ContentLibrary.get_kit(CORE_POWER_ID).get_action(TIDE_ACTION)
	if not Action.is_valid(action): return fail_test('%s is on the kit.' % TIDE_ACTION)
	assert_false(action.is_available_to_activate(kraken, gear), 'It cannot be raised again.')

func test_the_tide_dies_with_the_kraken():
	# until = MANUAL means "rest of the scene", which must not outlive its owner. The failure this
	# guards is silent and permanent - see the design doc's risks - so it is pinned rather than
	# assumed from the default.
	await _raise_the_tide()
	assert_true(_tide_is_up(), 'Up while it lives.')
	await game.execute_event(&'event_unit_die', {unit = kraken})
	assert_false(_tide_is_up(), 'And gone with it.')

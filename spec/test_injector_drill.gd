# The Injector Drill - a heavy melee weapon whose charges are a fuel tank, not ammunition.
#
#   "You may attack with this weapon without expending or requiring charges, and it can be destroyed
#    even with no charges remaining."
#
# consumes_charges -> false is BOTH halves of the first sentence: Action.consumes_charges (action.gd:108)
# is read at unit_action.gd:153 (refuse with REASON.NO_CHARGES when empty - "without requiring") and at
# unit_action.gd:274 (spend one on every use - "without expending"). Task 2 spends them by hand instead.
#
# THE SECOND SENTENCE IS NOT IMPLEMENTED AND CANNOT BE FROM A MOD. UnitPrinter.get_destructable_gear
# (unit_printer.gd:311-320) requires gear.has_charges_left(), so a drill at 0 charges is not offered as
# a destruction target. test_a_drill_at_zero_charges_is_not_destructible_yet ASSERTS THE WRONG
# BEHAVIOUR on purpose, so that the day a unit_printer.gd_ext.gd probe closes the gap, this test fails
# loudly instead of the gap being forgotten (design section 5; memory lancer-tactics-dead-extension-seams
# lists unit_printer.gd as an unproven seam).
#
# DICE (plan section B7): a weapon attack crits on a natural 20 and doubles its damage roll, so this
# file seeds a uniform 4 - a hit against evasion -10, never a crit, and every damage die a 4, making
# 1d6+3 exactly 7 however many dice the roll pulls. after_each clears the leftovers.
extends GutTest

const DRILL := &'mw_injector_drill'
const DRILL_ACTION := &'action_injector_drill'

var game:Gamemaster
var draugr:Unit
var target:Unit
var drill:GearCore

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	draugr = SpecFactory.create_unit(game.map, Vector2i(0, 0), Faction.PLAYER)
	drill = draugr.core.equip_system(DRILL)
	draugr.core.full_repair()
	target = SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	target.core.frame.stat.evasion = -10 # any d20 lands; the roll is never the variable
	target.core.frame.stat.armor = 0
	target.core.frame.stat.health = 40
	target.core.full_repair()

func after_each():
	Dice.CHEAT_ROLL_QUEUE.clear()

func attack(victim:Unit) -> void:
	Dice.CHEAT_ROLL_QUEUE.append_array([4, 4, 4, 4, 4, 4])
	await SpecFactory.use(game, draugr, DRILL, DRILL_ACTION, victim)

func drill_action() -> ActionAttackWeapon:
	return drill.get_action(DRILL_ACTION) as ActionAttackWeapon

func drill_specific() -> SpecificAction:
	return SpecificAction.create(draugr, drill, drill_action())

func test_the_drill_deals_1d6_plus_3_kinetic():
	assert_true(GearCore.is_valid(drill), 'Fixture: the drill is equipped.')
	var before:int = target.core.current.health
	await attack(target)
	assert_eq(before - target.core.current.health, 7, 'A 4 on the damage die, plus 3.')
	assert_eq(drill_action().get_damage_type(drill), Lancer.DAMAGE_TYPE.KINETIC, 'Kinetic.')

func test_the_drill_is_a_heavy_melee_weapon():
	var action := drill_action()
	assert_true(action.is_weapon_size(Lancer.WEAPON_SIZE.HEAVY), 'Heavy.')
	assert_true(action.is_weapon_type(Lancer.WEAPON_TYPE.MELEE), 'Melee.')
	assert_eq(action.get_action_type(drill_specific()), Lancer.ACTION.QUICK, 'A heavy weapon is a quick action.')

func test_the_drill_reaches_two_tiles_and_no_further():
	# get_target_range returns threat_distance for a melee weapon with threat > 0
	# (action_attack_weapon.gd:198-201).
	var specific := drill_specific()
	assert_eq(drill_action().get_target_range(specific), 2, 'Threat 2.')
	var in_range := UnitTargeting.get_tiles_in_range(specific)
	assert_true(in_range.has(Vector2i(2, 0)), 'Two tiles away is reachable.')
	assert_false(in_range.has(Vector2i(3, 0)), 'Three is not.')

func test_the_drill_starts_with_four_charges():
	assert_eq(drill.charges_current, 4, 'charges_max = 4, and full_repair fills it.')

func test_attacking_does_not_spend_a_charge():
	# "without expending charges" - unit_action.gd:274 only spends when consumes_charges is true.
	await attack(target)
	assert_eq(drill.charges_current, 4, 'Still four.')

func test_the_drill_attacks_with_no_charges_left():
	# "without requiring charges" - unit_action.gd:153 would otherwise refuse with REASON.NO_CHARGES.
	drill.charges_current = 0
	var before:int = target.core.current.health
	await attack(target)
	assert_eq(before - target.core.current.health, 7, 'An empty drill still swings.')

func test_a_drill_with_charges_is_destructible():
	assert_eq(UnitPrinter.get_destructable_gear([drill]).size(), 1, 'A licensed weapon can be shot off.')

func test_a_drill_at_zero_charges_is_not_destructible_yet():
	# DELIBERATELY ASSERTING THE GAP (see this file's header). The rules text promises the opposite;
	# unit_printer.gd:311-320 gates destructability on has_charges_left() and no mod-side seam has been
	# proven to reach it. If this test ever fails, the gap is CLOSED - delete the test, do not "fix" it.
	drill.charges_current = 0
	assert_eq(UnitPrinter.get_destructable_gear([drill]).size(), 0,
		'Known gap: the engine will not offer an empty Limited weapon as a destruction target.')

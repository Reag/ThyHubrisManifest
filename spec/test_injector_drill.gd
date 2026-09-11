# The Injector Drill - a heavy melee weapon whose charges are a fuel tank, not ammunition.
#
#   "You may attack with this weapon without expending or requiring charges, and it can be destroyed
#    even with no charges remaining."
#
# consumes_charges -> false is BOTH halves of the first sentence: Action.consumes_charges (action.gd:108)
# is read at unit_action.gd:153 (refuse with REASON.NO_CHARGES when empty - "without requiring") and at
# unit_action.gd:274 (spend one on every use - "without expending"). Task 2 spends them by hand instead.
#
# THE SECOND SENTENCE lives in res/engine/character/unit/service/unit_printer.gd_ext.gd: vanilla's
# UnitPrinter.get_destructable_gear (unit_printer.gd:311-320) requires gear.has_charges_left(), and
# the extension whitelists the drill past that check. test_a_drill_at_zero_charges_is_still_destructible
# is the liveness probe for that seam (proven 2026-09-10 on 1.4.0; it needs mod_main.gd's
# EXTENDED_AUTOLOADS reload), and the Stub Cannon test beside it proves the whitelist changes nothing
# else.
#
# DICE (plan section B7): a weapon attack crits on a natural 20 and doubles its damage roll, so this
# file seeds a uniform 4 - a hit against evasion -10, never a crit, and every damage die a 4, making
# 1d6+3 exactly 7 however many dice the roll pulls. after_each clears the leftovers.
#
# TASK 2 ADDED an on-hit confirm ("expend a charge for a free tech?") to this same action, and
# SpecFactory's default responder auto-answers every yesno with `true`. Left alone, that would make
# this file's basic-loadout target (which always has ms_fragment_signal, a valid quick tech) silently
# accept the offer and spend a charge on ANY successful swing - which is not what this file is about;
# the on-hit rider gets its own coverage in test_injector_drill_tech.gd. before_each declines it so
# these tests stay about consumes_charges alone, exactly as they were written for Task 1.
extends GutTest

const FrameIsolation := preload('res://testkit/frame_isolation.gd')
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
	FrameIsolation.isolate_frame(target)
	target.core.frame.stat.evasion = -10 # any d20 lands; the roll is never the variable
	target.core.frame.stat.armor = 0
	target.core.frame.stat.health = 40
	target.core.full_repair()
	SpecFactory.current_responder.chosen_yesnos = false # decline Task 2's on-hit offer; see header

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

func test_a_drill_at_zero_charges_is_still_destructible():
	# "it can be destroyed even with no charges remaining." Vanilla's UnitPrinter.get_destructable_gear
	# (unit_printer.gd:311-320) gates on has_charges_left(), so this assertion can ONLY pass if the
	# mod's unit_printer.gd_ext.gd override is live - it is the liveness probe for that seam as well as
	# the rules test (memory lancer-tactics-dead-extension-seams: the install log proves nothing).
	drill.charges_current = 0
	assert_eq(UnitPrinter.get_destructable_gear([drill]).size(), 1,
		'An empty drill is still a destruction target.')

func test_other_limited_gear_at_zero_charges_stays_non_destructible():
	# The override is a whitelist, not a rule change: vanilla Limited gear keeps vanilla behaviour.
	var stub:GearCore = draugr.core.equip_system(&'mw_stub_cannon')
	stub.charges_current = 0
	assert_eq(UnitPrinter.get_destructable_gear([stub]).size(), 0,
		'A vanilla Limited weapon with no charges is not offered, exactly as before.')
	assert_eq(UnitPrinter.get_destructable_gear([drill, stub]).size(), 1, 'Only the drill.')

# The Injector Drill's free tech offer, exercised with a REAL choice at the table: a Draugr carrying
# BOTH the Injector Drill and Quarantine can spend the drill's charge on Isolation instead of the
# basic Fragment Signal every mech has. test_injector_drill_tech.gd only ever has the one option
# (a plain unit's only tech is Fragment Signal), so nothing there proves the free tech can be a piece
# of the Draugr's OWN kit, or that doing so is attributed and rate-limited correctly.
#
# WHY THE RESPONDER PICKS ISOLATION WITH NO EXTRA CONFIGURATION. free_tech_options's player prompt is
# NOT a multiple_choice/brochure request - CommonActionUtil.choose_and_use routes a player-controlled
# unit with more than one option through choice_bus.choose_from_gear_for (common_action_util.gd:672-679),
# which opens a ChoiceBus.TYPE.gear request (choice_bus.gd:57,118-119). SpecFactory.ChoiceBusResponder's
# choose_gear (spec_factory.gd:391,516-521) answers EVERY gear request with possible_actions[0] -
# unconditionally; it does not consult chosen_multiple_choice_index, and mod_choice_responder.gd does
# not override it. So the pick is whatever free_tech_options put first, and that is a fact about
# LOADOUT ORDER, not about this test:
#   - free_tech_options (action_injector_drill.gd:109-125) builds its first batch from
#     UnitRelation.get_tech_attacks_that_can_react_against, which reads
#     LoadoutCore.get_all_tech_attacks (loadout_core.gd:527-531): EQUIPPED tech attacks first, the
#     BASIC ones (Fragment Signal) last.
#   - ms_quarantine.tres lists its own two actions as [Isolation, Lockdown]
#     (Kit.get_tech_attack_actions preserves .tres array order, kit.gd:136-139).
# So the built list is [Isolation, Lockdown, Fragment Signal] and array[0] is Isolation - no
# multiple_choice_queue entry needed. Every test below still asserts on the RESULT (which buff landed)
# rather than trusting that chain blind, so a modkit reorder that silently flipped the pick would fail
# loudly here instead of passing for the wrong reason.
extends GutTest

const FrameIsolation := preload('res://testkit/frame_isolation.gd')
const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')

const DRILL := &'mw_injector_drill'
const DRILL_ACTION := &'action_injector_drill'
const QUARANTINE := &'ms_quarantine'
const ISOLATION := &'action_isolation'
const ISOLATION_BUFF := &'buff_isolation'
const LOCKDOWN_BUFF := &'buff_lockdown'
const ISOLATION_USAGE_GROUP := &'quarantine_isolation' ## action_isolation.tres' usage_group

var game:Gamemaster
var draugr:Unit
var target:Unit
var drill:GearCore
var quarantine:GearCore

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	draugr = SpecFactory.create_unit(game.map, Vector2i(0, 0), Faction.PLAYER)
	drill = draugr.core.equip_system(DRILL)
	quarantine = draugr.core.equip_system(QUARANTINE)
	draugr.core.full_repair()
	target = _victim_at(Vector2i(1, 0))

func after_each():
	Dice.CHEAT_ROLL_QUEUE.clear()

func _victim_at(tile:Vector2i) -> Unit:
	var unit := SpecFactory.create_unit(game.map, tile, Faction.AI_ENEMY)
	FrameIsolation.isolate_frame(unit)
	unit.core.frame.stat.evasion = -10 # the drill's own attack lands on any roll
	unit.core.frame.stat.edef = -10    # so does the free tech's own attack roll
	unit.core.frame.stat.armor = 0
	unit.core.frame.stat.health = 40
	unit.core.frame.stat.heat = 30
	unit.core.full_repair()
	unit.core.current.heat = 0
	return unit

## Accepts the drill's "may expend a charge" confirmation, then swings. Dice generous: the weapon
# attack and the queued tech attack both pull off the same queue (test_injector_drill_tech.gd's
# comment on drill_with explains why 8 is plenty).
func drill_with(victim:Unit) -> void:
	SpecFactory.current_responder.chosen_yesnos = true
	Dice.CHEAT_ROLL_QUEUE.append_array([4, 4, 4, 4, 4, 4, 4, 4])
	await SpecFactory.use(game, draugr, DRILL, DRILL_ACTION, victim)

func locks_on(unit:Unit, buff_id:StringName) -> Array[BuffCore]:
	return UnitCondition.get_buffs(unit, buff_id)

func test_isolation_through_the_drill_locks_the_target_via_quarantine_not_the_drill():
	assert_true(locks_on(target, ISOLATION_BUFF).is_empty(), 'Not locked before the drill fires (positive control).')
	await drill_with(target)
	assert_eq(locks_on(target, ISOLATION_BUFF).size(), 1, 'Isolation landed - the free tech WAS a piece of the Draugr\'s own kit.')
	assert_true(locks_on(target, LOCKDOWN_BUFF).is_empty(), 'Not Lockdown - the other half of Quarantine was not what got picked.')
	assert_false(target.has_status(Lancer.STATUS.IMPAIRED), 'Not basic Fragment Signal either.')
	var lock:BuffCore = locks_on(target, ISOLATION_BUFF).front()
	assert_eq(lock.from_gear, quarantine.persistent_id, 'Attributed to QUARANTINE, the gear that actually owns Isolation...')
	assert_ne(lock.from_gear, drill.persistent_id, '...never to the drill that merely offered it for free.')

func test_isolation_through_the_drill_applies_two_infection():
	assert_eq(Infection.count(target), 0, 'Uninfected before the drill fires (positive control).')
	await drill_with(target)
	assert_eq(Infection.count(target), 2, "Isolation's own two Infection - not the drill's own damage type.")

func test_isolation_through_the_drill_spends_exactly_one_drill_charge():
	await drill_with(target)
	assert_eq(drill.charges_current, 3, 'One charge, not two (drill swing is free per action_injector_drill.gd), and not zero.')

func test_isolation_through_the_drill_counts_against_isolations_own_per_round_limit():
	# The free activation has to go through the SAME per-round bookkeeping a direct Invade would
	# (GearCore.increment_action_usage, gear_core.gd:171-177) - otherwise a Draugr could launder every
	# Isolation through the drill and dodge "1/round" entirely. Proven two ways in one test: the raw
	# counter, and a real second attempt actually refused (the same shape as
	# test_isolation.gd's test_isolation_is_once_per_round).
	await drill_with(target)
	assert_eq(quarantine.get_uses_this_round_alt(ISOLATION_USAGE_GROUP), 1, 'Recorded as one real use of Isolation.')
	Dice.CHEAT_ROLL_QUEUE.append(20)
	await SpecFactory.use(game, draugr, QUARANTINE, ISOLATION, target)
	assert_eq(Infection.count(target), 2, 'The direct second use in the same round was refused - still just the first two Infection.')

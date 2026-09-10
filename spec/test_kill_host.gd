# Kill Host - the PESTILENCE-class NHP's protocol.
#
#   "Take 2 heat. All targets with INFECTION within RANGE 5 of you take AP ENERGY equal to 2 + twice
#    their current INFECTION. Then choose one of the following:
#    - Targets become IMPAIRED until the end of their next turn, or JAMMED if they have at least 3
#      INFECTION.
#    - Targets become SLOWED until the end of their next turn, or PRONE and IMMOBILIZED if they have
#      at least 3 INFECTION.
#    Targets then clear all INFECTION."
#
# ALLIES ARE TARGETS TOO (design decision D5): the row says "all targets with INFECTION", and the
# frame does not care whose side you are on. get_characters_within does no faction filtering, so this
# is the default rather than something the code has to arrange.
#
# ORDER OF OPERATIONS (plan decision D8). Damage, then the choice, then the statuses, then the clear:
#   - the damage is the only step the rules put before the choice, and a target it kills is not a
#     target for anything after it - hence test_a_target_killed_by_the_damage_is_skipped;
#   - the INFECTION counts are SNAPSHOTTED once, before the first damage event, and the same
#     snapshot feeds both the damage arithmetic and the ">= 3" escalation. Reading the count twice
#     would make the escalation depend on whatever a reaction to the damage did in between;
#   - the prompt opens only when at least one target survived. Asking the player to choose an effect
#     for a pile of wrecks is a bug report waiting to happen - test_no_infected_targets_means_no_prompt.
#
# A PROTOCOL NEEDS SpecFactory.start_turn FIRST. unit_action.gd refuses one unless
# state.is_using_protocols, which only the turn start opens; without it every activation dies with
# "[ Gear not available ] reason : protocol" in red and the assertions read as broken content
# (CLAUDE.md). A protocol is naturally 1/round with no override, because ACTION_COST[PROTOCOL] is 0
# and Action.get_per_round_hard_limit returns 1 for any naturally free action (action.gd:155-158).
#
# THE MAP IS 20x20 so "beyond Range 5" is a real distance and not Tile's 1000 sentinel (memory
# draugr-infection-engine-gotchas item 6). Infection.apply deals heat equal to the count, so every
# fixture raises frame.stat.heat and zeroes current.heat after infecting.
extends GutTest

const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')
const KillHost := preload('res://unpacked/Reag-ThyHubris/res/content/gear/horus/systems/ms_pestilence_class_nhp/action_kill_host.gd')
const PromptWatcher := preload('res://testkit/prompt_watcher.gd')

const NHP := &'ms_pestilence_class_nhp'
const IMPAIR := 0
const SLOW := 1

var game:Gamemaster
var draugr:Unit
var victim:Unit
var watcher:PromptWatcher

func before_each():
	game = SpecFactory.setup_gamemaster(self, false, SpecFactory.create_combat(Landscape.create_default(Vector2i(20, 20))))
	draugr = SpecFactory.create_unit(game.map, Vector2i(0, 0), Faction.PLAYER)
	draugr.core.frame.stat.heat = 20
	draugr.core.equip_system(NHP)
	draugr.core.full_repair()
	draugr.core.current.heat = 0
	victim = _unit_at(Vector2i(2, 0), Faction.AI_ENEMY)
	watcher = add_child_autoqfree(PromptWatcher.new())

func after_each():
	Dice.CHEAT_ROLL_QUEUE.clear()

func _unit_at(tile:Vector2i, faction:Faction.SIDE) -> Unit:
	var unit := SpecFactory.create_unit(game.map, tile, faction)
	unit.core.frame.stat.health = 60
	unit.core.frame.stat.heat = 20
	unit.core.frame.stat.armor = 0
	unit.core.full_repair()
	unit.core.current.heat = 0
	return unit

func _infect(unit:Unit, n:int) -> void:
	await Infection.apply(SpecFactory.dummy_event({unit = unit}), unit, n)
	unit.core.current.heat = 0

## A protocol needs the turn open. chosen_multiple_choice_index picks the menu answer.
func _fire(option:int = IMPAIR) -> void:
	SpecFactory.current_responder.chosen_multiple_choice_index = option
	await SpecFactory.start_turn(game, draugr)
	await SpecFactory.use_solo(game, draugr, NHP)

# ---------------------------------------------------------------- the protocol itself

func test_kill_host_is_a_protocol():
	var gear:GearCore = draugr.get_gear(NHP)
	assert_true(GearCore.is_valid(gear), 'Fixture: the NHP is equipped.')
	if not GearCore.is_valid(gear): return
	var action:Action = gear.get_solo_action()
	assert_true(action is ActionSystem, 'An ActionSystem.')
	var specific := SpecificAction.create(draugr, gear, action)
	assert_eq(action.get_action_type(specific), Lancer.ACTION.PROTOCOL, 'A protocol.')
	assert_eq(action.get_per_round_hard_limit(specific), 1, 'And therefore 1/round, with no override.')

func test_the_draugr_takes_two_heat():
	await _infect(victim, 1)
	await _fire()
	assert_eq(draugr.core.current.heat, 2, 'self_heat_dice = "2", spent by spend_actions.')

# ---------------------------------------------------------------- the damage

func test_an_infected_target_takes_two_plus_twice_its_infection():
	await _infect(victim, 3)
	var before:int = victim.core.current.health
	await _fire()
	assert_eq(before - victim.core.current.health, 8, '2 + 2 x 3.')

func test_one_infection_is_four_damage():
	await _infect(victim, 1)
	var before:int = victim.core.current.health
	await _fire()
	assert_eq(before - victim.core.current.health, 4, '2 + 2 x 1.')

func test_the_damage_ignores_armor():
	victim.core.frame.stat.armor = 3
	victim.core.full_repair()
	victim.core.current.heat = 0
	await _infect(victim, 1)
	var before:int = victim.core.current.health
	await _fire()
	assert_eq(before - victim.core.current.health, 4, 'AP: all four land through Armor 3.')

func test_the_damage_is_energy():
	# A resistance keyed to ENERGY halves it; keyed to anything else it would not fire at all.
	# Infection 3 makes the damage 8, so the halved figure is unambiguous.
	var resist := BuffResistDamage.new()
	resist.to = Buff.TO.RESIST_DAMAGE
	resist.damage_types = [Lancer.DAMAGE_TYPE.ENERGY]
	UnitCondition.apply_buff(SpecFactory.dummy_event(), victim, resist)
	await _infect(victim, 3)
	var before:int = victim.core.current.health
	await _fire()
	assert_eq(before - victim.core.current.health, 4, 'Energy resistance halved the 8.')

func test_an_infected_ally_is_hit_too():
	# Design decision D5: "as written - allies included."
	var friend := _unit_at(Vector2i(0, 2), Faction.PLAYER)
	await _infect(friend, 1)
	await _infect(victim, 1)
	var before:int = friend.core.current.health
	await _fire()
	assert_eq(before - friend.core.current.health, 4, 'The plague does not check sides.')

func test_a_clean_character_is_untouched():
	var clean := _unit_at(Vector2i(1, 1), Faction.AI_ENEMY)
	await _infect(victim, 1)
	var before:int = clean.core.current.health
	await _fire()
	assert_eq(clean.core.current.health, before, 'No INFECTION, no detonation.')
	assert_false(clean.has_status(Lancer.STATUS.IMPAIRED), 'And no status either.')

func test_a_character_beyond_range_five_is_untouched():
	var distant := _unit_at(Vector2i(7, 0), Faction.AI_ENEMY)
	await _infect(distant, 2)
	await _infect(victim, 1)
	var before:int = distant.core.current.health
	await _fire()
	assert_eq(distant.core.current.health, before, 'Seven tiles is outside Range 5.')
	assert_eq(Infection.count(distant), 2, 'And its INFECTION is left alone.')

# ---------------------------------------------------------------- the choice

func test_the_prompt_offers_exactly_two_options():
	await _infect(victim, 1)
	await _fire()
	var menus := watcher.kinds(PromptWatcher.KIND.multiple_choice)
	assert_eq(menus.size(), 1, 'One menu.')
	if menus.is_empty(): return
	assert_eq(menus[0].choices.size(), 2, 'Two options.')
	assert_eq(menus[0].title, tr('gear.ms_pestilence_class_nhp.action_kill_host.name'), 'Titled Kill Host.')
	assert_ne(menus[0].choices[0].text, 'gear.ms_pestilence_class_nhp.action_kill_host.option_impair',
		'The option text is translated, not a raw key.')

func test_the_first_option_impairs():
	await _infect(victim, 2)
	await _fire(IMPAIR)
	assert_true(victim.has_status(Lancer.STATUS.IMPAIRED), 'Impaired.')
	assert_false(victim.has_status(Lancer.STATUS.JAMMED), 'Not jammed: fewer than 3 INFECTION.')

func test_three_infection_jams_instead():
	await _infect(victim, 3)
	await _fire(IMPAIR)
	assert_true(victim.has_status(Lancer.STATUS.JAMMED), 'Jammed at 3 or more.')
	assert_false(victim.has_status(Lancer.STATUS.IMPAIRED), 'Instead of impaired, not as well as.')

func test_the_second_option_slows():
	await _infect(victim, 2)
	await _fire(SLOW)
	assert_true(victim.has_status(Lancer.STATUS.SLOWED), 'Slowed.')
	assert_false(victim.has_status(Lancer.STATUS.PRONE), 'Not prone: fewer than 3 INFECTION.')

func test_three_infection_prones_and_immobilizes():
	await _infect(victim, 4)
	await _fire(SLOW)
	assert_true(victim.has_status(Lancer.STATUS.PRONE), 'Prone.')
	assert_true(victim.has_status(Lancer.STATUS.IMMOBILIZED), 'And immobilized.')
	assert_false(victim.has_status(Lancer.STATUS.SLOWED), 'Instead of slowed.')

func test_the_statuses_end_at_the_end_of_the_targets_next_turn():
	# until = END_OF_NEXT_TURN: turn_count rises on the HOLDER's own turn start
	# (unit_condition.gd:15-30) and the buff clears at turn_count >= 1 at any turn end (:33-49).
	await _infect(victim, 1)
	await _fire(IMPAIR)
	await SpecFactory.end_turn(game, draugr)
	assert_true(victim.has_status(Lancer.STATUS.IMPAIRED), 'The Draugr ending its turn does not end it.')
	await SpecFactory.pass_turn(game, victim)
	assert_false(victim.has_status(Lancer.STATUS.IMPAIRED), 'The end of the target next turn does.')

# ---------------------------------------------------------------- the aftermath

func test_infection_is_cleared_from_every_target():
	var friend := _unit_at(Vector2i(0, 2), Faction.PLAYER)
	await _infect(friend, 2)
	await _infect(victim, 3)
	await _fire()
	assert_eq(Infection.count(victim), 0, 'Cleared.')
	assert_eq(Infection.count(friend), 0, 'From the ally as well.')
	assert_eq(UnitCondition.get_buffs(victim, Infection.BUFF_ID).size(), 0, 'And the buff went with it.')

func test_a_target_killed_by_the_damage_is_skipped():
	# Structure damage rolls an unseeded structure-table d6 (memory item 9); a 6 is IMPAIRED, which
	# does not matter here because this unit is dying either way at structure 1.
	var doomed := _unit_at(Vector2i(1, 0), Faction.AI_ENEMY)
	doomed.core.frame.stat.health = 1
	doomed.core.frame.stat.structure = 1
	doomed.core.full_repair()
	doomed.core.current.heat = 0
	await _infect(doomed, 1)
	await _infect(victim, 1)
	Dice.CHEAT_ROLL_QUEUE.append(6)
	await _fire(IMPAIR)
	assert_false(Unit.is_valid(doomed) and doomed.is_on_map(), 'The 4 damage killed it.')
	assert_true(victim.has_status(Lancer.STATUS.IMPAIRED), 'And the survivor still took its status.')

func test_no_infected_targets_means_no_prompt():
	await _fire()
	assert_true(watcher.kinds(PromptWatcher.KIND.multiple_choice).is_empty(), 'Nothing to choose for.')
	assert_eq(draugr.core.current.heat, 2, 'The protocol still costs its 2 heat.')

func test_every_infected_target_dying_means_no_prompt():
	# Same shape as test_a_target_killed_by_the_damage_is_skipped, doubled: with TWO infected targets
	# and BOTH dying to the AP ENERGY damage, survivors ends up empty and activate() returns at :81
	# before choose_option ever runs. Structure damage rolls an unseeded structure-table d6 (memory
	# item 9); structure = 1 kills outright on either outcome, so the queued 6s just keep the roll
	# deterministic, one per doomed unit.
	var doomed_a := _unit_at(Vector2i(1, 0), Faction.AI_ENEMY)
	doomed_a.core.frame.stat.health = 1
	doomed_a.core.frame.stat.structure = 1
	doomed_a.core.full_repair()
	doomed_a.core.current.heat = 0
	var doomed_b := _unit_at(Vector2i(1, 1), Faction.AI_ENEMY)
	doomed_b.core.frame.stat.health = 1
	doomed_b.core.frame.stat.structure = 1
	doomed_b.core.full_repair()
	doomed_b.core.current.heat = 0
	await _infect(doomed_a, 1)
	await _infect(doomed_b, 1)

	# Positive control: both start alive and infected, so the damage - not a fixture mistake - is what
	# kills them.
	assert_true(Unit.is_valid(doomed_a) and doomed_a.is_on_map(), 'Fixture: A starts alive.')
	assert_true(Unit.is_valid(doomed_b) and doomed_b.is_on_map(), 'Fixture: B starts alive.')
	assert_true(Infection.is_infected(doomed_a), 'Fixture: A starts infected.')
	assert_true(Infection.is_infected(doomed_b), 'Fixture: B starts infected.')

	Dice.CHEAT_ROLL_QUEUE.append_array([6, 6])
	await _fire(IMPAIR)

	assert_false(Unit.is_valid(doomed_a) and doomed_a.is_on_map(), 'The 4 damage killed A.')
	assert_false(Unit.is_valid(doomed_b) and doomed_b.is_on_map(), 'The 4 damage killed B.')
	assert_true(Dice.CHEAT_ROLL_QUEUE.is_empty(), 'Both structure rolls were drawn.')
	assert_true(watcher.kinds(PromptWatcher.KIND.multiple_choice).is_empty(),
		'No survivors, so activate() returns before the choice prompt.')
	assert_eq(draugr.core.current.heat, 2, 'The protocol still costs its 2 heat, spent before the damage loop.')

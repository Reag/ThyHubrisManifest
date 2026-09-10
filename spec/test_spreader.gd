# Spreader - Disease's second Invade option.
#
#   "Your target takes 1 INFECTION and is SLOWED for as long as they have INFECTION. While they have
#    INFECTION, any character that starts their turn adjacent to the target, or moves adjacent to
#    them for the first time in a round, must make a SYSTEMS check or take 1 INFECTION."
#
# buff_spreader sits on the VICTIM, is MANUAL, carries applies_statuses = [slowed], and is linked to
# the victim's Infection so it dies with it. Reactive on step/new_turn at POST, firing for the
# TRIGGERING unit rather than the holder - hence a plain Buff, not a BuffReactionSelf
# (action_reaction_self.gd:11-15 demands triggering unit == holder). Vanilla's precedent is the
# Specter's buff_drain_systems_specter.gd, whose .tres uses the same two triggers.
#
# ONCE PER UNIT PER ROUND uses vanilla's buff_track_affection recipe
# (action_reaction_on_coming_within.gd:86-104): a hidden UNTIL.START_OF_TURN buff on the AFFECTED
# unit, so it clears at that unit's own next turn start (unit_condition.gd:15-21 from
# event_turn_start.gd:76 - BEFORE the NEW_TURN POST reactions queued at :56). The marker names the
# holder as well as the kit, because two Spreader victims are two separate effects (decision D6).
#
# DELIBERATELY 3 HEAT, NOT 1 (decision D2): unlike Symptom, Spreader's text does not say "instead of
# Invade's normal heat", so the standard 2 heat still lands on top of the Infection's 1.
extends GutTest

const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')
const InfectionLinks := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection_links.gd')

const DISEASE := &'ms_disease'
const SPREADER := &'action_spreader'
const SPREADER_BUFF := &'buff_spreader'

var game:Gamemaster
var draugr:Unit
var target:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	draugr = _fresh(Vector2i(0, 0), Faction.PLAYER)
	draugr.core.equip_system(DISEASE)
	draugr.core.full_repair()
	target = _fresh(Vector2i(2, 2), Faction.AI_ENEMY)
	target.core.frame.stat.edef = -10

func after_each():
	Dice.CHEAT_ROLL_QUEUE.clear()

func _fresh(tile:Vector2i, faction:Faction.SIDE) -> Unit:
	var unit := SpecFactory.create_unit(game.map, tile, faction)
	unit.core.frame.stat.heat = 30
	unit.core.full_repair()
	unit.core.current.heat = 0
	return unit

func spread_onto(victim:Unit) -> void:
	Dice.CHEAT_ROLL_QUEUE.append(20)
	await SpecFactory.use(game, draugr, DISEASE, SPREADER, victim)

func test_spreader_applies_one_infection_and_the_slow():
	await spread_onto(target)
	assert_eq(Infection.count(target), 1, 'One Infection.')
	assert_true(target.has_status(Lancer.STATUS.SLOWED), 'And it is slowed.')
	assert_false(UnitCondition.get_buffs(target, SPREADER_BUFF).is_empty(), 'By buff_spreader.')

func test_spreader_keeps_the_invades_own_two_heat():
	await spread_onto(target)
	assert_eq(target.core.current.heat, 3, "2 from the invade plus 1 from the Infection; Spreader's text does not replace the heat.")

func test_the_slow_lasts_until_the_infection_clears():
	await spread_onto(target)
	Dice.CHEAT_ROLL_QUEUE.append(20) # the end-of-turn Infection check passes
	await SpecFactory.pass_turn(game, target)
	assert_false(Infection.is_infected(target), 'Infection cleared.')
	assert_false(target.has_status(Lancer.STATUS.SLOWED), 'And the slow went with it.')

func test_the_slow_survives_a_turn_the_infection_survives():
	await spread_onto(target)
	Dice.CHEAT_ROLL_QUEUE.append(1) # the check fails
	await SpecFactory.pass_turn(game, target)
	assert_true(target.has_status(Lancer.STATUS.SLOWED), 'Still slowed, because still infected.')

func test_a_character_starting_its_turn_adjacent_rolls_and_can_fail():
	var neighbour := _fresh(Vector2i(2, 1), Faction.PLAYER)
	await spread_onto(target)
	Dice.CHEAT_ROLL_QUEUE.append(1) # neighbour's Systems check, failed
	await SpecFactory.start_turn(game, neighbour)
	assert_eq(Infection.count(neighbour), 1, 'One Infection from standing next to it.')
	assert_true(Dice.CHEAT_ROLL_QUEUE.is_empty(), 'Exactly one check was rolled.')

func test_a_passed_check_costs_nothing():
	var neighbour := _fresh(Vector2i(2, 1), Faction.PLAYER)
	await spread_onto(target)
	Dice.CHEAT_ROLL_QUEUE.append(20)
	await SpecFactory.start_turn(game, neighbour)
	assert_eq(Infection.count(neighbour), 0, 'Passed; nothing spreads.')
	assert_true(Dice.CHEAT_ROLL_QUEUE.is_empty(), 'But a check WAS made.')

func test_a_character_moving_adjacent_rolls_once_and_not_again_that_round():
	var mover := _fresh(Vector2i(0, 2), Faction.PLAYER)
	await spread_onto(target)
	Dice.CHEAT_ROLL_QUEUE.append(1)
	await SpecFactory.move(game, mover, Vector2i(1, 2)) # adjacent to (2,2)
	assert_eq(Infection.count(mover), 1, 'Moving adjacent costs one check.')
	await SpecFactory.move(game, mover, Vector2i(2, 1)) # still adjacent, second approach
	assert_eq(Infection.count(mover), 1, 'Not a second time in the same round.')
	assert_true(Dice.CHEAT_ROLL_QUEUE.is_empty(), 'Only one check was ever rolled.')

func test_the_tracking_clears_at_the_characters_own_turn_start():
	var mover := _fresh(Vector2i(0, 2), Faction.PLAYER)
	await spread_onto(target)
	Dice.CHEAT_ROLL_QUEUE.append(1)
	await SpecFactory.move(game, mover, Vector2i(1, 2))
	assert_eq(Infection.count(mover), 1, 'First approach.')
	Dice.CHEAT_ROLL_QUEUE.append(1)
	await SpecFactory.start_turn(game, mover) # buff_track_affection is UNTIL.START_OF_TURN
	assert_eq(Infection.count(mover), 2, 'A new round, a new check.')

func test_a_character_that_is_not_adjacent_is_untouched():
	var distant := _fresh(Vector2i(0, 0), Faction.PLAYER)
	await spread_onto(target)
	await SpecFactory.start_turn(game, distant)
	assert_eq(Infection.count(distant), 0, 'Two tiles away is not adjacent.')

func test_the_victim_itself_never_triggers_it():
	await spread_onto(target)
	Dice.CHEAT_ROLL_QUEUE.append(1) # this is the Infection end-of-turn check, not a Spreader check
	await SpecFactory.pass_turn(game, target)
	assert_eq(Infection.count(target), 1, 'Its own turn does not re-infect it.')
	assert_true(Dice.CHEAT_ROLL_QUEUE.is_empty(), 'And only the Infection check was rolled.')

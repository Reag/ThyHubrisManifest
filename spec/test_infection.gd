# Infection - the status every Draugr piece hangs off. Rules text: gear.buff_infection.effect.
#
#   "Infection works similarly to Burn, but applies Heat instead of damage. When characters take
#    Infection, they immediately take an equal amount of Heat, and mark down how much Infection
#    they received. If a character already has Infection, additional Infection is added on top of
#    what they already had. At the end of their turn, Infected characters must roll a Systems
#    check. On a success, they clear all Infection; otherwise, they take Heat equal to the amount
#    of Infection currently marked. If an action would clear BURN, such as stabilize, it also
#    clears INFECTION."
#
# One buff_infection per victim carries the count in its BuffCore state; infection.gd is the only
# reader and writer (design doc 2026-09-09-draugr-design.md, section 1). Burn is a bespoke int on
# UnitBattleState, which has a class_name and so cannot be extended - hence a buff. Nothing here
# goes through a prompt, so no responder is needed.
extends GutTest

const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')

var game:Gamemaster
var unit:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	unit = SpecFactory.create_unit(game.map)
	unit.core.current.heat = 0

## A spec has no live event block, so apply() runs the heat through the level's own runner.
func infect(target:Unit, n:int) -> void:
	await Infection.apply(SpecFactory.dummy_event({unit = target}), target, n)

func test_a_fresh_unit_is_not_infected():
	assert_eq(Infection.count(unit), 0, 'No count.')
	assert_false(Infection.is_infected(unit), 'Not infected.')

func test_applying_marks_the_count_and_deals_that_much_heat():
	await infect(unit, 2)
	assert_eq(Infection.count(unit), 2, 'Two marked.')
	assert_eq(unit.core.current.heat, 2, 'Two heat, immediately.')
	assert_eq(UnitCondition.get_buffs(unit, Infection.BUFF_ID).size(), 1, 'One buff carries it.')

func test_applying_again_stacks_onto_the_existing_count():
	await infect(unit, 2)
	await infect(unit, 3)
	assert_eq(Infection.count(unit), 5, 'Added on top of what was there.')
	assert_eq(unit.core.current.heat, 5, 'Heat for each application.')
	assert_eq(UnitCondition.get_buffs(unit, Infection.BUFF_ID).size(), 1, 'Still one buff, not a row of identical icons.')

func test_the_buff_is_named_with_its_count():
	await infect(unit, 3)
	var core:BuffCore = Infection.get_core(unit)
	assert_true(core.name_text().contains('3'), 'The name shows the count: %s' % core.name_text())

func test_tech_immune_units_cannot_be_infected():
	# Infection is a data virus. The engine already refuses tech buffs to tech-immune units
	# (buff.gd check_if_prohibited); apply() refuses the same way rather than leaving a buff every
	# later reader would have to re-check.
	var immunity := Buff.new()
	immunity.to = Buff.TO.TECH_IMMUNITY
	UnitCondition.apply_buff(SpecFactory.dummy_event(), unit, immunity)
	await infect(unit, 2)
	assert_eq(Infection.count(unit), 0, 'Refused.')
	assert_eq(unit.core.current.heat, 0, 'And no heat either.')

func test_clear_removes_the_buff_and_the_count():
	await infect(unit, 2)
	Infection.clear(SpecFactory.dummy_event(), unit)
	assert_false(Infection.is_infected(unit), 'Gone.')
	assert_eq(UnitCondition.get_buffs(unit, Infection.BUFF_ID).size(), 0, 'Buff gone with it.')

# ---------- end of the holder's turn ----------
# Mirrors burn (event_turn_end.gd:92-107) but as a reactive buff, because the victim owns none
# of the Draugr's gear. Dice.CHEAT_ROLL_QUEUE feeds the d20: 20 passes, 1 fails, on a stock unit
# with +0 Systems against target 10.

func test_passing_the_check_clears_infection():
	await infect(unit, 3)
	unit.core.current.heat = 0
	Dice.CHEAT_ROLL_QUEUE.append(20)
	await SpecFactory.pass_turn(game, unit)
	assert_eq(Infection.count(unit), 0, 'Cleared on a passed check.')
	assert_eq(unit.core.current.heat, 0, 'No heat on a pass.')

func test_failing_the_check_deals_heat_equal_to_the_count_and_keeps_it():
	await infect(unit, 3)
	unit.core.current.heat = 0
	Dice.CHEAT_ROLL_QUEUE.append(1)
	await SpecFactory.pass_turn(game, unit)
	assert_eq(unit.core.current.heat, 3, 'Heat equal to the marked count.')
	assert_eq(Infection.count(unit), 3, 'Still infected, at the same count.')

func test_the_check_only_happens_on_the_holders_own_turn():
	var other := SpecFactory.create_unit(game.map, Vector2i(2, 2))
	await infect(unit, 2)
	unit.core.current.heat = 0
	Dice.CHEAT_ROLL_QUEUE.append(1)
	await SpecFactory.pass_turn(game, other)
	assert_eq(Infection.count(unit), 2, 'Untouched by someone else ending their turn.')
	assert_eq(unit.core.current.heat, 0, 'No heat either.')
	Dice.CHEAT_ROLL_QUEUE.clear()

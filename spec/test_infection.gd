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

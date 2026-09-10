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

func test_an_infected_unit_shows_the_miasma_scaled_to_its_count():
	# buff_infection.tres carries fxe_infected.tscn (a green recolour of vanilla fxe_burning, same
	# script), and the buff's ticket passes the count as `number`, which fxe_burning.gd reads as
	# particle intensity. The scene must be in the fx-endless index or the controller logs an error.
	assert_false(ContentLibrary.get_fxendless_path(&'fxe_infected').is_empty(), 'fxe_infected is indexed.')
	await infect(unit, 3)
	var core := Infection.get_core(unit)
	var tickets:Array[FxEndless.Ticket] = core.base.get_attached_fx(core, unit)
	assert_eq(tickets.size(), 1, 'One miasma per infected unit.')
	if tickets.is_empty(): return
	assert_eq(tickets[0].fxe_id, &'fxe_infected', 'The green one, not the burn.')
	assert_eq(tickets[0].context.number, 3, 'Intensity follows the count.')
	assert_eq(tickets[0].context.unit, unit, 'Anchored to the infected unit.')

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

# ---------- cleared with Burn ----------
# "If an action would clear BURN, such as stabilize, it also clears INFECTION." 1.4.0 has an
# event for that (event_unit_clear_burn, trigger clear_burn); 1.3.3 does not, so Stabilize's
# stabilize trigger plus its burn variant key is the fallback there. Both engines disable the
# burn variant on burn <= 0, so an infected unit with no Burn needs action_stabilize.gd_ext.gd to
# unlock it - and the only proof an extension runs is a test that fails without it.

func equip_stabilize(target:Unit) -> void:
	if target.get_gear(&'ms_stabilize') == null: target.core.equip_system(&'ms_stabilize')

## Primary group: heat 0 and no EXPOSED makes "skip_primary" available; full HP disables repair.
func stabilize_burn(target:Unit) -> void:
	equip_stabilize(target)
	target.core.current.heat = 0
	await SpecFactory.start_turn(game, target)
	await SpecFactory.use_solo(game, target, &'ms_stabilize', [], [], 'burn')

func test_clearing_burn_with_stabilize_clears_infection_too():
	await infect(unit, 2)
	unit.state.burn = 2
	await stabilize_burn(unit)
	assert_eq(unit.state.burn, 0, 'Burn cleared (vanilla).')
	assert_false(Infection.is_infected(unit), 'Infection went with it.')

func test_stabilize_offers_burn_clearing_to_an_infected_unit_without_burn():
	await infect(unit, 2)
	unit.state.burn = 0
	equip_stabilize(unit)
	var specific := SpecificAction.from_id(unit, &'ms_stabilize')
	var burn_variant:VariantAction = null
	for group:VariantActionGroup in specific.action.get_alternate_actions(specific):
		for variant:VariantAction in group.list:
			if variant.key == &'burn': burn_variant = variant
	assert_not_null(burn_variant, 'The burn variant is listed.')
	if burn_variant != null: assert_false(burn_variant.is_disabled, 'And offered, because the unit is infected.')

func test_stabilizing_away_infection_without_burn_works_end_to_end():
	await infect(unit, 2)
	unit.state.burn = 0
	await stabilize_burn(unit)
	assert_false(Infection.is_infected(unit), 'Cleared through the burn variant with no Burn to clear.')

func test_any_burn_clear_clears_infection_on_140():
	# Whitewash and the Sealant Gun go through the same event on 1.4.0; Stabilize is the only
	# path on 1.3.3, which the tests above cover.
	if not ResourceLoader.exists('res://content/events/event_unit_clear_burn.gd'):
		pass_test('1.3.3 has no clear-burn event.')
		return
	await infect(unit, 2)
	unit.state.burn = 1
	await game.execute_event(&'event_unit_clear_burn', {unit = unit})
	assert_eq(unit.state.burn, 0, 'Burn cleared.')
	assert_false(Infection.is_infected(unit), 'Infection cleared by the event alone.')

# ---------- what must NOT clear it ----------

func test_a_passed_burn_save_at_end_of_turn_does_not_clear_infection():
	# 1.4.0's end-of-turn Burn resolution fires event_unit_clear_burn when the Engineering save
	# passes; that is the Burn mechanic, not "an action that would clear BURN", so Infection stays.
	# 1.3.3 has no event there and behaves this way already; this pins both engines to it.
	# Roll order at end of turn: the Infection Systems check (PRE) rolls first, then the Burn save.
	await infect(unit, 2)
	unit.state.burn = 1
	unit.core.current.heat = 0
	Dice.CHEAT_ROLL_QUEUE.append_array([1, 20])
	await SpecFactory.pass_turn(game, unit)
	assert_eq(unit.state.burn, 0, 'The Burn save passed and cleared Burn.')
	assert_eq(Infection.count(unit), 2, 'Infection survived the Burn save.')
	assert_eq(unit.core.current.heat, 2, 'The failed Infection check still dealt its heat.')
	Dice.CHEAT_ROLL_QUEUE.clear()

func test_stabilize_keeps_the_burn_variant_disabled_for_an_uninfected_unit():
	# The extension mutates the variant list; an uninfected unit must see vanilla's list.
	unit.state.burn = 0
	equip_stabilize(unit)
	var specific := SpecificAction.from_id(unit, &'ms_stabilize')
	var burn_variant:VariantAction = null
	var has_skip := false
	for group:VariantActionGroup in specific.action.get_alternate_actions(specific):
		for variant:VariantAction in group.list:
			if variant.key == &'burn': burn_variant = variant
			if variant.key == &'skip_secondary': has_skip = true
	assert_not_null(burn_variant, 'The burn variant is listed.')
	if burn_variant != null: assert_true(burn_variant.is_disabled, 'And stays disabled with no Burn and no Infection.')
	assert_true(has_skip, 'Vanilla still offers the secondary skip.')

func test_stabilizing_without_the_burn_variant_keeps_infection():
	# The stabilize trigger fires for every Stabilize; only the burn variant may clear Infection.
	await infect(unit, 2)
	unit.state.burn = 0
	SpecFactory.apply(unit, &'impaired', Lancer.UNTIL.MANUAL)
	equip_stabilize(unit)
	unit.core.current.heat = 0
	await SpecFactory.start_turn(game, unit)
	await SpecFactory.use_solo(game, unit, &'ms_stabilize', [], [], 'condition_self')
	assert_false(unit.has_status(&'impaired'), 'Stabilize ran its condition-clearing variant.')
	assert_eq(Infection.count(unit), 2, 'Infection untouched by a Stabilize that did not clear Burn.')

func test_marking_zero_does_nothing():
	Infection.mark(SpecFactory.dummy_event({unit = unit}), unit, 0)
	assert_false(Infection.is_infected(unit), 'No buff for a zero mark.')
	assert_eq(UnitCondition.get_buffs(unit, Infection.BUFF_ID).size(), 0, 'Nothing attached.')

func test_another_unit_clearing_its_own_burn_leaves_the_holder_alone():
	# The stabilize / clear_burn filters key on the holder; an ally's Stabilize must not reach us.
	var other := SpecFactory.create_unit(game.map, Vector2i(2, 2))
	await infect(unit, 2)
	other.state.burn = 2
	await stabilize_burn(other)
	assert_eq(other.state.burn, 0, 'The other unit cleared its own Burn.')
	assert_eq(Infection.count(unit), 2, 'Our Infection is untouched.')

# Atrophy - the Carrion Beast's reaction.
#
#   Trigger: "A character with INFECTION within SENSORS is about to roll a save or check"
#   Effect:  "1/turn, reduce the target's INFECTION by 1. The target takes +1 DIFFICULTY on the
#             triggering roll."
#
# AUTOMATIC, NOT PROMPTED (design decision D4): the save-modifier hook is synchronous and runs before
# the roll, so there is nowhere to ask. It fires whenever it is eligible and spends the reaction.
#
# ONE to = save BUFF COVERS "A SAVE OR CHECK". UnitHasecheck.roll_check (unit_hasecheck.gd:161-256)
# is the single function behind both: handle_check calls it at :133 for a plain check, and a forced
# save reaches the same handle_check through event_unit_save.gd:54-63 with is_save = true (which only
# changes the battle-log key). The Infection end-of-turn check goes through it too, which is the
# designed combo.
#
# THE DICE ARE THE ASSERTION. roll_check draws the d20 at :200 and the accuracy/difficulty die at
# :202, in that order. Seeded [10, 4] against target 10 on a stock unit (+0 Systems):
#   no Atrophy -> 10          -> PASS, and the 4 is still in the queue afterwards
#   Atrophy    -> 10 - 4 = 6  -> FAIL, and the queue is empty
# Same seeds, opposite outcomes, and the leftover die is itself the proof that no difficulty die was
# rolled. That is why after_each asserts nothing and just clears.
#
# WHY THE BUFF SURVIVES ITS OWN CONSUMPTION (plan decision D4): consume_buffs only offers is_onetime
# buffs to on_consumption (unit_condition.gd:936-938) and clears them unless the method returns
# false. Returning false keeps the marker in place, so nothing depends on an aura refresh to put it
# back; the 1/turn limit is the gear's own per-turn counter, not the buff's presence.
#
# THE MAP IS 20x20 (memory draugr-infection-engine-gotchas item 6) and Sensors is pinned to 5, so the
# aura's footprint is 10.
extends GutTest

const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')
const DraugrReach := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/draugr_reach.gd')

const BEAST := &'ms_carrion_beast'
const ATROPHY := &'buff_atrophy'
const ATROPHY_GROUP := &'carrion_beast_atrophy'

var game:Gamemaster
var draugr:Unit
var victim:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self, false, SpecFactory.create_combat(Landscape.create_default(Vector2i(20, 20))))
	draugr = SpecFactory.create_unit(game.map, Vector2i(0, 0), Faction.PLAYER)
	draugr.core.frame.stat.sensor_range = 5
	draugr.core.frame.stat.heat = 20
	draugr.core.equip_system(BEAST)
	SpecFactory.apply_passive_buffs(draugr)
	draugr.core.current.heat = 0
	victim = _enemy_at(Vector2i(3, 0))

func after_each():
	Dice.CHEAT_ROLL_QUEUE.clear()

func _enemy_at(tile:Vector2i) -> Unit:
	var unit := SpecFactory.create_unit(game.map, tile, Faction.AI_ENEMY)
	unit.core.frame.stat.health = 40
	unit.core.frame.stat.heat = 20
	unit.core.full_repair()
	unit.core.current.heat = 0
	return unit

func _infect(unit:Unit, n:int) -> void:
	await Infection.apply(SpecFactory.dummy_event({unit = unit}), unit, n)
	unit.core.current.heat = 0

## Plant the aura buffs. Auras only run inside UnitTile.update_tracking_and_statuses
## (passive_aura.gd:24, called from unit_tile.gd:24), which the engine drives from moves, spawns and
## status changes; a spec drives it by hand.
func _settle() -> void:
	UnitTile.update_tracking_and_statuses(game.map)

func _has_atrophy(unit:Unit) -> bool:
	return UnitCondition.has_buff(unit, ATROPHY)

## A plain SYSTEMS check against 10. handle_check/roll_check execute no events, so a dummy event is
## enough; Context.create fills its map from the unit (context.gd:77-79).
func _check(unit:Unit) -> bool:
	return await UnitHasecheck.make_check(SpecFactory.dummy_event({unit = unit}), unit, 10, Lancer.HASE.SYS)

# ---------------------------------------------------------------- the aura

func test_the_aura_plants_atrophy_on_a_character_in_reach():
	_settle()
	assert_true(_has_atrophy(victim), 'Three tiles away, inside the footprint.')

func test_the_aura_does_not_reach_beyond_sensors_plus_five():
	var distant := _enemy_at(Vector2i(11, 0))
	_settle()
	assert_false(_has_atrophy(distant), 'Eleven tiles is outside Sensors 5 + 5.')

func test_the_draugr_never_carries_its_own_atrophy():
	# applies_to_self = false (plan decision D6): the rules row says "the TARGET's INFECTION".
	await _infect(draugr, 2)
	_settle()
	assert_false(_has_atrophy(draugr), 'Not on the Draugr.')

# ---------------------------------------------------------------- the difficulty

func test_an_infected_character_takes_a_difficulty_die_on_a_check():
	await _infect(victim, 2)
	_settle()
	Dice.CHEAT_ROLL_QUEUE.append_array([10, 4])
	var passed:bool = await _check(victim)
	assert_false(passed, '10 minus a 4 difficulty die is 6, against a target of 10.')
	assert_true(Dice.CHEAT_ROLL_QUEUE.is_empty(), 'Both dice were drawn.')

func test_a_clean_character_rolls_untouched():
	_settle()
	Dice.CHEAT_ROLL_QUEUE.append_array([10, 4])
	var passed:bool = await _check(victim)
	assert_true(passed, 'A flat 10 makes the target of 10.')
	assert_eq(Dice.CHEAT_ROLL_QUEUE.size(), 1, 'The difficulty die was never rolled.')

func test_a_forced_save_draws_it_too():
	# The other half of "a save or check": event_unit_save.gd:54-63 reaches the same handle_check.
	# No forcing unit, so the save target is a flat 10 and the arithmetic matches the check above.
	await _infect(victim, 2)
	_settle()
	Dice.CHEAT_ROLL_QUEUE.append_array([10, 4])
	await game.execute_event(&'event_unit_save', {target_unit = victim, category = Lancer.HASE.SYS})
	assert_eq(Infection.count(victim), 1, 'Atrophy fired on the save.')
	assert_true(Dice.CHEAT_ROLL_QUEUE.is_empty(), 'And drew its difficulty die.')

# ---------------------------------------------------------------- the reduction

func test_atrophy_reduces_infection_by_one():
	await _infect(victim, 3)
	_settle()
	Dice.CHEAT_ROLL_QUEUE.append_array([10, 4])
	await _check(victim)
	assert_eq(Infection.count(victim), 2, 'Three, less one.')
	assert_eq(victim.core.current.heat, 0, 'Reducing INFECTION deals no heat.')

func test_the_last_point_is_cleared_outright():
	await _infect(victim, 1)
	_settle()
	Dice.CHEAT_ROLL_QUEUE.append_array([10, 4])
	await _check(victim)
	assert_eq(Infection.count(victim), 0, 'Nothing left.')
	assert_eq(UnitCondition.get_buffs(victim, Infection.BUFF_ID).size(), 0, 'And the buff went with it.')

# ---------------------------------------------------------------- the cost

func test_atrophy_spends_the_draugr_reaction():
	await _infect(victim, 2)
	_settle()
	var before:int = draugr.core.current.reactions
	assert_true(before > 0, 'Fixture: the Draugr has a reaction.')
	Dice.CHEAT_ROLL_QUEUE.append_array([10, 4])
	await _check(victim)
	assert_eq(draugr.core.current.reactions, before - 1, 'One reaction, spent.')

func test_atrophy_does_nothing_without_a_reaction_available():
	await _infect(victim, 2)
	_settle()
	draugr.core.current.reactions = 0
	Dice.CHEAT_ROLL_QUEUE.append_array([10, 4])
	var passed:bool = await _check(victim)
	assert_true(passed, 'No reaction, no difficulty.')
	assert_eq(Infection.count(victim), 2, 'And no reduction.')
	assert_eq(Dice.CHEAT_ROLL_QUEUE.size(), 1, 'The difficulty die was never rolled.')

func test_atrophy_fires_once_per_turn():
	# 1/turn is the engine's own per-turn usage counter, keyed to a private usage group
	# (gear_core.gd:173-188). Both rolls stay inside one turn, because that counter is cleared at
	# EVERY unit's turn start (unit_action.gd:66-70) - memory item 12.
	await _infect(victim, 3)
	_settle()
	Dice.CHEAT_ROLL_QUEUE.append_array([10, 4])
	await _check(victim)
	assert_eq(Infection.count(victim), 2, 'First roll: fired.')
	Dice.CHEAT_ROLL_QUEUE.clear()
	Dice.CHEAT_ROLL_QUEUE.append_array([10, 4])
	var passed:bool = await _check(victim)
	assert_true(passed, 'Second roll in the same turn: no difficulty.')
	assert_eq(Infection.count(victim), 2, 'And no second reduction.')

func test_a_turn_start_refreshes_it():
	await _infect(victim, 3)
	_settle()
	Dice.CHEAT_ROLL_QUEUE.append_array([10, 4])
	await _check(victim)
	Dice.CHEAT_ROLL_QUEUE.clear()
	await SpecFactory.start_turn(game, draugr)
	Dice.CHEAT_ROLL_QUEUE.append_array([10, 4])
	await _check(victim)
	assert_eq(Infection.count(victim), 1, 'Fired again after the turn boundary.')

# ---------------------------------------------------------------- the combo, and the survival

func test_the_infection_end_of_turn_check_is_the_designed_combo():
	# buff_infection's own end-of-turn SYSTEMS check goes through handle_check, so Atrophy reaches it.
	# The reduction happens inside roll_check (:195) BEFORE the d20 (:200), so the heat on a failure
	# is the REDUCED count - which is the order the rules row states.
	await _infect(victim, 3)
	Dice.CHEAT_ROLL_QUEUE.append_array([10, 4])
	await SpecFactory.pass_turn(game, victim)
	assert_eq(Infection.count(victim), 2, 'Atrophy took one before the roll.')
	assert_eq(victim.core.current.heat, 2, 'The failed check burns the reduced count, not the old one.')

func test_the_marker_survives_its_own_consumption():
	# on_consumption returns false, so the buff is not cleared (plan decision D4). Without this the
	# marker would depend on an aura refresh to come back.
	await _infect(victim, 3)
	_settle()
	Dice.CHEAT_ROLL_QUEUE.append_array([10, 4])
	await _check(victim)
	assert_true(_has_atrophy(victim), 'Still marked.')

# ---------------------------------------------------------------- the Draugr's own state (review)

func test_atrophy_does_nothing_once_the_carrion_beast_is_destroyed():
	# No test previously covered the "Draugr alive with the Kit intact" half of the gate
	# (check_if_passive_applies's gear.is_intact() check). Positive control first, on a fresh
	# infection count, so the second roll's outcome can only be explained by the destruction.
	await _infect(victim, 3)
	_settle()
	Dice.CHEAT_ROLL_QUEUE.append_array([10, 4])
	var passed_before:bool = await _check(victim)
	assert_false(passed_before, 'Positive control: Atrophy still fires with the Carrion Beast intact.')
	assert_eq(Infection.count(victim), 2, 'And reduced Infection, same as every other firing test.')

	# A fresh turn restores the 1/turn allowance and the reaction, so intactness is the only thing
	# that changed for the second roll.
	await SpecFactory.start_turn(game, draugr)
	draugr.get_gear(BEAST).is_destroyed = true

	Dice.CHEAT_ROLL_QUEUE.append_array([10, 4])
	var passed_after:bool = await _check(victim)
	assert_true(passed_after, 'A destroyed Carrion Beast grants nothing: the check goes through untouched.')
	assert_eq(Infection.count(victim), 2, 'No further reduction.')
	assert_eq(Dice.CHEAT_ROLL_QUEUE.size(), 1, 'The difficulty die was never rolled.')

func test_atrophy_does_nothing_once_the_draugr_is_dead():
	# The other half of the same gate: draugr.is_on_map() (buff_atrophy.gd:55) is what "alive" means
	# here. Same shape as the destruction test above, including the positive control.
	await _infect(victim, 3)
	_settle()
	Dice.CHEAT_ROLL_QUEUE.append_array([10, 4])
	var passed_before:bool = await _check(victim)
	assert_false(passed_before, 'Positive control: Atrophy still fires while the Draugr is alive.')
	assert_eq(Infection.count(victim), 2, 'And reduced Infection.')

	await SpecFactory.start_turn(game, draugr)
	await game.execute_event(&'event_unit_die', {unit = draugr})

	Dice.CHEAT_ROLL_QUEUE.append_array([10, 4])
	var passed_after:bool = await _check(victim)
	assert_true(passed_after, 'A dead Draugr grants nothing: the check goes through untouched.')
	assert_eq(Infection.count(victim), 2, 'No further reduction.')
	assert_eq(Dice.CHEAT_ROLL_QUEUE.size(), 1, 'The difficulty die was never rolled.')

# ---------------------------------------------------------------- isolation (Task 3b)

func test_an_isolated_draugr_cannot_atrophy():
	# The rules call Atrophy a reaction, and Isolation forbids reactions - but Atrophy had no Action
	# of its own for Isolation's gate to test against. action_atrophy exists purely to close that gap
	# (see its own header, and buff_atrophy.gd's Task 3b comment). A second, un-isolated Draugr/victim
	# pair well out of the first Draugr's reach is the positive control, so this needs no
	# turn-boundary bookkeeping to avoid Isolation itself expiring between rolls.
	var control_draugr := SpecFactory.create_unit(game.map, Vector2i(0, 19), Faction.PLAYER)
	control_draugr.core.frame.stat.sensor_range = 5
	control_draugr.core.frame.stat.heat = 20
	control_draugr.core.equip_system(BEAST)
	SpecFactory.apply_passive_buffs(control_draugr)
	control_draugr.core.current.heat = 0
	var control_victim := _enemy_at(Vector2i(3, 19))

	await _infect(victim, 2)
	await _infect(control_victim, 2)
	UnitCondition.apply_buff_id(SpecFactory.dummy_event(), draugr, &'buff_isolation')
	_settle()

	Dice.CHEAT_ROLL_QUEUE.append_array([10, 4])
	var isolated_passed:bool = await _check(victim)
	assert_true(isolated_passed, 'An Isolated Draugr cannot Atrophy.')
	assert_eq(Infection.count(victim), 2, 'No reduction.')

	Dice.CHEAT_ROLL_QUEUE.append_array([10, 4])
	var control_passed:bool = await _check(control_victim)
	assert_false(control_passed, 'Positive control: an un-isolated Draugr still Atrophies on the same seeded roll.')
	assert_eq(Infection.count(control_victim), 1, 'And reduces Infection.')

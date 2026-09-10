# Linked effects - "lasts until the target clears INFECTION" (design section 1, "Linked effects").
#
# TWO DIFFERENT TRICKS, because the engine expires the two kinds of effect differently:
#   - a STATUS carries its own `until` (status_condition.gd:6; unit_condition.gd:16 says outright
#     that these resources are unique per application), so it is set to UNTIL.MANUAL once.
#   - a BUFF's `until` is on the SHARED Buff resource (buff.gd:119) and must never be written, so the
#     per-instance BuffCore.turn_count (buff_core.gd:7) is walked back one at every one of the
#     holder's end-of-turn PREs instead - Face Thy Judgement's trick (action_face_thy_judgement.gd:151-168).
#
# The decrement happens at END_TURN/PRE (event_turn_end.gd:17) and expiry at :40, so a linked buff is
# always one step ahead of the reaper.
extends GutTest

const FrameIsolation := preload('res://testkit/frame_isolation.gd')
const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')
const InfectionLinks := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection_links.gd')

var game:Gamemaster
var unit:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	unit = SpecFactory.create_unit(game.map)
	FrameIsolation.isolate_frame(unit)
	unit.core.frame.stat.heat = 30
	unit.core.current.heat = 0

func after_each():
	Dice.CHEAT_ROLL_QUEUE.clear()

func infect(target:Unit, n:int) -> void:
	await Infection.apply(SpecFactory.dummy_event({unit = target}), target, n)

## A buff built here rather than loaded: `until` and the script are exactly what each test needs, and
## holding the returned BuffCore is the only reliable identity a generic buff has.
func give_buff(target:Unit, until:Lancer.UNTIL) -> BuffCore:
	var effect := Buff.new()
	effect.until = until
	return UnitCondition.apply_buff(SpecFactory.dummy_event({unit = target}), target, effect)

## Applies via UnitCondition directly and returns what it hands back, rather than SpecFactory.apply
## (which discards it) + UnitCondition.get_status (which only ever returns the FIRST match of a
## type - useless once a test needs to hold a SECOND instance of the same status and source).
func give_status(target:Unit, until:Lancer.UNTIL) -> StatusCondition:
	return UnitCondition.apply_status(SpecFactory.dummy_event({unit = target}), target, Lancer.STATUS.IMPAIRED, until, 'spec_source')

## End a turn with the Infection check FAILING, so the Infection (and therefore the links) survives.
func survive_a_turn() -> void:
	Dice.CHEAT_ROLL_QUEUE.append(1)
	await SpecFactory.pass_turn(game, unit)
	assert_true(Dice.CHEAT_ROLL_QUEUE.is_empty(), 'The turn consumed exactly the seeded check.')

func test_an_unlinked_buff_expires_at_the_end_of_the_next_turn():
	# The control. Without this, every test below could be passing because nothing expires in a spec.
	await infect(unit, 1)
	var effect := give_buff(unit, Lancer.UNTIL.END_OF_NEXT_TURN)
	await survive_a_turn()
	assert_false(unit.state.buffs.has(effect), 'Nobody held it open, so it is gone.')

func test_a_linked_buff_survives_the_holders_end_of_turn():
	await infect(unit, 1)
	var effect := give_buff(unit, Lancer.UNTIL.END_OF_NEXT_TURN)
	assert_true(InfectionLinks.link(unit, effect), 'Linked.')
	await survive_a_turn()
	assert_true(unit.state.buffs.has(effect), 'Still there.')
	assert_eq(effect.turn_count, 0, 'The end-of-turn PRE walked turn_count back one.')

func test_a_linked_buff_survives_two_end_of_turns():
	# One decrement could be luck; two is the mechanism.
	await infect(unit, 1)
	var effect := give_buff(unit, Lancer.UNTIL.END_OF_NEXT_TURN)
	InfectionLinks.link(unit, effect)
	await survive_a_turn()
	await survive_a_turn()
	assert_true(unit.state.buffs.has(effect), 'Held open indefinitely.')

func test_a_linked_buff_survives_someone_elses_turn_ending():
	# end_turn_for_statuses runs for EVERY unit at the end of EVERY turn (event_turn_end.gd:40), but
	# turn_count only rises on the holder's own turn start - so no decrement is needed here, and the
	# effect must not quietly vanish while our reaction is not even firing.
	var other := SpecFactory.create_unit(game.map, Vector2i(2, 0))
	await infect(unit, 1)
	var effect := give_buff(unit, Lancer.UNTIL.END_OF_NEXT_TURN)
	InfectionLinks.link(unit, effect)
	await SpecFactory.pass_turn(game, other)
	assert_true(unit.state.buffs.has(effect), 'Another unit ending its turn does not touch it.')

func test_clearing_infection_clears_a_linked_buff():
	await infect(unit, 1)
	var effect := give_buff(unit, Lancer.UNTIL.END_OF_NEXT_TURN)
	InfectionLinks.link(unit, effect)
	Infection.clear(SpecFactory.dummy_event({unit = unit}), unit)
	assert_false(Infection.is_infected(unit), 'Infection gone.')
	assert_false(unit.state.buffs.has(effect), 'And the effect went with it.')

func test_a_linked_status_is_set_to_manual_and_survives():
	await infect(unit, 1)
	var status := give_status(unit, Lancer.UNTIL.END_OF_NEXT_TURN)
	assert_true(InfectionLinks.link(unit, status), 'Linked.')
	assert_eq(status.until, Lancer.UNTIL.MANUAL, 'A linked status stops expiring on its own.')
	await survive_a_turn()
	assert_true(unit.has_status(Lancer.STATUS.IMPAIRED), 'Still impaired.')

func test_clearing_infection_clears_a_linked_status():
	await infect(unit, 1)
	var status := give_status(unit, Lancer.UNTIL.END_OF_NEXT_TURN)
	InfectionLinks.link(unit, status)
	Infection.clear(SpecFactory.dummy_event({unit = unit}), unit)
	assert_false(unit.has_status(Lancer.STATUS.IMPAIRED), 'Cleared with the Infection.')

func test_linking_without_an_infection_buff_is_refused():
	var effect := give_buff(unit, Lancer.UNTIL.END_OF_NEXT_TURN)
	assert_false(InfectionLinks.link(unit, effect), 'Nothing to link to.')
	assert_eq(InfectionLinks.records(unit), [] as Array[String], 'And nothing was recorded.')

func test_linking_the_same_effect_twice_records_it_once():
	await infect(unit, 1)
	var effect := give_buff(unit, Lancer.UNTIL.END_OF_NEXT_TURN)
	InfectionLinks.link(unit, effect)
	InfectionLinks.link(unit, effect)
	assert_eq(InfectionLinks.records(unit).size(), 1, 'One record, so one decrement per turn end.')

func test_a_manual_buff_is_linked_without_being_walked_backwards():
	# Spreader's own buff is MANUAL. Decrementing a MANUAL buff's turn_count would be meaningless
	# bookkeeping that drifts forever, so extend_tracked only touches the two timed cases.
	await infect(unit, 1)
	var effect := give_buff(unit, Lancer.UNTIL.MANUAL)
	InfectionLinks.link(unit, effect)
	await survive_a_turn()
	assert_true(unit.state.buffs.has(effect), 'Still there, as MANUAL always would be.')
	assert_eq(effect.turn_count, 1, 'And its turn_count only ever went up, the normal way.')

func test_a_second_status_of_the_same_type_and_source_is_linked_too():
	# apply_status appends a fresh StatusCondition every call; both must be MANUAL and both must
	# go when the Infection does, or the second one outlives it (Spreader re-slows across rounds).
	await infect(unit, 1)
	var first := give_status(unit, Lancer.UNTIL.END_OF_NEXT_TURN)
	assert_true(InfectionLinks.link(unit, first), 'First link.')
	var second := give_status(unit, Lancer.UNTIL.END_OF_NEXT_TURN)
	assert_true(InfectionLinks.link(unit, second), 'Second link.')
	assert_eq(second.until, Lancer.UNTIL.MANUAL, 'The second instance was switched to MANUAL too.')
	Infection.clear(SpecFactory.dummy_event({unit = unit}), unit)
	assert_false(unit.has_status(Lancer.STATUS.IMPAIRED), 'Both IMPAIRED instances went with the Infection.')

func test_an_effect_on_another_unit_cannot_be_linked():
	var other := SpecFactory.create_unit(game.map, Vector2i(2, 2))
	await infect(unit, 1)
	var foreign := give_status(other, Lancer.UNTIL.END_OF_NEXT_TURN)
	assert_false(InfectionLinks.link(unit, foreign), 'Refused.')
	assert_ne(foreign.until, Lancer.UNTIL.MANUAL, 'And not mutated.')

func test_a_passed_check_clears_the_links_from_inside_the_buff():
	# The in-play path: the end-of-turn Systems check passes, the buff clears itself inside
	# activate, on_clear runs clear_all while the event block is live.
	await infect(unit, 1)
	var status := give_status(unit, Lancer.UNTIL.END_OF_NEXT_TURN)
	assert_true(InfectionLinks.link(unit, status), 'Linked.')
	Dice.CHEAT_ROLL_QUEUE.append(20)
	await SpecFactory.pass_turn(game, unit)
	assert_false(Infection.is_infected(unit), 'The check passed and cleared the Infection.')
	assert_false(unit.has_status(Lancer.STATUS.IMPAIRED), 'And the linked status with it.')

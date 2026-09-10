# The Ceaseless Death, the banking half.
#
#   "1/turn, it gains 1 Resilience when a hostile character within |SENSORS| is destroyed or loses a
#    structure. At the start of its turn, it gains 1 Resilience if it has less than 4 structure."
#   (localizations.csv, gear.cp_cupiditas_vitae.action_ceaseless_death.effect)
#
# Two ActionReactions on cp_cupiditas_vitae, deliberately in SEPARATE usage groups (see the plan's
# section B3 and decision C3): the 1/turn limit is the engine's own per-turn usage counter, and one
# shared group would let the start-of-turn gain eat the allowance for the whole of the Draugr's turn.
#
# The delicate one is DEATH. event_unit_die.gd queues its POST reactions at :81 and removes the unit
# from the map at :83, so by the time activate() runs the victim has no tiles and every distance to
# it reads as Tile's 1000 sentinel. Everything this reaction needs to know is therefore asked in
# triggers_on_event, which trigger_occurred calls synchronously at :81. The two "beyond Sensors" and
# "ally" tests are the ones that would go green for the wrong reason if that were not true, so
# test_a_kill_just_inside_sensors_still_pays is here to prove the boundary is real and not an
# artifact of everything being 1000 away.
#
# The map is 20x20: the default spec landscape is 5x5 and a unit outside it has no occupied tiles at
# all (memory draugr-infection-engine-gotchas item 6).
extends GutTest

const FrameIsolation := preload('res://testkit/frame_isolation.gd')
const Resilience := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/cp_cupiditas_vitae/resilience.gd')
const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')
const DRAUGR_FRAME := 'res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/mf_draugr.tres'

var game:Gamemaster
var draugr:Unit
var victim:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self, false, SpecFactory.create_combat(Landscape.create_default(Vector2i(20, 20))))
	draugr = SpecFactory.create_unit(game.map, Vector2i(0, 0))
	draugr.core.change_mech_frame(load(DRAUGR_FRAME))
	SpecFactory.apply_passive_buffs(draugr)
	FrameIsolation.isolate_frame(draugr)
	draugr.core.frame.stat.heat = 20
	draugr.core.current.heat = 0
	draugr.core.current.structure = 2 # two missing, so the cap is 3 and nothing below hits it
	victim = _enemy_at(Vector2i(3, 0))

## A stock hostile with enough health to be killed on demand and no armor in the way.
func _enemy_at(tile:Vector2i, faction:Faction.SIDE = Faction.AI_ENEMY) -> Unit:
	var unit := SpecFactory.create_unit(game.map, tile, faction)
	FrameIsolation.isolate_frame(unit)
	unit.core.frame.stat.health = 10
	unit.core.frame.stat.structure = 2
	unit.core.frame.stat.armor = 0
	unit.core.full_repair()
	return unit

## Enough KINETIC to empty the health bar; event_unit_damage.queue_structure_or_stress_if_necessary
## (:235-244) then queues event_unit_structure, which structures and - at zero - queues the death.
func _blow_up(unit:Unit) -> void:
	await SpecFactory.damage(game, unit, 999, Lancer.DAMAGE_TYPE.KINETIC)

func test_a_hostile_losing_a_structure_within_sensors_banks_a_point():
	Dice.CHEAT_ROLL_QUEUE.append(6) # a 6 on the structure table is IMPAIRED, which the fixture survives; unseeded, 4 of 6 outcomes kill a 2-structure unit with no destructible gear
	await SpecFactory.damage(game, victim, 10, Lancer.DAMAGE_TYPE.KINETIC)
	assert_true(Dice.CHEAT_ROLL_QUEUE.is_empty(), 'The structure check consumed its seed.')
	Dice.CHEAT_ROLL_QUEUE.clear()
	assert_eq(victim.core.current.structure, 1, 'Fixture: it lost exactly one structure and lived.')
	assert_eq(Resilience.count(draugr), 1, 'And the Draugr banked a point.')

func test_a_hostile_being_destroyed_within_sensors_banks_a_point():
	# The death path specifically: the reaction's whole filter runs while the corpse is still on the
	# map (plan B3). If it ran a moment later, distance_between would answer 1000 - but this kill
	# goes through event_unit_structure first, which queues `structured` before `death` and banks
	# the point there; the 1/turn limit then swallows `death`. It is
	# test_a_hostile_killed_outright_banks_a_point_through_the_death_trigger, below, that would go
	# red if the death branch broke.
	victim.core.current.structure = 1
	await _blow_up(victim)
	assert_false(Unit.is_valid(victim) and victim.is_on_map(), 'Fixture: it really died.')
	assert_eq(Resilience.count(draugr), 1, 'The Draugr banked a point off the kill.')

func test_a_kill_just_inside_sensors_still_pays():
	# The Draugr's sensor_range is 5. This one sits exactly there.
	var edge := _enemy_at(Vector2i(5, 0))
	edge.core.current.structure = 1
	await _blow_up(edge)
	assert_eq(Resilience.count(draugr), 1, 'Distance 5 is inside SENSORS 5.')

func test_a_kill_beyond_sensors_pays_nothing():
	var distant := _enemy_at(Vector2i(12, 0))
	distant.core.current.structure = 1
	await _blow_up(distant)
	assert_eq(Resilience.count(draugr), 0, 'Distance 12 is outside SENSORS 5.')

func test_an_allys_death_pays_nothing():
	var friend := _enemy_at(Vector2i(2, 0), Faction.PLAYER)
	friend.core.current.structure = 1
	await _blow_up(friend)
	assert_eq(Resilience.count(draugr), 0, '"a hostile character" - allies do not feed it.')

func test_only_one_point_per_turn():
	var second := _enemy_at(Vector2i(2, 0))
	Dice.CHEAT_ROLL_QUEUE.append(6) # a 6 on the structure table is IMPAIRED, which the fixture survives; unseeded, 4 of 6 outcomes kill a 2-structure unit with no destructible gear
	await SpecFactory.damage(game, victim, 10, Lancer.DAMAGE_TYPE.KINETIC)
	Dice.CHEAT_ROLL_QUEUE.append(6) # same, for the second hit
	await SpecFactory.damage(game, second, 10, Lancer.DAMAGE_TYPE.KINETIC)
	assert_true(Dice.CHEAT_ROLL_QUEUE.is_empty(), 'The structure check consumed its seed.')
	Dice.CHEAT_ROLL_QUEUE.clear()
	assert_eq(second.core.current.structure, 1, 'Fixture: the second one structured too.')
	assert_eq(Resilience.count(draugr), 1, '1/turn: the second structure in the same turn paid nothing.')

func test_a_new_turn_reopens_the_allowance():
	# every_new_turn_refresh clears uses_this_turn for EVERY unit at every turn start
	# (unit_action.gd:67-70 from event_turn_start.gd:42-43), so anyone's turn re-arms this.
	var second := _enemy_at(Vector2i(2, 0))
	Dice.CHEAT_ROLL_QUEUE.append(6) # a 6 on the structure table is IMPAIRED, which the fixture survives; unseeded, 4 of 6 outcomes kill a 2-structure unit with no destructible gear
	await SpecFactory.damage(game, victim, 10, Lancer.DAMAGE_TYPE.KINETIC)
	assert_true(Dice.CHEAT_ROLL_QUEUE.is_empty(), 'The structure check consumed its seed.')
	Dice.CHEAT_ROLL_QUEUE.clear()
	await SpecFactory.start_turn(game, victim)
	Dice.CHEAT_ROLL_QUEUE.append(6) # same, for the second hit
	await SpecFactory.damage(game, second, 10, Lancer.DAMAGE_TYPE.KINETIC)
	assert_true(Dice.CHEAT_ROLL_QUEUE.is_empty(), 'The structure check consumed its seed.')
	Dice.CHEAT_ROLL_QUEUE.clear()
	assert_eq(Resilience.count(draugr), 2, 'A fresh turn, a fresh point.')

func test_the_start_of_its_turn_pays_while_it_is_below_four_structure():
	# Its own turn, and its own allowance: this must NOT be blocked by, or block, the kill gain.
	assert_eq(draugr.core.current.structure, 2, 'Fixture: below four.')
	await SpecFactory.start_turn(game, draugr)
	assert_eq(Resilience.count(draugr), 1, 'Start of turn, one point.')
	Dice.CHEAT_ROLL_QUEUE.append(6) # a 6 on the structure table is IMPAIRED, which the fixture survives; unseeded, 4 of 6 outcomes kill a 2-structure unit with no destructible gear
	await SpecFactory.damage(game, victim, 10, Lancer.DAMAGE_TYPE.KINETIC)
	assert_true(Dice.CHEAT_ROLL_QUEUE.is_empty(), 'The structure check consumed its seed.')
	Dice.CHEAT_ROLL_QUEUE.clear()
	assert_eq(Resilience.count(draugr), 2, 'And the kill gain still has its own 1/turn allowance.')

func test_the_start_of_turn_gain_stops_at_full_structure():
	draugr.core.current.structure = 4
	await SpecFactory.start_turn(game, draugr)
	assert_eq(Resilience.count(draugr), 0, '"if it has less than 4 structure" - at four it pays nothing.')

func test_another_units_turn_start_pays_nothing():
	await SpecFactory.start_turn(game, victim)
	assert_eq(Resilience.count(draugr), 0, 'It is the START OF ITS TURN, not of anyone else.')

func test_a_hostile_killed_outright_banks_a_point_through_the_death_trigger():
	# Every hit that empties the last structure fires `structured` first (event_unit_structure.gd:72)
	# and the 1/turn limit then swallows `death`, so the kill tests above never exercise the death
	# trigger. A kill queued straight to event_unit_die (an execution, a scripted death) does.
	await game.execute_event(&'event_unit_die', {unit = victim})
	assert_false(Unit.is_valid(victim) and victim.is_on_map(), 'Fixture: it really died.')
	assert_eq(Resilience.count(draugr), 1, 'Banked through the death trigger alone.')

# ---------- the Carrion Beast's reach (sub-project 6) ----------
# "within SENSORS" is now draugr_reach.within_sensors, which adds 5 against a target carrying
# INFECTION while the Carrion Beast is equipped. Everything else about this reaction is unchanged:
# the whole filter still runs inside triggers_on_event, while the corpse is still on the map.

func _equip_carrion_beast() -> void:
	draugr.core.equip_system(&'ms_carrion_beast')
	SpecFactory.apply_passive_buffs(draugr)
	FrameIsolation.isolate_frame(draugr)
	draugr.core.frame.stat.heat = 20
	draugr.core.current.heat = 0
	draugr.core.current.structure = 2

func test_an_infected_kill_beyond_sensors_pays_with_the_carrion_beast():
	_equip_carrion_beast()
	var distant := _enemy_at(Vector2i(8, 0)) # outside Sensors 5, inside Sensors + 5
	await Infection.apply(SpecFactory.dummy_event({unit = distant}), distant, 1)
	distant.core.current.structure = 1
	await _blow_up(distant)
	assert_eq(Resilience.count(draugr), 1, 'Eight tiles is inside SENSORS 5 + 5 against an infected target.')

func test_an_infected_kill_beyond_sensors_pays_nothing_without_the_carrion_beast():
	var distant := _enemy_at(Vector2i(8, 0))
	await Infection.apply(SpecFactory.dummy_event({unit = distant}), distant, 1)
	distant.core.current.structure = 1
	await _blow_up(distant)
	assert_eq(Resilience.count(draugr), 0, 'INFECTION alone does not widen SENSORS; the system does.')

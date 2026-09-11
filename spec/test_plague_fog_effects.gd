# The three things the plague fog does while the Draugr is standing in it.
#
#   "While you are inside the fog:
#    - Gain 1 Resilience when a hostile character begins their turn inside the fog.
#    - Gain +1 |ACCURACY| on attacks against targets in the fog.
#    - Hostile characters automatically fail |SYSTEMS| checks to remove |INFECTION| at the end of
#      their turn."
#
# All three are gated on "while YOU are inside the fog", so every test below has a paired negative
# with the Draugr stepped out. That gate is the whole design of the ability - the Draugr has to
# stand in its own poison to get anything out of it - and it is the half most likely to be silently
# dropped, because dropping it makes every positive test still pass.
#
# The fog is placed by the real protocol rather than spawned by hand, so this file also stands as an
# integration test of Task 4. SpecFactory.start_turn is required before the protocol
# (unit_action.gd:141) - see test_plague_vent.gd's header.
#
# The accuracy test drives a real attack: attack_roll.gd:182-189 reads Buff.TO.ATTACK_ROLL buffs off
# the attacker and turns each into an accuracy mod, and Dice.roll_d6_accuracy then rolls one d6 per
# point (dice.gd:86-88). So the tell for "+1 accuracy applied" is that an accuracy d6 was consumed at
# all - with no mods, no d6 is rolled and the queue does not advance. That is asserted through the
# damage that lands rather than by reading the roll, so the assertion survives a refactor of PreAttack.
extends GutTest

const FrameIsolation := preload('res://testkit/frame_isolation.gd')
const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')
const Resilience := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/cp_cupiditas_vitae/resilience.gd')
const PlagueFog := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/cp_cupiditas_vitae/plague_fog.gd')
const DRAUGR_FRAME := 'res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/mf_draugr.tres'

const CORE_POWER := &'cp_cupiditas_vitae'
const PROTOCOL := &'action_plague_vent_dispersal'

# GEOMETRY. The fog is a BLAST 2 centred on CENTRE, so "inside" is distance <= 2 from it. The melee
# weapon has threat 1, so every attack below has to be between ADJACENT tiles - which is why the
# out-of-fog positions are one step past the edge rather than across the map.
#
#   (4,1) EDGE_OUT   3 from centre - outside the fog, adjacent to EDGE_IN
#   (4,2) EDGE_IN    2 from centre - inside the fog, adjacent to EDGE_OUT and to INSIDE. The Draugr
#                    starts here: inside its own cloud, and 2 from CENTRE so it can place it.
#   (4,3) INSIDE     1 from centre - inside
#   (4,4) CENTRE
#   (4,9) FAR        5 from centre - outside, and far enough that nothing reaches it
const CENTRE := Vector2i(4, 4)
const EDGE_IN := Vector2i(4, 2)
const EDGE_OUT := Vector2i(4, 1)
const INSIDE := Vector2i(4, 3)
const FAR := Vector2i(4, 9)
const MELEE := &'mw_tactical_melee_weapon' ## 1d6+2 KINETIC, no tags, threat 1

var game:Gamemaster
var draugr:Unit
var victim:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self, false, SpecFactory.create_combat(Landscape.create_default(Vector2i(20, 20))))
	draugr = SpecFactory.create_unit(game.map, EDGE_IN)
	draugr.core.change_mech_frame(load(DRAUGR_FRAME))
	draugr.core.equip_system(MELEE)
	SpecFactory.apply_passive_buffs(draugr)
	FrameIsolation.isolate_frame(draugr)
	draugr.core.frame.stat.heat = 20
	draugr.core.current.heat = 0
	draugr.core.current.structure = 1 # cap 4, so Resilience gains are never clipped
	victim = _enemy_at(INSIDE)

func after_each():
	Dice.CHEAT_ROLL_QUEUE.clear()

func _enemy_at(tile:Vector2i, faction:Faction.SIDE = Faction.AI_ENEMY) -> Unit:
	var unit := SpecFactory.create_unit(game.map, tile, faction)
	FrameIsolation.isolate_frame(unit)
	unit.core.frame.stat.health = 60
	unit.core.frame.stat.evasion = -10 # any d20 lands; the roll is never the variable
	unit.core.frame.stat.armor = 0
	unit.core.full_repair()
	unit.core.current.heat = 0
	return unit

## Vent at CENTRE, with both hostiles passing their placement saves so the starting Infection is 1.
func _vent() -> void:
	await SpecFactory.start_turn(game, draugr)
	Dice.CHEAT_ROLL_QUEUE.append_array([20, 20, 20, 20])
	await SpecFactory.use(game, draugr, CORE_POWER, PROTOCOL, [CENTRE])
	Dice.CHEAT_ROLL_QUEUE.clear()

## UnitTile.move_to(unit, tile) is unit_tile.gd:10 - it repositions and refreshes the tile caches
## without running a move event, which is what a fixture wants.
func _step_draugr_out(tile:Vector2i = EDGE_OUT) -> void:
	UnitTile.move_to(draugr, tile)
	assert_eq(PlagueFog.covering(draugr).size(), 0, 'Fixture: the Draugr is out of its own fog.')

# ---------------------------------------------------------------- Resilience

func test_a_hostile_starting_its_turn_in_the_fog_banks_a_point():
	await _vent()
	var before:int = Resilience.count(draugr)
	await SpecFactory.start_turn(game, victim)
	assert_eq(Resilience.count(draugr) - before, 1, 'One point off the hostile standing in the gas.')

func test_a_hostile_starting_its_turn_outside_the_fog_banks_nothing():
	await _vent()
	UnitTile.move_to(victim, FAR)
	var before:int = Resilience.count(draugr)
	await SpecFactory.start_turn(game, victim)
	assert_eq(Resilience.count(draugr), before, 'Out of the cloud, out of the deal.')

func test_it_banks_nothing_while_the_draugr_stands_outside_its_own_fog():
	await _vent()
	_step_draugr_out()
	var before:int = Resilience.count(draugr)
	await SpecFactory.start_turn(game, victim)
	assert_eq(Resilience.count(draugr), before, '"While you are inside the fog" gates all three effects.')

func test_an_ally_starting_its_turn_in_the_fog_banks_nothing():
	await _vent()
	var friend := _enemy_at(Vector2i(5, 5), Faction.PLAYER)
	var before:int = Resilience.count(draugr)
	await SpecFactory.start_turn(game, friend)
	assert_eq(Resilience.count(draugr), before, '"a hostile character".')

# ---------------------------------------------------------------- accuracy

## One attack with a fixed queue. [10, 6, 3, 4] covers both shapes: with +1 accuracy the engine
## rolls d20 then ONE accuracy d6 (10 + 6 = 16) and then the damage dice; without it there is no
## accuracy die at all - Dice.roll_d6_accuracy returns 0 without touching the queue when the total
## is 0 (dice.gd:86-88) - so the 6 is consumed as the damage die instead. The health delta therefore
## differs, and that is what is asserted.
##
## Nothing else adds or removes accuracy here: the targets have evasion -10 so the d20 always lands,
## the landscape is open so there is no cover, and a MELEE weapon takes no engagement difficulty
## (ActionAttackWeapon.is_difficulty_when_engaged returns weapon_type != MELEE,
## action_attack_weapon.gd:254-255) - which matters, because every attack in this file is between
## adjacent units and would otherwise be engaged.
func _attack(target:Unit) -> int:
	var gear:GearCore = draugr.get_gear(MELEE)
	assert_true(GearCore.is_valid(gear), 'Fixture: the melee weapon is equipped.')
	if not GearCore.is_valid(gear): return 0
	var before:int = target.core.current.health
	Dice.CHEAT_ROLL_QUEUE.append_array([10, 6, 3, 4])
	await game.execute_event('event_gear_activate', {
		action = gear.get_solo_action(), unit = draugr, gear = gear, target_unit = target,
	})
	Dice.CHEAT_ROLL_QUEUE.clear()
	return before - target.core.current.health

func test_an_attack_on_a_target_in_the_fog_gains_an_accuracy_die():
	await _vent()
	var with_fog:int = await _attack(victim)
	assert_eq(with_fog, 5, 'The 6 went to the accuracy die, so the damage die was the 3: 3 + 2.')

func test_an_attack_on_a_target_outside_the_fog_gains_nothing():
	# EDGE_OUT is one step past the cloud's edge and adjacent to the Draugr, so the weapon reaches it.
	await _vent()
	var edge := _enemy_at(EDGE_OUT)
	assert_eq(PlagueFog.covering(edge).size(), 0, 'Fixture: that one is out of the gas.')
	assert_eq(await _attack(edge), 8, 'No accuracy die was rolled, so the 6 was the damage die: 6 + 2.')

func test_the_accuracy_bonus_needs_the_draugr_in_the_fog_too():
	# The Draugr steps out to EDGE_OUT and a hostile takes the EDGE_IN tile it vacated: still in the
	# gas, still adjacent, and now the only thing that has changed is where the Draugr is standing.
	await _vent()
	_step_draugr_out()
	var edge_victim := _enemy_at(EDGE_IN)
	assert_eq(PlagueFog.covering(edge_victim).size(), 1, 'Fixture: the target is still in the gas.')
	assert_eq(UnitRelation.distance_between(draugr, edge_victim), 1, 'Fixture: and still in reach.')
	assert_eq(await _attack(edge_victim), 8, '"While you are inside the fog".')

# ---------------------------------------------------------------- Infection auto-fail

func test_a_hostile_in_the_fog_automatically_fails_its_infection_check():
	await _vent()
	assert_eq(Infection.count(victim), 1, 'Fixture: the placement save gave it one Infection.')
	var heat_before:int = victim.core.current.heat
	Dice.CHEAT_ROLL_QUEUE.append_array([20]) # a natural 20 would pass the check outright
	await SpecFactory.pass_turn(game, victim)
	assert_true(Infection.is_infected(victim), 'The Infection did not clear.')
	assert_eq(victim.core.current.heat - heat_before, 1, 'And it took heat equal to the count.')

func test_a_hostile_outside_the_fog_still_gets_its_roll():
	await _vent()
	UnitTile.move_to(victim, FAR)
	Dice.CHEAT_ROLL_QUEUE.append_array([20])
	await SpecFactory.pass_turn(game, victim)
	assert_false(Infection.is_infected(victim), 'Out of the fog, a 20 clears it as normal.')

func test_the_auto_fail_needs_the_draugr_in_the_fog_too():
	await _vent()
	_step_draugr_out()
	Dice.CHEAT_ROLL_QUEUE.append_array([20])
	await SpecFactory.pass_turn(game, victim)
	assert_false(Infection.is_infected(victim), '"While you are inside the fog" - the Draugr left, so the check is fair.')

func test_an_allys_infection_check_is_never_sabotaged():
	# The fog inherits the Draugr's faction. A Draugr does not make its own side's recovery harder.
	await _vent()
	var friend := _enemy_at(Vector2i(5, 5), Faction.PLAYER)
	await Infection.apply(SpecFactory.dummy_event({unit = friend}), friend, 1)
	Dice.CHEAT_ROLL_QUEUE.append_array([20])
	await SpecFactory.pass_turn(game, friend)
	assert_false(Infection.is_infected(friend), 'Allies roll normally.')

# The Ceaseless Death, the spending half.
#
#   "After |OVERSHIELD| is reduced, if the Draugr would take damage while it has Resilience, it
#    reduces all remaining damage to 1 and loses 1 Resilience. If the Draugr is |SHREDDED| or the
#    damage would ignore |RESISTANCE|, it takes the damage as normal and still loses 1 Resilience."
#
# A buff on the Draugr with triggers_on = [damage], trigger_timing = PRE, which decrements the
# counter and - unless the engine is about to ignore reductions anyway - applies a ONE-SHOT cap buff
# cloned from the Napoleon's Flash Aegis (buff_flash_aegis.tres: BuffResistDamage,
# cap_instead_of_resist, is_onetime).
#
# WHY THE CAP IS DYNAMIC. event_unit_damage.gd applies the cap at :93-94 and only then calls
# damage(), which subtracts OVERSHIELD at :215-218. So a flat cap of 1 would be eaten by the
# overshield and let nothing through - the opposite of "after OVERSHIELD is reduced". The cap is
# overshield + 1, computed at get_values time, which the engine recomputes at :62-63 after the PRE
# reactions have run. test_overshield_is_spent_first_and_then_one_point_lands is that arithmetic.
#
# WHY THE TWO EXCEPTIONS ARE EXPLICIT. Neither is something the engine does for us:
#   NO_REDUCE  damage_modifications.gd:59 returns BEFORE the cap is collected at :62, so an
#              irreducible hit is never capped anyway - but the buff would still be applied, and
#              never consumed (:113 is unreachable on that path), so it would cap the NEXT hit.
#   SHREDDED   :73-77 returns AFTER the cap was collected, so a shredded Draugr WOULD still be
#              capped if we applied the buff. The rules say it should not be. And again the buff
#              would leak, for the same reason.
# Both spend a point regardless. The two "still spends" tests are the point of this file.
extends GutTest

const Resilience := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/cp_cupiditas_vitae/resilience.gd')
const DRAUGR_FRAME := 'res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/mf_draugr.tres'

const CAP_BUFF := &'buff_ceaseless_death_cap'

var game:Gamemaster
var draugr:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	draugr = SpecFactory.create_unit(game.map, Vector2i(0, 0))
	draugr.core.change_mech_frame(load(DRAUGR_FRAME))
	SpecFactory.apply_passive_buffs(draugr)
	draugr.core.current.armor = 0 # armor would confound every damage number below; current is a
	# SEPARATE Statblock, snapshotted by the full_repair inside apply_passive_buffs
	# (unit_printer.gd:73), and damage_modifications.gd:97 reads current - not frame.stat, which is
	# also a shared, cached Frame resource that must not be mutated by a spec (memory:
	# lancer-tactics-engine-gotchas-tear).
	draugr.core.frame.stat.heat = 20
	draugr.core.current.heat = 0
	draugr.core.current.structure = 1 # three missing, so the cap is 4 and _bank never clips
	draugr.core.current.health = draugr.get_health_max()

func _bank(n:int) -> void:
	Resilience.gain(draugr, n)
	assert_eq(Resilience.count(draugr), n, 'Fixture: %s Resilience banked.' % n)

func _health_lost_from(amount:int, type:Lancer.DAMAGE_TYPE = Lancer.DAMAGE_TYPE.KINETIC, flags:Array = []) -> int:
	var before:int = draugr.core.current.health
	await SpecFactory.damage(game, draugr, amount, type, flags)
	return before - draugr.core.current.health

func test_with_no_resilience_damage_lands_in_full():
	assert_eq(await _health_lost_from(5), 5, 'Nothing banked, nothing shrugged off.')

func test_one_point_reduces_the_hit_to_one():
	_bank(1)
	assert_eq(await _health_lost_from(5), 1, '"reduces all remaining damage to 1".')
	assert_eq(Resilience.count(draugr), 0, 'And it cost the point.')

func test_it_only_spends_one_point_per_instance():
	_bank(3)
	assert_eq(await _health_lost_from(5), 1, 'Capped.')
	assert_eq(Resilience.count(draugr), 2, 'Exactly one point, not the whole pool.')

func test_a_second_instance_needs_a_second_point():
	_bank(2)
	assert_eq(await _health_lost_from(5), 1, 'First hit capped.')
	assert_eq(await _health_lost_from(5), 1, 'Second hit capped too.')
	assert_eq(Resilience.count(draugr), 0, 'Two hits, two points.')
	assert_eq(await _health_lost_from(5), 5, 'And the third arrives at full strength.')

func test_the_cap_does_not_linger_into_an_unprotected_hit():
	# The cap buff is is_onetime and event_unit_damage.gd:73-77 consumes it. If it ever leaked, this
	# is the test that would catch it - and that leak is the exact failure the SHREDDED and
	# NO_REDUCE branches exist to prevent.
	_bank(1)
	assert_eq(await _health_lost_from(5), 1, 'Fixture: the point was spent on the first hit.')
	assert_eq(UnitCondition.get_buffs(draugr, CAP_BUFF).size(), 0, 'The one-shot cap was consumed.')
	assert_eq(await _health_lost_from(5), 5, 'So the next hit is not capped.')

func test_overshield_is_spent_first_and_then_one_point_lands():
	_bank(1)
	draugr.state.overshield = 3
	assert_eq(await _health_lost_from(5), 1, 'Overshield ate 3; 1 reached health.')
	assert_eq(draugr.state.overshield, 0, 'And the overshield is gone.')

func test_a_shredded_draugr_takes_it_all_and_still_pays():
	SpecFactory.apply(draugr, Lancer.STATUS.SHREDDED)
	assert_true(draugr.has_status(Lancer.STATUS.SHREDDED), 'Fixture: SHREDDED.')
	_bank(1)
	assert_eq(await _health_lost_from(5), 5, '"it takes the damage as normal".')
	assert_eq(Resilience.count(draugr), 0, '"and still loses 1 Resilience".')
	assert_eq(UnitCondition.get_buffs(draugr, CAP_BUFF).size(), 0, 'And no cap buff was left behind.')

func test_irreducible_damage_takes_it_all_and_still_pays():
	_bank(1)
	assert_eq(await _health_lost_from(5, Lancer.DAMAGE_TYPE.KINETIC, [EventService.DAMAGE_FLAG.NO_REDUCE]), 5,
		'"the damage would ignore RESISTANCE".')
	assert_eq(Resilience.count(draugr), 0, 'And still loses the point.')
	assert_eq(UnitCondition.get_buffs(draugr, CAP_BUFF).size(), 0, 'And no cap buff was left behind.')

func test_heat_is_not_damage_and_is_left_alone():
	# Infection applies HEAT (infection.gd:56-58). If Resilience burned a point on every point of
	# Infection the Draugr took, the whole License I loop would drain it. Lancer does not call heat
	# damage, and neither do we.
	_bank(1)
	var before:int = draugr.core.current.heat
	await SpecFactory.damage(game, draugr, 3, Lancer.DAMAGE_TYPE.HEAT)
	assert_eq(draugr.core.current.heat - before, 3, 'All three points of heat arrived.')
	assert_eq(Resilience.count(draugr), 1, 'And nothing was spent.')

func test_burn_is_damage_and_is_capped():
	# BURN goes through event_unit_damage's non-HEAT branch (:117-123) and is real damage, so the
	# rules' unqualified "damage" covers it. Lancer.DAMAGE_TYPE is {KINETIC, ENERGY, EXPLOSIVE, HEAT,
	# BURN} (lancer.gd:110) - BURN and HEAT are NOT the same type.
	_bank(1)
	assert_eq(await _health_lost_from(5, Lancer.DAMAGE_TYPE.BURN), 1, 'Burn damage is capped like any other.')
	assert_eq(Resilience.count(draugr), 0, 'And costs a point.')

func test_self_inflicted_damage_is_capped_like_any_other():
	# DECISION C1. The rules give no exclusion, so resist_self_inflicted = true - unlike vanilla's
	# Flash Aegis, which sets it false (buff_resist_damage.gd:23, buff_flash_aegis.gd:6-7).
	# Sub-project 4's Dig In deals SELF_INFLICTED damage and should carry NO_REDUCE if it wants to
	# bypass this. If the controller reverses C1, this test flips to assert 5 and 1.
	_bank(1)
	assert_eq(await _health_lost_from(5, Lancer.DAMAGE_TYPE.KINETIC, [EventService.DAMAGE_FLAG.SELF_INFLICTED]), 1,
		'Self-inflicted damage is still damage.')
	assert_eq(Resilience.count(draugr), 0, 'And costs a point.')

func test_a_hit_overshield_absorbs_entirely_spends_nothing():
	# "After reducing OVERSHIELD, if the Draugr would take damage": nothing lands, nothing is spent.
	Resilience.gain(draugr, 1)
	draugr.state.overshield = 5
	var before := draugr.core.current.health
	await SpecFactory.damage(game, draugr, 3, Lancer.DAMAGE_TYPE.KINETIC)
	assert_eq(draugr.core.current.health, before, 'Overshield took all of it.')
	assert_eq(draugr.state.overshield, 2, 'Three points of overshield gone.')
	assert_eq(Resilience.count(draugr), 1, 'No Resilience spent on a hit that dealt nothing.')

func test_a_hit_armor_zeroes_spends_nothing():
	# The Draugr has armor 1: a 1-damage kinetic hit is already 0 before Resilience is asked.
	Resilience.gain(draugr, 1)
	draugr.core.current.armor = 1
	var before := draugr.core.current.health
	await SpecFactory.damage(game, draugr, 1, Lancer.DAMAGE_TYPE.KINETIC)
	assert_eq(draugr.core.current.health, before, 'Armor ate the point.')
	assert_eq(Resilience.count(draugr), 1, 'No Resilience spent.')

func test_one_attack_with_two_damage_types_costs_one_point():
	# The engine fires one damage event per damage type and keeps resist buffs alive between them
	# (SKIP_CONSUMING_RESIST_BUFFS on all but the last). One Resilience covers the whole attack.
	Resilience.gain(draugr, 2)
	var before := draugr.core.current.health
	await SpecFactory.damage(game, draugr, 3, Lancer.DAMAGE_TYPE.KINETIC, [EventService.DAMAGE_FLAG.SKIP_CONSUMING_RESIST_BUFFS])
	await SpecFactory.damage(game, draugr, 3, Lancer.DAMAGE_TYPE.ENERGY)
	assert_eq(before - draugr.core.current.health, 2, 'Each sub-instance capped to 1.')
	assert_eq(Resilience.count(draugr), 1, 'One point for the whole attack.')

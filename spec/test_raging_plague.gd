# The Raging Plague. "The Draugr's melee attacks gain OVERKILL against targets with |INFECTION|."
# (localizations.csv, gear.mt_raging_plague.effect)
#
# A BuffWeaponTypeTag on the Draugr, handed out by a PassiveBuffApplicator on mt_raging_plague.
# The whole risk in this trait is WHICH CONTEXT is asked whether the tag applies: overkill is
# decided from the event_unit_attack_declared context, which carries no target_unit at all (see the
# plan's section B2, and buff_raging_plague.gd's header). test_the_tag_is_live_in_the_context_that_
# decides_overkill is the direct proof of that; every other test here is the behaviour it buys.
#
# Dice arithmetic (plan section B3): queue [10, 1, 2, 4] against mw_tactical_melee_weapon (1d6+2).
# WITH overkill the 1 rerolls to 4, so damage is 4+2=6 and the Draugr takes 1 heat. WITHOUT it the
# 1 stands, damage is 1+2=3 and there is no heat - and the unused 4 is why after_each clears.
extends GutTest

const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')
const DRAUGR_FRAME := 'res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/mf_draugr.tres'

const MELEE := &'mw_tactical_melee_weapon' ## 1d6+2 KINETIC, weapon_type 2 (MELEE), no inherent tags
const RANGED := &'mw_assault_rifle'        ## the not-melee control

var game:Gamemaster
var draugr:Unit
var target:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	draugr = _draugr_at(Vector2i(0, 0))
	target = _target_at(Vector2i(1, 0))

func after_each():
	Dice.CHEAT_ROLL_QUEUE.clear()

func _draugr_at(tile:Vector2i) -> Unit:
	var unit := SpecFactory.create_unit(game.map, tile)
	unit.core.change_mech_frame(load(DRAUGR_FRAME))
	unit.core.equip_system(MELEE)
	unit.core.equip_system(RANGED)
	SpecFactory.apply_passive_buffs(unit) # runs mt_raging_plague's PassiveBuffApplicator
	unit.core.frame.stat.heat = 20
	unit.core.current.heat = 0
	return unit

func _target_at(tile:Vector2i) -> Unit:
	var unit := SpecFactory.create_unit(game.map, tile, Faction.AI_ENEMY)
	unit.core.frame.stat.health = 40
	unit.core.frame.stat.evasion = -10 # any d20 lands; the roll is never the variable
	unit.core.frame.stat.armor = 0
	unit.core.full_repair()
	return unit

func _infect(unit:Unit, n:int) -> void:
	await Infection.apply(SpecFactory.dummy_event({unit = unit}), unit, n)

## One attack, with the queue from the file header.
func _attack(attacker:Unit, weapon_id:StringName, victim:Unit) -> void:
	var gear:GearCore = attacker.get_gear(weapon_id)
	assert_true(GearCore.is_valid(gear), 'Fixture: %s is equipped.' % weapon_id)
	if not GearCore.is_valid(gear): return
	Dice.CHEAT_ROLL_QUEUE.append_array([10, 1, 2, 4])
	await game.execute_event('event_gear_activate', {
		action = gear.get_solo_action(), unit = attacker, gear = gear, target_unit = victim,
	})

func test_a_melee_attack_on_an_uninfected_target_does_not_overkill():
	var health:int = target.core.current.health
	await _attack(draugr, MELEE, target)
	assert_eq(health - target.core.current.health, 3, 'The 1 stood: 1 + 2 damage.')
	assert_eq(draugr.core.current.heat, 0, 'And no overkill heat.')

func test_a_melee_attack_on_an_infected_target_overkills():
	await _infect(target, 1)
	var health:int = target.core.current.health
	await _attack(draugr, MELEE, target)
	assert_eq(health - target.core.current.health, 6, 'The 1 was rerolled to a 4: 4 + 2 damage.')
	assert_eq(draugr.core.current.heat, 1, 'And the Draugr took a point of overkill heat.')

func test_a_ranged_attack_on_an_infected_target_does_not_overkill():
	await _infect(target, 1)
	await _attack(draugr, RANGED, target)
	assert_eq(draugr.core.current.heat, 0, 'weapon_types = [MELEE] keeps the rifle out of it.')

func test_a_unit_without_the_trait_does_not_overkill():
	var stranger := SpecFactory.create_unit(game.map, Vector2i(0, 1))
	stranger.core.equip_system(MELEE)
	stranger.core.full_repair()
	stranger.core.frame.stat.heat = 20
	stranger.core.current.heat = 0
	await _infect(target, 1)
	var health:int = target.core.current.health
	await _attack(stranger, MELEE, target)
	assert_eq(health - target.core.current.health, 3, 'No trait, no reroll.')
	assert_eq(stranger.core.current.heat, 0, 'And no heat.')

func test_clearing_the_infection_takes_the_overkill_with_it():
	await _infect(target, 2)
	Infection.clear(SpecFactory.dummy_event(), target)
	var health:int = target.core.current.health
	await _attack(draugr, MELEE, target)
	assert_eq(health - target.core.current.health, 3, 'Not infected any more, so no overkill.')

func test_the_tag_is_live_in_the_context_that_decides_overkill():
	# THE ENGINE FACT THIS TRAIT STANDS ON, asserted directly rather than inferred from damage.
	# This rebuilds exactly the context action_attack.gd:266-272 hands to event_unit_attack_declared
	# - unit, gear, action, resource and nothing else - and asks the same question
	# action_attack_weapon.gd:257 asks. If a modkit update ever starts passing target_unit here, this
	# still passes (the buff prefers target_unit when it has one) and nothing needs changing; if the
	# DeclaredAttackSummary stops being reachable, this goes red before any damage assertion does.
	await _infect(target, 1)
	var specific := SpecificAction.from_id(draugr, MELEE)
	assert_true(SpecificAction.is_valid(specific), 'Fixture: the melee weapon resolves to an action.')
	if not SpecificAction.is_valid(specific): return

	var attacked:Array[Unit] = [target]
	var no_tiles:Array[Vector2i] = []
	var no_voxels:Array[Vector3i] = []
	var declared := DeclaredAttackSummary.create(attacked, no_tiles, no_tiles, no_voxels)
	var declared_context := Context.create({
		unit = draugr, gear = specific.gear, action = specific.action, resource = declared,
	})
	assert_null(declared_context.target_unit, 'The declared context genuinely has no target_unit.')
	assert_true(specific.action.is_overkill(declared_context), 'And OVERKILL is granted anyway.')

	Infection.clear(SpecFactory.dummy_event(), target)
	assert_false(specific.action.is_overkill(declared_context), 'Cured, and the tag goes away.')

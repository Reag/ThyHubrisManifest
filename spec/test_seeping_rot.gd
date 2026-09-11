# The Seeping Rot. "When the Draugr triggers |OVERKILL|, the target gains 1 |INFECTION|."
# (localizations.csv, gear.mt_seeping_rot.effect)
#
# An OnHitEffect at on_resolution, injected onto every attack by buff_seeping_rot
# (BuffWeaponTypeOnHit, Buff.TO.ONHIT_EFFECT) which mt_seeping_rot hands out through a
# PassiveBuffApplicator. Overkill is only knowable after the whole declared attack has rolled its
# damage, which is why this is on_resolution and not on_hit - see onhit_seeping_rot.gd's header and
# the plan's section B1.
#
# Driven with mw_segment_knife (1d3+1, inherent OVERKILL tag) rather than with The Raging Plague, so
# this suite fails only when THIS trait is broken. One composition test at the bottom drives the two
# together, because that pairing is the whole point of the frame.
#
# Dice (plan section B3): the knife is a d3. [10, 1, 2, 3] => hit_rolls [1], crit_rolls [2], the 1
# rerolls to 3 for one overkill tick. [10, 2, 3] => no 1s, no overkill, and no leftovers.
extends GutTest

const FrameIsolation := preload('res://testkit/frame_isolation.gd')
const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')
const DRAUGR_FRAME := 'res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/mf_draugr.tres'

const KNIFE := &'mw_segment_knife'          ## 1d3+1, tags = [overkill]
const PLAIN_MELEE := &'mw_tactical_melee_weapon' ## 1d6+2, no tags - for the composition test

var game:Gamemaster
var draugr:Unit
var target:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	draugr = SpecFactory.create_unit(game.map, Vector2i(0, 0))
	draugr.core.change_mech_frame(load(DRAUGR_FRAME))
	draugr.core.equip_system(KNIFE)
	draugr.core.equip_system(PLAIN_MELEE)
	SpecFactory.apply_passive_buffs(draugr)
	FrameIsolation.isolate_frame(draugr)
	draugr.core.frame.stat.heat = 20
	draugr.core.current.heat = 0

	target = SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	FrameIsolation.isolate_frame(target)
	target.core.frame.stat.health = 40
	target.core.frame.stat.evasion = -10
	target.core.frame.stat.armor = 0
	target.core.full_repair()
	target.core.current.heat = 0

func after_each():
	Dice.CHEAT_ROLL_QUEUE.clear()

func _attack(attacker:Unit, weapon_id:StringName, victim:Unit, rolls:Array) -> void:
	var gear:GearCore = attacker.get_gear(weapon_id)
	assert_true(GearCore.is_valid(gear), 'Fixture: %s is equipped.' % weapon_id)
	if not GearCore.is_valid(gear): return
	Dice.CHEAT_ROLL_QUEUE.append_array(rolls)
	await game.execute_event('event_gear_activate', {
		action = gear.get_solo_action(), unit = attacker, gear = gear, target_unit = victim,
	})

func test_an_overkilling_hit_infects_the_target():
	await _attack(draugr, KNIFE, target, [10, 1, 2, 3])
	assert_eq(draugr.core.current.heat, 1, 'Fixture: the attack really did overkill once.')
	assert_eq(Infection.count(target), 1, 'And the target caught one Infection.')

func test_a_hit_that_does_not_overkill_infects_nobody():
	await _attack(draugr, KNIFE, target, [10, 2, 3])
	assert_eq(draugr.core.current.heat, 0, 'Fixture: no overkill.')
	assert_eq(Infection.count(target), 0, 'So nothing to catch.')

func test_a_miss_infects_nobody():
	# A missed roll still HAS a damage summary (event_unit_attack_declared.gd:145 assigns one to
	# every roll, hit or not), and that summary still carries the overkill heat from the dice. Reading
	# it without checking roll.hit would infect on a miss.
	FrameIsolation.isolate_frame(target)
	target.core.frame.stat.evasion = 50
	target.core.full_repair()
	await _attack(draugr, KNIFE, target, [1, 1, 2, 3])
	assert_eq(Infection.count(target), 0, 'A miss overkills nothing.')

func test_a_second_overkill_stacks_a_second_point():
	await _attack(draugr, KNIFE, target, [10, 1, 2, 3])
	Dice.CHEAT_ROLL_QUEUE.clear()
	# DEVIATION FROM THE BRIEF (documented in task-2-report.md): the engine's no-repeat-action rule
	# (action.gd:161-163, get_per_turn_soft_limit == 1 for a non-free QUICK action) blocks a second
	# use of the SAME gear within one turn. Without a turn boundary here the second _attack below
	# aborts with "invalid context! ... specific: invalid" (UnitAction.can_activate_gear returning
	# false) and Infection.count never moves - confirmed live 2026-09-09.
	# SpecFactory.start_turn alone is enough: event_turn_start.execute() unconditionally clears
	# uses_this_turn for every gear on every map unit (UnitAction.every_new_turn_refresh, called for
	# "pan_unit in context.map.get_all_units()" regardless of whose turn it is), and event_turn_start
	# has no is_taking_turn precondition (unlike event_turn_end, which requires it already true - the
	# fresh draugr from SpecFactory.create_unit starts with is_taking_turn false, so end_turn would
	# itself abort here). It does not reapply buff_seeping_rot / buff_raging_plague -
	# PassiveBuffApplicator.reapply_at_the_start_of_each_turn defaults false and neither trait sets it
	# - so this cannot double the ONHIT_EFFECT buff.
	await SpecFactory.start_turn(game, draugr)
	await _attack(draugr, KNIFE, target, [10, 1, 2, 3])
	assert_eq(Infection.count(target), 2, 'One per overkilling attack, added on top.')

func test_the_raging_plague_and_the_seeping_rot_compose():
	# The frame's actual loop: an already-infected target makes a plain melee weapon OVERKILL (Task
	# 1), and that overkill then feeds the target another Infection (this task). Neither trait's own
	# suite covers the pair, and this is the interaction the frame is built around.
	await Infection.apply(SpecFactory.dummy_event({unit = target}), target, 1)
	assert_eq(Infection.count(target), 1, 'Fixture: one to start with.')
	await _attack(draugr, PLAIN_MELEE, target, [10, 1, 2, 4])
	assert_eq(draugr.core.current.heat, 1, 'The Raging Plague granted OVERKILL and it triggered.')
	assert_eq(Infection.count(target), 2, 'The Seeping Rot added the second point.')

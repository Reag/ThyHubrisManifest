# To Twist Truth. Asserts on UnitCondition.get_invisibility_summary(...).ignores_invisible DIRECTLY,
# never on damage. Our buff's d6 and vanilla's miss-check d6 (attack_util.gd:74) both pop from
# Dice.CHEAT_ROLL_QUEUE - the queue order is load-bearing, and a damage-based assertion could pass
# while proving the opposite of what it claims (or nothing at all: SpecFactory hands a queued plan
# straight to an attack with no range validation, so damage proves plumbing, not this buff - the same
# mocked-CompconPlan lesson test_to_bend_reality.gd learned).
# See D:\DEV\lancer-tactics-claude\specs\2026-09-06-banshee-remaining-traits-design.md, "To Twist
# Truth" section, for the full design and the probability-equivalence arithmetic.
extends GutTest

const BANSHEE_FRAME := 'res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/mf_banshee.tres'
const BUFF_ID := &'buff_to_twist_truth'

var game:Gamemaster
var banshee:Unit
var target:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	banshee = SpecFactory.create_unit(game.map, Vector2i(1,1))
	target = SpecFactory.create_unit(game.map, Vector2i(5,1), Faction.AI_ENEMY)
	SpecFactory.apply(target, Lancer.STATUS.INVISIBLE)

## Arms the Banshee with its own frame. change_mech_frame, NOT core.frame = load(...) - the latter
## skips loadout.regenerate_derived_gear (unit_printer.gd:94), so the trait's PassiveBuffApplicator
## never runs and buff_to_twist_truth is never applied.
func _arm_banshee() -> void:
	banshee.core.change_mech_frame(load(BANSHEE_FRAME))
	SpecFactory.apply_passive_buffs(banshee)

func _attack_context() -> Context:
	return Context.create({unit = banshee, target_unit = target, map = game.map})

func test_the_banshee_has_the_buff_once_armed():
	_arm_banshee()
	assert_true(UnitCondition.has_buff(banshee, BUFF_ID),
		'Sanity check: To Twist Truth is equipped and its passive applies the buff.')

func test_a_low_roll_ignores_invisibility_on_the_banshees_own_attack():
	_arm_banshee()
	Dice.CHEAT_ROLL_QUEUE = [1] # <=3 -> ignore invisibility
	var summary := UnitCondition.get_invisibility_summary(_attack_context())
	assert_true(summary.ignores_invisible,
		'A low roll (<=3) makes the Banshee ignore invisibility on its own attack.')

func test_a_high_roll_does_not_ignore_invisibility():
	_arm_banshee()
	Dice.CHEAT_ROLL_QUEUE = [6] # >3 -> do not ignore
	var summary := UnitCondition.get_invisibility_summary(_attack_context())
	assert_false(summary.ignores_invisible,
		'A high roll (>3) leaves invisibility unignored - the ordinary vanilla check still applies.')

func test_the_trait_never_applies_when_the_banshee_is_the_target():
	# THE GATE. get_invisibility_summary asks BOTH parties (unit_condition.gd:453) for their
	# IGNORE_INVISIBLE buffs, so with no gate the Banshee's own buff would also fire when it is the
	# one being shot AT. Queue a low roll: without `core.get_owner_unit(context.map) != context.unit`
	# the gateless code would call Dice.roll_d6(), pop this 1, and wrongly report ignores_invisible.
	_arm_banshee()
	SpecFactory.apply(banshee, Lancer.STATUS.INVISIBLE)
	Dice.CHEAT_ROLL_QUEUE = [1]
	var reverse_context := Context.create({unit = target, target_unit = banshee, map = game.map})
	var summary := UnitCondition.get_invisibility_summary(reverse_context)
	assert_false(summary.ignores_invisible,
		'The trait never fires when the Banshee is the TARGET rather than the attacker, whatever the roll.')

func test_without_the_trait_equipped_invisibility_is_never_ignored():
	# Banshee is never armed with the frame here, so no buff exists to apply at all.
	Dice.CHEAT_ROLL_QUEUE = [1]
	var summary := UnitCondition.get_invisibility_summary(_attack_context())
	assert_false(summary.ignores_invisible,
		'Without To Twist Truth equipped, invisibility is never ignored, whatever the roll.')

## THE STRAY-ROLL FIX. Proves the corruption directly: if the trait rolled unconditionally, this
## queued [1] would be popped and the queue would come back empty. It must come back untouched,
## because nothing in this attack is invisible at all - the target here carries no INVISIBLE
## status and no TREAT_AS_INVISIBLE buff. This is exactly what was silently eating queued rolls
## out from under spec/test_to_bend_reality.gd (a rail rifle's 1d6+1 damage roll), one Banshee
## attack at a time.
##
## Reverting the gate in buff_to_twist_truth.gd back to the bare `return Dice.roll_d6() <= 3`
## makes this fail: Dice.CHEAT_ROLL_QUEUE ends up [] instead of [1]. Confirmed 2026-09-07 (see
## D:\DEV\lancer-tactics-claude\.superpowers\sdd\ttt-stray-roll-fix.md for the failure output).
func test_no_die_is_rolled_when_nothing_is_invisible():
	_arm_banshee()
	var visible_target := SpecFactory.create_unit(game.map, Vector2i(5,3), Faction.AI_ENEMY)
	Dice.CHEAT_ROLL_QUEUE = [1]
	var context := Context.create({unit = banshee, target_unit = visible_target, map = game.map})
	UnitCondition.get_invisibility_summary(context)
	assert_eq(Dice.CHEAT_ROLL_QUEUE, [1],
		'Nothing is invisible in this attack, so the trait must not touch the dice queue at all.')

## THE CASE THE TRAIT EXISTS FOR. get_invisibility_summary treats a TREAT_AS_INVISIBLE buff on
## either party as equivalent to the INVISIBLE status (unit_condition.gd:456-457) - that is how the
## Banshee's own tear-attacks (buff_tear_invisibility, a TREAT_AS_INVISIBLE buff with no real
## geometry wired up here) reach this trait at all, with no STATUS.INVISIBLE anywhere in sight.
## Wiring an actual tear into this fixture is a lot of unrelated setup (TearRouting geometry, a
## second frame placed on the map) just to prove the gate reads TREAT_AS_INVISIBLE - so this uses
## vanilla's buff_flicker_field_projector (content/gear/ssc/systems/ms_flicker_field_projector),
## a plain `to = &"treat_as_invisible"` buff whose own check_if_passive_applies only requires the
## holder to be the attack's target - same shape as buff_tear_invisibility from the gate's point of
## view, without needing a tear on the map.
func test_the_trait_still_fires_for_a_target_made_invisible_only_by_a_treat_as_invisible_buff():
	_arm_banshee()
	var buffed_target := SpecFactory.create_unit(game.map, Vector2i(5,3), Faction.AI_ENEMY)
	SpecFactory.apply_buff(buffed_target, &'buff_flicker_field_projector')
	Dice.CHEAT_ROLL_QUEUE = [1] # <=3 -> ignore invisibility
	var context := Context.create({unit = banshee, target_unit = buffed_target, map = game.map})
	var summary := UnitCondition.get_invisibility_summary(context)
	assert_true(summary.ignores_invisible,
		'A TREAT_AS_INVISIBLE buff on the target, with no INVISIBLE status at all, still opens the gate and lets the trait fire.')

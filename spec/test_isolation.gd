# Isolation - the first of Quarantine's two Invade options.
#
#   "Your target takes 2 INFECTION instead of Invade's normal heat and cannot take reactions until the
#    end of their next turn."
#
# get_damage_dice -> '' is "instead of Invade's normal heat": ActionAttackTech.get_damage_dice
# (action_attack_tech.gd:17) returns '2' for every invade, and that is the heat this replaces. The only
# heat the target takes is the 2 that Infection itself deals.
#
# ==================== WHAT ACTUALLY STOPS A REACTION ====================
# buff_isolation is `to = action_forbidden` with the Infiltrator's Ambush filter verbatim. The gate is
# UnitAction.get_gear_unavailable_reason's last clause (unit_action.gd:157, REASON.FORBIDDEN), and
# EVERY reaction passes through it TWICE:
#   - at QUEUE time: ReactionBus.does_reaction_trigger's fifth clause is
#     UnitAction.can_activate_gear(...) (reaction_bus.gd:121), which calls is_gear_available FIRST,
#     before its as_freebie shortcut - so a forbidden reaction is never even turned into an EventBlock.
#   - at EXECUTE time: event_gear_activate.check_specific_context re-runs it (:33-52) and prints
#     "[ Gear not available ] reason : FORBIDDEN" in red.
# test_an_isolated_unit_cannot_dig_in is the end-to-end proof of the first gate; the three
# get_gear_unavailable_reason tests are the precise ones.
#
# WHY THE "FREE TRAIT REACTION STILL FIRES" TEST ASSERTS THE GATE AND NOT A TRIGGER (plan decision D7):
# event_turn_end.gd:40 expires END_OF_NEXT_TURN buffs BEFORE :46 queues the END_TURN/POST reactions, so
# any test that drove a POST trait reaction would find the Isolation already gone and pass for the
# wrong reason.
#
# ==================== DURATION ====================
# until = 1 is Lancer.UNTIL.END_OF_NEXT_TURN (lancer.gd:46-48). turn_count rises only on the HOLDER's
# own turn start (unit_condition.gd:15-30) and END_OF_NEXT_TURN clears at turn_count >= 1
# (:33-49), so a lock applied on the Draugr's turn survives the Draugr's turn end and dies at the end
# of the target's next turn.
extends GutTest

const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')
const InfectionLinks := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection_links.gd')

const QUARANTINE := &'ms_quarantine'
const ISOLATION := &'action_isolation'
const ISOLATION_BUFF := &'buff_isolation'
const DISEASE := &'ms_disease'
const SYMPTOM := &'action_symptom'
const ROOT := &'ms_root'
const DIG_IN := &'action_dig_in'
const REGENERATION := &'mt_regeneration' ## the Balor's consumes_rxn = false trait

var game:Gamemaster
var draugr:Unit
var target:Unit
var shover:Unit
var quarantine:GearCore

func before_each():
	# 20x20, not the 5x5 default (memory item 6): test_an_isolated_unit_cannot_dig_in shoves someone.
	game = SpecFactory.setup_gamemaster(self, false, SpecFactory.create_combat(Landscape.create_default(Vector2i(20, 20))))
	draugr = SpecFactory.create_unit(game.map, Vector2i(5, 5), Faction.PLAYER)
	quarantine = draugr.core.equip_system(QUARANTINE)
	draugr.core.full_repair()
	target = _victim_at(Vector2i(6, 5))
	shover = SpecFactory.create_unit(game.map, Vector2i(7, 5), Faction.PLAYER)
	shover.core.full_repair()

func after_each():
	Dice.CHEAT_ROLL_QUEUE.clear()

func _victim_at(tile:Vector2i) -> Unit:
	var unit := SpecFactory.create_unit(game.map, tile, Faction.AI_ENEMY)
	unit.core.frame.stat.edef = -10 # a cheated 20 always lands
	unit.core.frame.stat.heat = 30
	unit.core.frame.stat.health = 40
	unit.core.frame.stat.armor = 0
	unit.core.full_repair()
	unit.core.current.heat = 0
	return unit

func isolate(victim:Unit) -> void:
	Dice.CHEAT_ROLL_QUEUE.append(20)
	await SpecFactory.use(game, draugr, QUARANTINE, ISOLATION, victim)

func locks_on(unit:Unit) -> Array[BuffCore]:
	return UnitCondition.get_buffs(unit, ISOLATION_BUFF)

## The reason the engine would give for refusing `action_id` on `kit_id` to `unit`, right now.
## This is literally what ReactionBus.does_reaction_trigger asks one line before deciding not to queue
## a reaction (reaction_bus.gd:121 -> unit_action.gd:110 -> :162 -> :131).
func refusal(unit:Unit, kit_id:StringName, action_id:StringName = &'') -> UnitAction.REASON:
	var gear:GearCore = unit.get_gear(kit_id)
	if not GearCore.is_valid(gear): return UnitAction.REASON.DESTROYED # fixture failure; the test will say so
	var action:Action = gear.get_action(action_id) if not action_id.is_empty() else gear.get_solo_action()
	if not Action.is_valid(action): return UnitAction.REASON.DESTROYED
	return UnitAction.get_gear_unavailable_reason(SpecificAction.create(unit, gear, action))

## Shove `victim` three tiles away from the shover, with no movement prompt
## (EventUnitPickMove.FLAG.AUTO_FURTHEST, event_unit_pick_move.gd:119-134). spec/test_dig_in.gd's helper.
func shove(victim:Unit) -> void:
	var events := CommonActionUtil.generate_knockback_events(
		victim, 3, SpecificAction.create(shover, null, null), shover.occupied_tiles(),
		[EventUnitPickMove.FLAG.AUTO_FURTHEST]
	)
	if events.is_empty(): return fail_test('Fixture: the knockback produced an event.')
	await game.execute_event_block(EventBlock.create_multiple(events))

func test_isolation_applies_two_infection_and_none_of_the_invades_own_heat():
	await isolate(target)
	assert_eq(Infection.count(target), 2, 'Two Infection.')
	assert_eq(target.core.current.heat, 2, 'Two heat, from the Infection alone - not four.')

func test_isolation_locks_the_target():
	await isolate(target)
	assert_eq(locks_on(target).size(), 1, 'One buff_isolation.')
	assert_eq(locks_on(target).front().from_gear, quarantine.persistent_id, 'Attributed to Quarantine.')

func test_a_miss_does_nothing():
	Dice.CHEAT_ROLL_QUEUE.append(1)
	target.core.frame.stat.edef = 30
	target.core.full_repair()
	await SpecFactory.use(game, draugr, QUARANTINE, ISOLATION, target)
	assert_eq(Infection.count(target), 0, 'No Infection.')
	assert_true(locks_on(target).is_empty(), 'And no lock.')

func test_an_isolated_unit_cannot_dig_in():
	# THE END-TO-END PROOF. Dig In is an entire_movement/PRE reaction that aborts an involuntary move;
	# under Isolation does_reaction_trigger refuses it at reaction_bus.gd:121 and it is never queued.
	target.core.equip_system(ROOT)
	target.core.full_repair()
	var from:Vector2i = target.tile()
	await isolate(target)
	await shove(target)
	assert_ne(target.tile(), from, 'It was shoved, because Dig In was never offered.')

func test_the_same_shove_is_refused_when_the_target_is_not_isolated():
	# The control. Without this, the test above could be passing because the shove or Dig In is broken.
	target.core.equip_system(ROOT)
	target.core.full_repair()
	var from:Vector2i = target.tile()
	await shove(target)
	assert_eq(target.tile(), from, 'Dig In works perfectly well when nobody has locked it out.')

func test_dig_in_is_refused_with_reason_forbidden():
	target.core.equip_system(ROOT)
	target.core.full_repair()
	assert_eq(refusal(target, ROOT, DIG_IN), UnitAction.REASON.NONE, 'Available before.')
	await isolate(target)
	assert_eq(refusal(target, ROOT, DIG_IN), UnitAction.REASON.FORBIDDEN, 'And forbidden after.')

func test_overwatch_is_refused_too():
	# Basic gear, on every mech; consumes_rxn is true, so the Ambush filter catches it.
	await isolate(target)
	assert_eq(refusal(target, &'ms_overwatch'), UnitAction.REASON.FORBIDDEN, 'No Overwatch either.')

func test_a_free_trait_reaction_still_fires():
	# consumes_rxn = false means requires_reaction_available() is false (action_reaction.gd:58,
	# action.gd:170), which is the whole of the Ambush filter's second clause. Asserted at the gate
	# rather than through a trigger: see this file's header.
	target.core.equip_system(REGENERATION)
	target.core.full_repair()
	await isolate(target)
	assert_eq(refusal(target, REGENERATION), UnitAction.REASON.NONE, 'A trait reaction is not a reaction.')

func test_ordinary_actions_are_untouched():
	target.core.equip_system(&'mw_tactical_melee_weapon')
	target.core.full_repair()
	await isolate(target)
	assert_eq(refusal(target, &'mw_tactical_melee_weapon'), UnitAction.REASON.NONE, 'It can still swing.')
	assert_eq(refusal(target, &'ms_scan', &'action_scan'), UnitAction.REASON.NONE, 'And still scan.')

func test_the_lock_survives_the_draugrs_own_turn_end():
	await isolate(target)
	await SpecFactory.pass_turn(game, draugr)
	assert_eq(locks_on(target).size(), 1, 'turn_count only rises on the HOLDER own turn start.')

func test_the_lock_ends_with_the_targets_next_turn():
	await isolate(target)
	Dice.CHEAT_ROLL_QUEUE.append(1) # the end-of-turn Infection check fails; irrelevant, but seeded
	await SpecFactory.pass_turn(game, target)
	assert_true(locks_on(target).is_empty(), 'Until the end of their next turn, and no longer.')

func test_isolation_is_once_per_round():
	# "Each may be used 1/round." get_per_round_hard_limit -> 1 with its own usage_group;
	# ActionAttackTech.get_per_turn_soft_limit is 99 for invades, so the round cap is the only thing
	# saying it. NO turn boundary between the two uses: a start_turn would reset the counter
	# (memory draugr-infection-engine-gotchas item 12) and the test would pass vacuously.
	await isolate(target)
	assert_eq(Infection.count(target), 2, 'First use landed.')
	Dice.CHEAT_ROLL_QUEUE.clear()
	await isolate(target)
	assert_eq(Infection.count(target), 2, 'The second use in the same round was refused.')

func test_the_lock_does_not_survive_the_draugrs_death():
	# D6: from_gear is a LIFETIME, not just a label. The engine clears attributed buffs when the
	# gear's OWNER dies - event_unit_die.gd's execute() calls
	# UnitCondition.clear_outgoing_buffs_from_unit(core, unit, ..., true), which for each of the
	# dying unit's non-basic gear clears every buff on every other unit with that gear's
	# persistent_id, but only when due_to_owner_dying and is_cleared_on_owner_death() (unit_condition.gd:1015-1029) -
	# buff_isolation never overrides that, so it defaults true. Infection carries no from_gear
	# (memory draugr-infection-engine-gotchas item 2) and must outlive the Draugr that inflicted it.
	# No core power on this fixture Draugr, so no death reaction (e.g. Ceaseless Death) complicates it.
	await isolate(target)
	assert_eq(locks_on(target).size(), 1, 'Locked before the Draugr dies (positive control).')
	await game.execute_event(&'event_unit_die', {unit = draugr})
	assert_true(locks_on(target).is_empty(), 'The lock died with the unit that owned the gear that applied it.')
	assert_eq(Infection.count(target), 2, 'Infection has no from_gear, and survives its source.')

func test_the_lock_does_not_survive_the_quarantine_being_destroyed():
	# D6, the other half: event_gear_destroy.gd:42 clears every buff attributed to the destroyed
	# gear's persistent_id on every unit, UNCONDITIONALLY (no is_cleared_on_owner_death gate at all -
	# that check only applies to the owner-death path above) - so the lock falls even with the Draugr
	# very much alive.
	await isolate(target)
	assert_eq(locks_on(target).size(), 1, 'Locked before Quarantine is destroyed (positive control).')
	await game.execute_event(&'event_gear_destroy', {unit = draugr, gear = quarantine})
	assert_true(quarantine.is_destroyed, 'Fixture sanity: Quarantine actually got destroyed.')
	assert_true(locks_on(target).is_empty(), 'The lock died with the gear that attributed it.')
	assert_eq(Infection.count(target), 2, 'Infection has no from_gear, and survives the gear that caused it.')

func test_symptom_can_bind_the_lock_to_the_infection():
	# Design section 5's stated synergy: both locks are buffs from tech gear expiring at the end of the
	# target next turn, so Symptom's bindable_effects lists them and a second Invade makes the lock last
	# as long as the Infection.
	draugr.core.equip_system(DISEASE)
	draugr.core.full_repair()
	await isolate(target)
	var lock:BuffCore = locks_on(target).front()
	Dice.CHEAT_ROLL_QUEUE.append(20)
	await SpecFactory.use(game, draugr, DISEASE, SYMPTOM, target)
	assert_true(InfectionLinks.is_linked(target, lock), 'Symptom bound it.')
	Dice.CHEAT_ROLL_QUEUE.append(1) # the Infection check fails, so the Infection - and the lock - stay
	await SpecFactory.pass_turn(game, target)
	assert_eq(locks_on(target).size(), 1, 'Still locked, because still infected.')

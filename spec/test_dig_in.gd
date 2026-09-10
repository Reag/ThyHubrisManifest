# Root / Dig In.
#
#   "1/turn, ignore the forced movement and take AP KINETIC equal to the number of spaces ignored."
#   Trigger: "You would be moved involuntarily"
#
# An ActionReactionSelf on entire_movement at PRE, filtered to involuntary movement that is not
# flagged NO_RXNS - Flash Anchor's template, action_flash_lock.gd:34-48, including its
# declined-prompt guard keyed on the triggering event's id (:18, :58). The number of spaces is
# context.array.size(): event_unit_pick_move fires no trigger of its own, so the pathfinder's path
# (pathfinder.gd:896-913, read back at event_unit_move.gd:137-138) is all a reaction can see.
#
# HOW ABORTING WORKS, because it is not obvious. ENTIRE_MOVEMENT/PRE fires INSIDE execute
# (event_unit_move.gd:71), long past EventBlock's own aborted-check (event_block.gd:99-103). What
# stops the move is :72's `if core.abort_without_unit(unit): return` - abort_when(false) returns the
# core's EXISTING `aborted` flag (event_core.gd:26-29), so set_aborted() from a PRE reaction is
# honoured one line later. Flash Anchor relies on exactly this.
#
# KNOCKBACK IN A SPEC: CommonActionUtil.generate_knockback_events with AUTO_FURTHEST
# (event_unit_pick_move.gd:119-134), which picks the destination with no movement prompt. The
# landscape is 20x20 because the default is 5x5 and a knockback needs room (memory item 6).
extends GutTest

const Resilience := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/cp_cupiditas_vitae/resilience.gd')
const PromptWatcher := preload('res://testkit/prompt_watcher.gd')
const DRAUGR_FRAME := 'res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/mf_draugr.tres'

const ROOT := &'ms_root'
const DIG_IN := &'action_dig_in'

var game:Gamemaster
var digger:Unit
var shover:Unit
var watcher:PromptWatcher

func before_each():
	game = SpecFactory.setup_gamemaster(self, false, SpecFactory.create_combat(Landscape.create_default(Vector2i(20, 20))))
	shover = SpecFactory.create_unit(game.map, Vector2i(5, 5), Faction.AI_ENEMY)
	shover.core.full_repair()
	digger = SpecFactory.create_unit(game.map, Vector2i(6, 5), Faction.PLAYER)
	digger.core.equip_system(ROOT)
	digger.core.frame.stat.health = 40
	digger.core.frame.stat.armor = 0
	digger.core.full_repair()
	watcher = add_child_autoqfree(PromptWatcher.new())

func after_each():
	Dice.CHEAT_ROLL_QUEUE.clear()

## Shove `victim` `spaces` tiles directly away from the shover, with no movement prompt.
func shove(victim:Unit, spaces:int) -> void:
	var events := CommonActionUtil.generate_knockback_events(
		victim, spaces, SpecificAction.create(shover, null, null), shover.occupied_tiles(),
		[EventUnitPickMove.FLAG.AUTO_FURTHEST]
	)
	if events.is_empty(): return fail_test('Fixture: the knockback produced an event.')
	await game.execute_event_block(EventBlock.create_multiple(events))

## An involuntary move `spaces` tiles east along a hand-built path, which is the ONLY way a spec can
## hand the move event a flag of its own. A knockback cannot: event_unit_pick_move builds the move's
## flags fresh from its own (event_unit_pick_move.gd:156-158) instead of forwarding them, and
## EventUnitMove.FLAG.NO_RXNS (= 1) collides with EventUnitPickMove.FLAG.NEAREST_VALID_TILES (= 1),
## which turns the shove into a shunt that aborts on the spot because the victim is already standing
## somewhere valid (:69-71). Measured 2026-09-10: `flags: [0, 2, 1]`, `event_unit_pick_move FIN
## (aborted)`, victim unmoved. Costs are arbitrary - create_for_involuntary leaves `spend_move`
## false, so has_enough_move_to_reach_end short-circuits at event_unit_move.gd:454.
func march(victim:Unit, spaces:int, flags:Array = []) -> void:
	var from:Vector2i = victim.tile()
	var path:Array[Pathfinder.Step] = []
	for step in range(1, spaces + 1): path.append(Pathfinder.Step.create(from + Vector2i(step, 0), step))
	await game.execute_event(&'event_unit_move', {
		unit = victim,
		array = path,
		resource = MovementType.create_for_involuntary(victim),
		object = SpecificAction.create(shover, null, null),
		flags = flags,
	})

func health_of(unit:Unit) -> int: return unit.core.current.health

func test_dig_in_aborts_an_involuntary_move():
	await shove(digger, 3)
	assert_eq(digger.tile(), Vector2i(6, 5), 'It did not budge.')

func test_the_self_damage_equals_the_planned_path_length():
	var before := health_of(digger)
	await shove(digger, 3)
	assert_eq(before - health_of(digger), 3, 'Three spaces ignored, three damage.')

func test_a_shorter_shove_costs_less():
	var before := health_of(digger)
	await shove(digger, 1)
	assert_eq(digger.tile(), Vector2i(6, 5), 'Still planted.')
	assert_eq(before - health_of(digger), 1, 'One space ignored, one damage.')

func test_the_damage_ignores_armor():
	# AP is EventService.DAMAGE_FLAG.AP; damage_modifications.gd:103 skips armor entirely when it is
	# set. Without the flag, armor 2 would leave only 1 of a 3-damage hit.
	digger.core.frame.stat.armor = 2
	digger.core.full_repair()
	var before := health_of(digger)
	await shove(digger, 3)
	assert_eq(before - health_of(digger), 3, 'Armour 2 buys nothing against AP.')

func test_the_damage_is_flagged_self_inflicted():
	# A default BuffResistDamage refuses self-inflicted damage outright
	# (buff_resist_damage.gd:42-44), so this cap is silent against Dig In and loud against anything
	# else. Two assertions, because only the pair proves the flag rather than a missing buff.
	var cap := BuffResistDamage.new()
	cap.to = Buff.TO.RESIST_DAMAGE
	cap.resist_everything = true
	cap.cap_instead_of_resist = true
	cap.reduction_amount = '1'
	UnitCondition.apply_buff(SpecFactory.dummy_event({unit = digger}), digger, cap)

	var before := health_of(digger)
	await shove(digger, 3)
	assert_eq(before - health_of(digger), 3, 'The cap declined to touch self-inflicted damage.')
	before = health_of(digger)
	await SpecFactory.damage(game, digger, 3, Lancer.DAMAGE_TYPE.KINETIC)
	assert_eq(before - health_of(digger), 1, 'The very same cap flattens an ordinary hit.')

## The Goblin's Puppet System moves its target with a MovementType that is not voluntary but is NOT
## forced either: vanilla builds it from movementtype_puppet_system.tres merged with
## MovementType.create(target, false) (action_puppet_system.gd:6-8), and that resource overrides
## ignores_reactions() so the move is not treated as a knockback. Dig In keys on the raw ignore_rxns
## flag that only MovementType.create_for_involuntary sets, so a puppeted Draugr walks.
func puppet(victim:Unit, spaces:int) -> void:
	var puppet_type:MovementType = load('res://content/gear/horus/systems/ms_h0r_os_system_upgrade_i/movementtype_puppet_system.tres').duplicate()
	puppet_type.merge_in(MovementType.create(victim, false))
	assert_false(puppet_type.voluntary, 'Fixture: the puppet move is involuntary.')
	assert_false(puppet_type.ignore_rxns, 'Fixture: and carries no forced-movement flag.')
	var from:Vector2i = victim.tile()
	var path:Array[Pathfinder.Step] = []
	for step in range(1, spaces + 1): path.append(Pathfinder.Step.create(from + Vector2i(step, 0), step))
	await game.execute_event(&'event_unit_move', {
		unit = victim,
		array = path,
		resource = puppet_type,
		object = SpecificAction.create(shover, null, null),
		flags = [EventUnitMove.FLAG.IGNORE_BEING_KNOCKED_OFF_COURSE],
	})

func test_the_puppet_system_never_offers_it():
	# Author ruling 2026-09-10: systems that are not forced movement (Puppet System) must not prompt.
	var start := digger.tile()
	await puppet(digger, 2)
	assert_eq(digger.tile(), start + Vector2i(2, 0), 'The puppeted Draugr moved; nothing to dig in against.')
	assert_eq(health_of(digger), 40, 'And paid nothing.')
	assert_true(watcher.kinds(PromptWatcher.KIND.yesno).is_empty(), 'No prompt was raised.')
	# Positive control: the same path as a real shove is offered and (auto-accepted) refused.
	await march(digger, 2)
	assert_eq(digger.tile(), start + Vector2i(2, 0), 'The forced move was dug in against.')
	assert_eq(health_of(digger), 38, 'Two spaces ignored, two damage.')

func test_a_friendly_forced_move_offers_it_too():
	# Author ruling 2026-09-10: forced movement from an ALLY prompts as well. (Flash Anchor filters
	# to hostile sources; Dig In does not.) An ally shoves via the same forced movement type.
	var ally := SpecFactory.create_unit(game.map, Vector2i(6, 7), Faction.PLAYER)
	ally.core.full_repair()
	var start := digger.tile()
	var from:Vector2i = digger.tile()
	var path:Array[Pathfinder.Step] = []
	for step in range(1, 3): path.append(Pathfinder.Step.create(from + Vector2i(step, 0), step))
	await game.execute_event(&'event_unit_move', {
		unit = digger,
		array = path,
		resource = MovementType.create_for_involuntary(digger),
		object = SpecificAction.create(ally, null, null),
		flags = [],
	})
	assert_eq(digger.tile(), start, 'Dug in against the friendly shove.')
	assert_eq(health_of(digger), 38, 'And paid for the two spaces.')
	assert_false(watcher.kinds(PromptWatcher.KIND.yesno).is_empty(), 'The prompt was raised.')

func test_a_voluntary_move_never_offers_it():
	var before := health_of(digger)
	await SpecFactory.move(game, digger, Vector2i(8, 5))
	assert_eq(digger.tile(), Vector2i(8, 5), 'It walked there itself.')
	assert_eq(before - health_of(digger), 0, 'And paid nothing.')
	assert_eq(watcher.kinds(PromptWatcher.KIND.yesno).size(), 0, 'It was never even asked.')

func test_a_no_rxns_move_never_offers_it():
	# EventUnitMove.FLAG.NO_RXNS is documented as "not enforced; reactions need to decide for
	# themselves" (event_unit_move.gd:26), which is why the script tests it by hand.
	await march(digger, 3, [EventUnitMove.FLAG.NO_RXNS])
	assert_ne(digger.tile(), Vector2i(6, 5), 'Mandatory movement cannot be dug in against.')
	assert_eq(watcher.kinds(PromptWatcher.KIND.yesno).size(), 0, 'No prompt either.')

	# The control, on the very same hand-built route: without the flag it IS dug in against, so the
	# two assertions above are the flag talking and not an unreactable fixture.
	UnitTile.move_to(digger, Vector2i(6, 5))
	await march(digger, 3)
	assert_eq(digger.tile(), Vector2i(6, 5), 'Unflagged, the same march is refused.')
	assert_eq(watcher.kinds(PromptWatcher.KIND.yesno).size(), 1, 'And this time it was asked.')

func test_declining_lets_the_move_happen():
	SpecFactory.current_responder.chosen_yesnos = false
	var before := health_of(digger)
	await shove(digger, 3)
	assert_ne(digger.tile(), Vector2i(6, 5), 'It got shoved.')
	assert_eq(before - health_of(digger), 0, 'And paid nothing for declining.')

func test_a_declined_prompt_is_not_offered_again_for_the_same_event():
	# Flash Anchor's guard (action_flash_lock.gd:18, :58): the declined event's id is stashed on the
	# gear, so a katamari or a re-entrant move cannot re-ask about the same shove.
	SpecFactory.current_responder.chosen_yesnos = false
	await shove(digger, 3)
	assert_eq(watcher.kinds(PromptWatcher.KIND.yesno).size(), 1, 'Asked exactly once.')

func test_it_consumes_the_reaction():
	var before:int = digger.core.current.reactions
	await shove(digger, 2)
	assert_eq(digger.core.current.reactions, before - 1, 'A reaction, spent.')

func test_it_is_once_per_turn_and_available_again_next_turn():
	# 1/turn is the engine's own per-turn usage counter: a private usage_group plus
	# get_per_turn_soft_limit -> 1 (unit_action.gd:167-168), with get_per_round_hard_limit lifted to
	# 99 because ActionReaction caps a reaction at 1/ROUND (action_reaction.gd:69) and the round
	# counter only resets on the digger's OWN turn (unit_action.gd:75-87). Reactions and the per-turn
	# counter both refresh at EVERY unit's turn start (unit_action.gd:67-72, event_turn_start.gd:43-44).
	var before := health_of(digger)
	await shove(digger, 2)
	assert_eq(before - health_of(digger), 2, 'First shove: dug in.')
	await shove(digger, 2)
	assert_ne(digger.tile(), Vector2i(6, 5), 'Second shove in the same turn: no second dig.')

	UnitTile.move_to(digger, Vector2i(6, 5))
	await SpecFactory.start_turn(game, shover)
	before = health_of(digger)
	await shove(digger, 2)
	assert_eq(digger.tile(), Vector2i(6, 5), 'A new turn, and it plants itself again.')
	assert_eq(before - health_of(digger), 2, 'Paying again.')

func test_on_a_draugr_with_resilience_it_costs_one_hit_point_and_one_point():
	# The author's recorded ruling (memory draugr-build-state, 2026-09-10): Dig In costing 1 damage
	# AND 1 Resilience is INTENDED - the frame is built around odd interactions, and Dig In carries no
	# NO_REDUCE flag. buff_ceaseless_death_cap.tres sets resist_self_inflicted = true, so the cap does
	# reach this damage; buff_ceaseless_death.gd spends the point either way.
	var draugr := SpecFactory.create_unit(game.map, Vector2i(10, 10), Faction.PLAYER)
	draugr.core.change_mech_frame(load(DRAUGR_FRAME))
	draugr.core.equip_system(ROOT)
	SpecFactory.apply_passive_buffs(draugr)
	draugr.core.frame.stat.armor = 0
	draugr.core.full_repair()
	Resilience.gain(draugr, 1)
	assert_eq(Resilience.count(draugr), 1, 'Fixture: one point banked.')

	UnitTile.move_to(shover, Vector2i(9, 10))
	var before := health_of(draugr)
	await shove(draugr, 3)
	assert_eq(draugr.tile(), Vector2i(10, 10), 'Planted.')
	assert_eq(before - health_of(draugr), 1, 'The Ceaseless Death caps its own self-harm at 1.')
	assert_eq(Resilience.count(draugr), 0, 'And it costs the point anyway.')

func test_dig_in_stands_down_when_another_reaction_already_cancelled_the_move():
	# event_unit_move.gd:295-333 collects EVERY unit's entire_movement/PRE reaction first and only
	# executes them afterward, with recheck_trigger_before_execution false - so if an earlier reaction
	# in that same batch already set_aborted() the move, Dig In (queued in the same batch) must stand
	# down rather than prompt, spend the reaction and deal damage for a move that no longer happens.
	#
	# Route: a real second reaction, vanilla Flash Anchor (ms_flash_anchor/action_flash_lock.gd),
	# which protects an ALLY from a hostile involuntary move and has no range check. Ordering is not
	# governed by ActionReaction.get_priority() here - execute_reaction_events_for_entire_katamari
	# flattens reaction_bus.trigger_occurred's blocks straight from its `for unit in
	# map.get_all_units()` loop with no priority sort - so the Flash-Anchor-holding unit must be
	# registered on the map BEFORE the digger for its reaction to run first. Both are created fresh
	# here, in that order, rather than reusing the shared `digger` (already registered before this
	# test body runs).
	var protector := SpecFactory.create_unit(game.map, Vector2i(5, 8), Faction.PLAYER)
	protector.core.equip_system(&'ms_flash_anchor')
	protector.core.full_repair()
	var ward := SpecFactory.create_unit(game.map, Vector2i(5, 6), Faction.PLAYER)
	ward.core.equip_system(ROOT)
	ward.core.frame.stat.health = 40
	ward.core.frame.stat.armor = 0
	ward.core.full_repair()

	var before_health := health_of(ward)
	var before_reactions:int = ward.core.current.reactions
	var events := CommonActionUtil.generate_knockback_events(
		ward, 3, SpecificAction.create(shover, null, null), shover.occupied_tiles(),
		[EventUnitPickMove.FLAG.AUTO_FURTHEST]
	)
	if events.is_empty(): return fail_test('Fixture: the knockback produced an event.')
	await game.execute_event_block(EventBlock.create_multiple(events))

	assert_eq(ward.tile(), Vector2i(5, 6), 'Flash Anchor already cancelled the move.')
	assert_eq(health_of(ward), before_health, 'Dig In dealt no damage for a move that never happened.')
	assert_eq(ward.core.current.reactions, before_reactions, 'Dig In never spent its reaction.')
	assert_eq(watcher.kinds(PromptWatcher.KIND.yesno).size(), 1, 'Only Flash Anchor prompted; Dig In was never offered.')

func test_the_per_turn_limit_is_distinct_from_the_reaction_point():
	# test_it_is_once_per_turn_and_available_again_next_turn (above) cannot tell the per-turn limit
	# from a merely-spent reaction point on a 1-reaction unit: either would refuse the second shove.
	# Giving the digger a second reaction point isolates the per-turn limit as the thing refusing it.
	digger.core.current.reactions = 2

	var before := health_of(digger)
	await shove(digger, 2)
	assert_eq(before - health_of(digger), 2, 'First shove: dug in.')
	assert_eq(digger.core.current.reactions, 1, 'Only one reaction spent.')

	before = health_of(digger)
	await shove(digger, 2)
	assert_ne(digger.tile(), Vector2i(6, 5), 'Second shove, same turn: the per-turn limit refuses it even with a reaction to spare.')
	assert_eq(digger.core.current.reactions, 1, 'And spends nothing trying.')

	UnitTile.move_to(digger, Vector2i(6, 5))
	await SpecFactory.start_turn(game, shover)
	before = health_of(digger)
	await shove(digger, 2)
	assert_eq(digger.tile(), Vector2i(6, 5), 'A new turn, and it plants itself again.')
	assert_eq(before - health_of(digger), 2, 'Paying again.')

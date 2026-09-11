# The Injector Drill's on-hit: "You may expend a charge to use Invade or a Quick Tech as a free
# action against the target."
#
# FOUR VANILLA CALLS, IN ORDER (plan section B3):
#   1. collect options - UnitRelation.get_tech_attacks_that_can_react_against for tech ATTACKS, plus a
#      sweep of quick tech ActionSystems, the Goblin's Reactive Code shape (action_reactive_code.gd:34-42).
#   2. CommonActionUtil.confirm_use - because the rules say "may" and choose_and_use gives a player with
#      exactly ONE option no prompt at all (common_action_util.gd:657-658). A plain unit has exactly one:
#      basic ms_fragment_signal. Also the only part of the flow the prompt watcher can see.
#   3. CommonActionUtil.choose_and_use_after_triggering_event - queues one event_gear_choose_and_use onto
#      event_unit_attack_declared, so the tech resolves AFTER the drill's damage.
#   4. deferred_spend - the charge is spent from inside the CHILD activation's spend_actions
#      (unit_action.gd:219 -> context.gd:42), so backing out of the tech costs nothing.
#
# WHAT THE FREE TECH IS, HERE: basic ms_fragment_signal, an ActionAttackTech invade whose on-hit applies
# impaired + slowed. That is the observable the "it actually fired" tests assert on.
#
# DICE: a uniform 4 (plan section B7) - a hit against evasion -10 and edef -10, never a crit, every
# damage die 4, so the drill's 1d6+3 is 7 and the queued tech attack also lands. Seed generously; the
# tech attack pulls its d20 after however many dice the weapon damage took, and after_each clears.
extends GutTest

const FrameIsolation := preload('res://testkit/frame_isolation.gd')
const PromptWatcher := preload('res://testkit/prompt_watcher.gd')
const DrillActionScript := preload('res://unpacked/Reag-ThyHubris/res/content/gear/horus/weapons/mw_injector_drill/action_injector_drill.gd')

const DRILL := &'mw_injector_drill'
const DRILL_ACTION := &'action_injector_drill'
const FULL_TECH := &'ms_aggressive_system_sync' # excommunicate + chains of prometheus: both FULL ActionAttackTech

var game:Gamemaster
var draugr:Unit
var target:Unit
var drill:GearCore
var watcher:PromptWatcher

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	draugr = SpecFactory.create_unit(game.map, Vector2i(0, 0), Faction.PLAYER)
	drill = draugr.core.equip_system(DRILL)
	draugr.core.full_repair()
	target = _victim_at(Vector2i(1, 0), Faction.AI_ENEMY)
	watcher = add_child_autoqfree(PromptWatcher.new())

func after_each():
	Dice.CHEAT_ROLL_QUEUE.clear()

func _victim_at(tile:Vector2i, faction:Faction.SIDE) -> Unit:
	var unit := SpecFactory.create_unit(game.map, tile, faction)
	FrameIsolation.isolate_frame(unit)
	unit.core.frame.stat.evasion = -10 # the weapon attack lands on any roll
	unit.core.frame.stat.edef = -10    # so does the free tech attack
	unit.core.frame.stat.armor = 0
	unit.core.frame.stat.health = 40
	unit.core.frame.stat.heat = 30
	unit.core.full_repair()
	unit.core.current.heat = 0
	return unit

func drill_with(victim:Unit, attacker:Unit = draugr) -> void:
	Dice.CHEAT_ROLL_QUEUE.append_array([4, 4, 4, 4, 4, 4, 4, 4])
	await SpecFactory.use(game, attacker, DRILL, DRILL_ACTION, victim)

func offers() -> Array[Dictionary]:
	return watcher.kinds(PromptWatcher.KIND.yesno)

func test_a_hit_asks_whether_to_spend_a_charge():
	await drill_with(target)
	assert_eq(offers().size(), 1, 'One confirmation, because the rules say "may".')

func test_saying_yes_fires_a_free_tech_at_the_target():
	# Fragment Signal is the only option a plain unit has, and it applies impaired + slowed on hit.
	SpecFactory.current_responder.chosen_yesnos = true
	await drill_with(target)
	assert_true(target.has_status(Lancer.STATUS.IMPAIRED), 'Fragment Signal landed.')
	assert_true(target.has_status(Lancer.STATUS.SLOWED), 'Both of its statuses.')

func test_saying_yes_spends_exactly_one_charge():
	SpecFactory.current_responder.chosen_yesnos = true
	await drill_with(target)
	assert_eq(drill.charges_current, 3, 'One charge, not two, and not zero.')

func test_saying_no_spends_nothing_and_fires_nothing():
	SpecFactory.current_responder.chosen_yesnos = false
	await drill_with(target)
	assert_eq(drill.charges_current, 4, 'No charge spent.')
	assert_false(target.has_status(Lancer.STATUS.IMPAIRED), 'And no tech was used.')

func test_the_drills_own_damage_still_lands_when_the_offer_is_declined():
	# The guard against a refactor that returns early out of on_hit before super's knockback/damage work.
	SpecFactory.current_responder.chosen_yesnos = false
	var before:int = target.core.current.health
	await drill_with(target)
	assert_eq(before - target.core.current.health, 7, 'A 4 on the damage die, plus 3.')

func test_an_empty_drill_offers_nothing():
	drill.charges_current = 0
	await drill_with(target)
	assert_eq(offers().size(), 0, 'Nothing to spend.')
	assert_false(target.has_status(Lancer.STATUS.IMPAIRED), 'And no free tech.')

func test_a_miss_offers_nothing():
	# on_hit is not reached at all on a miss (event_unit_attack.gd:82-95).
	FrameIsolation.isolate_frame(target)
	target.core.frame.stat.evasion = 30
	target.core.full_repair()
	await drill_with(target)
	assert_eq(offers().size(), 0, 'No hit, no offer.')
	assert_eq(drill.charges_current, 4, 'And no charge.')

func test_the_free_tech_costs_no_action():
	# choose_and_use runs the chosen action with Action.FLAG.AS_FREEBIE (common_action_util.gd:692-693),
	# so the only action point spent all turn is the drill's own quick.
	SpecFactory.current_responder.chosen_yesnos = true
	var before:int = draugr.state.actions
	await drill_with(target)
	assert_eq(before - draugr.state.actions, Lancer.ACTION_COST_QUICK, 'One quick action, for the swing.')

func test_an_ai_draugr_is_not_asked_and_uses_the_tech_anyway():
	# CommonActionUtil.confirm_use answers for an AI unit without opening a request
	# (common_action_util.gd:304-310), and choose_and_use picks the highest AI score (:678-684).
	var ai_draugr := SpecFactory.create_unit(game.map, Vector2i(3, 0), Faction.AI_ENEMY)
	var ai_drill := ai_draugr.core.equip_system(DRILL)
	ai_draugr.core.full_repair()
	var victim := _victim_at(Vector2i(2, 0), Faction.PLAYER)
	await drill_with(victim, ai_draugr)
	assert_eq(offers().size(), 0, 'The AI is never asked.')
	assert_eq(ai_drill.charges_current, 3, 'It spent a charge regardless.')

func test_the_free_tech_only_lands_on_the_drills_target_not_a_bystander():
	# WHY: choose_and_use_after_triggering_event passes attacked_unit as target_unit_or_tiles, so
	# decompose_variant_targets forces Action.FLAG.TARGETS_ARE_MANDATORY on the queued
	# event_gear_choose_and_use (common_action_util.gd:596-597) - the chosen tech cannot be redirected
	# onto anyone else, even another enemy sitting in the same sensor range as the actual target.
	SpecFactory.current_responder.chosen_yesnos = true
	var bystander := _victim_at(Vector2i(2, 0), Faction.AI_ENEMY)
	await drill_with(target)
	assert_true(target.has_status(Lancer.STATUS.IMPAIRED), 'Fragment Signal landed on the actual target.')
	assert_false(bystander.has_status(Lancer.STATUS.IMPAIRED), 'Not on the bystander sharing sensor range.')

func test_free_tech_options_excludes_a_full_action_tech():
	# WHY: the rules say "Invade or a QUICK Tech" - free_tech_options drops anything whose
	# get_action_type() isn't QUICK (action_injector_drill.gd:112). ms_aggressive_system_sync's two
	# actions (Chains of Prometheus, Excommunicate) are both FULL ActionAttackTech (action_type = 2),
	# so equipping it must not add its kit to the offer, while the always-present basic
	# ms_fragment_signal (a QUICK invade) still does.
	draugr.core.equip_system(FULL_TECH)
	draugr.core.full_repair()
	var drill_action:DrillActionScript = drill.get_action(DRILL_ACTION) as DrillActionScript
	var options:Array[SpecificAction] = drill_action.free_tech_options(draugr, target)
	var offered_kits:Array[StringName] = []
	for specific:SpecificAction in options: offered_kits.append(specific.gear.kit.compcon_id)
	assert_false(offered_kits.has(FULL_TECH), 'The FULL-action tech kit is excluded.')
	assert_true(offered_kits.has(&'ms_fragment_signal'), 'The QUICK invade is still offered.')

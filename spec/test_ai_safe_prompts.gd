# AI-SAFE PROMPTS: a card that asks the player something must have an answer ready when the mech is
# NOT player-controlled. fateofman's Cascades hands a cascading PLAYER mech to the AI (faction
# AI_ALLY), and its Cascade Personalities then runs EVERY system on that mech through the AI
# (cascade_system_action_ai.gd gather_specifics) - not only the NHP's own. Its safety scan skips an
# action whose script chain contains a literal `choice_bus.` with no `is_player_controlled`
# (:129-138), but this mod prompts through reag_compat's `Compat.`, which the scan cannot see. An
# unguarded prompt reached on an AI turn awaits an answer nobody can give: a soft-lock.
#
# Two sites were unguarded (design 2026-09-28 §1): TearRouting.choose_tear (Tear Move, Tear Close)
# and Face Thy Judgement's choose_effect. Every other Compat. prompt in this mod already has a
# Kill Host-shaped `if not unit.is_player_controlled(): return <default>` (action_kill_host.gd:135).
# NOTE (review, 2026-09-28): the scan is a RAW text match, comments included, and the two Tear
# callers mention `choice_bus.choose_unit` in their header comments - so Cascades happens to skip
# them today, and the Banshee guard is a defence against a LATENT hang (reworded comments, a changed
# scan, or an AI hand-over that runs no scan), not a repair of one seen in play. Face Thy Judgement
# is a REACTION, which the fallback never gathers and the scan never reads, so its guard is the one
# that stands between a triggered reaction on an AI unit and an unanswerable prompt.
#
# THE ASSERTION IS A PROMPT COUNT, via testkit/prompt_watcher.gd, listening ALONGSIDE the stock
# responder. In a spec the responder answers every prompt, so an unguarded prompt does not hang here
# - it is simply OBSERVED, and "zero prompts on an AI unit" is what goes red before the fix. The
# player-controlled controls prove the prompt still fires for a player.
#
#   powershell -ExecutionPolicy Bypass -File D:/DEV/lancer-tactics-claude/tools/run-hidden.ps1 -Log C:/Users/User/AppData/Local/Temp/x.log --gut-script=res://unpacked/Reag-ThyHubris/spec/test_ai_safe_prompts.gd
extends GutTest

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')
const PromptWatcher := preload('res://testkit/prompt_watcher.gd')

const BANSHEE_FRAME := 'res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/mf_banshee.tres'
const KEENING_KIT_ID := &'cp_the_keening'
const BANSHEE_TILE := Vector2i(1, 1)
const NEAR_TEAR := Vector2i(3, 3)
const FAR_TEAR := Vector2i(9, 9)

var game:Gamemaster
var watcher:PromptWatcher

func before_each():
	# test_tear_pick.gd's fixture: a fresh gamemaster with a campaign_core, which the tear verbs need.
	game = SpecFactory.setup_gamemaster(self, true, SpecFactory.create_combat(Landscape.create_default(Vector2i(14, 14))))
	game.campaign_core = CampaignCore.create(SpecFactory.create_campaign_base())
	game.map.campaign_core = game.campaign_core
	watcher = add_child_autoqfree(PromptWatcher.new())

func after_each():
	TearRouting.invalidate(game.map)

# ------------------------------------------------------------------ Banshee: choose_tear

func _banshee(faction:Faction.SIDE) -> Unit:
	var unit := SpecFactory.create_unit(game.map, BANSHEE_TILE, faction)
	unit.core.change_mech_frame(load(BANSHEE_FRAME))
	unit.state.overcharge_actions = 99 # two tear placements in one turn
	unit.update_cached_values_and_token(SpecFactory.dummy_event())
	unit.core.current.speed = unit.core.get_speed_max()
	return unit

func _two_tears(banshee:Unit) -> Array[Unit]:
	await SpecFactory.use(game, banshee, KEENING_KIT_ID, &'action_tear', [FAR_TEAR])
	await SpecFactory.use(game, banshee, KEENING_KIT_ID, &'action_tear', [NEAR_TEAR])
	var tears := TearRouting.open_tears(game.map)
	# FAR FIRST, deliberately: a "first candidate" default would pick the far one and go red.
	tears.sort_custom(func(a:Unit, b:Unit) -> bool:
		return UnitRelation.distance_between(banshee, a) > UnitRelation.distance_between(banshee, b))
	return tears

func _tear_move(banshee:Unit) -> SpecificAction:
	var gear:GearCore = banshee.get_gear(KEENING_KIT_ID)
	return SpecificAction.create(banshee, gear, gear.get_action(&'action_tear_move'))

func test_an_ai_controlled_banshee_is_never_asked_which_tear():
	var banshee := _banshee(Faction.AI_ALLY) # what Cascades sets on a cascading player mech
	assert_false(banshee.is_player_controlled(), 'Fixture: the AI holds the Banshee.')
	var tears := await _two_tears(banshee)
	if tears.size() != 2: return fail_test('Fixture: two tears, got %d.' % tears.size())
	watcher.prompts.clear()

	var chosen:Unit = await TearRouting.choose_tear(_tear_move(banshee), tears)

	assert_true(watcher.kinds(PromptWatcher.KIND.tile_set).is_empty(), 'No tile pick was opened on an AI turn - that prompt has no answerer in play.')
	assert_true(Unit.is_valid(chosen), 'A tear was still chosen.')
	if Unit.is_valid(chosen): assert_eq(chosen.tile(), NEAR_TEAR, 'The NEAREST tear, not the first offered.')

func test_a_player_controlled_banshee_is_still_asked():
	var banshee := _banshee(Faction.PLAYER)
	var tears := await _two_tears(banshee)
	if tears.size() != 2: return fail_test('Fixture: two tears, got %d.' % tears.size())
	watcher.prompts.clear()

	var chosen:Unit = await TearRouting.choose_tear(_tear_move(banshee), tears)

	assert_eq(watcher.kinds(PromptWatcher.KIND.tile_set).size(), 1, 'The player is asked exactly once.')
	assert_true(Unit.is_valid(chosen), 'And the answer resolves to a tear (testkit/tile_set_answerer.gd picks the first offered tile).')

func test_nearest_tear_breaks_ties_by_list_order():
	var banshee := _banshee(Faction.AI_ALLY)
	await SpecFactory.use(game, banshee, KEENING_KIT_ID, &'action_tear', [Vector2i(1, 4)])
	await SpecFactory.use(game, banshee, KEENING_KIT_ID, &'action_tear', [Vector2i(4, 1)])
	var tears := TearRouting.open_tears(game.map)
	if tears.size() != 2: return fail_test('Fixture: two tears, got %d.' % tears.size())
	assert_eq(TearRouting.nearest_tear(banshee, tears), tears[0], 'Both at distance 3: the first in the list wins, deterministically.')
	var reversed:Array[Unit] = [tears[1], tears[0]]
	assert_eq(TearRouting.nearest_tear(banshee, reversed), tears[1], 'Reverse the list and the other wins - it is list order, not identity.')

# ------------------------------------------------------------------ Erinyes: choose_effect

const CORE_POWER_ID := &'cp_dhiyed_observation'
const CHAIN_TRAIT_ID := &'mt_bind_thy_flesh'
const TECH_KIT := &'ms_lock_on' ## a real tech action, so "the effect of a tech action" is honest

func _erinyes(faction:Faction.SIDE) -> Unit:
	var unit := SpecFactory.create_unit(game.map, Vector2i(0, 0), faction)
	unit.core.equip_system(CORE_POWER_ID)
	unit.core.equip_system(CHAIN_TRAIT_ID)
	unit.core.equip_system(TECH_KIT)
	return unit

## test_dhiyed_observation.gd's _chained_victim: an enemy chained to an anchor the Erinyes owns.
func _chained_victim(erinyes:Unit, tile:Vector2i) -> Unit:
	var victim := SpecFactory.create_unit(game.map, tile, Faction.AI_ENEMY)
	var anchor_core := UnitCore.create(erinyes.get_faction(), ContentLibrary.get_mech_frame(&'dep_chain_erinyes'))
	var anchor := Unit.create(anchor_core)
	UnitAction.set_deployable_owner(anchor, erinyes, erinyes.get_gear(CHAIN_TRAIT_ID))
	await game.execute_event(&'event_unit_spawn', {unit = anchor, target_tiles = [Vector2i(1, 1)]})
	var chain_buff:Buff = ContentLibrary.get_buff(&'buff_bind_thy_flesh')
	var buff_core := UnitCondition.apply_buff(SpecFactory.dummy_event(), victim, chain_buff, erinyes.get_gear(CHAIN_TRAIT_ID))
	chain_buff.bind(buff_core, anchor, victim)
	return victim

## TWO expiring tech statuses, so the choice between them is real and the menu path is reached.
func _two_expiring_effects(erinyes:Unit, victim:Unit) -> void:
	var tech_gear:GearCore = erinyes.get_gear(TECH_KIT)
	SpecFactory.apply(victim, &'impaired', Lancer.UNTIL.END_OF_THIS_TURN, tech_gear.persistent_id)
	SpecFactory.apply(victim, &'slowed', Lancer.UNTIL.END_OF_THIS_TURN, tech_gear.persistent_id)

func _judgement(erinyes:Unit) -> Dictionary:
	var gear:GearCore = erinyes.get_gear(CORE_POWER_ID)
	var action:Action = gear.get_action(&'action_face_thy_judgement')
	return {gear = gear, action = action, context = Context.create({unit = erinyes, gear = gear, action = action})}

func test_an_ai_controlled_erinyes_is_never_asked_which_effect():
	var erinyes := _erinyes(Faction.AI_ALLY)
	assert_false(erinyes.is_player_controlled(), 'Fixture: the AI holds the Erinyes.')
	var victim := await _chained_victim(erinyes, Vector2i(2, 2))
	_two_expiring_effects(erinyes, victim)
	var judgement := _judgement(erinyes)
	var extendable:Array = judgement.action.extendable_effects(erinyes, judgement.gear, victim)
	if extendable.size() != 2: return fail_test('Fixture: two extendable effects, got %d.' % extendable.size())
	watcher.prompts.clear()

	var chosen = await judgement.action.choose_effect(judgement.context, victim, extendable)

	assert_true(watcher.kinds(PromptWatcher.KIND.multiple_choice).is_empty(), 'No menu was opened on an AI turn.')
	assert_true(watcher.kinds(PromptWatcher.KIND.yesno).is_empty(), 'And no confirm either.')
	assert_eq(chosen, extendable.front(), 'The first extendable effect is the AI default - "you may" is not declined by a mech nobody is steering.')

func test_an_ai_controlled_erinyes_with_one_effect_skips_the_confirm_too():
	var erinyes := _erinyes(Faction.AI_ALLY)
	var victim := await _chained_victim(erinyes, Vector2i(2, 2))
	SpecFactory.apply(victim, &'impaired', Lancer.UNTIL.END_OF_THIS_TURN, erinyes.get_gear(TECH_KIT).persistent_id)
	var judgement := _judgement(erinyes)
	var extendable:Array = judgement.action.extendable_effects(erinyes, judgement.gear, victim)
	if extendable.size() != 1: return fail_test('Fixture: one extendable effect, got %d.' % extendable.size())
	watcher.prompts.clear()

	var chosen = await judgement.action.choose_effect(judgement.context, victim, extendable)

	# confirm_use answers for an AI unit by itself (ai_confirms_use, default true), so this passed before
	# the guard too; it pins the behaviour, not the skip.
	assert_true(watcher.kinds(PromptWatcher.KIND.yesno).is_empty(), 'No confirm is raised for an AI unit.')
	assert_eq(chosen, extendable.front(), 'And the one effect is extended.')

func test_a_player_controlled_erinyes_is_still_asked_which_effect():
	var erinyes := _erinyes(Faction.PLAYER)
	var victim := await _chained_victim(erinyes, Vector2i(2, 2))
	_two_expiring_effects(erinyes, victim)
	var judgement := _judgement(erinyes)
	var extendable:Array = judgement.action.extendable_effects(erinyes, judgement.gear, victim)
	if extendable.size() != 2: return fail_test('Fixture: two extendable effects, got %d.' % extendable.size())
	watcher.prompts.clear()

	var chosen = await judgement.action.choose_effect(judgement.context, victim, extendable)

	assert_eq(watcher.kinds(PromptWatcher.KIND.multiple_choice).size(), 1, 'The player is asked exactly once.')
	assert_eq(chosen, extendable.front(), 'The stock responder answers index 0.')

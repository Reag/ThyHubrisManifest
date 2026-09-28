# AI-SAFE PROMPTS: a card that asks the player something must have an answer ready when the mech is
# NOT player-controlled. fateofman's Cascades hands a cascading PLAYER mech to the AI (faction
# AI_ALLY), and its Cascade Personalities then runs EVERY system on that mech through the AI
# (cascade_system_action_ai.gd gather_specifics) - not only the NHP's own. Its safety scan skips an
# action whose script chain contains a literal `choice_bus.` with no `is_player_controlled`
# (:129-138), but this mod prompts through reag_compat's `Compat.`, which the scan cannot see. An
# unguarded prompt on an AI turn awaits an answer nobody can give: a soft-lock.
#
# Two sites were unguarded (design 2026-09-28 §1): TearRouting.choose_tear (Tear Move, Tear Close)
# and Face Thy Judgement's choose_effect. Every other Compat. prompt in this mod already has a
# Kill Host-shaped `if not unit.is_player_controlled(): return <default>` (action_kill_host.gd:135).
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

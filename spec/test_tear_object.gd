# The tear object's wiring. Clause 2: "undamageable Size 1 objects that do not cause obstruction."
extends GutTest

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')
const TEAR_PATH := 'res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/dep_tear_banshee.tres'

func test_the_tear_frame_loads():
	assert_true(is_instance_valid(load(TEAR_PATH) as Frame), 'dep_tear_banshee is a Frame.')

func test_the_tear_is_a_non_obstructing_marker():
	var tear:Frame = load(TEAR_PATH)
	assert_eq(tear.entity_type, Frame.ENTITY.MARKER, 'A tear is a marker, not a real entity.')
	assert_false(tear.is_obstruction, 'Clause 2: tears do not cause obstruction.')

func test_the_tear_is_size_one():
	var tear:Frame = load(TEAR_PATH)
	assert_eq(tear.stat.size, 1, 'Clause 2: Size 1.')

func test_the_tear_outlives_its_owner():
	# Lifecycle decision: tears are holes in reality, not drones. This is the FLAG, not a missing
	# trait - is_deactivated_on_owner_death defaults TRUE (frame.gd:65), so it must be set false.
	var tear:Frame = load(TEAR_PATH)
	assert_false(tear.is_deactivated_on_owner_death,
		'Tears persist after the Banshee dies.')

func test_the_tear_is_undamageable():
	# "Undamageable" is the stock shared trait, no code.
	var tear:Frame = load(TEAR_PATH)
	var trait_ids:Array[StringName] = []
	for kit:Kit in tear.traits: trait_ids.append(kit.compcon_id)
	assert_true(trait_ids.has(&'mt_invulnerable'), 'Clause 2: undamageable.')

func test_the_frame_id_matches_what_routing_looks_for():
	# tear_routing finds tears by frame id. A rename that misses one side leaves routing silently
	# finding nothing, which looks exactly like "tears do not work".
	assert_eq((load(TEAR_PATH) as Frame).compcon_id, TearRouting.TEAR_FRAME_ID,
		'The frame id and the routing constant agree.')

# --- creation ---

var game:Gamemaster
var banshee:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self, true, SpecFactory.create_combat(Landscape.create_default(Vector2i(12,12))))

	# SpecFactory GAP, not optional bookkeeping. setup_gamemaster with make_fresh_gamemaster = true
	# returns early (spec_factory.gd:29-33) and never assigns campaign_core - the shared, non-fresh
	# path a few lines below it does. Anything reaching event_unit_die then dies on
	# `context.map.campaign_core.get_lancer_by_id(...)` (event_service.gd:80) with
	# `Nonexistent function get_lancer_by_id in base Nil` - which surfaces as "the tear did not
	# disappear", i.e. broken content rather than a missing fixture. This is what the non-fresh path
	# would have done for us.
	game.campaign_core = CampaignCore.create(SpecFactory.create_campaign_base())
	game.map.campaign_core = game.campaign_core

	banshee = SpecFactory.create_unit(game.map, Vector2i(1,1))
	# change_mech_frame, not a raw core.frame assignment: the latter skips
	# core.loadout.regenerate_derived_gear, so get_gear(&'cp_the_keening') finds nothing and
	# SpecFactory.use silently no-ops ("Could not find gear for cp_the_keening").
	banshee.core.change_mech_frame(load('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/mf_banshee.tres'))
	banshee.state.overcharge_actions = 99 # do not run out of actions mid-spec
	banshee.update_cached_values_and_token(SpecFactory.dummy_event())

func test_using_tear_places_a_tear():
	await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear', [Vector2i(4,4)])
	assert_eq(TearRouting.open_tears(game.map).size(), 1, 'One tear on the map.')

func test_the_tear_lands_where_it_was_aimed():
	await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear', [Vector2i(4,4)])
	var tears := TearRouting.open_tears(game.map)
	if tears.is_empty(): return fail_test('A tear was placed.')
	assert_eq(tears[0].tile(), Vector2i(4,4), 'It is where the player put it.')

func test_tear_reaches_sensors_not_a_fixed_range():
	# Clause 1 says "within SENSORS", which scales with the pilot. ActionSystemDeploy has an export
	# for exactly this, so it needs no code - but nothing else would notice a hardcoded number.
	var action:ActionSystemDeploy = ContentLibrary.get_kit(&'cp_the_keening').get_action(&'action_tear')
	assert_true(action.deploy_to_sensors, 'Tear deploys to sensor range.')

func test_the_cap_is_enforced():
	# Exact equality, not assert_lte: assert_lte alone would also pass an over-strict
	# implementation that stops short of the cap (e.g. refusing after just one tear). Attempting
	# more than the cap must land at EXACTLY MAX_TEARS, catching both directions.
	for i:int in TearRouting.MAX_TEARS + 3:
		await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear', [Vector2i(3 + (i % 8), 3 + (i / 8))])
	assert_eq(TearRouting.open_tears(game.map).size(), TearRouting.MAX_TEARS,
		'Attempting more than MAX_TEARS tears lands at exactly MAX_TEARS.')

# --- closing ---
#
# Close is the BANSHEE's verb, on cp_the_keening, NOT the tear's own. It lived on the tear's kit
# until 2026-09-08 and was completely unreachable there: a tear is Frame.ENTITY.MARKER, and
# UnitAction.can_be_activated_for_faction requires is_actor(), so a marker's action bar never
# renders. Every tear opened was permanent. The specs below passed anyway, because
# SpecFactory.use_solo fires event_gear_activate directly and never asks whether the action could
# have been reached - which is exactly what test_closing_is_reachable_from_the_banshees_gear now
# pins down.
#
# SpecFactory's ChoiceBusResponder answers the "which tear?" pick with the front of the candidate
# list unless chosen_unit is set, so a one-tear fixture closes the tear it just made.

func _close_a_tear() -> void:
	await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear_close')

func test_closing_a_tear_removes_it():
	await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear', [Vector2i(4,4)])
	if TearRouting.open_tears(game.map).is_empty(): return fail_test('A tear was placed to close.')
	await _close_a_tear()
	assert_eq(TearRouting.open_tears(game.map).size(), 0, 'The tear is gone.')

func test_closing_frees_a_slot_against_the_cap():
	# Otherwise a player who fills the cap and then tidies up is permanently locked out - the cap
	# would be a lifetime budget rather than a limit on how many are open at once.
	for i:int in TearRouting.MAX_TEARS:
		await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear', [Vector2i(3 + (i % 8), 3 + (i / 8))])
	if TearRouting.open_tears(game.map).is_empty(): return fail_test('Tears were placed.')
	await _close_a_tear()
	assert_lt(TearRouting.open_tears(game.map).size(), TearRouting.MAX_TEARS,
		'Closing one frees a slot.')

func test_closing_is_reachable_from_the_banshees_gear():
	# THE TEST WHOSE ABSENCE HID THE BUG. Every other close spec drives the action directly; this one
	# asks the question the UI and the AI ask - can_activate_gear - which is the only route a player
	# ever has to it. On the tear's own kit this returned false forever.
	await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear', [Vector2i(4,4)])
	var specific := SpecificAction.from_id(banshee, &'cp_the_keening', &'action_tear_close')
	assert_true(SpecificAction.is_valid(specific),
		'The Banshee\'s own gear carries action_tear_close.')
	assert_true(UnitAction.can_activate_gear(specific),
		'With a tear open, the Banshee can actually reach Close Tear.')

func test_closing_is_not_offered_with_no_tear_open():
	# The other half of reachability: it must not sit on the bar as a click into an empty pick.
	var specific := SpecificAction.from_id(banshee, &'cp_the_keening', &'action_tear_close')
	if not SpecificAction.is_valid(specific): return fail_test('The action exists on the gear.')
	assert_false(UnitAction.can_activate_gear(specific), 'Nothing to close, so nothing is offered.')

func test_closing_only_offers_the_banshees_own_tears():
	# Routing is universal, but the VERBS are not - clause 8 is the Banshee's. Someone else's tear is
	# not ours to close, exactly as it is not ours to move (test_tear_move.gd).
	var other := SpecFactory.create_unit(game.map, Vector2i(11,11), Faction.AI_ENEMY)
	other.core.change_mech_frame(load('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/mf_banshee.tres'))
	other.state.overcharge_actions = 99
	other.update_cached_values_and_token(SpecFactory.dummy_event())
	await SpecFactory.use(game, other, &'cp_the_keening', &'action_tear', [Vector2i(10,10)])
	assert_eq(TearRouting.open_tears(game.map).size(), 1, 'Fixture: exactly one tear, and it is theirs.')

	var specific := SpecificAction.from_id(banshee, &'cp_the_keening', &'action_tear_close')
	if not SpecificAction.is_valid(specific): return fail_test('The action exists on the gear.')
	assert_false(UnitAction.can_activate_gear(specific), 'Another Banshee\'s tear is not ours to close.')

func test_closing_spends_the_quick_action():
	# The old tear-side version never called spend_actions at all, so the "quick action" the prose
	# promises was free. Measured against the action POOL (normal + overcharge) rather than
	# state.actions alone, because the fixture hands the Banshee overcharge to fit several tear
	# actions into one turn and UnitAction.spend draws from whichever it must.
	await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear', [Vector2i(4,4)])
	if TearRouting.open_tears(game.map).is_empty(): return fail_test('A tear was placed to close.')
	var before:int = UnitAction.current_total(banshee)
	await _close_a_tear()
	assert_eq(UnitAction.current_total(banshee), before - Lancer.ACTION_COST_QUICK,
		'Clause 8: closing costs exactly one quick action.')

func test_cancelling_the_pick_costs_nothing():
	# spend_actions sits BELOW the pick in activate() precisely so a player who opens the menu and
	# changes their mind has not spent their turn. abort_all makes the responder abort the request,
	# which is what the cancel button does.
	#
	# TWO tears, not one: since 2026-09-08 a single candidate is taken without prompting at all (see
	# TearRouting.choose_tear, and spec/test_tear_pick.gd for why the prompt was worse than useless
	# for a lone tear), so there is no pick to cancel unless there is a real choice to make.
	await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear', [Vector2i(4,4)])
	await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear', [Vector2i(6,6)])
	if TearRouting.open_tears(game.map).size() != 2: return fail_test('Two tears were placed, so a pick is offered.')
	var before:int = UnitAction.current_total(banshee)

	SpecFactory.current_responder.abort_all = true
	await _close_a_tear()
	SpecFactory.current_responder.abort_all = false

	assert_eq(TearRouting.open_tears(game.map).size(), 2, 'Cancelling leaves both tears open.')
	assert_eq(UnitAction.current_total(banshee), before, 'And costs no action.')

func test_closing_a_tear_shuts_its_window():
	# The close action must drop the routing caches, not merely delete the unit. They are keyed on
	# TILE, so a closed tear whose entry survived keeps answering routed queries as though the window
	# were still open - and nothing about the map would look wrong. This is what notices;
	# test_closing_a_tear_removes_it above would pass with a stale cache.
	#
	# Asserted through can_affect rather than through the routing library directly, because that is
	# the user-visible effect: with the tear gone, the tangible Banshee can no longer touch the ghost.
	var ghost := SpecFactory.create_unit(game.map, Vector2i(9,9), Faction.AI_ENEMY)
	SpecFactory.apply(ghost, Lancer.STATUS.INTANGIBLE)
	assert_false(UnitRelation.can_affect(banshee, ghost), 'Sanity: no window before the tear.')

	await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear', [Vector2i(4,4)])
	if TearRouting.open_tears(game.map).is_empty(): return fail_test('A tear was placed to close.')
	assert_true(UnitRelation.can_affect(banshee, ghost), 'Sanity: the open tear does bridge them.')

	await _close_a_tear()
	assert_false(UnitRelation.can_affect(banshee, ghost),
		'A closed tear bridges nothing - its cache entry went with it.')

func test_closing_is_a_quick_action():
	var action:Action = ContentLibrary.get_kit(&'cp_the_keening').get_action(&'action_tear_close')
	if not Action.is_valid(action): return fail_test('cp_the_keening carries action_tear_close.')
	assert_eq(action.get_action_type(null), Lancer.ACTION.QUICK, 'Clause 8: a quick action.')

func test_closing_stays_out_of_the_gear_tooltip():
	# Like Move Tear, it is a verb of Tear described inside Tear's own effect text, not a third mode
	# of the core power. The Keening must still read as two abilities.
	var kit:Kit = ContentLibrary.get_kit(&'cp_the_keening')
	if not Kit.is_valid(kit): return fail_test('cp_the_keening loaded.')
	assert_false(kit.get_action(&'action_tear_close').show_in_tooltip(kit),
		'Close Tear does not list itself as a separate ability.')

func test_closing_has_its_own_usage_group():
	# Every action on cp_the_keening sets one explicitly. Without it get_usage_group_for_action falls
	# back to the KIT id, and the 1/turn repeat-action rule would be shared with Tear and Mourning
	# Call - closing a tear would silently consume the core power's own allowance.
	var action:Action = ContentLibrary.get_kit(&'cp_the_keening').get_action(&'action_tear_close')
	if not Action.is_valid(action): return fail_test('cp_the_keening carries action_tear_close.')
	assert_eq(action.usage_group, &'action_tear_close', 'Close Tear does not share a round allowance.')

func test_closing_is_named_from_the_core_powers_key():
	# The localization key is derived from the KIT plus the action id, so moving the action between
	# kits moves its key. A miss here reads back as the raw key in the UI.
	var gear:GearCore = banshee.get_gear(&'cp_the_keening')
	if not GearCore.is_valid(gear): return fail_test('The Banshee carries The Keening.')
	var specific := SpecificAction.from_id(banshee, &'cp_the_keening', &'action_tear_close')
	assert_eq(specific.action.name(specific), 'Close Tear', 'Its name resolves on its new kit.')

func test_an_intangible_banshee_can_still_open_a_tear():
	# PLAYTEST FIX 8.3, and the reachability half of it. Vanilla ActionSystemDeploy refuses outright
	# while INTANGIBLE (action_system_deploy.gd:21) - a sensible default for dropping a physical
	# drone, and exactly backwards for a window between tangible and intangible space. Clause 1
	# carries no tangibility condition, and the Banshee's own Whispering is its main way of getting
	# there, so the vanilla check locked the frame out of its own core power.
	SpecFactory.apply(banshee, Lancer.STATUS.INTANGIBLE)
	if not banshee.has_status(Lancer.STATUS.INTANGIBLE): return fail_test('The Banshee is intangible.')

	var specific := SpecificAction.from_id(banshee, &'cp_the_keening', &'action_tear')
	if not SpecificAction.is_valid(specific): return fail_test('The Banshee carries action_tear.')
	assert_true(UnitAction.can_activate_gear(specific),
		'An INTANGIBLE Banshee can reach Tear - this is what the UI and the AI ask.')

	await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear', [Vector2i(4,4)])
	assert_eq(TearRouting.open_tears(game.map).size(), 1, 'And the tear actually lands.')

func test_the_tear_cap_still_refuses_at_the_limit():
	# The other side of not chaining to super: the cap is this action's OWN check and must survive
	# being restated alongside the intangibility exemption.
	for i:int in TearRouting.MAX_TEARS:
		await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear', [Vector2i(3 + (i % 8), 3 + (i / 8))])
	if TearRouting.open_tears(game.map).size() != TearRouting.MAX_TEARS: return fail_test('The cap was filled.')
	var specific := SpecificAction.from_id(banshee, &'cp_the_keening', &'action_tear')
	assert_false(UnitAction.can_activate_gear(specific), 'At the cap, Tear is not offered.')

# --- the visual (2026-09-08) ---
#
# The tear used to render as res://assets/frames/shared/dep_missing_frame.png - the engine's
# "this frame has no art" box. Its look now comes from an FxEndless scene attached by a plain
# Passive on mt_tear_banshee, with the sprite set to blank.png (vanilla's own idiom for an
# fx-only deployable: dep_unstable_system_reactor, dep_remote_projector_aegis and three others).
#
# These assert the WIRING, not the pixels. Nothing else in the suite would notice if the passive
# lost its fxe, the scene stopped loading, or the sprite went back to the placeholder - the tear
# would simply be invisible in play and every other test would stay green. That is the same shape
# as the two unreachable-pick bugs this frame has already shipped, so it gets an assertion.

func _tear_visual_passive() -> Passive:
	for kit:Kit in (load(TEAR_PATH) as Frame).traits:
		if kit.compcon_id != &'mt_tear_banshee': continue
		for passive:Passive in kit.passives:
			if passive.fxe != null: return passive
	return null

func test_the_tear_carries_a_visual_fx():
	assert_not_null(_tear_visual_passive(),
		'mt_tear_banshee carries a Passive with an fxe - without it the tear is invisible.')

func test_the_tear_fx_scene_actually_loads():
	# A PackedScene reference that fails to load yields a null fxe_id and the ticket is dropped
	# silently by Passive.get_attached_fx.
	var passive:Passive = _tear_visual_passive()
	assert_not_null(passive, 'precondition: the visual passive exists')
	if passive == null: return
	assert_true(is_instance_valid(passive.fxe.instantiate()), 'fxe_void_tear.tscn instantiates.')
	assert_ne(passive.get_fxe_id(), &'', 'the fxe resolves to a real id, so a ticket can be issued.')

func test_the_tear_no_longer_uses_the_missing_frame_placeholder():
	var tear:Frame = load(TEAR_PATH)
	assert_false(tear.sprites.is_empty(), 'the frame has a sprite')
	for sprite:Texture2D in tear.sprites:
		assert_false(sprite.resource_path.contains('dep_missing_frame'),
			'the tear is not drawn with the engine placeholder box.')

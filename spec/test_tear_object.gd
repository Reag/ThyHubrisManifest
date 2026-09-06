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

func test_closing_a_tear_removes_it():
	await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear', [Vector2i(4,4)])
	var tears := TearRouting.open_tears(game.map)
	if tears.is_empty(): return fail_test('A tear was placed to close.')
	await SpecFactory.use_solo(game, tears[0], &'mt_tear_banshee')
	assert_eq(TearRouting.open_tears(game.map).size(), 0, 'The tear is gone.')

func test_closing_frees_a_slot_against_the_cap():
	# Otherwise a player who fills the cap and then tidies up is permanently locked out - the cap
	# would be a lifetime budget rather than a limit on how many are open at once.
	for i:int in TearRouting.MAX_TEARS:
		await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear', [Vector2i(3 + (i % 8), 3 + (i / 8))])
	var tears := TearRouting.open_tears(game.map)
	if tears.is_empty(): return fail_test('Tears were placed.')
	await SpecFactory.use_solo(game, tears[0], &'mt_tear_banshee')
	assert_lt(TearRouting.open_tears(game.map).size(), TearRouting.MAX_TEARS,
		'Closing one frees a slot.')

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
	var tears := TearRouting.open_tears(game.map)
	if tears.is_empty(): return fail_test('A tear was placed to close.')
	assert_true(UnitRelation.can_affect(banshee, ghost), 'Sanity: the open tear does bridge them.')

	await SpecFactory.use_solo(game, tears[0], &'mt_tear_banshee')
	assert_false(UnitRelation.can_affect(banshee, ghost),
		'A closed tear bridges nothing - its cache entry went with it.')

func test_closing_is_a_quick_action():
	var action:Action = ContentLibrary.get_kit(&'mt_tear_banshee').get_action(&'action_tear_close')
	assert_eq(action.get_action_type(null), Lancer.ACTION.QUICK, 'Clause 8: a quick action.')

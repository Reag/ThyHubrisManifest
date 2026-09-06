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

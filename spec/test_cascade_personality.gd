# CASCADE PERSONALITIES - the PESTILENCE-class NHP's personality file for fateofman's Cascade
# Personalities mod. The Sixth Voice's spec/test_cascade_personality.gd carries the long header;
# the mechanism is one JSON file under res/cascade_personality/, read by fateofman's
# personality_registry.gd when installed and dropped silently by LancerTacticsMod when not
# (lancer_tactics_mod.gd:82-91: no resgrp glob matches .json).
#
# THIS SPEC NEEDS NONE OF FATEOFMAN'S CODE - it mirrors the registry's own rules
# (personality_registry.gd:10-15, 61-78 in fateofman-cascade_personalities 1.43.0). The end-to-end
# half is the opt-in spec/test_cascade_integration.gd.
#
# Design: D:/DEV/lancer-tactics-claude/specs/2026-09-28-cascade-personalities-integration-design.md
#
#   powershell -ExecutionPolicy Bypass -File D:/DEV/lancer-tactics-claude/tools/run-hidden.ps1 -Log C:/Users/User/AppData/Local/Temp/x.log --gut-script=res://unpacked/Reag-ThyHubris/spec/test_cascade_personality.gd
extends GutTest

const ModResources := preload('res://testkit/mod_resources.gd')

const MOD_ID := 'Reag-ThyHubris'
const MOD_RES_DIR := 'res://unpacked/Reag-ThyHubris/'
const FOLDER := 'res://unpacked/Reag-ThyHubris/res/cascade_personality'
const FILE_NAME := 'thy_hubris.json'
const FILE := FOLDER + '/' + FILE_NAME

const OUR_NHP_KITS:Array[StringName] = [&'ms_pestilence_class_nhp']

const KNOWN_TRAITS:Array[StringName] = [
	&'subtlety', &'logical_emotional', &'aggression', &'esotericism', &'range_preference',
	&'relationship_with_pilot', &'self_preservation', &'restraint', &'misanthropy',
]
const ZERO_TO_ONE_TRAITS:Array[StringName] = [&'esotericism', &'range_preference']

const KNOWN_TAGS:Array[StringName] = [
	&'nhp', &'shield', &'buff', &'debuff', &'grenade', &'mine', &'drone', &'deployable', &'utility',
	&'protocol', &'reaction', &'overcharge', &'core_power', &'teleport', &'disengage',
	&'attack', &'melee', &'aoe', &'tech',
	&'knockback', &'loading', &'thrown', &'arcing', &'seeking', &'kinetic', &'energy', &'explosive', &'burn', &'heat',
	&'grappled', &'stunned', &'impaired', &'slowed', &'immobilized', &'lockon',
]

func _parsed() -> Dictionary:
	if not FileAccess.file_exists(FILE): return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(FILE))
	return parsed if parsed is Dictionary else {}

func _personalities() -> Dictionary:
	var personalities = _parsed().get('personalities', {})
	return personalities if personalities is Dictionary else {}

func test_the_folder_holds_exactly_our_one_json_file():
	assert_true(DirAccess.dir_exists_absolute(FOLDER), '%s exists.' % FOLDER)
	if not DirAccess.dir_exists_absolute(FOLDER): return
	var jsons:Array[String] = []
	for file_name:String in DirAccess.get_files_at(FOLDER):
		if file_name.get_extension() == 'json': jsons.append(file_name)
	assert_eq(jsons, [FILE_NAME], 'One personality file, named as the design says.')

func test_the_file_is_a_json_object_with_a_personalities_object():
	assert_true(FileAccess.file_exists(FILE), '%s exists.' % FILE)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(FILE)) if FileAccess.file_exists(FILE) else null
	assert_true(parsed is Dictionary, 'The file parses to a JSON object.')
	assert_true(_parsed().get('personalities') is Dictionary, 'It carries a "personalities" object.')
	assert_false(_parsed().has('action_tags'), 'No action_tags (design §3).')
	assert_false(_parsed().has('bark_incidents'), 'No bark_incidents (design §3).')

func test_every_personality_names_one_of_our_own_nhp_kits():
	var personalities := _personalities()
	assert_false(personalities.is_empty(), 'At least one personality.')
	for kit_id in personalities:
		var id := StringName(kit_id)
		assert_true(OUR_NHP_KITS.has(id), '%s is one of this mod\'s NHP kits.' % kit_id)
		var kit:Kit = ContentLibrary.get_kit(id)
		assert_true(Kit.is_valid(kit), '%s is a Kit ContentLibrary knows.' % kit_id)
		if not Kit.is_valid(kit): continue
		assert_true(kit.is_nhp(), '%s carries the NHP tag.' % kit_id)
		var path:String = ContentLibrary.main.compcon_id_to_path.get(id, '')
		assert_true(path.begins_with(MOD_RES_DIR), '%s is OUR resource, at %s.' % [kit_id, path])
		assert_true(personalities[kit_id] is Dictionary, '%s\'s personality is an object.' % kit_id)

func test_every_nhp_kit_this_mod_ships_has_a_personality():
	var personalities := _personalities()
	var found:Array[StringName] = []
	for resource:Resource in ModResources.load_ours(MOD_ID, &'kits'):
		if resource is Kit and resource.is_nhp(): found.append(resource.compcon_id)
	found.sort()
	var expected:Array[StringName] = OUR_NHP_KITS.duplicate()
	expected.sort()
	assert_eq(found, expected, 'OUR_NHP_KITS lists exactly the NHP kits in this mod.')
	for id:StringName in found:
		assert_true(personalities.has(String(id)), '%s has a personality entry.' % id)

func test_every_trait_is_known_and_inside_the_registrys_range():
	var personalities := _personalities()
	for kit_id in personalities:
		var weights = personalities[kit_id].get('trait_weights', {})
		assert_true(weights is Dictionary, '%s.trait_weights is an object.' % kit_id)
		if not (weights is Dictionary): continue
		assert_eq(weights.size(), KNOWN_TRAITS.size(), '%s sets all nine axes explicitly.' % kit_id)
		for trait_name in weights:
			var trait_id := StringName(trait_name)
			assert_true(KNOWN_TRAITS.has(trait_id), '%s.%s is a trait the registry knows.' % [kit_id, trait_name])
			var value = weights[trait_name]
			assert_true(value is float or value is int, '%s.%s is a number.' % [kit_id, trait_name])
			if not (value is float or value is int): continue
			var minimum := 0.0 if ZERO_TO_ONE_TRAITS.has(trait_id) else -1.0
			assert_between(float(value), minimum, 1.0, '%s.%s = %s is inside %s..1.' % [kit_id, trait_name, value, minimum])

func test_every_tag_affinity_is_a_known_tag_with_a_number():
	var personalities := _personalities()
	for kit_id in personalities:
		var affinity = personalities[kit_id].get('tag_affinity', {})
		assert_true(affinity is Dictionary, '%s.tag_affinity is an object.' % kit_id)
		if not (affinity is Dictionary): continue
		assert_false(affinity.is_empty(), '%s names at least one favourite kind of action.' % kit_id)
		for tag in affinity:
			assert_true(KNOWN_TAGS.has(StringName(tag)), '%s.tag_affinity.%s is a tag the scorer emits.' % [kit_id, tag])
			assert_true(affinity[tag] is float or affinity[tag] is int, '%s.tag_affinity.%s is a number.' % [kit_id, tag])

func test_the_authors_rulings_are_the_shipped_values():
	# Design §3: a HORUS plague that kills its hosts, allies included (Draugr D5 "as written").
	var pestilence:Dictionary = _personalities().get('ms_pestilence_class_nhp', {}).get('trait_weights', {})
	assert_eq(float(pestilence.get('misanthropy', 0.0)), 0.8, 'Pestilence does not care who it hits.')
	assert_eq(float(pestilence.get('esotericism', 0.0)), 0.8, 'Pestilence is strange.')
	assert_eq(float(pestilence.get('logical_emotional', 0.0)), -0.5, 'Pestilence culls the damaged.')

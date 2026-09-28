# CASCADE PERSONALITIES, END TO END - OPT-IN. The Sixth Voice's spec/test_cascade_integration.gd
# carries the long header. fateofman's two mods are NOT residents; absent, every test is PENDING with
# the recipe in its message; present, they must be ACTIVE. Nothing here names a fateofman class or
# preloads a fateofman path - the file must parse without them (CLAUDE.md: a spec that fails to
# parse is skipped, not failed).
#
# Design: D:/DEV/lancer-tactics-claude/specs/2026-09-28-cascade-personalities-integration-design.md §5
extends GutTest

const Compat := preload('res://testkit/modkit_compat.gd')

const CASCADES_DIR := 'res://unpacked/fateofman-cascades'
const PERSONALITIES_DIR := 'res://unpacked/fateofman-cascade_personalities'
const CASCADE_UTIL := CASCADES_DIR + '/res/cascade_util.gd'
const REGISTRY := PERSONALITIES_DIR + '/res/personality_registry.gd'
const CASCADE_AI := PERSONALITIES_DIR + '/res/cascade_ai.gd'
const OUR_JSON := 'res://unpacked/Reag-ThyHubris/res/cascade_personality/thy_hubris.json'

const DRAUGR_FRAME := 'res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/mf_draugr.tres'
const NHP_KIT := &'ms_pestilence_class_nhp'

const RECIPE := """OPT-IN: fateofman's mods are not unpacked. To run this spec:
  cd D:/DEV/lancer-tactics-modkit
  unzip -oq C:/Users/User/AppData/Roaming/LancerTactics/mods/fateofman-cascades.zip -d .
  unzip -oq C:/Users/User/AppData/Roaming/LancerTactics/mods/fateofman-cascade_personalities.zip -d .
  rm -f .godot/uid_cache.bin && "D:/DEV/Godot_v4.7.2-stable_win64_console.exe" --headless --path . --import
  <run this spec through tools/run-hidden.ps1>
  rm -rf unpacked/fateofman-cascades unpacked/fateofman-cascade_personalities
  rm -f .godot/uid_cache.bin && <--import again>; git diff our mods for collateral re-saves."""

var game:Gamemaster
var draugr:Unit

static func fateofman_present() -> bool:
	return DirAccess.dir_exists_absolute(CASCADES_DIR) and DirAccess.dir_exists_absolute(PERSONALITIES_DIR)

func before_each() -> void:
	if not fateofman_present(): return
	game = SpecFactory.setup_gamemaster(self)
	draugr = SpecFactory.create_unit(game.map, Vector2i(2, 2))
	draugr.core.change_mech_frame(load(DRAUGR_FRAME))
	draugr.core.equip_system(NHP_KIT)
	draugr.update_cached_values_and_token(SpecFactory.dummy_event())

func _ours() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(OUR_JSON)).get('personalities', {})

func test_both_fateofman_mods_are_active_when_unpacked():
	if not fateofman_present(): return pending(RECIPE)
	assert_true(Compat.is_mod_active('fateofman-cascades'), 'fateofman-cascades installed from unpacked/.')
	assert_true(Compat.is_mod_active('fateofman-cascade_personalities'), 'fateofman-cascade_personalities installed from unpacked/.')

func test_the_registry_resolves_pestilence_to_our_json():
	if not fateofman_present(): return pending(RECIPE)
	var registry = load(REGISTRY)
	var ours := _ours()
	for kit_id in ours:
		var found:Dictionary = registry.get_personality_for_kit(StringName(kit_id))
		assert_false(found.is_empty(), '%s is registered.' % kit_id)
		if found.is_empty(): continue
		for trait_name in ours[kit_id].trait_weights:
			assert_eq(found[&'trait_weights'].get(StringName(trait_name)), float(ours[kit_id].trait_weights[trait_name]),
				'%s.%s reached the registry unclamped.' % [kit_id, trait_name])
		for tag in ours[kit_id].tag_affinity:
			assert_eq(found[&'tag_affinity'].get(StringName(tag)), float(ours[kit_id].tag_affinity[tag]), '%s affinity %s reached the registry.' % [kit_id, tag])

func test_a_cascading_draugr_plays_as_pestilence():
	if not fateofman_present(): return pending(RECIPE)
	var util = load(CASCADE_UTIL)
	var ai = load(CASCADE_AI)
	var gear:GearCore = draugr.get_gear(NHP_KIT)
	if not GearCore.is_valid(gear): return fail_test('Fixture: the Draugr carries Pestilence.')

	gear.set_state(util.NHP_CASCADING_GEAR_STATE_KEY, true)
	util.apply_full_cascade(draugr, SpecFactory.dummy_event(), gear)

	assert_true(util.is_cascading(draugr), 'The Draugr is cascading.')
	assert_eq(draugr.get_faction(), Faction.AI_ALLY, 'The AI holds it.')
	var traits:Dictionary = ai.get_traits(draugr)
	assert_eq(traits.get(&'misanthropy'), 0.8, 'Pestilence does not care who it hits - OUR value, not the neutral default.')
	assert_eq(traits.get(&'esotericism'), 0.8, 'Pestilence is strange.')

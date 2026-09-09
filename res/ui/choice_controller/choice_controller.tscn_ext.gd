# Installs Acid Spill's qualifying-endpoint highlight. On 1.4.0 it also installs the mod's
# tile-set picker (see reag_tile_set_picker.gd).
#
# A .tscn_ext.gd is the composable mod mechanism: it ADDS a child rather than replacing a script, so
# it does not conflict with another mod extending the same scene, and it overrides no base-game
# method. The listener finds ChoiceBus and EffectsControllerBus itself - both are static singleton
# .tres resources (tilepicker.gd:5-6), not autoloads - so it needs nothing from this scene except a
# place in the tree.
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-04-acid-spill-design.md
#
# extends RefCounted, NOT Node: engine/mod/lancer_tactics_mod.gd:239 does
# `var extending_obj:RefCounted = extending_script.new()`, and the Mod Tool's own template
# (addons/mod_tool/interface/file_system/file_system_context_actions.gd:153) generates
# `extends RefCounted` for a .tscn_ext.gd. Verified 2026-09-04: `extends Node` here crashed
# extend_scene with "Trying to assign value of type 'Node' to a variable of type 'RefCounted'",
# which silently drops the whole extension (no scene modification, no further error) since the
# caller only guards on `not extending_obj`.
extends RefCounted

const AcidSpillHighlight := preload('./acid_spill_highlight.gd')

const Compat := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/reag_compat.gd')
## 1.4.0-only; load()ed, never preload()ed - its script does not parse against the 1.3.3 TilePicker.
const TILE_SET_PICKER_SCENE := 'res://unpacked/Reag-ThyHubris/res/ui/choice_controller/reag_tile_set_picker.tscn'

func modify_scene(scene_root:Node) -> Node:
	# Idempotency guards: see mod_main.gd's reapply_scene_extensions_140, which calls this function a
	# SECOND time as a 1.4.0 workaround for a ModLoader scene-extension caching bug. If that workaround
	# ever runs against a scene that (for whatever reason) already carries these children -- e.g. a
	# future engine fix makes ModLoader's own first pass stick after all -- this must not double them.
	if scene_root.find_child('AcidSpillHighlight', false, false) == null:
		var listener := AcidSpillHighlight.new()
		listener.name = 'AcidSpillHighlight'
		scene_root.add_child(listener)
		# Required by the modding guide: an added child needs an owner or it is not saved with the scene.
		listener.owner = scene_root

	# 1.4.0 deleted choose_target_tiles / tilepicker_ability; put our own picker where the engine's
	# was. ChoiceController.initialize walks its children and initialises every TilePicker, so this
	# overrides nothing. A sub-scene INSTANCE, so its own %ChoiceRequestReceiver survives the re-pack.
	if Compat.is_140() and scene_root.find_child('ReagTileSetPicker', false, false) == null:
		var picker:Node = load(TILE_SET_PICKER_SCENE).instantiate()
		picker.name = 'ReagTileSetPicker'
		scene_root.add_child(picker)
		picker.owner = scene_root
	return scene_root

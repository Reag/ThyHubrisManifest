# Installs Acid Spill's qualifying-endpoint highlight.
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

func modify_scene(scene_root:Node) -> Node:
	var listener := AcidSpillHighlight.new()
	listener.name = 'AcidSpillHighlight'
	scene_root.add_child(listener)
	# Required by the modding guide: an added child needs an owner or it is not saved with the scene.
	listener.owner = scene_root
	return scene_root

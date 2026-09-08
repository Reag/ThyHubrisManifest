extends Node

const MOD_ID := "Reag-ThyHubris" ## Name of the directory that this file is in

# 1.4.0 workaround (see reload_extended_autoloads_140 below)
const MOD_LIBRARY_140 := 'res://engine/mod/mod_library.gd' # exists only on 1.4.0; used purely as a version test, never named as a class
## Autoloads this mod extends with .gd_ext.gd files, by autoload name => vanilla script path.
const EXTENDED_AUTOLOADS := {
	&'UnitRelation': 'res://engine/character/unit/service/unit_relation.gd',
	&'UnitTile': 'res://engine/character/unit/service/unit_tile.gd',
}

# Runs when this mod is activated (whenever active mods are changed)
func _init() -> void:
	ModLoaderLog.info("Activating.", MOD_ID)

	# Adds the translations from your localization/localizations.csv
	LancerTacticsMod.add_translations(MOD_ID)

	# Automatically scans everything in your mod's res/ directory, and:
	# 1. Adds any new RESOURCES (.tres, .tscn, images) or SCRIPTS (.gd) to the virtual
	#    filesystem if there was no vanilla corresponding file.
	# 2. Overwrites any RESOURCES that already existed at those corresponding locations
	# 3. Installs any SCRIPTS (.gd) that already existed as a script_extension. (Warning: cannot extend class_name scripts)
	LancerTacticsMod.add_overwrite_extend_mod_resources(MOD_ID)

	# In case you need to manually replace your own resources // script extensions, you can do so with these:
	#var mod_dir_path := ModLoaderMod.get_unpacked_dir().path_join(MOD_ID)
	#var res_dir_path := LancerTacticsMod.get_mod_res_dir(MOD_ID)
	#LancerTacticsMod.replace_resource(MOD_ID, "res://some_vanilla_resource.tres", mod_dir_path.path_join("your_replacement_resource.tres"))
	#LancerTacticsMod.extend_script(MOD_ID, mod_dir_path.path_join("your_extending_script.gd"))
	#LancerTacticsMod.extend_scene(MOD_ID, mod_dir_path.path_join("your_extending_script.tscn_ext.gd"))

# Runs when this mod's node is added to the tree (whenever active mods are changed)
func _ready() -> void:
	if ResourceLoader.exists(MOD_LIBRARY_140): reload_extended_autoloads_140.call_deferred()

## 1.4.0 installs mods AFTER the autoloads exist and then only reloads an autoload whose PLAIN .gd a
## mod replaced: ModApplier.apply_script_changes_to_autoload_nodes matches each mod file's vanilla
## path against the autoload table, and our files' vanilla paths end in ".gd_ext.gd", so UnitRelation
## and UnitTile keep their pre-extension scripts and none of our overrides run. (1.3.3 never had the
## problem: ModLoader ran before those autoloads were instantiated.)
##
## Deferred from _ready on purpose: ModApplier.execute_apply_modset installs every mod and then
## applies all queued script extensions synchronously, so by the time this deferred call runs,
## load(vanilla_path) already returns the extended script (take_over_path). Self-disabling: on 1.3.3
## _ready never schedules it, and once Wickworks fixes the matching the node already holds the
## extended script and the comparison below skips it. Reported upstream 2026-09-08.
func reload_extended_autoloads_140() -> void:
	for autoload_name:StringName in EXTENDED_AUTOLOADS:
		var node:Node = get_tree().root.get_node_or_null(NodePath(autoload_name))
		if node == null: continue
		var extended:Script = load(EXTENDED_AUTOLOADS[autoload_name])
		if node.get_script() == extended: continue # already right (engine fixed, or nothing extended it)
		node.set_script(null)
		node.set_script(extended)
		ModLoaderLog.info('Reloaded autoload %s with its script extension (1.4.0 workaround).' % autoload_name, MOD_ID)

# Runs when this mod is deactivated due to user input or the normal mod reset/reactivate sequence.
# Should undo any non-standard stuff you've done in _init or _ready.
#func deactivate() -> void:
	#ModLoaderLog.info("Deactivating", MOD_ID)

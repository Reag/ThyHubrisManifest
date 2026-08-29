extends Node

const MOD_ID := "Reag-ThyHubris" ## Name of the directory that this file is in

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
#func _ready() -> void:
	#ModLoaderLog.info("Activating (ready)", MOD_ID)

# Runs when this mod is deactivated due to user input or the normal mod reset/reactivate sequence.
# Should undo any non-standard stuff you've done in _init or _ready.
#func deactivate() -> void:
	#ModLoaderLog.info("Deactivating", MOD_ID)

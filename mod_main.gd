extends Node

const MOD_ID := "Reag-ThyHubris" ## Name of the directory that this file is in

# 1.4.0 workaround (see reload_extended_autoloads_140 below)
const MOD_LIBRARY_140 := 'res://engine/mod/mod_library.gd' # exists only on 1.4.0; used purely as a version test, never named as a class
## Autoloads this mod extends with .gd_ext.gd files, by autoload name => vanilla script path.
const EXTENDED_AUTOLOADS := {
	&'UnitRelation': 'res://engine/character/unit/service/unit_relation.gd',
	&'UnitTile': 'res://engine/character/unit/service/unit_tile.gd',
	&'UnitPrinter': 'res://engine/character/unit/service/unit_printer.gd',
}

# 1.4.0 workaround #2 (see reapply_scene_extensions_140 below)
const CHOICE_CONTROLLER_SCENE_PATH := 'res://ui/choice_controller/choice_controller.tscn'
const ChoiceControllerExt := preload('res://unpacked/Reag-ThyHubris/res/ui/choice_controller/choice_controller.tscn_ext.gd')
## Keeps the re-packed scene alive; see reapply_scene_extensions_140 for why that matters. An
## instance var, not static: the embassy node (this script) lives exactly as long as the mod is
## active, and TH declares requires_restart: true in manifest.json, so there is no deactivate() to
## release it from - the node going away when the mod is torn down is the only cleanup needed.
var _kept_choice_controller_scene:PackedScene

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

	register_glossary_terms()

	# In case you need to manually replace your own resources // script extensions, you can do so with these:
	#var mod_dir_path := ModLoaderMod.get_unpacked_dir().path_join(MOD_ID)
	#var res_dir_path := LancerTacticsMod.get_mod_res_dir(MOD_ID)
	#LancerTacticsMod.replace_resource(MOD_ID, "res://some_vanilla_resource.tres", mod_dir_path.path_join("your_replacement_resource.tres"))
	#LancerTacticsMod.extend_script(MOD_ID, mod_dir_path.path_join("your_extending_script.gd"))
	#LancerTacticsMod.extend_scene(MOD_ID, mod_dir_path.path_join("your_extending_script.tscn_ext.gd"))

## Terms the mod uses in its rule text that the base game's glossary does not list.
##
## GlossaryItem.process_glossed_text turns |markup| into a link only when find_key_from_label can
## resolve the label to a key in cached_term_keys (glossary_item.gd:174-209), and that list is
## loaded from the game's own glossary json - which has no "efficient" entry, in either engine.
## Appending to the cache is how gavstarb-horus_alts_1st_party/mod_main.gd:32-35 does it, and the
## priming call is load-bearing: the cache is filled lazily on the first lookup, so appending before
## that would be overwritten by the fill.
##
## find_key_from_label also refuses any key whose ".desc" row is missing (:203-206), so both CSV
## rows have to exist for this to have any effect at all.
func register_glossary_terms() -> void:
	GlossaryItem.find_key_from_label('') # force the lazy cache fill before we append to it
	for term:StringName in [&'lancer.term.efficient']:
		if not GlossaryItem.cached_term_keys.has(term): GlossaryItem.cached_term_keys.append(term)

# Runs when this mod's node is added to the tree (whenever active mods are changed)
func _ready() -> void:
	if ResourceLoader.exists(MOD_LIBRARY_140):
		reload_extended_autoloads_140.call_deferred()
		reapply_scene_extensions_140.call_deferred()

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

## 1.4.0 workaround #2. ModLoader's own scene-extension mechanism
## (addons/mod_loader/internal/scene_extension.gd:_save_scene) packs the extended scene into a LOCAL
## PackedScene variable and take_over_path()s it onto the vanilla path -- but nothing else keeps that
## local variable alive once _save_scene() returns, so Godot's refcounting frees it immediately, and a
## RefCounted Resource's destructor un-registers itself from the resource cache on the way out. Every
## later load() of choice_controller.tscn therefore returns the plain, UNEXTENDED scene straight off
## disk: no AcidSpillHighlight, no ReagTileSetPicker. choice_controller.tscn is an ext_resource of
## gamemaster.tscn, not something Gamemaster.create_gamemaster_node loads directly - the load that
## matters is the game's first load() of gamemaster.tscn (engine/gamemaster/gamemaster.gd:48), for
## every real game AND every spec, and the deferred call below beats it.
##
## Confirmed 2026-09-09 building Task 6 (the tile-set picker): a load() of choice_controller.tscn
## issued ONE FRAME after ModLoader's own take_over_path (deferred from inside modify_scene itself, so
## strictly after _save_scene had already run) came back without either mod child already.
## test_tile_set_picker.gd's own header calls this out as "the open risk this file exists to settle" --
## it turned out to be real, and this is the fix, at the same deferred timing as the autoload
## workaround above (well after ModApplier has finished applying every mod's changes).
##
## The fix is the same shape as reload_extended_autoloads_140: redo the extension ourselves, after
## ModLoader has already run and lost its copy, and this time keep a REAL reference
## (_kept_choice_controller_scene) so the resource-cache entry has something to survive on. Reuses
## choice_controller.tscn_ext.gd's own modify_scene() rather than duplicating its logic, and that
## function is written to be idempotent (skips a child it can already find by name) in case a future
## engine fix makes ModLoader's own first pass stick after all, so calling it a second time here is
## always safe.
func reapply_scene_extensions_140() -> void:
	var scene = load(CHOICE_CONTROLLER_SCENE_PATH)
	if scene == null: return
	var fresh:Node = scene.instantiate()
	if fresh == null: return
	var modified:Node = ChoiceControllerExt.new().modify_scene(fresh)
	if modified == null: modified = fresh
	var packed := PackedScene.new()
	var pack_err := packed.pack(modified)
	modified.queue_free()
	if pack_err != OK:
		ModLoaderLog.error('Failed to re-pack choice_controller.tscn (1.4.0 workaround): error %s' % pack_err, MOD_ID)
		return
	packed.take_over_path(CHOICE_CONTROLLER_SCENE_PATH)
	_kept_choice_controller_scene = packed # load-bearing: see the function header above.
	ModLoaderLog.info('Re-applied choice_controller.tscn scene extension with a held reference (1.4.0 workaround).', MOD_ID)

# Runs when this mod is deactivated due to user input or the normal mod reset/reactivate sequence.
# Should undo any non-standard stuff you've done in _init or _ready.
#func deactivate() -> void:
	#ModLoaderLog.info("Deactivating", MOD_ID)

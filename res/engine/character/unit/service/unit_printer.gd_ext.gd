# Script extension on the UnitPrinter autoload. ONE RULE so far; anything added later gets its own
# banner, as unit_relation.gd_ext.gd does, because a .gd_ext.gd's path IS its declaration and there
# is nowhere else a second rule on this file could live.
#
#   DRAUGR (mw_injector_drill) - "it can be destroyed even with no charges remaining."
#
# Vanilla's get_destructable_gear (unit_printer.gd:311-320) requires gear.has_charges_left(), which
# for a Limited kit means charges_current > 0 (gear_core.gd:249). That is right for Limited gear in
# general - an empty Stub Cannon is not a system that can be shot off - but the drill's rules text
# says the opposite in so many words, so the drill is whitelisted here by kit id. Nothing else
# changes: kit.is_destructable() and not gear.is_destroyed still apply, and every other kit goes
# through the vanilla check untouched.
#
# Why an extension and not a Kit property: Kit has no "destructible while empty" export and the base
# game is off limits. Why the whitelist is a const here rather than read off the Kit: a .tres cannot
# carry a custom flag without a script of its own, and a Kit subclass script is the one thing the
# ContentLibrary globs would mis-file (the filename prefix decides the index, not the class).
#
# 1.4.0: the autoload keeps its pre-extension script unless mod_main.gd reloads it
# (EXTENDED_AUTOLOADS + reload_extended_autoloads_140); UnitPrinter is in that table. The liveness
# proof is spec/test_injector_drill.gd's zero-charges test, which only vanilla could fail.
extends "res://engine/character/unit/service/unit_printer.gd"

## Kits whose rules text says they stay destructible with no charges left.
const DESTRUCTIBLE_WHILE_EMPTY:Array[StringName] = [&'mw_injector_drill']

static func get_destructable_gear(gear_list:Array[GearCore]) -> Array[GearCore]:
	var destructable_gear := super.get_destructable_gear(gear_list)
	for gear:GearCore in gear_list:
		if destructable_gear.has(gear): continue
		if not GearCore.is_valid(gear) or gear.is_destroyed: continue
		if not gear.kit.is_destructable(): continue
		if not DESTRUCTIBLE_WHILE_EMPTY.has(gear.kit.compcon_id): continue
		destructable_gear.append(gear)
	return destructable_gear

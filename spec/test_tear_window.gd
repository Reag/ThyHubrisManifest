# Integration: does tear routing actually reach the engine?
#
# test_tear_routing.gd proves the RULES with no extension involved. This file proves the SEAMS. If
# this is red while that is green, an extension is not firing - which is a precise signal, and the
# reason the brain lives in plain script.
extends GutTest

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')

var game:Gamemaster
var banshee:Unit
var ghost:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self, true, SpecFactory.create_combat(Landscape.create_default(Vector2i(12,12))))
	banshee = SpecFactory.create_unit(game.map, Vector2i(1,1))
	ghost = SpecFactory.create_unit(game.map, Vector2i(10,10), Faction.AI_ENEMY)
	SpecFactory.apply(ghost, Lancer.STATUS.INTANGIBLE)

func after_each():
	TearRouting.invalidate(game.map)

func test_line_of_sight_is_widened_through_a_tear():
	# The seam assertion. A tile the tear can see must appear in the viewer's line of sight.
	#
	# CANNOT be tested on the bare create_default map used elsewhere in this file: that landscape is
	# flat with zero blockers, so get_tiles_in_los already returns every tile on the board with no
	# range cap (confirmed against unit_tile.gd:525-543 and the permissive-visibility sightline
	# layer, which caps nothing but elevation). A tear placed at (6,6) can only contribute tiles that
	# are ALREADY in that total, so before == after regardless of whether the seam fires - the
	# original form of this test could never go red even with a dead extension. A real obstruction is
	# required to make "not yet visible" a meaningful state.
	#
	# The wall geometry is from test/gamemaster/test_map_sightlines.gd
	# (test_elevation_blocks_los_in_abstract): a blocker at (2,1)-(2,3), with (4,0) visible around its
	# open end and (4,1) shadowed behind it.
	#
	# The HEIGHT is deliberately 4 rather than that test's 2. That test queries can_tile_see with an
	# explicit layer of 1, whereas get_tiles_in_los derives its height from
	# UnitTile.effective_height(unit, ...) and then takes maxi(from_height, to_height) - and a unit
	# standing on flat ground is tall enough to see straight over a height-2 wall. Vanilla says so
	# itself two lines later: at layer 2 the same wall stops blocking. A wall the viewer can see over
	# makes the sanity check below fail and the whole test meaningless, so it has to out-top the unit.
	SpecFactory.set_tiles_elevation(game.map, 4, [Vector2i(2,1), Vector2i(2,2), Vector2i(2,3)])
	game.map.calculate_los_blockers()

	var hidden_tile := Vector2i(4,1)
	var before := UnitTile.get_tiles_in_los(banshee)
	assert_false(Tile.in_bitwise_array(before, hidden_tile),
		'Sanity check: the wall genuinely blocks direct sight to the hidden tile.')

	# Placed around the open end of the wall: visible to the Banshee directly (same spot vanilla
	# proves visible from (1,1)), and with a plain, unobstructed line of its own to the hidden tile.
	_place_tear(Vector2i(4,0))
	var after := UnitTile.get_tiles_in_los(banshee)
	assert_true(Tile.in_bitwise_array(after, hidden_tile),
		'Opening a tear changes what the Banshee can see. If this is red the unit_tile seam is dead.')

func test_the_seam_is_inert_when_no_tear_is_open():
	# Guards the other direction: the override must be inert when no tear is on the map, or every
	# other frame in the game inherits the Banshee's optics.
	#
	# Asserted against the ROUTING CONTRIBUTION, not by calling get_tiles_in_los twice and comparing
	# - two identical calls are equal whether or not the override does anything, so that form would
	# pass on a completely broken seam.
	var los := UnitTile.get_tiles_in_los(banshee)
	var contribution := TearRouting.tiles_visible_via_tears(game.map, banshee.tile())
	assert_true(Tile.is_bitwise_array_empty(contribution), 'Routing adds nothing with no tears open.')
	assert_true(Tile.are_bitwise_arrays_same(los, super_los_baseline()),
		'So line of sight matches what vanilla geometry alone produces.')

## Vanilla's own answer for this viewer, computed without going through the override: the sweep the
## engine would do from the Banshee's tile. Gives the inertness test something real to compare to.
func super_los_baseline() -> PackedInt64Array:
	return UnitTile.get_tiles_in_los_alt(game.map, banshee.tile())

func _place_tear(tile:Vector2i) -> Unit:
	var tear := SpecFactory.create_unit(game.map, tile)
	tear.core.frame = load('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/dep_tear_banshee.tres')
	tear.update_cached_values_and_token(SpecFactory.dummy_event())
	TearRouting.invalidate(game.map)
	return tear

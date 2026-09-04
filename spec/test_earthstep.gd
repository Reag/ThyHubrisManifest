# Earthstep - characters standing in difficult terrain cannot OVERWATCH the Nuckelavee.
#
#   "The Nuckelavee does not trigger |OVERWATCH| from characters in difficult terrain."
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-04-earthstep-design.md
#
# The characters in the terrain are the WATCHERS, not the Nuckelavee - their footing is fouled, so
# they cannot bring a weapon to bear as it goes past. That reading is why this cannot be a
# MovementType flag: ignore_rxns is a property of the MOVER and has no way to say "except from
# watchers whose own footing is fouled".
#
# ANY difficult terrain counts, not only the Nuckelavee's own. That is the opposite of Caustic
# Earth, deliberately - this trait is about the watcher's footing, whoever fouled it. So these tests
# lay their own terrain rather than using Poisoned Soil.
#
# NOT via SpecFactory.set_terrain: that writes map.ground_terrain, and get_surface_terrain_at - the
# accessor the pathfinder uses to charge for difficult terrain (pathfinder.gd:79,93) - never reads
# it. surface_terrain is merged from ground_surface_terrain plus dynamic terrain
# (map_state.gd:474-478). Measured: with set_terrain the same tile reports ground=true,
# surface=false, and this trait's test could never pass. See _make_rough.
#
# Modelled on vanilla's own test/gear/test_ms_overwatch.gd: spec units already carry ms_overwatch
# from the basic loadout, the watcher only needs a weapon, and "did overwatch fire" reads off
# mover.current_damage().
extends GutTest

const EARTHSTEP_ID := &'mt_earthstep'

## Geometry copied from vanilla's test/gear/test_ms_overwatch.gd, which is known to produce an
## overwatch: the watcher sits at the origin and the mover starts ADJACENT to it before walking away.
## Do not "tidy" these - the fixture failing to overwatch at all is the one thing that would make
## every "no damage" assertion in this file vacuous. All inside the 5x5 default map.
const WATCHER_TILE := Vector2i(0, 0)
const START := Vector2i(1, 1)
const FINISH := Vector2i(3, 3)

var game:Gamemaster
var nuckelavee:Unit
var watcher:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self)

	nuckelavee = SpecFactory.create_unit(game.map, START, Faction.AI_ENEMY)
	nuckelavee.core.equip_system(EARTHSTEP_ID)
	nuckelavee.core.frame.stat.health = 100 # survive the overwatch so damage is readable, not fatal
	nuckelavee.core.full_repair()
	SpecFactory.apply_passive_buffs(nuckelavee)

	watcher = SpecFactory.create_unit(game.map, WATCHER_TILE)
	watcher.core.equip_system(&'mw_assault_rifle')
	SpecFactory.apply_passive_buffs(watcher)

## Lay real vanilla difficult terrain on `tiles`, and nowhere else. TerrainBlockData.BLANK goes
## everywhere not listed, which is what SpecFactory.set_terrain does anyway.
func _make_rough(tiles:Array[Vector2i]) -> void:
	var rough := TerrainBlockData.new()
	rough.difficult_terrain = true
	for tile:Vector2i in tiles:
		game.map.ground_surface_terrain[tile] = rough
		game.map.calculate_surface_merged_terrain_and_height_at(tile)

# ============================== the extension is alive ==============================

func test_a_watcher_on_clean_ground_overwatches_the_nuckelavee():
	# THE VACUITY GUARD FOR THIS WHOLE FILE, and the proof the fixture can produce an overwatch at
	# all. If this fails, nothing below means anything - every "no damage" assertion would pass
	# against a fixture that simply never overwatches.
	await SpecFactory.move(game, nuckelavee, FINISH)
	assert_eq(nuckelavee.tile(), FINISH, 'It actually moved.')
	assert_gt(nuckelavee.current_damage(), 0, 'The watcher caught it.')

func test_a_watcher_standing_in_difficult_terrain_does_not():
	# The trait. Same fixture, same move; the only difference is the ground under the WATCHER.
	_make_rough([WATCHER_TILE])
	await SpecFactory.move(game, nuckelavee, FINISH)
	assert_eq(nuckelavee.tile(), FINISH, 'It actually moved.')
	assert_eq(nuckelavee.current_damage(), 0, 'Fouled footing, no shot.')

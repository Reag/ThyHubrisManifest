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
const PoisonedSoil := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_nuckelavee/mt_poisoned_soil/passive_poisoned_soil.gd')

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

# ============================== what it must NOT do ==============================

func test_a_watcher_in_difficult_terrain_still_overwatches_anybody_else():
	# The override keys on the MOVER carrying Earthstep. Fouled footing is not a general excuse to
	# stop watching - without this, the trait would be a map-wide overwatch shutdown that happens to
	# be on the Nuckelavee's card.
	# Starts adjacent to the watcher, same as the Nuckelavee does, and walks away down its own lane
	# so it never contends for a tile with anyone.
	_make_rough([WATCHER_TILE])
	var stranger := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	stranger.core.frame.stat.health = 100
	stranger.core.full_repair()
	SpecFactory.apply_passive_buffs(stranger)

	await SpecFactory.move(game, stranger, Vector2i(3, 0))
	assert_eq(stranger.tile(), Vector2i(3, 0), 'It actually moved.')
	assert_gt(stranger.current_damage(), 0, 'Somebody without Earthstep is still caught.')

func test_the_nuckelavee_still_overwatches_from_difficult_terrain_itself():
	# The trait is about being moved PAST, not about watching. A Nuckelavee standing in its own filth
	# shoots at passers-by exactly as anyone would - the override reads target_unit, never from_unit,
	# for the Earthstep half.
	# The Nuckelavee stands at START (1,1) and the prey starts adjacent at (2,1), mirroring the
	# watcher/mover adjacency the fixture is built on.
	_make_rough([START])
	nuckelavee.core.equip_system(&'mw_assault_rifle')
	SpecFactory.apply_passive_buffs(nuckelavee)

	var prey := SpecFactory.create_unit(game.map, Vector2i(2, 1))
	prey.core.frame.stat.health = 100
	prey.core.full_repair()
	SpecFactory.apply_passive_buffs(prey)

	await SpecFactory.move(game, prey, Vector2i(4, 1))
	assert_eq(prey.tile(), Vector2i(4, 1), 'It actually moved.')
	assert_gt(prey.current_damage(), 0, 'The Nuckelavee shot it from the muck.')

func test_a_flying_watcher_over_difficult_terrain_still_overwatches():
	# It is hovering, not standing - there is nothing under its feet to foul. The engine agrees:
	# MovementType.ignores_difficult_terrain() (movement_type.gd:107-108) returns true outright for a
	# flying unit, and the pathfinder skips difficult terrain's extra cost for the same reason.
	#
	# This also stops a zero-g map handing the Nuckelavee blanket immunity, since MovementType.create
	# sets `flying` from STATUS.FLYING OR is_in_zero_g (movement_type.gd:46).
	#
	# Asserted white-box on is_footing_fouled, like test_attack_triggered_reactions_are_not_suppressed
	# below, rather than through a real move-and-shoot. FLYING also lifts the watcher's effective
	# floor by Lancer.FLYING_HEIGHT (unit_tile.gd:230, +3) - a real engine mechanic completely
	# separate from Earthstep, and it puts the watcher out of vertical reach of this fixture's
	# threat-1 assault rifle regardless of what is_footing_fouled returns. Routing through
	# SpecFactory.move and reading current_damage() would therefore read 0 whether or not the guard
	# is there, proving nothing about Earthstep either way. Confirmed by direct measurement:
	# UnitRelation.get_weapons_that_can_react_against(watcher, nuckelavee, false) is empty here purely
	# from the elevation check in can_units_touch_elevationwise, even with is_footing_fouled false.
	_make_rough([WATCHER_TILE])
	# Without this the test passes for the wrong reason if _make_rough ever silently stops working.
	assert_true(game.map.get_surface_terrain_at(WATCHER_TILE).difficult_terrain,
		'Fixture check: the ground under the watcher really is difficult.')
	SpecFactory.apply(watcher, Lancer.STATUS.FLYING)

	assert_false(UnitRelation.is_footing_fouled(watcher), 'A hovering watcher is not standing in the muck.')

func test_attack_triggered_reactions_are_not_suppressed():
	# The one assumption in this trait worth distrusting, asserted directly.
	#
	# The override is gated on use_normal_range_instead_of_threat == false to separate movement
	# overwatches from attack-triggered reactions - Punishment, Cover Me, Reflexive Blow, Flank, Fix
	# and Flank, Instinct Mode - all of which pass TRUE and must keep working. That parameter does not
	# actually mean "is this an overwatch"; the split is a coincidence that holds today.
	#
	# Asserted white-box on the function rather than by orchestrating a real Punishment. Punishment
	# needs an honorable-challenge mark on the attacker, a third unit being attacked within 3, and a
	# reaction available - a large fixture to prove one boolean, and vanilla's own
	# test/talent/test_t_exemplar.gd already covers Punishment itself. What is OURS to prove is that
	# the flag still divides the two, and this proves exactly that.
	_make_rough([WATCHER_TILE])

	assert_true(
		UnitRelation.get_weapons_that_can_overwatch(watcher, nuckelavee, false).is_empty(),
		'Threat-based calls - the movement overwatches - are suppressed.')
	assert_false(
		UnitRelation.get_weapons_that_can_overwatch(watcher, nuckelavee, true).is_empty(),
		'Range-based calls - the attack reactions - are not.')

func test_poisoned_soils_trail_blinds_a_watcher_too():
	# The two traits compose. Task 1 used vanilla map terrain because the rule is about the watcher's
	# footing whoever fouled it; this proves our own trail is footing as well, through the real
	# terrain-zone path rather than SpecFactory.set_terrain.
	var soil_gear:GearCore = nuckelavee.core.equip_system(&'mt_poisoned_soil')
	SpecFactory.apply_passive_buffs(nuckelavee)

	PoisonedSoil.write_trail(soil_gear, [WATCHER_TILE] as Array[Vector2i])
	# GearCore.set_state does not refresh the map - only set_aura_active does - so ask for a sweep,
	# exactly as action_poisoned_soil_lay.gd has to.
	UnitTile.update_tracking_and_statuses(game.map)
	assert_true(game.map.get_surface_terrain_at(WATCHER_TILE).difficult_terrain,
		'Fixture check: the trail really reached the map.')

	await SpecFactory.move(game, nuckelavee, FINISH)
	assert_eq(nuckelavee.tile(), FINISH, 'It actually moved.')
	assert_eq(nuckelavee.current_damage(), 0, 'Standing in the trail blinds the watcher too.')

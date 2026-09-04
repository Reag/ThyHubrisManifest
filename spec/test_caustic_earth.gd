# Caustic Earth - the Nuckelavee's ground bites whoever stands in it.
#
#   "Characters who start their turn in or enter a space of |difficult terrain| created by the
#    Nuckelavee take |1 AP ENERGY|. Characters can take this damage 1/round. Characters who ignore
#    |difficult terrain| ignore this damage"
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-04-caustic-earth-design.md
#
# TerrainData.DANGEROUS_TERRAIN.ENERGY is NOT this trait - it fires at turn END for 5 on a failed
# engineering check and limits per TURN. The chassis is ActionReactionOnComingWithin, which owns
# both triggers and a per-character 1/round limiter built on buff_track_affection.
#
# Every case here asserts on real HP loss. A silently-dead reaction looks exactly like "the engine
# does not do that", so asserting on the affection buff or on the tile query alone would be evidence
# of nothing. Every damage assertion is paired with the same manoeuvre over clean ground.
extends GutTest

const PoisonedSoil := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_nuckelavee/mt_poisoned_soil/passive_poisoned_soil.gd')

const SOIL_ID := &'mt_poisoned_soil'
const CAUSTIC_ID := &'mt_caustic_earth'

const NUCK_TILE := Vector2i(0, 0)
const VICTIM_TILE := Vector2i(4, 0)
## The fouled tile. Directly west of where the victim starts, so one step reaches it.
##
## SpecFactory.setup_gamemaster's default combat is a 5x5 map (Tile.MIN_MAP_DIMENSION), so every
## tile below is kept inside x,y in [0,4] - the brief's original (5,0)/(5,1) sat one column off the
## east edge, which silently produced a zero-step pathfinder (no move, no reaction, tile unchanged)
## rather than an error. Confirmed via victim.tile() logging before landing on this fix.
const ACID := Vector2i(3, 0)
## Same distance from the victim, never fouled - the control tile for every vacuity guard.
const CLEAN := Vector2i(4, 1)

var game:Gamemaster
var nuckelavee:Unit
var soil_gear:GearCore
var victim:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	nuckelavee = SpecFactory.create_unit(game.map, NUCK_TILE)
	soil_gear = nuckelavee.core.equip_system(SOIL_ID)
	nuckelavee.core.equip_system(CAUSTIC_ID)
	SpecFactory.apply_passive_buffs(nuckelavee)

	victim = SpecFactory.create_unit(game.map, VICTIM_TILE, Faction.AI_ENEMY)
	SpecFactory.apply_passive_buffs(victim)

## Foul `tiles` as Poisoned Soil would. Caustic Earth reads the passive directly rather than the
## map, so no terrain refresh is needed here - unlike test_poisoned_soil.gd, which goes through the
## pathfinder and does need one.
func _foul(tiles:Array[Vector2i]) -> void:
	PoisonedSoil.write_trail(soil_gear, tiles)

func _health(unit:Unit) -> int:
	return unit.core.current.health

# ============================== entering the terrain ==============================

func test_stepping_into_the_acid_costs_one_hp():
	_foul([ACID])
	await SpecFactory.start_turn(game, victim)
	var before:int = _health(victim)
	await SpecFactory.move(game, victim, ACID)
	assert_eq(_health(victim), before - 1, 'One step into the acid, one HP.')

func test_stepping_onto_clean_ground_costs_nothing():
	# Vacuity guard for the test above. Without it, a trait that damaged EVERY mover would pass.
	_foul([ACID])
	await SpecFactory.start_turn(game, victim)
	var before:int = _health(victim)
	await SpecFactory.move(game, victim, CLEAN)
	assert_eq(_health(victim), before, 'The same move onto unfouled ground is free.')

func test_the_damage_is_armour_piercing():
	# 1 AP ENERGY. Without the AP flag, 1 point of armour absorbs the whole thing and the trait
	# silently does nothing to any armoured target.
	_foul([ACID])
	victim.core.current.armor = 1
	await SpecFactory.start_turn(game, victim)
	var before:int = _health(victim)
	await SpecFactory.move(game, victim, ACID)
	assert_eq(_health(victim), before - 1, 'Armour does not reduce it.')

func test_the_armour_in_that_fixture_really_does_absorb_ordinary_damage():
	# Pairs with the test above: proves the armour was actually applied, so "AP works" cannot pass
	# because the fixture never had armour in the first place.
	victim.core.current.armor = 1
	var before:int = _health(victim)
	await SpecFactory.damage(game, victim, 1, Lancer.DAMAGE_TYPE.ENERGY)
	assert_eq(_health(victim), before, 'A plain 1 ENERGY is absorbed by 1 armour.')

# ============================== starting a turn in the terrain ==============================

func test_starting_a_turn_in_the_acid_costs_one_hp():
	# The victim is already standing on the tile when its turn begins - no movement involved, so
	# this can only come from the new_turn trigger.
	_foul([VICTIM_TILE])
	var before:int = _health(victim)
	await SpecFactory.start_turn(game, victim)
	assert_eq(_health(victim), before - 1, 'Waking up in the acid costs a point.')

func test_starting_a_turn_on_clean_ground_costs_nothing():
	# Vacuity guard.
	_foul([ACID])
	var before:int = _health(victim)
	await SpecFactory.start_turn(game, victim)
	assert_eq(_health(victim), before, 'Its own tile is clean, so nothing happens.')

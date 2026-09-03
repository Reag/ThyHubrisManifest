# Undulating Form.
#
#   "The Kraken may move through other characters, and may end its movement overlapping them, so
#    long as at least one space it occupies is free."
#
# Design notes live in D:\DEV\lancer-tactics-claude\specs\2026-09-02-kraken-design.md.
#
# This is the REDUCED trait. As first written it also squeezed through terrain gaps narrower than
# the frame; that half was spiked and rejected - the decision lives in Pathfinder.Occupation, and
# Pathfinder carries a class_name so it cannot be extended, while UnitTile's occupancy helpers take
# a size rather than a unit and so cannot single out one frame. What ships rides
# Buff.TO.CAN_SHARE_SPACE, which the pathfinder consults at :115-120.
#
# These specs ask the buff the same question the pathfinder does, rather than running a full path:
# the condition is the part with room to be wrong, and building a real corridor of obstructions to
# path through would test the pathfinder more than the trait.
extends GutTest

const TRAIT_ID := &'mt_undulating_form'
const KRAKEN_TILE := Vector2i(0, 0)
## The spec map is 5x5, so a 2x2 footprint must start at 3 or less on both axes or it clips off-map
## and get_occupied returns fewer tiles - which is a different rule (bigunit_offmap_point) and one
## this trait deliberately does not waive.
const DESTINATION := Vector2i(2, 2)

var game:Gamemaster
var kraken:Unit
var plain:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	kraken = SpecFactory.create_unit(game.map, KRAKEN_TILE)
	kraken.core.equip_system(TRAIT_ID)
	plain = SpecFactory.create_unit(game.map, Vector2i(4, 0))
	SpecFactory.apply_passive_buffs(kraken)
	SpecFactory.apply_passive_buffs(plain)

## The question the pathfinder asks, in the shape it asks it (pathfinder.gd:92, :116).
func _sharing_context(mover:Unit, destination:Vector2i, blocking:Unit) -> Context:
	return Context.create({unit = mover, target_tiles = [destination], target_unit = blocking})

## SpecFactory builds size 1 dummies, so the footprint is set here, immediately before asking.
## Not in before_each: applying passive buffs and adding units both trigger the cached-value refresh
## that recomputes occupying_size from the frame, which would silently put it back to 1.
func _may_share(mover:Unit, destination:Vector2i, blocking:Unit, footprint:int = 2) -> bool:
	mover.state.occupying_size = footprint
	return UnitCondition.has_buff_to(mover, Buff.TO.CAN_SHARE_SPACE, _sharing_context(mover, destination, blocking))

## An obstruction standing at a tile, which is what actually blocks a footprint.
func _blocker_at(tile:Vector2i) -> Unit:
	return SpecFactory.create_unit(game.map, tile, Faction.AI_ENEMY)

# ============================== the permission ==============================

func test_it_may_end_its_move_overlapping_a_character():
	# One blocker under a 2x2 footprint leaves three spaces clear, so the Kraken may flow over it.
	var destination := DESTINATION
	var blocker := _blocker_at(destination)
	assert_true(_may_share(kraken, destination, blocker), 'It may share that space.')

func test_a_unit_without_the_trait_may_not():
	# Guards every permissive assertion here against a vacuous pass - if CAN_SHARE_SPACE were
	# somehow universal, these tests would be green for the wrong reason.
	var destination := DESTINATION
	var blocker := _blocker_at(destination)
	assert_false(_may_share(plain, destination, blocker), 'A plain unit may not.')

# ============================== "at least one space free" ==============================

func test_it_may_not_when_every_space_it_would_cover_is_taken():
	# The clause that stops this being "walk through anything". A 2x2 footprint with all four tiles
	# occupied has nowhere for the Kraken to actually be.
	var destination := DESTINATION
	var blocker := _blocker_at(destination)
	for tile:Vector2i in UnitTile.get_occupied(destination, 2, game.map.size):
		if tile != destination: _blocker_at(tile)

	assert_false(_may_share(kraken, destination, blocker), 'With every space taken, it may not.')

func test_one_free_space_is_enough():
	# Three of four covered still leaves somewhere to stand.
	var destination := DESTINATION
	var blocker := _blocker_at(destination)
	var covered := UnitTile.get_occupied(destination, 2, game.map.size)
	assert_eq(covered.size(), 4, 'The footprint is the 2x2 this test assumes.')
	if covered.size() != 4: return

	for i:int in covered.size():
		if i < 3 and covered[i] != destination: _blocker_at(covered[i])
	assert_true(_may_share(kraken, destination, blocker), 'One clear space is enough.')

func test_units_it_is_holding_do_not_count_against_it():
	# A Kraken that has grappled the room would otherwise block itself: its own katamari is standing
	# in the spaces it wants to move into. Mirrors the pathfinder's own filter.
	var destination := DESTINATION
	var held := _blocker_at(destination)
	var gear := kraken.core.equip_system(&'mt_my_domain')
	Katamari.attach_units(SpecFactory.dummy_event(), kraken, held, gear.persistent_id)
	for tile:Vector2i in UnitTile.get_occupied(destination, 2, game.map.size):
		if tile == destination: continue
		Katamari.attach_units(SpecFactory.dummy_event(), kraken, _blocker_at(tile), gear.persistent_id)

	assert_true(_may_share(kraken, destination, held), 'Its own prisoners are not in its way.')

# ============================== who it works for ==============================

func test_it_does_not_let_others_stand_on_the_kraken():
	# The engine asks the same question from both sides. Answering the mirror image would let
	# anything on the map end its move on top of the Kraken, which the trait does not say.
	var mover:Unit = SpecFactory.create_unit(game.map, Vector2i(4, 4), Faction.AI_ENEMY)
	assert_false(
		UnitCondition.has_buff_to(kraken, Buff.TO.CAN_SHARE_SPACE,
			Context.create({unit = mover, target_tiles = [KRAKEN_TILE], target_unit = kraken})),
		'Somebody else moving onto the Kraken gets no help from its trait.')

func test_a_size_one_body_has_nowhere_to_flow():
	# Not an oversight: with a single tile, the only space it occupies IS the one it is trying to
	# share, so "at least one space free" can never hold. Recorded so the behaviour is deliberate.
	var destination := DESTINATION
	var blocker := _blocker_at(destination)
	assert_false(_may_share(kraken, destination, blocker, 1), 'A size 1 Kraken cannot share space.')

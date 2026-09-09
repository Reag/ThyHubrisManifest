# Bind Thy Flesh - the chain itself.
#
#   "The targeted character cannot move away from the chain. This effect lasts until the target
#    makes a HULL check as a quick action, or the object is moved or destroyed."
#
# Design notes live in D:\DEV\lancer-tactics-claude\specs\2026-09-02-bind-thy-flesh-design.md.
# In short: "cannot move away" is a FROZEN DISTANCE - a chained character may never end up further
# from the anchor than it was when chained, so each character carries its own leash on its own buff
# instance. The restriction rides Buff.TO.MOVEMENT_RESTRICTION, which the pathfinder intersects with
# the unit's reachable tiles (pathfinder.gd:344-349).
#
# These specs cover the chain in isolation, applying the buff directly. The trigger - reacting to
# the Erinyes' own area patterns and chaining everyone caught - is a separate piece.
extends GutTest

const BUFF_ID := &'buff_bind_thy_flesh'
const ANCHOR_KIT := &'mt_chain_erinyes'

var game:Gamemaster
var anchor:Unit
var chained:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	anchor = SpecFactory.create_unit(game.map, Vector2i(0, 0))
	anchor.core.equip_system(ANCHOR_KIT)
	chained = SpecFactory.create_unit(game.map, Vector2i(2, 0))

## Apply the chain and record what it is tethered to, the way the trigger will.
func _chain(unit:Unit) -> BuffCore:
	var core := UnitCondition.apply_buff_id(SpecFactory.dummy_event(), unit, BUFF_ID)
	ContentLibrary.get_buff(BUFF_ID).bind(core, anchor, unit)
	return core

## The tiles the restriction still permits this unit to stand on.
func _allowed_tiles(core:BuffCore) -> Array[Vector2i]:
	var values := core.get_values(Context.create({unit = chained, map = game.map}))
	return Tile.from_bitwise_array(values.object, game.map.size)

func test_the_anchor_object_exists_and_is_destructible():
	# "or the object is moved or destroyed" only means something if the anchor can be destroyed.
	var frame:Frame = ContentLibrary.get_mech_frame(&'dep_chain_erinyes')
	assert_true(Frame.is_valid(frame), 'dep_chain_erinyes is in the frames index.')
	if not Frame.is_valid(frame): return
	assert_eq(frame.entity_type, Frame.ENTITY.OBJECT, 'It is an object, as the trait says.')
	assert_gt(frame.stat.health, 0, 'And it has health, so it can be shot off.')

func test_the_chain_records_the_distance_it_was_made_at():
	var core := _chain(chained)
	var expected:int = ContentLibrary.get_buff(BUFF_ID).measure(anchor, chained)
	assert_eq(core.get_state('leash', -1), expected, 'Leash is the distance when chained.')

func test_it_bans_every_tile_further_from_the_anchor():
	var core := _chain(chained)
	var leash:int = core.get_state('leash', 0)
	var allowed := _allowed_tiles(core)
	assert_false(allowed.is_empty(), 'Some tiles are still allowed.')

	var too_far:Array[Vector2i] = []
	for tile:Vector2i in allowed:
		if Tile.distance(Tile.get_closest_pair_between(anchor.occupied_tiles(), [tile]).from, tile) > leash:
			too_far.append(tile)
	assert_eq(too_far.size(), 0, 'No allowed tile is further from the anchor than the leash.')

func test_it_still_allows_closing_in_on_the_anchor():
	# "cannot move away" restricts retreat only - approaching and circling stay legal.
	var core := _chain(chained)
	var allowed := _allowed_tiles(core)
	assert_true(allowed.has(anchor.tile()), 'It may still close right in on the anchor.')

func test_each_character_gets_its_own_leash():
	# One pattern catches characters at different ranges, and they all chain to the same anchor, so
	# the leash cannot live on the shared Buff resource.
	var near := SpecFactory.create_unit(game.map, Vector2i(1, 0))
	var far := SpecFactory.create_unit(game.map, Vector2i(3, 0))
	var near_core := _chain(near)
	var far_core := _chain(far)
	assert_lt(near_core.get_state('leash', 0), far_core.get_state('leash', 0),
		'The closer character is on the shorter leash.')

func test_destroying_the_anchor_lifts_the_restriction():
	var core := _chain(chained)
	assert_false(_allowed_tiles(core).is_empty(), 'Restricted while the anchor stands.')

	await game.execute_event(&'event_unit_die', {unit = anchor})
	var context := Context.create({unit = chained, map = game.map})
	assert_false(ContentLibrary.get_buff(BUFF_ID).is_buff_context_valid_for_passive(core, context),
		'With the anchor gone the restriction no longer applies.')

func test_the_chained_character_is_offered_an_escape_action():
	# The escape lives on the anchor's kit as a situational action, so it shows up for whoever is
	# chained rather than for the anchor (unit_action.gd:27-49).
	_chain(chained)
	var situational := UnitAction.get_situational_actions(chained)
	var from_the_chain:Array = situational.filter(func(specific:SpecificAction) -> bool:
		return specific.gear.kit.compcon_id == ANCHOR_KIT)
	assert_gt(from_the_chain.size(), 0, 'The chained character can try to break free.')

func test_the_escape_is_a_quick_action_hull_check():
	var kit:Kit = ContentLibrary.get_kit(ANCHOR_KIT)
	if not Kit.is_valid(kit): return fail_test('%s loaded.' % ANCHOR_KIT)
	# The kit also carries the release reaction that frees everyone when the shackle is destroyed,
	# so the escape is found by id rather than assumed to be the only action.
	var escape:Action = kit.get_action(&'action_chain_erinyes_escape')
	if not is_instance_valid(escape): return fail_test('The escape action is on the anchor kit.')
	assert_eq(escape.action_type, Lancer.ACTION.QUICK, 'A quick action, as the trait says.')
	assert_eq(escape.make_save_type, Lancer.HASE.HULL, 'Against HULL.')
	assert_true(escape.is_check_instead_of_save, 'And it is a check, not a save.')

func test_the_chained_character_cannot_actually_walk_away():
	# End to end, through the pathfinder rather than just reading the buff back: the point of the
	# restriction is that the move does not happen.
	var core := _chain(chained)
	var leash:int = core.get_state('leash', 0)
	var buff:Buff = ContentLibrary.get_buff(BUFF_ID)

	var retreat := Vector2i(mini(chained.tile().x + leash + 2, game.map.size.x - 1), chained.tile().y)
	assert_gt(Tile.distance(anchor.tile(), retreat), leash, 'The tile we are trying is beyond the leash.')

	await SpecFactory.move(game, chained, retreat)
	assert_ne(chained.tile(), retreat, 'It did not reach the tile beyond its leash.')
	assert_lte(buff.measure(anchor, chained), leash, 'And it is still no further out than when chained.')

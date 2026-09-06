# Clause 7: "An attack cannot travel more than half its maximum range after passing through a tear."
#
# Agreed reading (2026-09-06): a tear REDIRECTS reach rather than extending it, so BOTH hold:
#
#     dist(shooter -> tear) + dist(tear -> target) <= max_range
#     dist(tear -> target)                        <= half of max_range
#
# These specs drive UnitTile.get_tiles_within directly rather than through a weapon, because that is
# the function the rule lives in and it takes max_range as a parameter - so the two legs can be set
# up exactly rather than inferred from whatever a particular gun happens to have.
#
# Every test needs an INTANGIBLE target: routing only ever applies across the tangibility line, so a
# tangible pair would test nothing at all (see test_tear_window.gd's periscope guard).
extends GutTest

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')

var game:Gamemaster
var shooter:Unit
var ghost:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self, true, SpecFactory.create_combat(Landscape.create_default(Vector2i(20,20))))
	game.campaign_core = CampaignCore.create(SpecFactory.create_campaign_base())
	game.map.campaign_core = game.campaign_core
	shooter = SpecFactory.create_unit(game.map, Vector2i(1,1))
	ghost = SpecFactory.create_unit(game.map, Vector2i(1,1), Faction.AI_ENEMY) # moved per-test
	SpecFactory.apply(ghost, Lancer.STATUS.INTANGIBLE)

func after_each():
	TearRouting.invalidate(game.map)

## Place a tear and put the ghost where the test wants it, then drop the caches.
func _setup(tear_tile:Vector2i, ghost_tile:Vector2i) -> void:
	var tear := SpecFactory.create_unit(game.map, tear_tile)
	tear.core.frame = load('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/dep_tear_banshee.tres')
	tear.update_cached_values_and_token(SpecFactory.dummy_event())
	UnitTile.move_to(ghost, ghost_tile)
	TearRouting.invalidate(game.map)

func test_a_route_inside_both_limits_is_allowed():
	# shooter (1,1) -> tear (5,1) is 4; tear -> ghost (7,1) is 2. Total 6 <= 10, and 2 <= half of 10.
	_setup(Vector2i(5,1), Vector2i(7,1))
	assert_true(TearRouting.routes_within_range(game.map, Vector2i(1,1), Vector2i(7,1), 1, 10),
		'A route inside both the total and the post-tear cap is allowed.')

func test_the_post_tear_leg_is_capped_at_half():
	# THE CLAUSE. shooter -> tear is 1, tear -> ghost is 8. Total 9 <= 10 so the total is fine, but 8
	# is well over half of 10 - and it is the half-cap alone that must refuse this.
	_setup(Vector2i(2,1), Vector2i(10,1))
	assert_false(TearRouting.routes_within_range(game.map, Vector2i(1,1), Vector2i(10,1), 1, 10),
		'The post-tear leg cannot exceed half the weapon max range.')

func test_the_total_route_cannot_exceed_max_range():
	# The other half of the agreed reading. tear -> ghost is 2, comfortably under half of 10, but the
	# shooter is 12 away from the tear so the whole route is 14. A tear redirects reach, not extends.
	_setup(Vector2i(13,1), Vector2i(15,1))
	assert_false(TearRouting.routes_within_range(game.map, Vector2i(1,1), Vector2i(15,1), 1, 10),
		'The whole route must still fit inside the weapon max range.')

func test_no_tear_means_no_route_at_any_range():
	assert_false(TearRouting.routes_within_range(game.map, Vector2i(1,1), Vector2i(3,1), 1, 10),
		'With no tear open nothing routes, whatever the range.')

func test_get_tiles_within_grants_a_qualifying_routed_target():
	# The seam, not just the predicate. The ghost sits outside the range box on purpose - a straight
	# line from the shooter is 9 away with max_range 6 - so only routing can put it in reach.
	# shooter (1,1) -> tear (4,1) is 3; tear -> ghost (7,1)... total 6, post-tear 3 = half of 6.
	_setup(Vector2i(4,1), Vector2i(7,1))
	var reachable := UnitTile.get_tiles_within(shooter, 6, true)
	assert_true(reachable.has(Vector2i(7,1)),
		'A routed target inside both limits is reachable even though the box alone would exclude it.')

func test_get_tiles_within_refuses_an_over_range_routed_target():
	# Same shape, but the post-tear leg breaks the half cap: tear (2,1) -> ghost (9,1) is 7, and half
	# of 8 is 4. The tile must NOT come back, even though a tear does bridge the pair.
	_setup(Vector2i(2,1), Vector2i(9,1))
	assert_true(TearRouting.routes_between(game.map, Vector2i(1,1), Vector2i(9,1), 1),
		'Sanity: the pair really is bridged, so a refusal below is the range rule and not the geometry.')
	var reachable := UnitTile.get_tiles_within(shooter, 8, true)
	assert_false(reachable.has(Vector2i(9,1)),
		'Clause 7 keeps an over-range routed target out of reach.')

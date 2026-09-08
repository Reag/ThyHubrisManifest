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

func test_the_range_rule_also_requires_the_tear_to_be_on_the_line():
	# routes_within_range is the tear WINDOW with a range budget bolted on, so it carries the same
	# strict collinearity precondition routes_between does. Everything about this route is affordable -
	# 4 tiles to the tear, 4 past it, against a range of 20 with a cap of 10 - and the only thing wrong
	# with it is that (5,4) is nowhere near the due-east line from (1,1) to (9,1).
	_setup(Vector2i(5,4), Vector2i(9,1))
	assert_false(TearRouting.routes_within_range(game.map, Vector2i(1,1), Vector2i(9,1), 1, 20),
		'An off-line tear routes nothing, however much range budget is left over.')

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

# ---------------------------------------------------------------------------- the reaction path
#
# WHICH PATHS THE CAP ACTUALLY REACHES was the open question of Task 5, and the fix plan's guess -
# that overwatch and reactions skip it, using "raw distance + can_see" - is WRONG. They also require
# UnitTargeting.get_tiles_in_range(specific).has(closest_pair.to)
# (unit_relation.gd:302-308, can_weapon_hit_target_as_rxn), and that walks straight back into
# UnitTile.get_tiles_within with the weapon's own range - this mod's override, cap and all.
#
# These two tests are what makes that claim checkable rather than a comment. The coverage note on
# unit_tile.gd_ext.gd's get_tiles_within asserts it in prose; if these go red, that prose is what
# became false. They are deliberately a matched pair: the refusal alone would pass on a reaction path
# that never fires for any reason at all.
#
# `use_normal_range_instead_of_threat = true` so the rifle is measured by its shooting range rather
# than its threat, which is the geometry the rest of this file is built on.

## Give the shooter a real gun and hand back the SpecificAction the reaction path would build for it.
func _arm_the_shooter() -> SpecificAction:
	var gear:GearCore = shooter.core.equip_system(&'mw_assault_rifle')
	SpecFactory.apply_passive_buffs(shooter)
	var actions:Array[ActionAttackWeapon] = gear.kit.get_weapon_actions()
	if actions.is_empty(): return null
	return SpecificAction.create(shooter, gear, actions[0])

func _reaction_range(specific:SpecificAction) -> int:
	return maxi(specific.action.threat_distance(specific), specific.action.ranged_distance(specific))

func test_a_reaction_inside_the_cap_still_fires():
	# The positive control, and it has to come first: without it the refusal below proves nothing,
	# since an empty list is also what a reaction path that never fires would return.
	var specific := _arm_the_shooter()
	if specific == null: return fail_test('The shooter has a weapon action to react with.')
	var weapon_range:int = _reaction_range(specific)
	var half:int = Util.half(weapon_range)
	# Post-tear leg exactly half the range, total exactly the range: the most generous route the cap
	# permits, and collinear with the shooter along y = 1.
	_setup(Vector2i(1 + weapon_range - half, 1), Vector2i(1 + weapon_range, 1))

	assert_false(UnitRelation.get_weapons_that_can_react_against(shooter, ghost, true).is_empty(),
		'A routed target inside both limits can be reacted against.')

func test_a_reaction_through_a_tear_obeys_the_half_range_cap():
	var specific := _arm_the_shooter()
	if specific == null: return fail_test('The shooter has a weapon action to react with.')
	var weapon_range:int = _reaction_range(specific)
	var half:int = Util.half(weapon_range)
	# Tear one step out, ghost one tile past the half-range cap beyond it. The TOTAL route
	# (1 + half + 1) is still inside the weapon's range, so only the half cap can refuse this.
	_setup(Vector2i(2,1), Vector2i(2 + half + 1, 1))
	assert_true(TearRouting.routes_between(game.map, Vector2i(1,1), ghost.tile(), 1),
		'Sanity: the pair really is bridged, so a refusal is the range rule and not the geometry.')
	assert_false(TearRouting.routes_within_range(game.map, Vector2i(1,1), ghost.tile(), 1, weapon_range),
		'Sanity: and the library does refuse it on the cap.')

	assert_true(UnitRelation.get_weapons_that_can_react_against(shooter, ghost, true).is_empty(),
		'Clause 7 reaches the reaction path too - it is not a targeting-overlay-only rule.')

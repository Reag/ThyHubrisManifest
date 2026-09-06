# To Bend Reality. Asserts the RULES, not the mechanism - so a later re-implementation can be checked
# against the same tests. See D:\DEV\lancer-tactics-claude\specs\2026-09-06-banshee-to-bend-reality-design.md
extends GutTest

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')
const TEAR_FRAME := 'res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/dep_tear_banshee.tres'
const PROXY_FRAME := 'res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/mt_to_bend_reality/dep_bend_proxy_banshee.tres'

var game:Gamemaster
var banshee:Unit
var target:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self, true, SpecFactory.create_combat(Landscape.create_default(Vector2i(20,20))))
	game.campaign_core = CampaignCore.create(SpecFactory.create_campaign_base())
	game.map.campaign_core = game.campaign_core
	banshee = SpecFactory.create_unit(game.map, Vector2i(1,1))
	target = SpecFactory.create_unit(game.map, Vector2i(10,1), Faction.AI_ENEMY)

func after_each():
	TearRouting.invalidate(game.map)

## Put a unit of the given frame on a tile. Used for both tears and bend proxies.
func _place_frame(frame_path:String, tile:Vector2i, owner_unit:Unit = null) -> Unit:
	var placed := SpecFactory.create_unit(game.map, tile)
	placed.core.frame = load(frame_path)
	if Unit.is_valid(owner_unit): placed.state.set_owner(owner_unit)
	placed.update_cached_values_and_token(SpecFactory.dummy_event())
	TearRouting.invalidate(game.map)
	return placed

func test_a_tear_is_recognised_as_a_tear():
	var tear := _place_frame(TEAR_FRAME, Vector2i(5,1))
	assert_true(TearRouting.is_tear(tear), 'A dep_tear_banshee is a tear.')
	assert_false(TearRouting.is_bend_proxy(tear), 'A tear is not a bend proxy.')

func test_a_bend_proxy_is_recognised_as_a_bend_proxy():
	var proxy := _place_frame(PROXY_FRAME, Vector2i(5,1), banshee)
	assert_true(TearRouting.is_bend_proxy(proxy), 'A dep_bend_proxy_banshee is a bend proxy.')
	assert_false(TearRouting.is_tear(proxy), 'A bend proxy is not a tear.')

func test_an_ordinary_unit_is_neither():
	assert_false(TearRouting.is_tear(banshee), 'A mech is not a tear.')
	assert_false(TearRouting.is_bend_proxy(banshee), 'A mech is not a bend proxy.')

func test_effective_tangibility_of_an_ordinary_unit_is_its_own():
	assert_false(TearRouting.effective_tangibility(banshee), 'A tangible mech reads tangible.')
	SpecFactory.apply(banshee, Lancer.STATUS.INTANGIBLE)
	assert_true(TearRouting.effective_tangibility(banshee), 'An INTANGIBLE mech reads intangible.')

func test_a_bend_proxy_reads_its_owners_tangibility():
	# THE RULE. The proxy itself never carries the status - create_targeting_proxy spawns a unit with
	# none - so reading has_status off it directly would make every bend look tangible.
	SpecFactory.apply(banshee, Lancer.STATUS.INTANGIBLE)
	var proxy := _place_frame(PROXY_FRAME, Vector2i(5,1), banshee)
	assert_false(proxy.has_status(Lancer.STATUS.INTANGIBLE), 'The proxy really has no status of its own.')
	assert_true(TearRouting.effective_tangibility(proxy), 'But it reads through to its INTANGIBLE owner.')

func test_a_bend_proxy_owned_by_tangible_unit_reads_as_tangible():
	# Bug catching test: an implementation that ignored the owner and just returned true for any bend
	# proxy would pass the existing suite, since it only tested intangible owners. This test ensures
	# the owner's tangibility is actually consulted.
	var proxy := _place_frame(PROXY_FRAME, Vector2i(5,1), banshee)
	assert_false(proxy.has_status(Lancer.STATUS.INTANGIBLE), 'The proxy has no status of its own.')
	assert_false(TearRouting.effective_tangibility(proxy), 'It reads through to its tangible owner.')

func test_a_bend_proxy_with_no_owner_reads_its_own_status():
	# The fallback is intentional: effective_tangibility reads the owner if one exists, and falls back
	# to the unit itself if not. This test pins the fallback as deliberate.
	var proxy := _place_frame(PROXY_FRAME, Vector2i(5,1))
	assert_false(proxy.has_status(Lancer.STATUS.INTANGIBLE), 'A freshly-placed proxy has no status.')
	assert_false(TearRouting.effective_tangibility(proxy), 'Without an owner, it reads its own status.')

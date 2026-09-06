# To Bend Reality. Asserts the RULES, not the mechanism - so a later re-implementation can be checked
# against the same tests. See D:\DEV\lancer-tactics-claude\specs\2026-09-06-banshee-to-bend-reality-design.md
extends GutTest

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')
const TEAR_FRAME := 'res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/dep_tear_banshee.tres'
const PROXY_FRAME := 'res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/mt_to_bend_reality/dep_bend_proxy_banshee.tres'

## The Kraken's Tide, per test_the_all_consuming_tide.gd. Applying it directly is the house pattern
## for a unit standing in for "a Kraken with the Tide up" - counts_as_every_tangibility keys off this
## buff alone, not off the Kraken frame, so it needs no Kraken to test.
const TIDE_BUFF_ID := &'buff_the_all_consuming_tide'

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

func test_a_bend_reaches_an_intangible_target_when_the_banshee_is_intangible():
	# THE CALENDULA CASE. Both parties INTANGIBLE - which happens when a Calendula has execrated the
	# target, or Weighing of Inequitable Hearts has caught it. The proxy carries no status, so
	# vanilla can_affect sees tangible-vs-intangible and refuses; effective tangibility rescues it.
	SpecFactory.apply(banshee, Lancer.STATUS.INTANGIBLE)
	SpecFactory.apply(target, Lancer.STATUS.INTANGIBLE)
	var proxy := _place_frame(PROXY_FRAME, Vector2i(5,1), banshee)
	assert_true(UnitRelation.can_affect(proxy, target),
		'An INTANGIBLE Banshee bends at an INTANGIBLE target.')

func test_a_bend_cannot_cross_the_tangibility_line_outward():
	# THE MODE SWITCH. "Instead of changing an attack's tangibility" - a bend never crosses the line.
	# Vanilla can_affect ALLOWS this pair (tangible proxy, tangible target), so only the early
	# refusal can stop it. Without it, a bend would be a strictly better tear window: no INVISIBLE
	# check and no half-range cap.
	SpecFactory.apply(banshee, Lancer.STATUS.INTANGIBLE)
	var proxy := _place_frame(PROXY_FRAME, Vector2i(5,1), banshee)
	assert_false(UnitRelation.can_affect(proxy, target),
		'An INTANGIBLE Banshee cannot bend at a tangible target.')

func test_a_bend_cannot_cross_the_tangibility_line_inward():
	SpecFactory.apply(target, Lancer.STATUS.INTANGIBLE)
	var proxy := _place_frame(PROXY_FRAME, Vector2i(5,1), banshee)
	assert_false(UnitRelation.can_affect(proxy, target),
		'A tangible Banshee cannot bend at an INTANGIBLE target - that is what the window is for.')

func test_a_bend_between_two_tangible_parties_is_ordinary():
	var proxy := _place_frame(PROXY_FRAME, Vector2i(5,1), banshee)
	assert_true(UnitRelation.can_affect(proxy, target),
		'Tangible Banshee, tangible target: nothing special, and nothing broken.')

func test_a_bend_reaches_a_kraken_with_the_tide_up_even_though_it_reads_tangible():
	# THE COMPOSITION CASE. TearRouting.effective_tangibility knows nothing about the Tide - it
	# compares raw INTANGIBLE status, and the Tide never touches the Kraken's real status (see the
	# tangibility workaround banner in unit_relation.gd_ext.gd). So an INTANGIBLE Banshee's proxy
	# reads intangible while a Tide-raised Kraken still reads tangible: exactly the mismatch the mode
	# switch above exists to refuse, unless the refusal is exempted for a party that counts as every
	# tangibility.
	#
	# The SAME Banshee attacking the SAME Kraken DIRECTLY, with no proxy at all, already succeeds -
	# super refuses on the identical raw mismatch, and counts_as_every_tangibility bridges it in the
	# widened branch (test_the_kraken_can_reach_an_intangible_character,
	# test_the_all_consuming_tide.gd). Routing the identical interaction through a bend must not flip
	# the answer: a Kraken with the Tide up counts as every tangibility, so it matches whatever the far
	# end of the bend is, proxy included.
	SpecFactory.apply(banshee, Lancer.STATUS.INTANGIBLE)
	var proxy := _place_frame(PROXY_FRAME, Vector2i(5,1), banshee)
	SpecFactory.apply_buff(target, TIDE_BUFF_ID)
	assert_true(UnitRelation.can_affect(proxy, target),
		'An INTANGIBLE Banshee bends at a Kraken with the Tide up, same as a direct attack would.')

func test_a_bend_inside_the_combined_range_is_allowed():
	# banshee (1,1) -> tear (5,1) is 4; tear -> target (10,1) is 5. Total 9 <= 10.
	_place_frame(TEAR_FRAME, Vector2i(5,1))
	assert_true(TearRouting.bends_within_range(game.map, Vector2i(1,1), Vector2i(10,1), 1, 10),
		'A bend whose two legs sum to within the weapon range is allowed.')

func test_a_bend_over_the_combined_range_is_refused():
	# banshee (1,1) -> tear (5,1) is 4; tear -> target (10,1) is 5. Total 9 > 8.
	_place_frame(TEAR_FRAME, Vector2i(5,1))
	assert_false(TearRouting.bends_within_range(game.map, Vector2i(1,1), Vector2i(10,1), 1, 8),
		'The combined distance must be within the weapon range.')

func test_a_bend_is_not_capped_at_half_range_after_the_tear():
	# THE DIFFERENCE FROM CLAUSE 7, asserted directly so the two rules cannot drift together.
	# banshee (1,1) -> tear (2,1) is 1; tear -> target (10,1) is 8. Total 9 <= 10, but 8 is well over
	# half of 10 - which routes_within_range refuses and bends_within_range must not.
	_place_frame(TEAR_FRAME, Vector2i(2,1))
	assert_false(TearRouting.routes_within_range(game.map, Vector2i(1,1), Vector2i(10,1), 1, 10),
		'The tear window still caps its post-tear leg at half range.')
	assert_true(TearRouting.bends_within_range(game.map, Vector2i(1,1), Vector2i(10,1), 1, 10),
		'A bend does not - clause 7 does not carry over.')

func test_no_tear_means_no_bend():
	assert_false(TearRouting.bends_within_range(game.map, Vector2i(1,1), Vector2i(3,1), 1, 10),
		'With no tear open nothing bends, whatever the range.')

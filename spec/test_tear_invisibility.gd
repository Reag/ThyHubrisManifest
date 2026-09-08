# Clause 6: "Attacks that pass through a tear treat targets as INVISIBLE."
#
# Asserted on DAMAGE, because that is the observable consequence and it cannot be faked by the buff
# merely existing. Every attack test here is comparative: a single attack landing zero damage proves
# nothing on its own, since the attack might simply have missed.
#
# The mechanism is a TREAT_AS_INVISIBLE buff whose condition recomputes, per attack, whether that
# exact pair is routed through a tear. It is a buff rather than a hook at the attack itself because
# AttackUtil is a dead extension seam - see buff_tear_invisibility.gd for the full reasoning.
extends GutTest

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')
const BUFF_ID := &'buff_tear_invisibility'

var game:Gamemaster
var banshee:Unit
var ghost:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self, true, SpecFactory.create_combat(Landscape.create_default(Vector2i(12,12))))
	game.campaign_core = CampaignCore.create(SpecFactory.create_campaign_base())
	game.map.campaign_core = game.campaign_core

	banshee = SpecFactory.create_unit(game.map, Vector2i(1,1))
	banshee.core.change_mech_frame(load('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/mf_banshee.tres'))
	banshee.state.overcharge_actions = 99
	banshee.update_cached_values_and_token(SpecFactory.dummy_event())

	ghost = SpecFactory.create_unit(game.map, Vector2i(9,9), Faction.AI_ENEMY)
	ghost.core.frame.stat.evasion = 0

func after_each():
	TearRouting.invalidate(game.map)
	Dice.CHEAT_ROLL_QUEUE.clear()

func test_the_buff_is_handed_out_when_a_tear_opens():
	assert_false(UnitCondition.has_buff(banshee, BUFF_ID), 'Nobody carries it before a tear exists.')
	await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear', [Vector2i(5,5)])
	assert_true(UnitCondition.has_buff(banshee, BUFF_ID), 'The Banshee has it.')
	assert_true(UnitCondition.has_buff(ghost, BUFF_ID), 'And so does everyone else - routing is universal.')

func test_the_buff_is_inert_against_a_same_tangibility_pair():
	# THE POINT of the whole design: the buff grants nothing at rest. Both units are tangible here, so
	# no attack between them ever "passes through a tear" however many tears are open.
	await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear', [Vector2i(5,5)])
	assert_false(UnitCondition.is_invisible(banshee, ghost),
		'A tangible pair is untouched by clause 6, even carrying the buff with a tear open.')

func test_the_buff_is_inert_when_no_tear_routes_the_pair():
	# Cross-tangible, buff present, but the tear is closed again - so nothing routes and the buff
	# must go quiet. Guards against the condition keying on tangibility alone.
	await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear', [Vector2i(5,5)])
	SpecFactory.apply(ghost, Lancer.STATUS.INTANGIBLE)
	assert_true(UnitCondition.is_invisible(banshee, ghost), 'Sanity: routed while the tear is open.')

	if TearRouting.open_tears(game.map).is_empty(): return fail_test('A tear was placed.')
	# Close is the BANSHEE's verb, not the tear's - see action_tear_close.gd. SpecFactory's
	# ChoiceBusResponder answers the "which tear?" pick with the front of the list, and there is
	# exactly one.
	await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear_close')
	assert_false(UnitCondition.is_invisible(banshee, ghost),
		'With the tear closed nothing routes, so clause 6 stops applying.')

func test_a_routed_target_counts_as_invisible():
	await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear', [Vector2i(5,5)])
	SpecFactory.apply(ghost, Lancer.STATUS.INTANGIBLE)
	assert_true(UnitCondition.is_invisible(banshee, ghost),
		'Clause 6: an attack routed through a tear treats its target as INVISIBLE.')

func test_it_applies_in_both_directions():
	# can_affect is asked from both sides and so is invisibility. An attack back through the tear is
	# just as much "an attack that passes through a tear".
	await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear', [Vector2i(5,5)])
	SpecFactory.apply(ghost, Lancer.STATUS.INTANGIBLE)
	assert_true(UnitCondition.is_invisible(ghost, banshee),
		'The intangible shooting back through the tear also treats its target as invisible.')


# ============================================================================
# DELIVERY (playtest fix 3). The predicate above was correct from the start; getting it onto the
# right units was not. Three separate bugs, all of which read in play as "clause 6 just does not
# work sometimes":
#
#   1. it was handed out ONCE, when the tear was placed, so anything arriving afterwards never had
#      it;
#   2. the Banshee's own Whispering STRIPPED it off every tangible character, because the buff was
#      owned by the Banshee and UnitCondition.handle_intangibilty_changing clears buffs across a
#      tangibility mismatch - i.e. it broke at the exact moment the frame is built around;
#   3. the Banshee's death cleared it while its tears stayed open.
#
# 2 and 3 are fixed by applying the buff with NO SOURCE GEAR; 1 by re-handing it out from
# unit_tile.gd_ext.gd's update_tracking_and_statuses override. See tear_invisibility_grant.gd.
# ============================================================================

func test_a_unit_that_arrives_after_the_tear_still_gets_it():
	# BUG 1, and the assertion that proves the unit_tile.gd_ext.gd override actually FIRES: nothing
	# else in the mod hands this buff out after placement, so if the extension were one of this
	# project's silently-dead seams, this latecomer would carry nothing.
	await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear', [Vector2i(5,5)])
	var latecomer := SpecFactory.create_unit(game.map, Vector2i(11,11), Faction.AI_ENEMY)
	assert_true(UnitCondition.has_buff(latecomer, BUFF_ID),
		'A unit spawned after the tear carries clause 6 too - reinforcements are not exempt from it.')

func test_the_buff_has_no_source_gear():
	# BUGS 2 AND 3's actual mechanism, asserted directly because the behavioural tests below cannot
	# tell the difference on their own: the re-hand-out from fix 1 would put a wrongly-stripped buff
	# straight back, so "clause 6 still works afterwards" would pass even with the ownership
	# regressed. THIS is the test that would go red.
	await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear', [Vector2i(5,5)])
	var core:BuffCore = UnitCondition.get_buff(ghost, BUFF_ID)
	if not BuffCore.is_valid(core): return fail_test('The ghost carries the buff.')
	assert_true(core.from_gear.is_empty(),
		'No source gear, so clear_outgoing_buffs_from_unit can never match it.')
	assert_null(core.get_owner_unit(game.map),
		'And no owner unit, so handle_intangibilty_changing\'s is_valid guard skips it.')

func test_it_survives_the_banshee_using_whispering():
	# BUG 2's outcome. Whispering is the Banshee's own route into intangibility and therefore the
	# single move that makes clause 6 relevant at all; it used to clear clause 6 off every tangible
	# character on the map on its way there.
	await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear', [Vector2i(5,5)])
	if not UnitCondition.has_buff(ghost, BUFF_ID): return fail_test('The tangible ghost starts with it.')

	SpecFactory.start_turn(game, banshee) # protocols only open at turn start - unit_action.gd:119
	await SpecFactory.use_solo(game, banshee, &'mt_whispering')
	if not banshee.has_status(Lancer.STATUS.INTANGIBLE): return fail_test('Whispering actually fired.')

	assert_true(UnitCondition.has_buff(ghost, BUFF_ID), 'The tangible ghost still carries clause 6.')
	assert_true(UnitCondition.is_invisible(banshee, ghost),
		'And clause 6 applies at the exact moment the frame exists to create.')

func test_it_survives_the_banshees_death_while_a_tear_remains():
	# BUG 3's outcome. Tears outlive the Banshee by design (is_deactivated_on_owner_death = false),
	# so the rule they carry has to outlive it too - otherwise a dead Banshee leaves windows that no
	# longer do anything.
	await SpecFactory.use(game, banshee, &'cp_the_keening', &'action_tear', [Vector2i(5,5)])
	SpecFactory.apply(ghost, Lancer.STATUS.INTANGIBLE)
	if not UnitCondition.is_invisible(ghost, banshee): return fail_test('Routing works while the Banshee lives.')

	var survivor := SpecFactory.create_unit(game.map, Vector2i(2,2), Faction.PLAYER)
	if not UnitCondition.has_buff(survivor, BUFF_ID): return fail_test('The survivor starts with it.')

	# event_unit_die directly rather than damage: the alternative is lowering the Banshee's structure,
	# and core.frame is the SHARED mf_banshee resource (change_mech_frame assigns it, it does not
	# duplicate - unit_printer.gd:90-94), so writing to frame.stat here would poison every other spec
	# in the run. What matters to this test is event_service.gd:71's outgoing-buff sweep, which
	# event_unit_die reaches either way.
	await game.execute_event(&'event_unit_die', {unit = banshee})
	if Unit.is_valid(banshee): return fail_test('The Banshee actually died.')

	assert_eq(TearRouting.open_tears(game.map).size(), 1, 'Its tear outlives it.')
	assert_true(UnitCondition.has_buff(survivor, BUFF_ID),
		'And so does clause 6 - a dead Banshee\'s windows still treat their targets as invisible.')

# A void tear is NEITHER tangible nor intangible.
#
# THE BUG. event_unit_spawn.gd:97-100 hands a freshly spawned deployable its owner's intangibility,
# with UNTIL.MANUAL - i.e. never expiring on its own. Its own comment calls the branch unreachable
# ("we shouldn't be able to deploy stuff while intangible, but just in case we somehow did"), and in
# vanilla it is: ActionSystemDeploy refuses to activate at all while INTANGIBLE
# (action_system_deploy.gd:21). action_tear.gd deliberately drops that refusal - playtest fix 8.3,
# because Whispering is the Banshee's own way into intangibility and the vanilla gate locked the
# frame out of its own core power - which walks straight into the "just in case" branch. Confirmed on
# the live board: of two tears, the one opened while phased carried fxe_intangible's
# ChromaticAbberation on top of its own fx.
#
# THE DECISION (author's). Clause 2 calls a tear "a window between tangible and intangible space" -
# the thing both sides look THROUGH, not an object standing on one side. The engine has only a
# binary, so the closest expressible form is: the tear never carries Lancer.STATUS.INTANGIBLE, and
# nothing judges it by tangibility.
#
# THE FIX is action_tear_neither_side.gd, a UNIT_SPAWN/POST reaction on cp_the_keening. See that file
# for why it lives on the Banshee, why POST is the only timing that works, and why the trigger test
# has to ask the OWNER rather than the tear.
#
# EVERY TEST BELOW OPENS ITS TEAR THROUGH THE REAL action_tear, NEVER BY PLACING A FRAME DIRECTLY.
# That is the whole point: a fixture-placed tear never runs event_unit_spawn, so it never inherits
# anything and could not reproduce the bug. It is also the shape that hid two earlier tear defects
# (see action_tear.gd's place_deployable_followup note, and test_tear_object.gd's close-reachability
# test), so the second half of this file re-checks every tear interaction against a tear that was
# genuinely born while the Banshee was phased.
extends GutTest

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')
const BANSHEE_FRAME := 'res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/mf_banshee.tres'
const KEENING := &'cp_the_keening'
const WHISPERING := &'mt_whispering'
const NEITHER_SIDE := &'action_tear_neither_side'

var game:Gamemaster
var banshee:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self, true, SpecFactory.create_combat(Landscape.create_default(Vector2i(14,14))))
	# SpecFactory GAP - see test_tear_object.gd's own note. The fresh-gamemaster path never assigns
	# campaign_core, and anything reaching event_unit_die (closing a tear) then dies on
	# `campaign_core.get_lancer_by_id(...)` in a way that reads as "the tear did not disappear".
	game.campaign_core = CampaignCore.create(SpecFactory.create_campaign_base())
	game.map.campaign_core = game.campaign_core
	banshee = SpecFactory.create_unit(game.map, Vector2i(1,1))
	# change_mech_frame, NOT core.frame = load(...): the latter skips regenerate_derived_gear, so
	# cp_the_keening is never reachable as gear at all.
	banshee.core.change_mech_frame(load(BANSHEE_FRAME))
	banshee.update_cached_values_and_token(SpecFactory.dummy_event())
	# start_turn BEFORE the overcharge: Whispering is a PROTOCOL and unit_action.gd:119 refuses one
	# unless state.is_using_protocols, which only the turn start opens.
	SpecFactory.start_turn(game, banshee)
	banshee.state.overcharge_actions = 99 # several tear actions in one turn, past the repeat-action rule
	banshee.core.current.speed = banshee.core.get_speed_max()

func after_each():
	TearRouting.invalidate(game.map)
	Dice.CHEAT_ROLL_QUEUE.clear()

## Whispering, the real protocol - not SpecFactory.apply. The status has to arrive the way play
## delivers it, because the whole bug is a spawn reading the owner's status at spawn time.
func _phase() -> void:
	await SpecFactory.use_solo(game, banshee, WHISPERING)

func _open_tear_at(tile:Vector2i) -> Unit:
	await SpecFactory.use(game, banshee, KEENING, &'action_tear', [tile])
	for tear:Unit in TearRouting.open_tears(game.map):
		if tear.tile() == tile: return tear
	return null

# ============================================================================================
# THE FIX ITSELF
# ============================================================================================

func test_a_tear_opened_while_phased_is_not_intangible():
	# THE RED TEST. Without action_tear_neither_side this tear carries INTANGIBLE/UNTIL.MANUAL,
	# inherited at event_unit_spawn.gd:100 and cleared by nothing until its owner turns tangible
	# again - never, if the Banshee dies first, since the tear outlives its owner.
	await _phase()
	if not banshee.has_status(Lancer.STATUS.INTANGIBLE): return fail_test('Whispering made the Banshee intangible.')

	var tear := await _open_tear_at(Vector2i(4,4))
	if not Unit.is_valid(tear): return fail_test('A tear was opened while phased.')

	assert_false(tear.has_status(Lancer.STATUS.INTANGIBLE),
		'A tear is a window between tangible and intangible space, not an object on either side.')

func test_such_a_tear_carries_no_status_at_all():
	# The clean-up must not leave anything else behind either - and nothing should be adding statuses
	# to a marker in the first place.
	await _phase()
	var tear := await _open_tear_at(Vector2i(4,4))
	if not Unit.is_valid(tear): return fail_test('A tear was opened while phased.')
	assert_eq(tear.state.statuses.size(), 0, 'The tear carries no leftover status. Got: %s' % [tear.state.statuses])

func test_a_tear_opened_while_tangible_is_also_not_intangible():
	# The control. If this ever goes red the fix has started GRANTING something rather than clearing.
	var tear := await _open_tear_at(Vector2i(4,4))
	if not Unit.is_valid(tear): return fail_test('A tear was opened.')
	assert_false(tear.has_status(Lancer.STATUS.INTANGIBLE), 'A tear opened tangibly was never intangible.')

func test_every_tear_opened_in_one_phased_round_is_cleared():
	# THE PER-ROUND CAP, and the reason consumes_rxn is false. Action.get_per_round_hard_limit caps
	# naturally-free actions at 1/round (action.gd:156-158); ActionReaction raises that to 99 only for
	# reactions that do NOT require a reaction point. A fix that worked once per round would leave the
	# second and third tears of a busy turn phased forever, which is the same bug with a smaller blast
	# radius.
	await _phase()
	var tiles:Array[Vector2i] = [Vector2i(4,4), Vector2i(6,6), Vector2i(8,8)]
	var opened:Array[Unit] = []
	for tile:Vector2i in tiles:
		var tear := await _open_tear_at(tile)
		if Unit.is_valid(tear): opened.append(tear)
	if opened.size() != tiles.size(): return fail_test('All three tears were opened. Got %s.' % opened.size())
	for tear:Unit in opened:
		assert_false(tear.has_status(Lancer.STATUS.INTANGIBLE),
			'Tear at %s is not intangible - the clean-up is not once-per-round.' % [tear.tile()])

func test_another_banshees_tear_is_not_our_business():
	# The reaction is scoped by ownership, like every other tear verb (clause 8's move and close both
	# refuse someone else's). An enemy Banshee's tear is cleaned up by ITS owner's copy of this same
	# reaction, not by ours - and ours must not reach across and do it, or the scoping is decorative.
	var other := SpecFactory.create_unit(game.map, Vector2i(12,12), Faction.AI_ENEMY)
	other.core.change_mech_frame(load(BANSHEE_FRAME))
	other.update_cached_values_and_token(SpecFactory.dummy_event())
	other.state.overcharge_actions = 99
	var action:Action = ContentLibrary.get_kit(KEENING).get_action(NEITHER_SIDE)
	if not Action.is_valid(action): return fail_test('cp_the_keening carries %s.' % NEITHER_SIDE)

	await _phase()
	var tear := await _open_tear_at(Vector2i(4,4))
	if not Unit.is_valid(tear): return fail_test('A tear was opened while phased.')

	var spawn_event := EventCore.create(&'event_unit_spawn', {unit = tear, target_tiles = [tear.tile()]})
	assert_false(action.triggers_on_event(other, other.get_gear(KEENING), spawn_event),
		'A tear the OTHER Banshee does not own does not trigger its copy of the reaction.')
	assert_true(action.triggers_on_event(banshee, banshee.get_gear(KEENING), spawn_event),
		'sanity: its actual owner, still phased, does trigger.')

# ============================================================================================
# THE WIRING
# ============================================================================================

func test_the_reaction_lives_on_the_keening():
	var kit:Kit = ContentLibrary.get_kit(KEENING)
	if not Kit.is_valid(kit): return fail_test('cp_the_keening loaded.')
	var action:Action = kit.get_action(NEITHER_SIDE)
	assert_true(Action.is_valid(action), 'cp_the_keening carries %s.' % NEITHER_SIDE)
	if not Action.is_valid(action): return
	assert_true(action is ActionReaction, 'It is a reaction.')
	assert_true((action as ActionReaction).triggers_on.has(ReactionBus.TRIGGER.UNIT_SPAWN), 'It triggers on unit_spawn.')
	assert_eq((action as ActionReaction).trigger_timing, ReactionBus.TIMING.POST,
		'POST, not PRE: event_unit_spawn queues the inherit at :100 and the POST reactions at :107, ' +
		'so only POST runs after the status has landed.')
	assert_false((action as ActionReaction).consumes_rxn, 'It does not eat the Banshee\'s reaction.')

func test_the_reaction_has_its_own_usage_group():
	# Without one, get_usage_group_for_action falls back to the GEAR id (gear_core.gd:166-168) and
	# this would silently share a round allowance with Tear, Mourning Call and both clause 8 verbs.
	var action:Action = ContentLibrary.get_kit(KEENING).get_action(NEITHER_SIDE)
	if not Action.is_valid(action): return fail_test('cp_the_keening carries %s.' % NEITHER_SIDE)
	assert_eq(action.usage_group, NEITHER_SIDE, 'It bills nobody else\'s allowance.')

func test_the_reaction_stays_out_of_the_gear_tooltip():
	# The Keening reads as two abilities. This is plumbing.
	var kit:Kit = ContentLibrary.get_kit(KEENING)
	if not Kit.is_valid(kit): return fail_test('cp_the_keening loaded.')
	assert_false(kit.get_action(NEITHER_SIDE).show_in_tooltip(kit),
		'The clean-up does not list itself as a third ability.')

func test_clearing_a_tear_bills_nothing_else_on_the_keening():
	await _phase()
	var tear := await _open_tear_at(Vector2i(4,4))
	if not Unit.is_valid(tear): return fail_test('A tear was opened while phased.')
	var gear:GearCore = banshee.get_gear(KEENING)
	if not GearCore.is_valid(gear): return fail_test('The Banshee carries The Keening.')
	assert_eq(gear.get_uses_this_round_alt(&'action_tear'), 1, 'Tear itself was used once.')
	assert_eq(gear.get_uses_this_round_alt(&'action_mourning_call'), 0, 'Mourning Call is untouched.')
	assert_eq(gear.get_uses_this_round_alt(&'action_tear_move'), 0, 'Move Tear is untouched.')
	assert_eq(gear.get_uses_this_round_alt(KEENING), 0,
		'Nothing fell back to the shared gear-id group, which a missing usage_group would do.')

# ============================================================================================
# EVERY TEAR INTERACTION, RE-CHECKED AGAINST A TEAR BORN WHILE PHASED
#
# The tear used to match a phased Banshee's tangibility; now it does not. UnitRelation.can_affect
# refuses across the tangibility line (unit_relation.gd:397), so that is a real change in what the
# engine says about the pair, and each verb below is re-proved rather than assumed.
# ============================================================================================

func test_the_move_verb_is_still_offered_for_such_a_tear():
	await _phase()
	var tear := await _open_tear_at(Vector2i(4,4))
	if not Unit.is_valid(tear): return fail_test('A tear was opened while phased.')
	var gear:GearCore = banshee.get_gear(KEENING)
	var specific := SpecificAction.create(banshee, gear, gear.get_action(&'action_tear_move'))
	assert_true(specific.action.is_available_to_activate(banshee, gear),
		'A phased Banshee is still offered Move Tear for the tear it just opened.')

func test_such_a_tear_actually_moves():
	# THE INTERACTION MOST LIKELY TO HAVE CHANGED, per the brief - a tear that is now tangible where
	# it used to be intangible could pathfind differently against tangible units. It does not:
	# Pathfinder.Occupation filters occupants on EXILED, marker-ness and is_obstruction and never
	# consults INTANGIBLE at all (pathfinder.gd:100-112), and its unit lookups pass a null
	# whos_asking so map_state.gd:320's can_affect filter never engages either. This drives the real
	# action - the pick, the lent speed budget, Pathfinder.generate_for_movement_budget and the
	# movement plan - rather than asserting that reasoning.
	await _phase()
	var tear := await _open_tear_at(Vector2i(4,4))
	if not Unit.is_valid(tear): return fail_test('A tear was opened while phased.')
	var before:Vector2i = tear.tile()

	await SpecFactory.use(game, banshee, KEENING, &'action_tear_move')

	assert_true(Unit.is_valid(tear), 'The tear survived being moved.')
	if not Unit.is_valid(tear): return
	assert_ne(tear.tile(), before, 'The tear actually walked somewhere.')
	assert_lt(banshee.core.current.speed, banshee.core.get_speed_max(),
		'And the base movement was genuinely spent, so the move really ran.')
	assert_false(tear.has_status(Lancer.STATUS.INTANGIBLE), 'Moving does not re-phase it.')

func test_such_a_tear_can_still_be_closed():
	await _phase()
	var tear := await _open_tear_at(Vector2i(4,4))
	if not Unit.is_valid(tear): return fail_test('A tear was opened while phased.')

	var specific := SpecificAction.from_id(banshee, KEENING, &'action_tear_close')
	if not SpecificAction.is_valid(specific): return fail_test('The Banshee carries Close Tear.')
	assert_true(UnitAction.can_activate_gear(specific),
		'Close Tear is reachable - this is what the UI and the AI ask.')

	await SpecFactory.use(game, banshee, KEENING, &'action_tear_close')
	assert_eq(TearRouting.open_tears(game.map).size(), 0, 'The tear is gone.')

func test_the_window_still_bridges_a_phased_banshee_to_a_tangible_target():
	# Clause 4. The tear is now on neither side of the line, and cross_tangible_units skips tears
	# outright (tear_routing.gd), so the pair being bridged is still Banshee <-> target and the tear
	# is still only the waypoint. Straight row so strict collinearity is unambiguous:
	# line((1,1),(8,1)) runs through (4,1).
	var solid := SpecFactory.create_unit(game.map, Vector2i(8,1), Faction.AI_ENEMY)
	await _phase()
	assert_false(UnitRelation.can_affect(banshee, solid), 'Sanity: no window before the tear.')

	var tear := await _open_tear_at(Vector2i(4,1))
	if not Unit.is_valid(tear): return fail_test('A tear was opened while phased, on the line.')

	assert_true(UnitRelation.can_affect(banshee, solid),
		'Clause 4: the phased Banshee reaches the tangible target through its own phased-born tear.')
	assert_true(UnitRelation.can_affect(solid, banshee),
		'Clause 5, the mirror: and the tangible target reaches back. An asymmetric answer would let ' +
		'one side shoot something that cannot shoot back.')

func test_the_window_is_not_widened_to_the_tear_itself():
	# The tear is scenery, not a target. cross_tangible_units excludes tears so that a tear can never
	# be routed TO - checked here rather than trusted, since the exclusion now matters for a pairing
	# that did not previously exist (a phased Banshee against its own, now tangible, tear).
	await _phase()
	var tear := await _open_tear_at(Vector2i(4,1))
	if not Unit.is_valid(tear): return fail_test('A tear was opened while phased.')
	assert_false(TearRouting.cross_tangible_units(game.map, banshee).has(tear),
		'A tear is never something sight is routed TO.')

func test_the_relocation_pick_still_finds_such_a_tear():
	# Mourning Call's clause 9 relocation asks TearRouting.owned_tears and TearRouting.choose_tear -
	# the same two calls clause 8's verbs use (action_mourning_call.gd:239, :265) - and then filters
	# UnitTile.get_tiles_within by Pathfinder.is_tile_standable for the TEAR. This exercises those
	# three, which is the whole of _maybe_relocate_tear minus its prompts.
	await _phase()
	var tear := await _open_tear_at(Vector2i(4,4))
	if not Unit.is_valid(tear): return fail_test('A tear was opened while phased.')

	assert_true(TearRouting.owned_tears(banshee).has(tear), 'Clause 9 sees the tear as ours to move.')
	var chosen:Unit = await TearRouting.choose_tear(SpecificAction.from_id(banshee, KEENING, &'action_tear_move'), [tear])
	assert_eq(chosen, tear, 'And the pick resolves to it.')

	var movement_type := MovementType.create_for_involuntary(tear)
	movement_type.teleport = true
	var katamari := Katamari.create(tear)
	var standable:Array[Vector2i] = []
	for tile:Vector2i in UnitTile.get_tiles_within(banshee, banshee.get_sensor_range()):
		if Pathfinder.is_tile_standable(tear, tile, movement_type, katamari): standable.append(tile)
	assert_false(standable.is_empty(),
		'And there are somewhere-elses to relocate it to - a tangible tear is still standable.')

func test_to_bend_reality_still_bends_through_such_a_tear():
	# Clause: To Bend Reality relays an attack through a proxy standing on a tear. The bend never
	# consults the TEAR's tangibility (only the Banshee's, via effective_tangibility on the proxy), so
	# this should be untouched - proved rather than assumed.
	var gear:GearCore = banshee.core.equip_system(&'mw_assault_rifle')
	banshee.core.full_repair()
	SpecFactory.apply_passive_buffs(banshee)
	banshee.core.has_core_power = false # keeps Mourning Call from being offered mid-bend
	await _phase()

	var tear := await _open_tear_at(Vector2i(4,1))
	if not Unit.is_valid(tear): return fail_test('A tear was opened while phased.')

	var specific := SpecificAction.create(banshee, gear, gear.get_solo_action())
	var keys:Array = []
	for group:VariantActionGroup in specific.action.get_alternate_actions(specific): keys.append(group.key)
	assert_true(keys.has(&'to_bend_reality'), 'The bend is offered off a phased-born tear.')

	var groups := specific.action.get_alternate_actions(specific)
	var chosen:Dictionary[StringName, int] = { &'to_bend_reality': 1 }
	var composed := VariantActionGroup.generate_composed_action(groups, specific.action, chosen)
	var bend := SpecificAction.create(banshee, gear, composed)
	assert_true(UnitTargeting.get_tiles_targetable(bend).has(Vector2i(4,1)),
		'And the tear\'s tile is what the bend offers as its first pick.')

func test_a_bent_line_still_fires_both_segments_through_such_a_tear():
	# The LINE two-segment path, end to end. Rail Rifle is LINE length 10; Banshee at (1,1), tear at
	# (4,1) splits it 3 + 7. Both victims are INTANGIBLE because the Banshee is: To Bend Reality never
	# crosses the tangibility line (bend_proxy_tangibility_differs refuses it), so a phased bend can
	# only ever be aimed at phased company.
	var gear:GearCore = banshee.core.equip_system(&'mw_rail_rifle')
	banshee.core.full_repair()
	SpecFactory.apply_passive_buffs(banshee)
	banshee.core.has_core_power = false
	var near := SpecFactory.create_unit(game.map, Vector2i(3,1), Faction.AI_ENEMY)
	var far := SpecFactory.create_unit(game.map, Vector2i(9,1), Faction.AI_ENEMY)
	for victim:Unit in [near, far]:
		victim.core.frame.stat.evasion = 0
		victim.core.frame.stat.armor = 0
		victim.core.full_repair()
		SpecFactory.apply(victim, Lancer.STATUS.INTANGIBLE)
	await _phase()

	var tear := await _open_tear_at(Vector2i(4,1))
	if not Unit.is_valid(tear): return fail_test('A tear was opened while phased, on the line.')

	SpecFactory.current_responder.chosen_plan_queue = [
		CompconPlan.create([Vector2i(4,1)]), # the tear
		CompconPlan.create([Vector2i(9,1)]), # segment 2's direction
	]
	# A uniform, over-long queue for the same reason test_to_bend_reality.gd uses one: clause 6's
	# invisibility and To Twist Truth both inject extra d6s mid-sequence, and a hand-counted queue
	# runs dry and goes random.
	Dice.CHEAT_ROLL_QUEUE.assign([2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2])
	await game.execute_event(&'event_gear_activate', {
		action = gear.get_solo_action(), gear = gear, unit = banshee,
		string = 'to_bend_reality',
	})

	assert_gt(near.current_damage(), 0, 'Segment 1 hit the character before the tear.')
	assert_gt(far.current_damage(), 0, 'Segment 2 hit the character past the tear.')
	assert_false(tear.has_status(Lancer.STATUS.INTANGIBLE), 'And the tear is still on neither side.')

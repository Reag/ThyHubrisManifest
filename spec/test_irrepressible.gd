# Irrepressible.
#
#   "If an effect would prevent the Kraken from taking a |reaction| (like |grapple|), it may take
#    |1 HEAT| to use a reaction anyway."
#
# Design notes live in D:\DEV\lancer-tactics-claude\specs\2026-09-02-kraken-design.md.
#
# Built entirely from vanilla buff keys, because the one case that needed an engine extension turned
# out not to be extensible - see test_a_jam_still_stops_its_reactions at the bottom.
#
#   Buff.TO.ACTION_PERMITTED_WHILE_GRAPPLING -> reactions and boosting while GRAPPLED
#
# That single key is the whole trait. The two jam-related halves both fell away on inspection:
# grappling while jammed already works for everyone (vanilla action_grapple.gd sets is_jammable to
# false), and reacting while jammed cannot be reached from a mod at all.
#
# The "must still be stopped" tests matter as much as the permissive ones: both keys are broad
# instruments, and a leak would quietly make the frame immune to things it should not be.
extends GutTest

const TRAIT_ID := &'mt_irrepressible'
const GRAPPLE_KIT := &'mw_grapple'
const OTHER_WEAPON := &'mw_assault_rifle'

var game:Gamemaster
var kraken:Unit
var plain:Unit ## a unit WITHOUT the trait, so every claim below is about the trait, not the engine

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	kraken = SpecFactory.create_unit(game.map, Vector2i(0, 0))
	kraken.core.equip_system(TRAIT_ID)
	plain = SpecFactory.create_unit(game.map, Vector2i(6, 6))
	SpecFactory.apply_passive_buffs(kraken)
	SpecFactory.apply_passive_buffs(plain)

## A context describing a REAL reaction - one that consumes the action economy, which is the only
## kind the gates actually stop. A reaction with consumes_rxn = false never reaches them at all
## (action_reaction.gd:49), which is why My Domain works while grappled without any of this.
func _reaction_context(unit:Unit) -> Context:
	var action := ActionReaction.new()
	action.consumes_rxn = true
	return Context.create({unit = unit, action = action})

func _specific(unit:Unit, gear:GearCore) -> SpecificAction:
	return SpecificAction.create(unit, gear, gear.get_solo_action())

# ============================== the permissions ==============================

func test_the_trait_grants_its_permissions():
	assert_true(UnitCondition.has_buff_to(kraken, Buff.TO.ACTION_PERMITTED_WHILE_GRAPPLING),
		'It may act while grappled.')

func test_a_unit_without_the_trait_has_none_of_them():
	# Guards every permissive test below against a vacuous pass.
	assert_false(UnitCondition.has_buff_to(plain, Buff.TO.ACTION_PERMITTED_WHILE_GRAPPLING),
		'A plain unit may not act while grappled.')

# ============================== held ==============================

func test_a_grapple_does_not_stop_its_reactions():
	SpecFactory.apply(kraken, Lancer.STATUS.GRAPPLED)
	assert_true(UnitAction.can_take_reactions(kraken, _reaction_context(kraken)),
		'Held, and still able to react.')

func test_a_grapple_stops_everyone_elses_reactions():
	SpecFactory.apply(plain, Lancer.STATUS.GRAPPLED)
	assert_false(UnitAction.can_take_reactions(plain, _reaction_context(plain)),
		'A plain unit held by a grapple cannot react.')

func test_a_grapple_does_not_stop_it_boosting():
	# The same key gates boosting, at unit_action.gd:505 - but only after an immobilisation check
	# that a grapple trips for whichever party is NOT the larger one. is_larger_in_grapple is set
	# here because that is the Kraken's normal case: Size 2 holding Size 1s.
	SpecFactory.apply(kraken, Lancer.STATUS.GRAPPLED)
	kraken.state.is_larger_in_grapple = true
	assert_false(UnitAction.is_boost_prohibited(kraken), 'Held, and still able to boost.')

func test_a_grapple_stops_everyone_elses_boosting():
	SpecFactory.apply(plain, Lancer.STATUS.GRAPPLED)
	plain.state.is_larger_in_grapple = true # same footing, so only the trait can explain a difference
	assert_true(UnitAction.is_boost_prohibited(plain), 'A plain held unit cannot boost.')

# ============================== jammed ==============================

func test_grappling_while_jammed_needs_no_trait_at_all():
	# Irrepressible was asked to allow grappling while jammed. It turns out nothing has to:
	# content/gear/basic/mw_grapple/action_grapple.gd overrides is_jammable() to false, so a jam
	# never applied to Grapple for anybody.
	#
	# Pinned with BOTH units, because the Kraken alone would pass this whether the reason were the
	# trait or the base game - which is exactly how an earlier version of this spec went green
	# against a buff that did nothing.
	var kraken_grapple := kraken.core.equip_system(GRAPPLE_KIT)
	var plain_grapple := plain.core.equip_system(GRAPPLE_KIT)
	if not (GearCore.is_valid(kraken_grapple) and GearCore.is_valid(plain_grapple)): return

	SpecFactory.apply(kraken, Lancer.STATUS.JAMMED)
	SpecFactory.apply(plain, Lancer.STATUS.JAMMED)
	assert_false(UnitAction.is_action_jammable(_specific(kraken, kraken_grapple)),
		'The Kraken may grapple while jammed.')
	assert_false(UnitAction.is_action_jammable(_specific(plain, plain_grapple)),
		'And so may anybody else - this is vanilla, not the trait.')

func test_jamming_still_applies_to_its_other_weapons():
	# The unjam is scoped to mw_grapple via BuffWeaponType.from_compcon_id. If it leaked, JAMMED
	# would stop meaning anything against this frame.
	var rifle := kraken.core.equip_system(OTHER_WEAPON)
	if not GearCore.is_valid(rifle): return

	SpecFactory.apply(kraken, Lancer.STATUS.JAMMED)
	assert_true(UnitAction.is_action_jammable(_specific(kraken, rifle)), 'Its rifle is still jammed.')

# ============================== what must STILL stop it ==============================

func test_it_still_cannot_react_with_no_reaction_left():
	SpecFactory.apply(kraken, Lancer.STATUS.GRAPPLED)
	kraken.core.current.reactions = 0
	assert_false(UnitAction.can_take_reactions(kraken, _reaction_context(kraken)),
		'A spent reaction is still spent.')

func test_an_unhindered_kraken_is_unaffected():
	assert_true(UnitAction.can_take_reactions(kraken, _reaction_context(kraken)),
		'A free Kraken reacts normally.')
	kraken.core.current.reactions = 0
	assert_false(UnitAction.can_take_reactions(kraken, _reaction_context(kraken)),
		'And is still bound by the ordinary rules.')

func test_a_jam_still_stops_its_reactions():
	# A KNOWN, ACCEPTED gap, pinned here rather than left implicit.
	#
	# JAMMED blocking a REACTION is the one bypass with no hook. can_take_reactions asks
	# context.action.is_jammable() directly (unit_action.gd:382), while the general action gate goes
	# through UnitAction.is_action_jammable (:142) - and only the latter honours IGNORE_JAMMED.
	#
	# A unit_action.gd_ext.gd was written to close it and DOES NOT WORK: ModLoader logs the
	# extension as installed, but no override on that file is ever invoked. Verified by print - an
	# override on unit_relation.gd next door fired 47 times in the same run while two separate
	# overrides on unit_action.gd fired zero. The likely difference is that unit_action.gd declares
	# static vars and unit_relation.gd does not.
	#
	# If a future modkit makes that file extensible, this test goes red and the rescue can go back in.
	SpecFactory.apply(kraken, Lancer.STATUS.JAMMED)
	assert_false(UnitAction.can_take_reactions(kraken, _reaction_context(kraken)),
		'Jamming still stops a real reaction, and the trait cannot currently help.')

# ============================== the heat ==============================
#
# These exercise the watcher's predicate rather than the heat event itself. What decides whether the
# Kraken is charged is "would this activation have been refused without the trait", and that is the
# part with room to be wrong; queueing the damage event afterwards is two lines of vanilla call.

func _watcher() -> Action:
	var kit:Kit = ContentLibrary.get_kit(TRAIT_ID)
	if not Kit.is_valid(kit) or kit.actions.is_empty(): return null
	return kit.actions[0]

func _activation_of(unit:Unit, action:Action, gear:GearCore = null) -> Context:
	return Context.create({unit = unit, action = action, gear = gear})

func test_it_charges_for_a_reaction_taken_while_held():
	var watcher := _watcher()
	if not Action.is_valid(watcher): return fail_test('The trait carries its watcher action.')

	SpecFactory.apply(kraken, Lancer.STATUS.GRAPPLED)
	var reaction := ActionReaction.new()
	reaction.consumes_rxn = true
	assert_true(watcher.was_rescued(kraken, _activation_of(kraken, reaction)),
		'A real reaction taken while held is charged for.')

func test_it_does_not_charge_when_nothing_was_blocking():
	# The whole point of charging on use: a Kraken that is neither held nor jammed pays nothing.
	var watcher := _watcher()
	if not Action.is_valid(watcher): return

	var reaction := ActionReaction.new()
	reaction.consumes_rxn = true
	assert_false(watcher.was_rescued(kraken, _activation_of(kraken, reaction)),
		'An unhindered reaction is free.')

func test_it_does_not_charge_for_something_a_grapple_never_stopped():
	# Held, but taking an ordinary action that a grapple does not prevent - no rescue, no heat.
	var watcher := _watcher()
	if not Action.is_valid(watcher): return

	SpecFactory.apply(kraken, Lancer.STATUS.GRAPPLED)
	var plain_reaction := ActionReaction.new()
	plain_reaction.consumes_rxn = false # the kind that was never gated in the first place
	assert_false(watcher.was_rescued(kraken, _activation_of(kraken, plain_reaction)),
		'A free-triggering reaction was never blocked, so costs nothing.')

func test_it_does_not_charge_for_grappling_while_jammed():
	# Because that was never blocked. Charging for it would be taxing the Kraken for something every
	# other mech does free.
	var watcher := _watcher()
	if not Action.is_valid(watcher): return
	var grapple_gear := kraken.core.equip_system(GRAPPLE_KIT)
	if not GearCore.is_valid(grapple_gear): return

	SpecFactory.apply(kraken, Lancer.STATUS.JAMMED)
	assert_false(
		watcher.was_rescued(kraken, _activation_of(kraken, grapple_gear.get_solo_action(), grapple_gear)),
		'No charge for something that was never stopped.')

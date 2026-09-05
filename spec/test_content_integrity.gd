# Content integrity for HORUS: Thy Hubris Manifest.
#
# The mod is early WIP, so this is deliberately about wiring rather than behaviour: is everything
# registered, under the right index, with localization to match. Behaviour specs belong beside
# each trait as it gets implemented.
extends GutTest

const ModContentAudit := preload('res://testkit/mod_content_audit.gd')
const PassiveEarthstep := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_nuckelavee/mt_earthstep/passive_earthstep.gd')

const MOD_ID := 'Reag-ThyHubris'

func test_the_mod_is_actually_loaded():
	assert_true(ModLoaderMod.is_mod_active(MOD_ID), '%s is loaded and active.' % MOD_ID)

func test_no_resource_is_filed_under_the_wrong_index():
	# ContentLibrary sorts by filename prefix, not script class. See mod_content_audit.gd.
	var problems := ModContentAudit.find_misfiled_resources(MOD_ID)
	for problem:String in problems: gut.p('  %s' % problem)
	assert_eq(problems.size(), 0, 'Every resource landed in the right ContentLibrary index.')

func test_infection_is_registered_as_a_buff():
	# This file was once named bt_infection.tres. "bt_" is a KIT prefix in vanilla
	# (bt_lock_hold_javelins_hornet.tres is a Kit), so the Buff was indexed as a Kit and
	# get_buff could never find it. Regression guard for the rename to buff_infection.tres.
	var buff:Buff = ContentLibrary.get_buff(&'buff_infection')
	assert_true(is_instance_valid(buff), 'buff_infection is in the buffs index.')
	assert_false(Kit.is_valid(ContentLibrary.get_kit(&'bt_infection')), 'It is no longer in the kits index.')

func test_draugr_frame_and_traits_are_registered():
	assert_true(is_instance_valid(ContentLibrary.get_mech_frame(&'mf_draugr')), 'mf_draugr is in the frames index.')
	for kit_id:StringName in [&'mt_raging_plague', &'mt_seeping_rot', &'mt_spreading_stain']:
		assert_true(Kit.is_valid(ContentLibrary.get_kit(kit_id)), '%s is in the kits index.' % kit_id)

# li_draugr is parked at D:\DEV\lancer-tactics-claude\parked\li_draugr.tres so the Draugr does not
# ship in the prototype. Its registration test goes back in with the license. The frame and trait
# tests below stay - those resources are still here, just unreachable without a license.

func test_implemented_content_is_localized():
	# A key with an empty value in the CSV is not registered at all, so tr() hands back the raw
	# key and that is what renders in game.
	for key:String in ['frame.mf_draugr.name', 'frame.mf_draugr.flavor.short', 'gear.buff_infection.name']:
		assert_ne(tr(key), key, '%s resolves to real text.' % key)

func test_draugr_traits_are_localized():
	# The three trait rows exist in localizations.csv but their values are still blank - the mod is
	# v0.0.1 and this copy has not been written yet. Pending rather than failing: it is a real gap,
	# but a suite that is permanently red is a suite people stop reading.
	var unwritten:PackedStringArray = []
	for kit_id:StringName in [&'mt_raging_plague', &'mt_seeping_rot', &'mt_spreading_stain']:
		var key := 'gear.%s.name' % kit_id
		if tr(key) == key: unwritten.append(key)

	if not unwritten.is_empty():
		pending('Trait names not written yet: %s' % ', '.join(unwritten))
		return

	assert_true(true, 'Every Draugr trait has a localized name.')

func test_erinyes_frame_is_registered():
	# Stub frame: statblock and mounts are placeholders, traits array is still empty. This asserts
	# the wiring only - that it lands in the frames index with its declared squad roles intact.
	var frame:Frame = ContentLibrary.get_mech_frame(&'mf_erinyes')
	assert_true(is_instance_valid(frame), 'mf_erinyes is in the frames index.')
	if not is_instance_valid(frame): return
	assert_eq(frame.role_primary, Lancer.SQUAD_ROLE.CONTROLLER, 'Erinyes is a Controller first.')
	assert_eq(frame.role_secondary, Lancer.SQUAD_ROLE.STRIKER, 'Erinyes is a Striker second.')

func test_erinyes_license_grants_the_frame_at_rank_2():
	# A frame nobody can unlock is invisible in game, so the license link is the thing worth guarding.
	var license:UnlockTree = ContentLibrary.get_license_tree(&'li_erinyes')
	assert_true(is_instance_valid(license), 'li_erinyes is in the licenses index.')
	if not is_instance_valid(license): return
	var primary:Frame = license.get_primary_frame()
	assert_true(is_instance_valid(primary), 'Rank 2 grants a frame.')
	if is_instance_valid(primary): assert_eq(primary.compcon_id, &'mf_erinyes', 'That frame is the Erinyes.')

func test_erinyes_name_is_localized():
	assert_ne(tr('frame.mf_erinyes.name'), 'frame.mf_erinyes.name', 'The Erinyes has a real name.')

func test_erinyes_flavor_is_written():
	# Same treatment as the Draugr traits: the CSV rows exist but are blank while the frame is a
	# stub. Pending, not failing - see test_draugr_traits_are_localized.
	var unwritten:PackedStringArray = []
	for key:String in ['frame.mf_erinyes.flavor', 'frame.mf_erinyes.flavor.short']:
		if tr(key) == key: unwritten.append(key)

	if not unwritten.is_empty():
		pending('Erinyes flavor not written yet: %s' % ', '.join(unwritten))
		return

	assert_true(true, 'The Erinyes has flavor text.')

const ERINYES_TRAITS := [&'mt_bind_thy_flesh', &'mt_know_thy_sins', &'mt_tattered_wings']
const ERINYES_CORE_POWER := &'cp_dhiyed_observation'

func test_erinyes_traits_and_core_power_are_registered():
	for kit_id:StringName in ERINYES_TRAITS + [ERINYES_CORE_POWER]:
		assert_true(Kit.is_valid(ContentLibrary.get_kit(kit_id)), '%s is in the kits index.' % kit_id)

func test_the_frame_carries_its_traits_in_book_order():
	# An unwired trait is a resource that loads fine and does nothing, which is the quiet way for
	# this to go wrong. Order is asserted because it drives display order on the character sheet.
	var frame:Frame = ContentLibrary.get_mech_frame(&'mf_erinyes')
	if not is_instance_valid(frame): return fail_test('mf_erinyes loaded.')
	var wired:Array[StringName] = []
	for kit:Kit in frame.traits: wired.append(kit.compcon_id)
	assert_eq(wired, ERINYES_TRAITS + [ERINYES_CORE_POWER], 'Three traits, then the core power.')

func test_erinyes_traits_are_flagged_as_traits():
	# is_trait drives Kit.is_destructable() and which half of the character sheet a kit shows in.
	# A frame trait that misses the flag is a destructible system sitting in the gear list.
	for kit_id:StringName in ERINYES_TRAITS + [ERINYES_CORE_POWER]:
		var kit:Kit = ContentLibrary.get_kit(kit_id)
		if not Kit.is_valid(kit): continue
		assert_true(kit.is_trait, '%s is flagged is_trait.' % kit_id)
		assert_false(kit.is_destructable(), 'And so is not destructible.')

func test_the_core_power_reads_as_a_core_power():
	# Kit.is_core_power() is nothing but a cp_ prefix check, so this is really a filename test.
	var kit:Kit = ContentLibrary.get_kit(ERINYES_CORE_POWER)
	if not Kit.is_valid(kit): return fail_test('%s loaded.' % ERINYES_CORE_POWER)
	assert_true(kit.is_core_power(), '%s is a core power.' % ERINYES_CORE_POWER)

func test_erinyes_gear_names_are_localized():
	for kit_id:StringName in ERINYES_TRAITS + [ERINYES_CORE_POWER]:
		var key := 'gear.%s.name' % kit_id
		assert_ne(tr(key), key, '%s resolves to real text.' % key)

func test_erinyes_gear_effects_are_written():
	# Stubs: the rows exist but are blank until the effect text is filled in. Pending, not failing -
	# same treatment as the Draugr traits above.
	var unwritten:PackedStringArray = []
	for kit_id:StringName in ERINYES_TRAITS + [ERINYES_CORE_POWER]:
		var key := 'gear.%s.effect' % kit_id
		if tr(key) == key: unwritten.append(key)

	if not unwritten.is_empty():
		pending('Effect text not written yet: %s' % ', '.join(unwritten))
		return

	assert_true(true, 'Every Erinyes trait and the core power has effect text.')

const DRAUGR_TRAITS := [&'mt_spreading_stain', &'mt_raging_plague', &'mt_seeping_rot']

func test_the_draugr_frame_carries_its_traits():
	# These three loaded and were indexed for two commits while attached to nothing: the frame had
	# no traits array at all. Registration alone is not evidence a trait does anything.
	var frame:Frame = ContentLibrary.get_mech_frame(&'mf_draugr')
	if not is_instance_valid(frame): return fail_test('mf_draugr loaded.')
	var wired:Array[StringName] = []
	for kit:Kit in frame.traits: wired.append(kit.compcon_id)
	assert_eq(wired, DRAUGR_TRAITS, 'All three Draugr traits are on the frame.')

func test_draugr_traits_are_flagged_as_traits():
	for kit_id:StringName in DRAUGR_TRAITS:
		var kit:Kit = ContentLibrary.get_kit(kit_id)
		if not Kit.is_valid(kit): continue
		assert_true(kit.is_trait, '%s is flagged is_trait.' % kit_id)
		assert_false(kit.is_destructable(), 'And so is not destructible.')

# ==================== DHIYED Observation ====================
# The core power is two sub-abilities on one kit, the way the Denali's Auto-Logistic CompCon carries
# Force Multiplier and Optimizer. Still stubs: these assert the wiring and the action economy, which
# is what the effects will be built on top of.

const CORE_POWER_ACTIONS := [&'action_face_thy_judgement', &'action_punishment']

func _core_power_action(action_id:StringName) -> Action:
	var kit:Kit = ContentLibrary.get_kit(ERINYES_CORE_POWER)
	if not Kit.is_valid(kit): return null
	for action:Action in kit.actions:
		if action.get_id() == action_id: return action
	return null

func test_the_core_power_carries_both_of_its_abilities():
	var kit:Kit = ContentLibrary.get_kit(ERINYES_CORE_POWER)
	if not Kit.is_valid(kit): return fail_test('%s loaded.' % ERINYES_CORE_POWER)
	var action_ids:Array[StringName] = []
	for action:Action in kit.actions: action_ids.append(action.get_id())
	for ability_id:StringName in CORE_POWER_ACTIONS:
		assert_true(action_ids.has(ability_id), '%s is on the core power.' % ability_id)
	# The kit also carries the Efficient refund, which is bookkeeping rather than an ability.
	assert_true(action_ids.has(&'action_dhiyed_observation_efficient'), 'And the Efficient refund.')

func test_face_thy_judgement_is_a_reaction_that_costs_the_reaction():
	# consumes_rxn is what limits it to 1/round: ActionReaction.get_per_round_hard_limit returns 1
	# only for reactions that actually spend the reaction point.
	var action := _core_power_action(&'action_face_thy_judgement')
	if action == null: return fail_test('action_face_thy_judgement loaded.')
	assert_true(action is ActionReaction, 'It is a reaction.')
	if action is ActionReaction: assert_true(action.consumes_rxn, 'And it spends the reaction, so it is 1/round.')

func test_punishment_is_a_free_action_that_spends_the_core_power():
	var action := _core_power_action(&'action_punishment')
	if action == null: return fail_test('action_punishment loaded.')
	assert_eq(action.action_type, Lancer.ACTION.FREE, 'A free action.')
	assert_true(action is ActionSystem, 'On the system archetype, which is what carries consumes_cp.')
	if action is ActionSystem: assert_true(action.consumes_cp, 'And it spends the core power.')

func test_the_core_power_abilities_are_named():
	for action_id:StringName in CORE_POWER_ACTIONS:
		var key := 'gear.%s.%s.name' % [ERINYES_CORE_POWER, action_id]
		assert_ne(tr(key), key, '%s resolves to real text.' % key)

func test_the_core_power_abilities_are_written():
	# Stubs: the rows exist and are blank until the effect text is filled in.
	var unwritten:PackedStringArray = []
	for action_id:StringName in CORE_POWER_ACTIONS:
		var key := 'gear.%s.%s.effect' % [ERINYES_CORE_POWER, action_id]
		if tr(key) == key: unwritten.append(key)

	if not unwritten.is_empty():
		pending('Core power effect text not written yet: %s' % ', '.join(unwritten))
		return

	assert_true(true, 'Both core power abilities have effect text.')

# ============================== Kraken ==============================
#
# Variant frame cloning the HA Saladin license. Everything below is wiring only - the three unique
# traits are behaviourless stubs and the statblock is the Saladin's, pending real numbers.
#
# There is deliberately NO license test here: test_variant_licenses.gd already asserts that
# li_kraken grants mf_kraken at rank 2, matches the Saladin's gear rank-for-rank, and counts as
# HORUS. Duplicating it would just be two places to update.

const KRAKEN_TRAITS := [&'mt_undulating_form', &'mt_my_domain', &'mt_irrepressible']
const KRAKEN_SHARED_TRAIT := &'mt_guardian'
const KRAKEN_CORE_POWER := &'cp_the_endless_black_sea'
## Drag To The Depths is three separate FREE actions rather than one with a sub-menu: they target
## completely differently, and VariantActionGroup only modifies a single action. See the design doc.
const KRAKEN_DRAG_MODES := [&'action_drag_grapple', &'action_drag_pull', &'action_drag_reposition']
const KRAKEN_TIDE_MODES := [&'action_the_all_consuming_tide', &'action_tide_undertow', &'action_tide_seize']
const KRAKEN_CORE_POWER_MODES := KRAKEN_DRAG_MODES + KRAKEN_TIDE_MODES

func test_kraken_frame_is_registered():
	var frame:Frame = ContentLibrary.get_mech_frame(&'mf_kraken')
	assert_true(is_instance_valid(frame), 'mf_kraken is in the frames index.')
	if not is_instance_valid(frame): return
	assert_eq(frame.role_primary, Lancer.SQUAD_ROLE.CONTROLLER, 'Kraken is a Controller first.')
	assert_eq(frame.role_secondary, Lancer.SQUAD_ROLE.DEFENDER, 'Kraken is a Defender second.')

func test_kraken_traits_and_core_power_are_registered():
	for kit_id:StringName in KRAKEN_TRAITS + [KRAKEN_CORE_POWER]:
		assert_true(Kit.is_valid(ContentLibrary.get_kit(kit_id)), '%s is in the kits index.' % kit_id)

func test_the_kraken_frame_carries_its_traits_in_book_order():
	# Guardian sits fourth, between the three unique traits and the core power, and is vanilla's
	# resource rather than a copy - so this also catches the shared trait being dropped or duplicated.
	var frame:Frame = ContentLibrary.get_mech_frame(&'mf_kraken')
	if not is_instance_valid(frame): return fail_test('mf_kraken loaded.')
	var wired:Array[StringName] = []
	for kit:Kit in frame.traits: wired.append(kit.compcon_id)
	assert_eq(wired, KRAKEN_TRAITS + [KRAKEN_SHARED_TRAIT, KRAKEN_CORE_POWER],
		'Three unique traits, then Guardian, then the core power.')

func test_kraken_traits_are_flagged_as_traits():
	for kit_id:StringName in KRAKEN_TRAITS + [KRAKEN_CORE_POWER]:
		var kit:Kit = ContentLibrary.get_kit(kit_id)
		if not Kit.is_valid(kit): continue
		assert_true(kit.is_trait, '%s is flagged is_trait.' % kit_id)
		assert_false(kit.is_destructable(), 'And so is not destructible.')

func test_the_kraken_core_power_reads_as_a_core_power():
	var kit:Kit = ContentLibrary.get_kit(KRAKEN_CORE_POWER)
	if not Kit.is_valid(kit): return fail_test('%s loaded.' % KRAKEN_CORE_POWER)
	assert_true(kit.is_core_power(), '%s is a core power.' % KRAKEN_CORE_POWER)

func test_the_kraken_core_power_has_six_distinct_modes():
	# The whole point of the core power's shape: the three Drag To The Depths options are FREE
	# actions that cost no core power, The All-Consuming Tide is a QUICK action that spends it, and
	# the Undertow and the Seize are reactions the Tide triggers on its own. Getting consumes_cp
	# backwards would leave a frame whose core power either never depletes or depletes on every free
	# use, and neither shows up as an error - just as a mech that plays wrong.
	var kit:Kit = ContentLibrary.get_kit(KRAKEN_CORE_POWER)
	if not Kit.is_valid(kit): return fail_test('%s loaded.' % KRAKEN_CORE_POWER)

	var by_id := {}
	for action:Action in kit.actions: by_id[action.get_id()] = action
	assert_eq(by_id.keys(), KRAKEN_CORE_POWER_MODES, 'It carries exactly its six modes.')

	for mode_id:StringName in KRAKEN_DRAG_MODES:
		var free_mode:Action = by_id.get(mode_id)
		if not Action.is_valid(free_mode): continue
		assert_eq(free_mode.get_action_type(null), Lancer.ACTION.FREE, '%s is free.' % mode_id)
		assert_false(bool(free_mode.consumes_core_power()), 'And %s does not spend the core.' % mode_id)

	var core_mode:Action = by_id.get(&'action_the_all_consuming_tide')
	if Action.is_valid(core_mode):
		assert_eq(core_mode.get_action_type(null), Lancer.ACTION.QUICK, 'The All-Consuming Tide is quick.')
		assert_true(bool(core_mode.consumes_core_power()), 'And spends the core.')

func test_the_kraken_core_power_modes_do_not_share_a_round_allowance():
	# Actions on one Kit default to a single usage_group keyed on the gear id, so a limited mode
	# would be silently spent by its neighbour. Bit the Erinyes once; pinned here from the start.
	var kit:Kit = ContentLibrary.get_kit(KRAKEN_CORE_POWER)
	if not Kit.is_valid(kit): return fail_test('%s loaded.' % KRAKEN_CORE_POWER)
	var groups := {}
	for action:Action in kit.actions: groups[action.usage_group] = true
	assert_eq(groups.size(), kit.actions.size(), 'Every mode has its own usage_group.')
	assert_false(groups.has(&''), 'And none of them fell back to the shared default.')

func test_kraken_names_are_localized():
	var keys:Array[String] = ['frame.mf_kraken.name']
	for kit_id:StringName in KRAKEN_TRAITS + [KRAKEN_CORE_POWER]:
		keys.append('gear.%s.name' % kit_id)
	for mode_id:StringName in KRAKEN_CORE_POWER_MODES:
		keys.append('gear.%s.%s.name' % [KRAKEN_CORE_POWER, mode_id])
	for key:String in keys:
		assert_ne(tr(key), key, '%s resolves to real text.' % key)

func test_kraken_effects_and_flavor_are_written():
	# Stub rows, blank until the copy is written. Pending, not failing - see the Draugr traits above.
	var unwritten:PackedStringArray = []
	for key:String in ['frame.mf_kraken.flavor', 'frame.mf_kraken.flavor.short',
			'gear.%s.effect' % KRAKEN_CORE_POWER, 'gear.%s.flavor' % KRAKEN_CORE_POWER]:
		if tr(key) == key: unwritten.append(key)
	for kit_id:StringName in KRAKEN_TRAITS:
		var key := 'gear.%s.effect' % kit_id
		if tr(key) == key: unwritten.append(key)
	for mode_id:StringName in KRAKEN_CORE_POWER_MODES:
		var key := 'gear.%s.%s.effect' % [KRAKEN_CORE_POWER, mode_id]
		if tr(key) == key: unwritten.append(key)

	if not unwritten.is_empty():
		pending('Kraken copy not written yet: %s' % ', '.join(unwritten))
		return

	assert_true(true, 'The Kraken has flavor and effect text throughout.')

# ============================== Nuckelavee ==============================
#
# Variant frame cloning the IPS-N Nelson license. Scaffold only: the three unique traits are
# behaviourless Kits, the statblock and mounts are the Nelson's, and there is no art yet - each of
# those has a pending guard below so it cannot be quietly forgotten.
#
# As with the Kraken there is deliberately NO license test here; test_variant_licenses.gd carries
# li_nuckelavee through all six of its clause tests from one row.

const NUCKELAVEE_TRAITS := [&'mt_poisoned_soil', &'mt_caustic_earth', &'mt_earthstep']
const NUCKELAVEE_CORE_POWER := &'cp_truth_in_filth'
## Truth in Filth is two parts: Acid Spill is a FREE weapon attack that does NOT spend the core,
## and The Desperate Clawing Hands Of The Dead is the PROTOCOL that does.
const NUCKELAVEE_SPILL := &'action_acid_spill'
const NUCKELAVEE_CLAWING_HANDS := &'action_the_desperate_clawing_hands_of_the_dead'
const NUCKELAVEE_CORE_POWER_MODES := [NUCKELAVEE_SPILL, NUCKELAVEE_CLAWING_HANDS]

func test_nuckelavee_frame_is_registered():
	var frame:Frame = ContentLibrary.get_mech_frame(&'mf_nuckelavee')
	assert_true(is_instance_valid(frame), 'mf_nuckelavee is in the frames index.')
	if not is_instance_valid(frame): return
	assert_eq(frame.role_primary, Lancer.SQUAD_ROLE.STRIKER, 'Nuckelavee is a Striker first.')
	assert_eq(frame.role_secondary, Lancer.SQUAD_ROLE.CONTROLLER, 'Nuckelavee is a Controller second.')

func test_nuckelavee_traits_and_core_power_are_registered():
	for kit_id:StringName in NUCKELAVEE_TRAITS + [NUCKELAVEE_CORE_POWER]:
		assert_true(Kit.is_valid(ContentLibrary.get_kit(kit_id)), '%s is in the kits index.' % kit_id)

func test_the_nuckelavee_frame_carries_its_traits_in_book_order():
	var frame:Frame = ContentLibrary.get_mech_frame(&'mf_nuckelavee')
	if not is_instance_valid(frame): return fail_test('mf_nuckelavee loaded.')
	var wired:Array[StringName] = []
	for kit:Kit in frame.traits: wired.append(kit.compcon_id)
	assert_eq(wired, NUCKELAVEE_TRAITS + [NUCKELAVEE_CORE_POWER], 'Three traits, then the core power.')

func test_nuckelavee_traits_are_flagged_as_traits():
	for kit_id:StringName in NUCKELAVEE_TRAITS + [NUCKELAVEE_CORE_POWER]:
		var kit:Kit = ContentLibrary.get_kit(kit_id)
		if not Kit.is_valid(kit): continue
		assert_true(kit.is_trait, '%s is flagged is_trait.' % kit_id)
		assert_false(kit.is_destructable(), 'And so is not destructible.')

func test_the_nuckelavee_core_power_reads_as_a_core_power():
	var kit:Kit = ContentLibrary.get_kit(NUCKELAVEE_CORE_POWER)
	if not Kit.is_valid(kit): return fail_test('%s loaded.' % NUCKELAVEE_CORE_POWER)
	assert_true(kit.is_core_power(), '%s is a core power.' % NUCKELAVEE_CORE_POWER)

func test_truth_in_filth_has_two_parts_with_the_right_economy():
	# Pinned from the scaffold, the way the Kraken's was: which half spends the core is invisible in
	# play if it is wrong - the frame just plays as though its core never depletes, or always does.
	var kit:Kit = ContentLibrary.get_kit(NUCKELAVEE_CORE_POWER)
	if not Kit.is_valid(kit): return fail_test('%s loaded.' % NUCKELAVEE_CORE_POWER)

	var by_id := {}
	for action:Action in kit.actions: by_id[action.get_id()] = action

	# The raw action list is no longer "exactly its two parts": by design, five bookkeeping
	# reactions (action_acid_spill_arm/_track/_fire/_disarm, action_clawing_hands_prone) also live on
	# this Kit as internal machinery, each overriding show_in_tooltip(_kit) -> false so the player
	# never sees them. Assert on what the test's comment actually cares about - what the PLAYER sees -
	# by filtering to the actions that show in the tooltip. This trades one guarantee for another
	# rather than strictly improving on the original: filtering to tooltip-visible actions pins the
	# player-facing set more precisely, but on its own no longer pins the COMPLETE action list, so an
	# eighth action, or a typo'd id on a hidden one, would pass silently. The explicit count below
	# restores that guarantee, which is why both assertions are kept.
	var player_facing_ids:Array = kit.actions.filter(func(action:Action) -> bool: return action.show_in_tooltip(kit)) \
		.map(func(action:Action) -> StringName: return action.get_id())
	assert_eq(player_facing_ids, NUCKELAVEE_CORE_POWER_MODES, 'It shows the player exactly its two parts.')
	assert_eq(kit.actions.size(), 7, 'Two player-facing parts plus five bookkeeping reactions, and nothing else.')

	var spill:Action = by_id.get(NUCKELAVEE_SPILL)
	if Action.is_valid(spill):
		assert_eq(spill.get_action_type(null), Lancer.ACTION.FREE, 'Acid Spill is free.')
		assert_false(bool(spill.consumes_core_power()), 'And does not spend the core.')

	var hands:Action = by_id.get(NUCKELAVEE_CLAWING_HANDS)
	if Action.is_valid(hands):
		assert_eq(hands.get_action_type(null), Lancer.ACTION.PROTOCOL, 'The Clawing Hands is a protocol.')
		assert_true(bool(hands.consumes_core_power()), 'And spends the core.')

func test_the_nuckelavee_core_power_parts_do_not_share_a_round_allowance():
	# Same trap as the Kraken's: actions on one Kit default to a usage_group keyed on the gear id.
	var kit:Kit = ContentLibrary.get_kit(NUCKELAVEE_CORE_POWER)
	if not Kit.is_valid(kit): return fail_test('%s loaded.' % NUCKELAVEE_CORE_POWER)
	var groups := {}
	for action:Action in kit.actions: groups[action.usage_group] = true
	assert_eq(groups.size(), kit.actions.size(), 'Both parts have their own usage_group.')
	assert_false(groups.has(&''), 'And neither fell back to the shared default.')

func test_caustic_earth_carries_one_correctly_configured_reaction():
	# Four exports, three of which fail silently and one of which fails invisibly.
	#
	# can_trigger_any_number_of_times_per_round is the load-bearing one: ActionReactionOnComingWithin
	# overrides get_per_round_hard_limit off it and IGNORES consumes_rxn, so at the default the trait
	# damages one character per ROUND in total - the text's 1/round-per-CHARACTER rule collapsed into
	# 1/round-per-Nuckelavee. Vanilla's own action_apocalypse_burn.tres omits it.
	#
	# show_in_tooltip is the invisible one: Action.show_in_tooltip returns TRUE for any trait
	# reaction whose KIT carries a trigger row (action.gd:343-344). mt_caustic_earth's is empty
	# today, so nothing leaks - but one localization row later would advertise this bookkeeping as a
	# separate ability, exactly as happened to all four Poisoned Soil actions.
	var kit:Kit = ContentLibrary.get_kit(&'mt_caustic_earth')
	if not Kit.is_valid(kit): return fail_test('mt_caustic_earth loaded.')

	var reactions:Array = kit.get_reactions()
	assert_eq(reactions.size(), 1, 'Caustic Earth is one reaction, not several.')
	if reactions.is_empty(): return

	# Deliberately UNTYPED. can_trigger_any_number_of_times_per_round, when_enter_within, DAMAGE and
	# DAMAGE_TYPE all live on ActionReactionOnComingWithin or on our own script, not on
	# ActionReaction - so a typed `var rxn:ActionReaction` makes every one of them a PARSE error,
	# and GUT responds to a parse error by SKIPPING the whole file with "Ignoring script ... because
	# it does not extend GutTest". The suite would still read green, just fifty tests shorter.
	var rxn = reactions[0]
	assert_eq(rxn.triggers_on, [&'step', &'new_turn'] as Array[StringName],
		'It reacts to entering and to starting a turn.')
	assert_true(rxn.when_enter_within, 'The entering half of the clause is on.')
	assert_true(rxn.when_start_turn_within, 'And the starting-a-turn half.')
	assert_eq(rxn.trigger_timing, ReactionBus.TIMING.POST, 'After the fact, so the unit is on the tile.')
	assert_false(rxn.consumes_rxn, 'A trait does not spend the pilot reaction.')

	# "1 AP ENERGY". The AP half is asserted behaviourally in test_caustic_earth.gd, against a
	# victim with 1 armour. The damage TYPE cannot be fully pinned that way: test_caustic_earth.gd's
	# before-1 assertions already prove it is not HEAT, which routes to heat() and never touches
	# health. They do NOT prove it is not BURN - event_unit_damage.gd calls damage() and THEN adds
	# burn, so a BURN-typed trait would pass every before-1 assertion unchanged; that half is instead
	# pinned by test_the_damage_is_armour_piercing's separate assert on victim.state.burn. Beyond
	# that, nothing in the engine distinguishes ENERGY from KINETIC or EXPLOSIVE at 1 point of AP
	# damage - resistance halves, and Util.half(1) is ceili(0.5) = 1, so even a resistant target
	# still loses exactly 1. Pinning the constant is the whole of the achievable coverage, and it is
	# a source-level assertion on purpose rather than by omission.
	assert_eq(rxn.DAMAGE, 1, 'One point.')
	assert_eq(rxn.DAMAGE_TYPE, Lancer.DAMAGE_TYPE.ENERGY, 'Of ENERGY.')
	assert_true(rxn.can_trigger_any_number_of_times_per_round,
		'Or the per-round hard limit caps the whole trait at one character per round.')
	assert_true(rxn.can_only_affect_a_unit_once_per_round, 'Characters take it 1/round.')
	assert_false(rxn.once_per_round_is_specific_to_gear,
		'"1/round" is unqualified - two Nuckelavees still only bite a character once.')
	assert_true(rxn.triggers_only_on_characters, 'The text says "Characters", so deployables are spared.')
	assert_false(rxn.show_in_tooltip(kit), 'Bookkeeping stays out of the trait tooltip.')

func test_earthstep_carries_its_marker_passive_and_nothing_else():
	# Earthstep has no actions and no behaviour of its own: the rule lives in
	# res/engine/character/unit/service/unit_relation.gd_ext.gd, which finds the frame by looking for
	# THIS PASSIVE TYPE rather than for the id mt_earthstep. Delete the passive and the extension
	# stops recognising the Nuckelavee - silently, since an override that never matches looks exactly
	# like an override that never runs. This is what notices.
	var kit:Kit = ContentLibrary.get_kit(&'mt_earthstep')
	if not Kit.is_valid(kit): return fail_test('mt_earthstep loaded.')

	assert_eq(kit.get_passives(PassiveEarthstep).size(), 1, 'Exactly one Earthstep marker.')
	assert_true(kit.actions.is_empty(), 'And no actions - the trait is entirely passive.')

func test_nuckelavee_names_are_localized():
	var keys:Array[String] = ['frame.mf_nuckelavee.name']
	for kit_id:StringName in NUCKELAVEE_TRAITS + [NUCKELAVEE_CORE_POWER]:
		keys.append('gear.%s.name' % kit_id)
	for mode_id:StringName in NUCKELAVEE_CORE_POWER_MODES:
		keys.append('gear.%s.%s.name' % [NUCKELAVEE_CORE_POWER, mode_id])
	for key:String in keys:
		assert_ne(tr(key), key, '%s resolves to real text.' % key)

func test_nuckelavee_effects_and_flavor_are_written():
	# Stub rows, blank until the copy is written. Pending, not failing - see the Draugr traits above.
	var unwritten:PackedStringArray = []
	for key:String in ['frame.mf_nuckelavee.flavor', 'frame.mf_nuckelavee.flavor.short',
			'gear.%s.effect' % NUCKELAVEE_CORE_POWER, 'gear.%s.flavor' % NUCKELAVEE_CORE_POWER]:
		if tr(key) == key: unwritten.append(key)
	for kit_id:StringName in NUCKELAVEE_TRAITS:
		var key := 'gear.%s.effect' % kit_id
		if tr(key) == key: unwritten.append(key)
	for mode_id:StringName in NUCKELAVEE_CORE_POWER_MODES:
		var key := 'gear.%s.%s.effect' % [NUCKELAVEE_CORE_POWER, mode_id]
		if tr(key) == key: unwritten.append(key)

	if not unwritten.is_empty():
		pending('Nuckelavee copy not written yet: %s' % ', '.join(unwritten))
		return

	assert_true(true, 'The Nuckelavee has flavor and effect text throughout.')

func test_nuckelavee_stats_are_its_own_and_not_the_nelsons():
	# The statblock and mounts ship as the Nelson's placeholders. The Kraken went two commits with
	# the Saladin's numbers before anyone noticed, so this says so out loud rather than hoping.
	var frame:Frame = ContentLibrary.get_mech_frame(&'mf_nuckelavee')
	var nelson:Frame = ContentLibrary.get_mech_frame(&'mf_nelson')
	if not is_instance_valid(frame): return fail_test('mf_nuckelavee loaded.')
	if not is_instance_valid(nelson): return fail_test('mf_nelson loaded.')

	if _statblock_signature(frame.stat) == _statblock_signature(nelson.stat):
		pending('Statblock is still the Nelson\'s placeholder.')
		return

	assert_true(true, 'The Nuckelavee has its own numbers.')

func test_the_nuckelavee_has_art():
	# An unwired sprite falls back to the missing-frame token, which reads in the catalog as a
	# broken frame rather than an unfinished one.
	var frame:Frame = ContentLibrary.get_mech_frame(&'mf_nuckelavee')
	if not is_instance_valid(frame): return fail_test('mf_nuckelavee loaded.')

	if frame.sprites.is_empty():
		pending('No art wired yet - drop a png in res/assets/frames/horus/mf_nuckelavee/.')
		return

	assert_true(true, 'The Nuckelavee has a sprite.')

func _statblock_signature(stat:Statblock) -> Array:
	if stat == null: return []
	return [stat.size, stat.structure, stat.stress, stat.health, stat.armor, stat.evasion, stat.edef,
		stat.speed, stat.heat, stat.save_target, stat.sensor_range, stat.tech_attack, stat.repairs,
		stat.systems_points, stat.reactions, stat.activations]

# ==================== Poisoned Soil ====================

const POISONED_SOIL_ACTIONS := [&'action_poisoned_soil_arm', &'action_poisoned_soil_track',
	&'action_poisoned_soil_lay', &'action_poisoned_soil_disarm']

func test_poisoned_soil_carries_one_terrain_zone_and_four_reactions():
	# The fourth reaction (disarm, on END_TURN) was added by the final review's round-2 fix: a round
	# stamp alone bounds a stale arm to the rest of the ARMING ROUND, which is one grain too coarse
	# for a turn-scoped effect - action_symbiosis_shared_turn.gd can grant a second, linked turn
	# within the same round. Disarming unconditionally at the end of the arming unit's own turn is
	# what actually closes that.
	var kit:Kit = ContentLibrary.get_kit(&'mt_poisoned_soil')
	if not Kit.is_valid(kit): return fail_test('mt_poisoned_soil loaded.')

	assert_eq(kit.get_passives(PassiveTerrainZone).size(), 1, 'Exactly one terrain zone.')

	var action_ids:Array[StringName] = []
	for action:Action in kit.actions: action_ids.append(action.get_id())
	assert_eq(action_ids, POISONED_SOIL_ACTIONS, 'Arm, track, lay, disarm - in that order.')

func test_no_poisoned_soil_reaction_consumes_the_reaction():
	# A consuming reaction is hard-capped at 1/round by ActionReaction.get_action_type returning
	# RXN, which would silently stop the tracker after its first step.
	var kit:Kit = ContentLibrary.get_kit(&'mt_poisoned_soil')
	if not Kit.is_valid(kit): return fail_test('mt_poisoned_soil loaded.')
	for action:Action in kit.actions:
		assert_true(action is ActionReaction, '%s is a reaction.' % action.get_id())
		if action is ActionReaction:
			assert_false(action.consumes_rxn, '%s does not spend the reaction.' % action.get_id())

func test_the_poisoned_soil_reactions_do_not_share_a_round_allowance():
	var kit:Kit = ContentLibrary.get_kit(&'mt_poisoned_soil')
	if not Kit.is_valid(kit): return fail_test('mt_poisoned_soil loaded.')
	var groups := {}
	for action:Action in kit.actions: groups[action.usage_group] = true
	assert_eq(groups.size(), kit.actions.size(), 'Every reaction has its own usage_group.')
	assert_false(groups.has(&''), 'And none fell back to the shared default.')

func test_the_poisoned_soil_reactions_are_hidden_from_the_tooltip():
	# All four are internal bookkeeping - the player never chooses any of them, and the trait's own
	# effect and trigger text already say what it does. Action.show_in_tooltip returns TRUE for any
	# trait reaction whose KIT carries a trigger row (action.gd:343-344), and mt_poisoned_soil has
	# one, so without an explicit override all four list themselves in the tooltip. Found in play.
	var kit:Kit = ContentLibrary.get_kit(&'mt_poisoned_soil')
	if not Kit.is_valid(kit): return fail_test('mt_poisoned_soil loaded.')
	for action:Action in kit.actions:
		assert_false(action.show_in_tooltip(kit), '%s stays out of the tooltip.' % action.get_id())

func test_poisoned_soil_terrain_is_visible():
	# Dynamic difficult terrain draws NOTHING on its own - confirmed in play, the trail was
	# completely invisible. PassiveTerrainZone.get_attached_fx returns no tickets unless the passive
	# carries an fxe, so this assertion is the difference between a trait that works and a trait
	# nobody can see working. Asserting the resolved id also proves the scene actually loaded.
	var kit:Kit = ContentLibrary.get_kit(&'mt_poisoned_soil')
	if not Kit.is_valid(kit): return fail_test('mt_poisoned_soil loaded.')
	var zones:Array = kit.get_passives(PassiveTerrainZone)
	if zones.is_empty(): return fail_test('mt_poisoned_soil carries a terrain zone.')
	assert_eq(zones[0].get_fxe_id(), &'fxe_poisoned_soil', 'The trail draws an effect on every fouled tile.')

# ============================== Banshee ==============================
#
# Variant frame cloning the SSC Death's Head license. Scaffold only: the three unique traits are
# behaviourless Kits, the statblock is the Death's Head's, and there is no art yet - each of those
# has a pending guard below so it cannot be quietly forgotten.
#
# The mounts are NOT the Death's Head's: the Banshee carries a Main and a Heavy where the base frame
# carries a Heavy and a Main/Aux, so the mount test below asserts the real loadout rather than
# guarding a placeholder.
#
# As with the Kraken and the Nuckelavee there is deliberately NO license test here;
# test_variant_licenses.gd carries li_banshee through all six of its clause tests from one row.

const BANSHEE_TRAITS := [&'mt_to_bend_reality', &'mt_to_twist_truth', &'mt_whispering']
const BANSHEE_CORE_POWER := &'cp_the_keening'
## The Keening is two parts, and unusually for this mod BOTH are QUICK actions: Tear does NOT spend
## the core power, Mourning Call does.
const BANSHEE_TEAR := &'action_tear'
const BANSHEE_MOURNING_CALL := &'action_mourning_call'
const BANSHEE_CORE_POWER_MODES := [BANSHEE_TEAR, BANSHEE_MOURNING_CALL]

func test_banshee_frame_is_registered():
	var frame:Frame = ContentLibrary.get_mech_frame(&'mf_banshee')
	assert_true(is_instance_valid(frame), 'mf_banshee is in the frames index.')
	if not is_instance_valid(frame): return
	assert_eq(frame.role_primary, Lancer.SQUAD_ROLE.ARTILLERY, 'Banshee is Artillery.')
	assert_eq(frame.role_secondary, Lancer.SQUAD_ROLE.NONE, 'And pure Artillery - no secondary role.')

func test_banshee_traits_and_core_power_are_registered():
	for kit_id:StringName in BANSHEE_TRAITS + [BANSHEE_CORE_POWER]:
		assert_true(Kit.is_valid(ContentLibrary.get_kit(kit_id)), '%s is in the kits index.' % kit_id)

func test_the_banshee_frame_carries_its_traits_in_book_order():
	var frame:Frame = ContentLibrary.get_mech_frame(&'mf_banshee')
	if not is_instance_valid(frame): return fail_test('mf_banshee loaded.')
	var wired:Array[StringName] = []
	for kit:Kit in frame.traits: wired.append(kit.compcon_id)
	assert_eq(wired, BANSHEE_TRAITS + [BANSHEE_CORE_POWER], 'Three traits, then the core power.')

func test_banshee_traits_are_flagged_as_traits():
	for kit_id:StringName in BANSHEE_TRAITS + [BANSHEE_CORE_POWER]:
		var kit:Kit = ContentLibrary.get_kit(kit_id)
		if not Kit.is_valid(kit): continue
		assert_true(kit.is_trait, '%s is flagged is_trait.' % kit_id)
		assert_false(kit.is_destructable(), 'And so is not destructible.')

func test_the_banshee_core_power_reads_as_a_core_power():
	var kit:Kit = ContentLibrary.get_kit(BANSHEE_CORE_POWER)
	if not Kit.is_valid(kit): return fail_test('%s loaded.' % BANSHEE_CORE_POWER)
	assert_true(kit.is_core_power(), '%s is a core power.' % BANSHEE_CORE_POWER)

func test_the_banshee_carries_a_main_and_a_heavy_mount():
	# Not a placeholder guard - this is the Banshee's real loadout, and it deliberately differs from
	# the Death's Head's Heavy + Main/Aux. Nothing else would notice if a later edit copied the base
	# frame's mounts across along with its statblock.
	var frame:Frame = ContentLibrary.get_mech_frame(&'mf_banshee')
	if not is_instance_valid(frame): return fail_test('mf_banshee loaded.')
	var mounts:Array[StringName] = []
	for mount:MountType in frame.mount_types: mounts.append(mount.compcon_id)
	assert_eq(mounts, [&'mount_main', &'mount_heavy'] as Array[StringName], 'A Main and a Heavy.')

func test_the_keening_has_two_parts_with_the_right_economy():
	# Pinned from the scaffold, the way the Kraken's and the Nuckelavee's were: which half spends the
	# core is invisible in play if it is wrong - the frame just plays as though its core never
	# depletes, or always does. Both halves being QUICK makes that worse, not better: the two are
	# indistinguishable in the action bar, so the only tell would be the core meter.
	var kit:Kit = ContentLibrary.get_kit(BANSHEE_CORE_POWER)
	if not Kit.is_valid(kit): return fail_test('%s loaded.' % BANSHEE_CORE_POWER)

	var by_id := {}
	for action:Action in kit.actions: by_id[action.get_id()] = action
	assert_eq(by_id.keys(), BANSHEE_CORE_POWER_MODES, 'It is exactly its two parts.')

	var tear:Action = by_id.get(BANSHEE_TEAR)
	if Action.is_valid(tear):
		assert_eq(tear.get_action_type(null), Lancer.ACTION.QUICK, 'Tear is a quick action.')
		assert_false(bool(tear.consumes_core_power()), 'And does not spend the core.')

	var mourning_call:Action = by_id.get(BANSHEE_MOURNING_CALL)
	if Action.is_valid(mourning_call):
		assert_eq(mourning_call.get_action_type(null), Lancer.ACTION.QUICK, 'Mourning Call is a quick action.')
		assert_true(bool(mourning_call.consumes_core_power()), 'And spends the core.')

func test_the_banshee_core_power_parts_do_not_share_a_round_allowance():
	# Same trap as the Kraken's and the Nuckelavee's: actions on one Kit default to a usage_group
	# keyed on the gear id, so a 1/round limit on either half would silently spend the other's.
	var kit:Kit = ContentLibrary.get_kit(BANSHEE_CORE_POWER)
	if not Kit.is_valid(kit): return fail_test('%s loaded.' % BANSHEE_CORE_POWER)
	var groups := {}
	for action:Action in kit.actions: groups[action.usage_group] = true
	assert_eq(groups.size(), kit.actions.size(), 'Both parts have their own usage_group.')
	assert_false(groups.has(&''), 'And neither fell back to the shared default.')

func test_banshee_names_are_localized():
	var keys:Array[String] = ['frame.mf_banshee.name']
	for kit_id:StringName in BANSHEE_TRAITS + [BANSHEE_CORE_POWER]:
		keys.append('gear.%s.name' % kit_id)
	for mode_id:StringName in BANSHEE_CORE_POWER_MODES:
		keys.append('gear.%s.%s.name' % [BANSHEE_CORE_POWER, mode_id])
	for key:String in keys:
		assert_ne(tr(key), key, '%s resolves to real text.' % key)

func test_banshee_effects_and_flavor_are_written():
	# Stub rows, blank until the copy is written. Pending, not failing - see the Draugr traits above.
	var unwritten:PackedStringArray = []
	for key:String in ['frame.mf_banshee.flavor', 'frame.mf_banshee.flavor.short',
			'gear.%s.effect' % BANSHEE_CORE_POWER, 'gear.%s.flavor' % BANSHEE_CORE_POWER]:
		if tr(key) == key: unwritten.append(key)
	for kit_id:StringName in BANSHEE_TRAITS:
		var key := 'gear.%s.effect' % kit_id
		if tr(key) == key: unwritten.append(key)
	for mode_id:StringName in BANSHEE_CORE_POWER_MODES:
		var key := 'gear.%s.%s.effect' % [BANSHEE_CORE_POWER, mode_id]
		if tr(key) == key: unwritten.append(key)

	if not unwritten.is_empty():
		pending('Banshee copy not written yet: %s' % ', '.join(unwritten))
		return

	assert_true(true, 'The Banshee has flavor and effect text throughout.')

func test_banshee_stats_are_its_own_and_not_the_deaths_heads():
	# The statblock ships as the Death's Head's placeholder. The Kraken went two commits with the
	# Saladin's numbers before anyone noticed, so this says so out loud rather than hoping.
	var frame:Frame = ContentLibrary.get_mech_frame(&'mf_banshee')
	var deaths_head:Frame = ContentLibrary.get_mech_frame(&'mf_deaths_head')
	if not is_instance_valid(frame): return fail_test('mf_banshee loaded.')
	if not is_instance_valid(deaths_head): return fail_test('mf_deaths_head loaded.')

	if _statblock_signature(frame.stat) == _statblock_signature(deaths_head.stat):
		pending('Statblock is still the Death\'s Head\'s placeholder.')
		return

	assert_true(true, 'The Banshee has its own numbers.')

func test_the_banshee_has_art():
	# An unwired sprite falls back to the missing-frame token, which reads in the catalog as a
	# broken frame rather than an unfinished one.
	var frame:Frame = ContentLibrary.get_mech_frame(&'mf_banshee')
	if not is_instance_valid(frame): return fail_test('mf_banshee loaded.')

	if frame.sprites.is_empty():
		pending('No art wired yet - drop a png in res/assets/frames/horus/mf_banshee/.')
		return

	assert_true(true, 'The Banshee has a sprite.')

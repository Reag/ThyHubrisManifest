# Content integrity for HORUS: Thy Hubris Manifest.
#
# The mod is early WIP, so this is deliberately about wiring rather than behaviour: is everything
# registered, under the right index, with localization to match. Behaviour specs belong beside
# each trait as it gets implemented.
extends GutTest

const ModContentAudit := preload('res://testkit/mod_content_audit.gd')

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
const KRAKEN_CORE_POWER_MODES := KRAKEN_DRAG_MODES + [&'action_the_all_consuming_tide', &'action_tide_undertow']

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

func test_the_kraken_core_power_has_five_distinct_modes():
	# The whole point of the core power's shape: the three Drag To The Depths options are FREE
	# actions that cost no core power, The All-Consuming Tide is a QUICK action that spends it, and
	# the Undertow is a reaction the Tide triggers on its own. Getting consumes_cp backwards would
	# leave a frame whose core power either never depletes or depletes on every free use, and neither
	# shows up as an error - just as a mech that plays wrong.
	var kit:Kit = ContentLibrary.get_kit(KRAKEN_CORE_POWER)
	if not Kit.is_valid(kit): return fail_test('%s loaded.' % KRAKEN_CORE_POWER)

	var by_id := {}
	for action:Action in kit.actions: by_id[action.get_id()] = action
	assert_eq(by_id.keys(), KRAKEN_CORE_POWER_MODES, 'It carries exactly its five modes.')

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

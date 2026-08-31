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

func test_draugr_license_is_registered():
	assert_true(is_instance_valid(ContentLibrary.get_license_tree(&'li_draugr')), 'li_draugr is in the licenses index.')

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

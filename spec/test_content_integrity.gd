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

func test_erinyes_license_is_owned_by_horus():
	# Manufacturer ownership is decided by mirror path (resgrp_man_horus globs **/horus/**.tres),
	# not by anything in the file - so this guards the folder as much as the resource.
	assert_eq(Manufacturer.get_id_for(&'li_erinyes'), &'horus', 'li_erinyes is a HORUS license.')

func test_erinyes_license_clones_dusk_wing_gear():
	# Thy Hubris licenses clone a core-book license wholesale, swapping only the frame and the
	# manufacturer. That duplicates Dusk Wing's gear list into our .tres, so this derives the
	# expectation from li_dusk_wing at runtime rather than hardcoding it: if a modkit update
	# changes what Dusk Wing grants, the clone has drifted and this goes red.
	var erinyes:UnlockTree = ContentLibrary.get_license_tree(&'li_erinyes')
	var dusk_wing:UnlockTree = ContentLibrary.get_license_tree(&'li_dusk_wing')
	assert_true(is_instance_valid(erinyes), 'li_erinyes loaded.')
	assert_true(is_instance_valid(dusk_wing), 'li_dusk_wing loaded.')
	if not (is_instance_valid(erinyes) and is_instance_valid(dusk_wing)): return

	for rank:int in [1, 2, 3]:
		assert_eq(_gear_ids(erinyes.get_rank(rank)), _gear_ids(dusk_wing.get_rank(rank)),
			'Rank %d grants the same gear as Dusk Wing.' % rank)

func test_erinyes_license_grants_the_erinyes_not_the_dusk_wing():
	# The one thing that must NOT be cloned.
	var erinyes:UnlockTree = ContentLibrary.get_license_tree(&'li_erinyes')
	if not is_instance_valid(erinyes): return fail_test('li_erinyes loaded.')
	var frame_ids:Array[StringName] = []
	for rank:int in [1, 2, 3]:
		var unlock_rank:UnlockRank = erinyes.get_rank(rank)
		if unlock_rank == null: continue
		for frame:Frame in unlock_rank.granted_frames: frame_ids.append(frame.compcon_id)
	assert_eq(frame_ids, [&'mf_erinyes'] as Array[StringName], 'It grants exactly the Erinyes.')

func _gear_ids(unlock_rank:UnlockRank) -> Array[StringName]:
	var ids:Array[StringName] = []
	if unlock_rank == null: return ids
	for kit:Kit in unlock_rank.granted_gear: ids.append(kit.compcon_id)
	return ids

# Content integrity for HORUS: Thy Hubris Manifest.
#
# The mod is early WIP, so this is deliberately about wiring rather than behaviour: is everything
# registered, under the right index, with localization to match. Behaviour specs belong beside
# each trait as it gets implemented.
extends GutTest

const ModContentAudit := preload('res://testkit/mod_content_audit.gd')
const Compat := preload('res://testkit/modkit_compat.gd')
const PassiveEarthstep := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_nuckelavee/mt_earthstep/passive_earthstep.gd')

const MOD_ID := 'Reag-ThyHubris'

func test_the_mod_is_actually_loaded():
	assert_true(Compat.is_mod_active(MOD_ID), '%s is loaded and active.' % MOD_ID)

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
	for kit_id:StringName in DRAUGR_TRAITS + [DRAUGR_CORE_POWER]:
		assert_true(Kit.is_valid(ContentLibrary.get_kit(kit_id)), '%s is in the kits index.' % kit_id)

func test_draugr_license_grants_the_frame_at_rank_2():
	# Unparked 2026-09-09 with the frame alone (design doc 2026-09-09-draugr-design.md, decision D7).
	# All three ranks are now filled; this test guards the rank-2 frame link specifically.
	var license:UnlockTree = ContentLibrary.get_license_tree(&'li_draugr')
	assert_true(is_instance_valid(license), 'li_draugr is in the licenses index.')
	if not is_instance_valid(license): return
	var primary:Frame = license.get_primary_frame()
	assert_true(is_instance_valid(primary), 'Rank 2 grants a frame.')
	if is_instance_valid(primary): assert_eq(primary.compcon_id, &'mf_draugr', 'That frame is the Draugr.')

const DRAUGR_LICENSE_II := [&'mw_injector_drill', &'ms_quarantine']

func test_draugr_license_grants_the_drill_and_quarantine_at_rank_2():
	# Design 2026-09-09-draugr-design.md section 5. Rank 2 grants the FRAME as well - the frame test
	# above is the other half and both must stay green.
	var license:UnlockTree = ContentLibrary.get_license_tree(&'li_draugr')
	assert_true(is_instance_valid(license), 'li_draugr is in the licenses index.')
	if not is_instance_valid(license): return
	var granted:Array[StringName] = []
	for kit:Kit in license.rank_2.granted_gear: granted.append(kit.compcon_id)
	assert_eq(granted, DRAUGR_LICENSE_II as Array[StringName], 'Rank II is the Injector Drill then Quarantine.')
	assert_eq(license.rank_2.granted_frames.size(), 1, 'And it still grants the frame.')

const DRAUGR_LICENSE_I := [&'ms_disease', &'ms_root']

func test_draugr_license_grants_disease_and_root_at_rank_1():
	# Design 2026-09-09-draugr-design.md section 4.
	var license:UnlockTree = ContentLibrary.get_license_tree(&'li_draugr')
	assert_true(is_instance_valid(license), 'li_draugr is in the licenses index.')
	if not is_instance_valid(license): return
	var granted:Array[StringName] = []
	for kit:Kit in license.rank_1.granted_gear: granted.append(kit.compcon_id)
	assert_eq(granted, DRAUGR_LICENSE_I as Array[StringName], 'Rank I is Disease then Root.')

const DRAUGR_LICENSE_III := [&'ms_carrion_beast', &'ms_pestilence_class_nhp']

func test_draugr_license_grants_the_carrion_beast_and_pestilence_at_rank_3():
	# Design 2026-09-09-draugr-design.md section 6. With this, all three ranks are filled and the
	# frame is complete.
	var license:UnlockTree = ContentLibrary.get_license_tree(&'li_draugr')
	assert_true(is_instance_valid(license), 'li_draugr is in the licenses index.')
	if not is_instance_valid(license): return
	var granted:Array[StringName] = []
	for kit:Kit in license.rank_3.granted_gear: granted.append(kit.compcon_id)
	assert_eq(granted, DRAUGR_LICENSE_III as Array[StringName], 'Rank III is the Carrion Beast then PESTILENCE.')

func test_the_license_i_systems_are_registered_and_unique():
	# A filename prefix decides the index, not the script class: ms_*.tres lands in resgrp_kits.
	for kit_id:StringName in DRAUGR_LICENSE_I:
		var kit:Kit = ContentLibrary.get_kit(kit_id)
		assert_true(Kit.is_valid(kit), '%s is in the kits index.' % kit_id)
		if not Kit.is_valid(kit): continue
		assert_eq(kit.sp_cost, 2, '%s costs 2 SP.' % kit_id)
		assert_true(kit.is_unique(), '%s is Unique.' % kit_id)
		assert_false(kit.is_trait, '%s is a real, destructible system.' % kit_id)

func test_the_disease_invades_do_not_share_an_allowance():
	# Same trap as the Kraken's and the Nuckelavee's: actions on one Kit default to a usage_group
	# keyed on the gear id (gear_core.gd:166-168), so "each may be used 1/round" would come out as
	# "one of them, once per round". Both options are 1/round in their own right.
	var kit:Kit = ContentLibrary.get_kit(&'ms_disease')
	if not Kit.is_valid(kit): return fail_test('ms_disease loaded.')
	var groups := {}
	for action:Action in kit.actions: groups[action.usage_group] = true
	assert_eq(groups.size(), kit.actions.size(), 'Every invade option has its own usage_group.')
	assert_eq(kit.actions.size(), 2, 'Symptom and Spreader.')

func test_the_injector_drill_is_registered_as_a_limited_weapon():
	# A filename prefix decides the index, not the script class: mw_*.tres lands in resgrp_kits.
	var kit:Kit = ContentLibrary.get_kit(&'mw_injector_drill')
	assert_true(Kit.is_valid(kit), 'mw_injector_drill is in the kits index.')
	if not Kit.is_valid(kit): return
	assert_eq(kit.charges_max, 4, 'Limited 4.')
	assert_eq(kit.actions.size(), 1, 'One attack profile.')
	assert_true(kit.actions[0] is ActionAttackWeapon, 'And it is a weapon attack.')
	assert_true(kit.is_destructable(), 'It is a real, destructible weapon.')

func test_quarantine_is_registered_and_its_invades_do_not_share_an_allowance():
	# Same trap as Disease's: actions on one Kit default to a usage_group keyed on the gear id
	# (gear_core.gd:166-168), so "each may be used 1/round" would come out as "one of them, once per
	# round". Both options are 1/round in their own right.
	var kit:Kit = ContentLibrary.get_kit(&'ms_quarantine')
	assert_true(Kit.is_valid(kit), 'ms_quarantine is in the kits index.')
	if not Kit.is_valid(kit): return
	assert_eq(kit.sp_cost, 2, 'Two SP.')
	assert_true(kit.is_unique(), 'Unique.')
	assert_eq(kit.actions.size(), 2, 'Isolation and Lockdown.')
	var groups := {}
	for action:Action in kit.actions: groups[action.usage_group] = true
	assert_eq(groups.size(), kit.actions.size(), 'Every invade option has its own usage_group.')

func test_the_carrion_beast_is_registered_as_a_two_sp_system():
	# A filename prefix decides the index, not the script class: ms_*.tres lands in resgrp_kits.
	# Design 2026-09-09-draugr-design.md section 6 gives it 2 SP and does NOT make it Unique, unlike
	# Disease, Root and Quarantine - the tags on this one are deliberately empty.
	var kit:Kit = ContentLibrary.get_kit(&'ms_carrion_beast')
	assert_true(Kit.is_valid(kit), 'ms_carrion_beast is in the kits index.')
	if not Kit.is_valid(kit): return
	assert_eq(kit.sp_cost, 2, 'Two SP.')
	assert_false(kit.is_trait, 'It is a real, destructible system.')
	assert_true(kit.has_passive_type(PassiveBuffApplicator), 'It hands out the reach buff.')
	# Task 3b: action_atrophy carries no behaviour of its own - it exists so Isolation's reaction gate
	# has something to test (buff_atrophy.gd) - but it still has to be wired onto the Kit to be found.
	var action_ids:Array[StringName] = []
	for action:Action in kit.actions: action_ids.append(action.get_id())
	assert_true(action_ids.has(&'action_atrophy'), 'The Atrophy reaction shell is registered on the Kit.')

func test_pestilence_is_registered_as_an_nhp_system():
	# A filename prefix decides the index, not the script class: ms_*.tres lands in resgrp_kits.
	# system_tags 13 is UNIQUE 1 + AI 4 + NHP 8 (kit.gd:30) - what all ten vanilla NHP systems set.
	var kit:Kit = ContentLibrary.get_kit(&'ms_pestilence_class_nhp')
	assert_true(Kit.is_valid(kit), 'ms_pestilence_class_nhp is in the kits index.')
	if not Kit.is_valid(kit): return
	assert_eq(kit.sp_cost, 3, 'Three SP.')
	assert_eq(kit.system_tags, 13, 'Unique, AI and NHP.')
	assert_true(kit.has_passive_type(PassiveAiPrivilege), 'It carries an AI privilege passive.')

func test_implemented_content_is_localized():
	# A key with an empty value in the CSV is not registered at all, so tr() hands back the raw
	# key and that is what renders in game.
	for key:String in ['frame.mf_draugr.name', 'frame.mf_draugr.flavor.short', 'gear.buff_infection.name']:
		assert_ne(tr(key), key, '%s resolves to real text.' % key)

# The Draugr license text was transcribed on 2026-09-09, ahead of the gear that will read it. Every
# rule-text row is asserted here so the compiled artifact cannot silently drift from the CSV (an
# outdated localizations.en.translation hands back raw keys and looks like broken content). The
# flavor rows are deliberately blank until the author pastes the lore, so they are not listed.
const DRAUGR_LICENSE_KEYS := [
	'gear.buff_infection.name.count',
	'gear.mt_spreading_stain.effect', 'gear.mt_spreading_stain.trigger',
	'gear.mt_raging_plague.effect',
	'gear.mt_seeping_rot.effect', 'gear.mt_seeping_rot.trigger',
	'gear.cp_cupiditas_vitae.name', 'gear.cp_cupiditas_vitae.effect', 'gear.cp_cupiditas_vitae.flavor',
	'gear.cp_cupiditas_vitae.resilience',
	'gear.cp_cupiditas_vitae.action_ceaseless_death.name', 'gear.cp_cupiditas_vitae.action_ceaseless_death.effect',
	'gear.cp_cupiditas_vitae.action_plague_vent_dispersal.name', 'gear.cp_cupiditas_vitae.action_plague_vent_dispersal.effect',
	'gear.ms_disease.name', 'gear.ms_disease.effect',
	'gear.ms_disease.action_symptom.name', 'gear.ms_disease.action_symptom.effect',
	'gear.ms_disease.action_spreader.name', 'gear.ms_disease.action_spreader.effect',
	'gear.buff_spreader.name', 'gear.buff_spreader.effect',
	'gear.buff_infection.eot.log', 'gear.ms_stabilize.burn.infection.effect',
	'gear.ms_root.name', 'gear.ms_root.effect',
	'gear.ms_root.action_dig_in.name', 'gear.ms_root.action_dig_in.effect', 'gear.ms_root.action_dig_in.trigger',
	'gear.mw_injector_drill.name', 'gear.mw_injector_drill.effect', 'gear.mw_injector_drill.on_hit',
	'gear.ms_quarantine.name', 'gear.ms_quarantine.effect',
	'gear.ms_quarantine.action_isolation.name', 'gear.ms_quarantine.action_isolation.effect',
	'gear.ms_quarantine.action_lockdown.name', 'gear.ms_quarantine.action_lockdown.effect',
	'gear.buff_isolation.name', 'gear.buff_isolation.effect',
	'gear.buff_lockdown.name', 'gear.buff_lockdown.effect',
	'gear.ms_carrion_beast.name', 'gear.ms_carrion_beast.effect',
	'gear.ms_carrion_beast.action_atrophy.name', 'gear.ms_carrion_beast.action_atrophy.effect',
	'gear.ms_carrion_beast.action_atrophy.trigger',
	'gear.ms_pestilence_class_nhp.name', 'gear.ms_pestilence_class_nhp.default_name',
	'gear.ms_pestilence_class_nhp.effect',
	'gear.ms_pestilence_class_nhp.action_kill_host.name', 'gear.ms_pestilence_class_nhp.action_kill_host.effect',
	'gear.ms_pestilence_class_nhp.action_kill_host.option_impair',
	'gear.ms_pestilence_class_nhp.action_kill_host.option_slow',
]

func test_draugr_license_text_is_localized():
	var raw:PackedStringArray = []
	for key:String in DRAUGR_LICENSE_KEYS:
		if tr(key) == key: raw.append(key)
	assert_eq(raw, PackedStringArray(), 'Every Draugr license rule-text key resolves to real text.')

func test_the_core_power_names_its_efficient_tag():
	# The glossary term is only reachable through a |Efficient| label in some rule text.
	assert_true(tr('gear.cp_cupiditas_vitae.effect').contains('|Efficient|'), 'CUPIDITAS VITAE says it is Efficient.')

func test_infection_has_a_glossary_entry():
	# Every Draugr row says |INFECTION|; without a registered term plus a .desc row the label is
	# coloured but has no hover text (glossary_item.gd:199-208 refuses a key with no description).
	# mod_main.register_glossary_terms appends the key; the CSV carries both rows. Matching is
	# case-insensitive there, so |Infection| in the buff rows resolves to the same entry.
	assert_eq(GlossaryItem.find_key_from_label('INFECTION'), 'lancer.term.infection',
		'The signature term links to its own glossary entry.')
	assert_eq(GlossaryItem.find_key_from_label('Infection'), 'lancer.term.infection', 'Either case.')

func test_resilience_has_a_glossary_entry():
	assert_eq(GlossaryItem.find_key_from_label('Resilience'), 'lancer.term.resilience',
		'The core power rows say |Resilience|; it links to its own entry.')

func test_draugr_rows_link_their_own_actions():
	# The wiki style guide's |Label=gear.<kit>.<action>| form gives the label the kit tooltip link
	# (glossary_item.gd:230-250 takes the explicit key and links any gear.* key whose kit exists).
	# A typo in the key silently degrades to plain coloured text, so every explicit link is checked.
	var links := {
		'gear.ms_disease.effect': ['gear.ms_disease.action_symptom', 'gear.ms_disease.action_spreader'],
		'gear.ms_root.effect': ['gear.ms_root.action_dig_in'],
		'gear.ms_quarantine.effect': ['gear.ms_quarantine.action_isolation', 'gear.ms_quarantine.action_lockdown'],
		'gear.ms_carrion_beast.effect': ['gear.ms_carrion_beast.action_atrophy'],
		'gear.ms_pestilence_class_nhp.effect': ['gear.ms_pestilence_class_nhp.action_kill_host'],
		'gear.cp_cupiditas_vitae.effect': ['gear.cp_cupiditas_vitae.action_ceaseless_death', 'gear.cp_cupiditas_vitae.action_plague_vent_dispersal'],
		'gear.buff_infection.effect': ['gear.ms_stabilize'],
	}
	for row:String in links:
		var processed:Dictionary = GlossaryItem.process_glossed_text(tr(row))
		for key:String in links[row]:
			assert_true(tr(row).contains('=%s|' % key), '%s links %s.' % [row, key])
			var kit_id:String = key.split('.')[1]
			assert_true(processed.bbcoded.contains('{"kit":"%s"}' % kit_id), '%s renders a kit link for %s.' % [row, kit_id])
			assert_true(tr('%s.name' % key) != '%s.name' % key, 'And the linked key has a name row.')

func test_every_draugr_kit_action_and_visible_buff_has_an_icon():
	# Icons drawn 2026-09-10 in the vanilla language (specs/2026-09-10-icon-language.md). A kit
	# without icon_override falls back to the generic glyph; an action without one inherits its
	# Kit's instead (action.gd:324-326 -> kit.gd:209), and only every action checked here carries
	# its own regardless, since each of these Kits has more than one. A visible buff without `icon`
	# falls back to generic. Hidden buffs (hide_from_player) need none.
	var kits:Array[StringName] = [&'mt_raging_plague', &'mt_seeping_rot', &'mt_spreading_stain', &'cp_cupiditas_vitae',
		&'mt_plague_fog', &'ms_disease', &'ms_root', &'ms_quarantine', &'ms_carrion_beast', &'ms_pestilence_class_nhp',
		&'mw_injector_drill']
	for kit_id:StringName in kits:
		var kit:Kit = ContentLibrary.get_kit(kit_id)
		if not Kit.is_valid(kit): fail_test('%s resolves.' % kit_id); continue
		assert_not_null(kit.icon_override, '%s has an icon.' % kit_id)
		for action:Action in kit.actions:
			if not action.show_in_tooltip(kit): continue
			if kit.actions.size() == 1: continue # a lone action wears the kit icon
			assert_not_null(action.icon_override, '%s: %s has its own icon.' % [kit_id, action.resource_path.get_file()])
	for buff_id:StringName in [&'buff_infection', &'buff_spreader', &'buff_isolation', &'buff_lockdown']:
		var buff:Buff = ContentLibrary.get_buff(buff_id)
		if not (is_instance_valid(buff) and buff is Buff): fail_test('%s resolves.' % buff_id); continue
		assert_false(buff.hide_from_player, '%s is player-facing.' % buff_id)
		assert_not_null(buff.icon, '%s has an icon.' % buff_id)

func test_atrophy_rows_carry_the_automatic_warning():
	# Author request 2026-09-10: the reaction fires automatically (engine limitation, design D4), and
	# the player is told so in red on both the kit and the action.
	for row:String in ['gear.ms_carrion_beast.effect', 'gear.ms_carrion_beast.action_atrophy.effect']:
		assert_true(tr(row).contains('[color=#e07057]') and tr(row).contains('[/color]'), '%s has the red warning.' % row)

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
const DRAUGR_CORE_POWER := &'cp_cupiditas_vitae'

func test_the_draugr_frame_carries_its_traits():
	# These three loaded and were indexed for two commits while attached to nothing: the frame had
	# no traits array at all. Registration alone is not evidence a trait does anything.
	var frame:Frame = ContentLibrary.get_mech_frame(&'mf_draugr')
	if not is_instance_valid(frame): return fail_test('mf_draugr loaded.')
	var wired:Array[StringName] = []
	for kit:Kit in frame.traits: wired.append(kit.compcon_id)
	assert_eq(wired, DRAUGR_TRAITS + [DRAUGR_CORE_POWER], 'Three traits, then the core power.')

func test_draugr_traits_are_flagged_as_traits():
	for kit_id:StringName in DRAUGR_TRAITS + [DRAUGR_CORE_POWER]:
		var kit:Kit = ContentLibrary.get_kit(kit_id)
		if not Kit.is_valid(kit): continue
		assert_true(kit.is_trait, '%s is flagged is_trait.' % kit_id)
		assert_false(kit.is_destructable(), 'And so is not destructible.')

func test_the_draugr_core_power_reads_as_a_core_power():
	# Kit.is_core_power() is nothing but a cp_ prefix check, so this is really a filename test -
	# and the filename is also what puts the kit in the kits index rather than the frames one.
	var kit:Kit = ContentLibrary.get_kit(DRAUGR_CORE_POWER)
	if not Kit.is_valid(kit): return fail_test('%s loaded.' % DRAUGR_CORE_POWER)
	assert_true(kit.is_core_power(), '%s is a core power.' % DRAUGR_CORE_POWER)

func test_the_core_power_carries_the_resilience_counter():
	# The die counter's key is what Translate.gear(kit_id, key) looks up for the tooltip label
	# (passive_die_counter.gd:48), and gear.cp_cupiditas_vitae.resilience is the row that answers it.
	var kit:Kit = ContentLibrary.get_kit(DRAUGR_CORE_POWER)
	if not Kit.is_valid(kit): return fail_test('%s loaded.' % DRAUGR_CORE_POWER)
	var counters:Array[Passive] = kit.get_passives(PassiveDieCounter)
	assert_eq(counters.size(), 1, 'Exactly one die counter on the core power.')
	if counters.is_empty(): return
	var die:PassiveDieCounter = counters[0]
	assert_eq(die.key, 'resilience', 'Keyed "resilience".')
	assert_eq(die.starting_value, 0, 'Starts empty.')
	assert_eq(die.min_value, 0, 'And can reach empty; the engine default of 1 would strand a point.')
	assert_ne(tr('gear.cp_cupiditas_vitae.%s' % die.key), 'gear.cp_cupiditas_vitae.%s' % die.key,
		'The counter label resolves to real text.')

func test_the_plague_fog_is_registered_and_named():
	# dep_ files land in the FRAMES index and mt_ files in the KITS index, by filename prefix alone
	# (engine/resource_groups/). A fog filed under the wrong one loads fine and is never found by
	# ContentLibrary.get_mech_frame, which is what ActionSystemDeploy needs.
	var fog:Frame = ContentLibrary.get_mech_frame(&'dep_plague_fog')
	assert_true(is_instance_valid(fog), 'dep_plague_fog is in the frames index.')
	if not is_instance_valid(fog): return
	assert_eq(fog.entity_type, Frame.ENTITY.MARKER, 'It is a marker, like every vanilla smoke cloud.')
	var wired:Array[StringName] = []
	for kit:Kit in fog.traits: wired.append(kit.compcon_id)
	assert_eq(wired, [&'mt_plague_fog', &'mt_expiration'] as Array[StringName],
		'Its own kit, then vanilla expiration - which is what makes it last until the end of the next turn.')
	assert_ne(tr('frame.dep_plague_fog.name'), 'frame.dep_plague_fog.name', 'And it has a name.')

func test_the_core_power_carries_all_four_of_its_actions():
	# Two named abilities plus two pieces of bookkeeping. The bookkeeping pair have no localization
	# rows and hide themselves from the tooltip, so nothing else would notice them going missing.
	var kit:Kit = ContentLibrary.get_kit(DRAUGR_CORE_POWER)
	if not Kit.is_valid(kit): return fail_test('%s loaded.' % DRAUGR_CORE_POWER)
	var action_ids:Array[StringName] = []
	for action:Action in kit.actions: action_ids.append(action.get_id())
	for expected:StringName in [
		&'action_ceaseless_death', &'action_ceaseless_death_structure',
		&'action_plague_vent_dispersal', &'action_cupiditas_vitae_efficient',
	]:
		assert_true(action_ids.has(expected), '%s is on the core power.' % expected)

	# Sharing a usage_group would make one action's use silently consume another's allowance
	# (gear_core.gd:166-168). The Erinyes was bitten by exactly this; see
	# action_face_thy_judgement.gd's header.
	var groups:Array[StringName] = []
	for action:Action in kit.actions:
		if action.usage_group.is_empty(): continue
		assert_false(groups.has(action.usage_group), '%s has a usage group of its own.' % action.get_id())
		groups.append(action.usage_group)

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
# behaviourless Kits, the statblock is the Death's Head's, and there is no art yet.
#
# CORRECTED: this banner used to claim "each of those has a pending guard below". Two do - the art
# guard and the copy guard - but the BEHAVIOURLESS TRAITS DO NOT. Their copy is written, so
# test_banshee_effects_and_flavor_are_written pends only on the core power's blank effect/flavor and
# says nothing about whether any trait actually does something. Nothing here would notice To Bend
# Reality, To Twist Truth or Whispering shipping as empty Kits with complete tooltips. The statblock
# guard is also gone by now - the frame has its own numbers.
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
## Task 3's kill rider (clause 7): the DEATH:PRE reaction that strips LEAVES_WRECK on a Mourning
## Call kill. It has no book entry, no player-facing name and nothing to say for itself, and until
## 2026-09-08 it had a Kit of its own (mt_mourning_call_wreckless) wired into the frame's traits --
## where the playtest found it showing up as a fourth, nameless trait. It now lives on
## cp_the_keening alongside the ability it belongs to; see action_mourning_call_wreckless.gd for why
## it has to be on the BANSHEE at all rather than on the target.
const BANSHEE_MOURNING_CALL_WRECKLESS := &'action_mourning_call_wreckless'
## The 2026-09-08 tangibility clean-up (clause 2): the UNIT_SPAWN:POST reaction that takes INTANGIBLE
## back off a tear the Banshee opened while phased. Same shape and same reasons as the wreckless
## reaction above - hidden, no book entry, and on the BANSHEE because a tear is a MARKER and a
## marker's own reactions can never fire.
const BANSHEE_TEAR_NEITHER_SIDE := &'action_tear_neither_side'

func test_banshee_frame_is_registered():
	var frame:Frame = ContentLibrary.get_mech_frame(&'mf_banshee')
	assert_true(is_instance_valid(frame), 'mf_banshee is in the frames index.')
	if not is_instance_valid(frame): return
	assert_eq(frame.role_primary, Lancer.SQUAD_ROLE.ARTILLERY, 'Banshee is Artillery.')
	assert_eq(frame.role_secondary, Lancer.SQUAD_ROLE.NONE, 'And pure Artillery - no secondary role.')

func test_banshee_traits_and_core_power_are_registered():
	for kit_id:StringName in BANSHEE_TRAITS + [BANSHEE_CORE_POWER]:
		assert_true(Kit.is_valid(ContentLibrary.get_kit(kit_id)), '%s is in the kits index.' % kit_id)
	assert_false(Kit.is_valid(ContentLibrary.get_kit(&'mt_mourning_call_wreckless')),
		'And the old standalone wreckless Kit is gone from the index entirely.')

func test_the_banshee_frame_carries_its_traits_in_book_order():
	var frame:Frame = ContentLibrary.get_mech_frame(&'mf_banshee')
	if not is_instance_valid(frame): return fail_test('mf_banshee loaded.')
	var wired:Array[StringName] = []
	for kit:Kit in frame.traits: wired.append(kit.compcon_id)
	# WHAT THE PLAYER SEES IN THE FRAME'S TRAIT LIST, and nothing else. There used to be a fifth
	# entry here -- mt_mourning_call_wreckless, a Kit that existed only to carry one hidden reaction
	# -- and the playtest saw it: a nameless trait in the book with no text and no effect. The
	# reaction moved onto cp_the_keening; this assertion is what keeps it from coming back.
	assert_eq(wired, BANSHEE_TRAITS + [BANSHEE_CORE_POWER], 'Three traits, then the core power. Nothing hidden in the list.')

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

	# The raw action list is no longer "exactly its two parts". BOTH of clause 8's verbs - Move Tear
	# and Close Tear - also live on this Kit, because they are verbs of Tear rather than further
	# modes of the core power: they are described inside Tear's own effect text, and each overrides
	# show_in_tooltip -> false so the gear tooltip still reads as two abilities. (Close Tear lived on
	# the tear's own kit until 2026-09-08, where it was unreachable - a marker never takes a turn -
	# so every tear opened was permanent.) Assert on what the PLAYER is shown, then pin the total
	# separately: filtering alone would let a fifth action, or a typo'd id on a hidden one, through
	# unnoticed, which is why both assertions are kept.
	var player_facing:Array = kit.actions.filter(func(action:Action) -> bool: return action.show_in_tooltip(kit)) 		.map(func(action:Action) -> StringName: return action.get_id())
	assert_eq(player_facing, BANSHEE_CORE_POWER_MODES, 'It shows the player exactly its two parts.')
	assert_eq(kit.actions.size(), 6, 'Two player-facing parts, the hidden Move Tear and Close Tear verbs, and two hidden reactions.')
	assert_true(by_id.has(BANSHEE_MOURNING_CALL_WRECKLESS), 'The wreckless reaction rides on this Kit, not on a trait of its own.')
	# The second hidden reaction, added 2026-09-08: a tear must be NEITHER tangible nor intangible,
	# and event_unit_spawn.gd:97-100 would otherwise hand one opened while phased a permanent
	# INTANGIBLE. It lives here for the same reason the wreckless reaction does - a reaction only runs
	# for a unit that has it equipped, and a tear is a MARKER that never takes a turn. See
	# spec/test_tear_tangibility.gd.
	assert_true(by_id.has(BANSHEE_TEAR_NEITHER_SIDE), 'The tear tangibility clean-up rides on this Kit too.')

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

# --- Banshee icons (2026-09-08) ---
#
# Every player-facing Kit on the Banshee carries an icon_override, and every Action either carries
# its own or is a KIT row that inherits the Kit's (action.gd:324-326 -> kit.gd:209) - mt_whispering's
# action_whispering is the one KIT row here. Without either, the engine falls back to
# Kit.DEFAULT_SYSTEM_ICON / Action.DEFAULT_ICON - the generic grey box - which is not an error and
# produces no warning, so a lost or mistyped reference is invisible except by looking at the gear
# bar.
#
# Asserts only that an icon is SET and LOADS, deliberately not WHICH one. The choice of art is the
# author's and may well change; a test naming specific files would have to be edited every time
# somebody picked a better icon, which is a test fighting its owner rather than protecting anything.
#
# Buffs are excluded on purpose: every buff on this frame is hide_from_player = true, so it has no
# icon to show. Both reactions (action_mourning_call_wreckless, action_tear_neither_side) are
# excluded for the same reason - ActionReaction is filtered out of the gear bar entirely.

## A row whose family is KIT carries no icon_override and inherits its Kit's glyph through
## Action.get_icon(kit) (action.gd:324-326 -> kit.gd:209). Any other value names a GLYPH FAMILY:
## every row with that name carries the identical texture. Rule:
## specs/2026-09-18-icon-sharing-design.md section 3.
const KIT := &'__kit__'

const BANSHEE_ICON_TARGETS := {
	# action_tear_close sits on cp_the_keening, NOT on the tear's own kit. It was moved there on
	# 2026-09-08: a tear is ENTITY.MARKER, so it never takes a turn and an action on its own kit is
	# unreachable in play. mt_tear_banshee now carries only the visual passive and no actions.
	&'cp_the_keening': {&'action_tear': &'blinkspace_jump',
						&'action_mourning_call': &'action_hologram_teleport',
						&'action_tear_move': &'move',
						&'action_tear_close': &'deactivate'},
	&'mt_tear_banshee': {},
	&'mt_to_bend_reality': {},
	&'mt_to_twist_truth': {},
	# The trait IS the action: one mechanic, one glyph. Both ends pointed at buff_flash_cloak.svg,
	# so this drops a duplicate reference rather than changing anything the player sees.
	&'mt_whispering': {&'action_whispering': KIT},
}

## action_bend_reality belongs to no Kit. It is a VARIANT action: buff_to_bend_reality swaps it in
## over the pilot's own weapon action at activation time, so it is never in any kit.actions array
## and has to be reached by path.
const BEND_REALITY_ACTION := 'res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/mt_to_bend_reality/action_bend_reality.tres'

func test_the_bend_reality_variant_has_an_icon():
	# It is what the player clicks in the variant picker, so it needs one as much as any gear-bar action.
	var action:Action = load(BEND_REALITY_ACTION)
	assert_true(Action.is_valid(action), 'action_bend_reality loads')
	if not Action.is_valid(action): return
	assert_not_null(action.icon_override, 'action_bend_reality has an icon_override')

func test_every_player_facing_banshee_kit_has_an_icon():
	for kit_id:StringName in BANSHEE_ICON_TARGETS:
		var kit:Kit = ContentLibrary.get_kit(kit_id)
		assert_true(Kit.is_valid(kit), '%s is registered' % kit_id)
		if not Kit.is_valid(kit): continue
		assert_not_null(kit.icon_override, '%s has an icon_override' % kit_id)

func test_every_player_facing_banshee_action_belongs_to_a_glyph_family():
	# action_tear_close lives on the TEAR's kit, not the Banshee's, so this walks the map rather
	# than assuming one owner.
	#
	# A KIT row carries NO icon_override and inherits the Kit's glyph; a named family carries one,
	# and every row sharing that name carries the identical texture. Two families on one Kit must
	# look different, or the gear bar draws two buttons the player cannot tell apart.
	var kits_per_action := {}
	for kit_id:StringName in BANSHEE_ICON_TARGETS:
		var kit:Kit = ContentLibrary.get_kit(kit_id)
		if not Kit.is_valid(kit): continue
		for action:Action in kit.actions:
			kits_per_action[action.resource_path] = kits_per_action.get(action.resource_path, 0) + 1

	var family_texture := {}
	for kit_id:StringName in BANSHEE_ICON_TARGETS:
		var kit:Kit = ContentLibrary.get_kit(kit_id)
		if not Kit.is_valid(kit): continue
		var by_id := {}
		for action:Action in kit.actions: by_id[action.get_id()] = action
		var texture_by_family := {}
		for action_id:StringName in BANSHEE_ICON_TARGETS[kit_id]:
			assert_true(by_id.has(action_id), '%s carries %s' % [kit_id, action_id])
			if not by_id.has(action_id): continue
			var action:Action = by_id[action_id]
			var label:String = '%s.%s' % [kit_id, action_id]
			var family:StringName = BANSHEE_ICON_TARGETS[kit_id][action_id]
			if family == KIT:
				assert_null(action.icon_override,
					'%s is a KIT row, so it carries NO icon_override and inherits the Kit glyph.' % label)
				assert_not_null(kit.icon_override,
					'%s inherits from %s, which therefore needs an icon_override.' % [label, kit_id])
				assert_eq(kits_per_action.get(action.resource_path, 0), 1,
					'%s is carried by exactly one tabled Kit (action.gd:58 caches the inherited icon).'
						% label)
				assert_eq(action.get_icon(kit), kit.icon_override,
					'%s is a KIT row: the engine fallback it depends on (action.gd:324-326 -> kit.gd:209) must actually resolve to the Kit glyph, or it renders a generic grey box.'
						% label)
				continue
			assert_not_null(action.icon_override, '%s has an icon_override' % label)
			if action.icon_override == null: continue
			if family_texture.has(family):
				assert_eq(action.icon_override, family_texture[family][0],
					'%s wears the same texture as %s - they are one family (%s).'
						% [label, family_texture[family][1], family])
			else:
				family_texture[family] = [action.icon_override, label]
			if not texture_by_family.has(family): texture_by_family[family] = action.icon_override
		var claimed := {}
		for family:StringName in texture_by_family:
			var tex:Texture2D = texture_by_family[family]
			assert_false(claimed.has(tex),
				'%s: family %s wears the same texture as family %s - the gear bar draws them as one button.'
					% [kit_id, family, claimed.get(tex, &'-')])
			claimed[tex] = family

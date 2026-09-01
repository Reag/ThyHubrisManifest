# Variant frames and the licenses that grant them.
#
# Thy Hubris variant frames are HORUS reskins of other manufacturers' mechs, and the source book
# states the rule in three clauses:
#
#   1. "Choosing a variant FRAME is mutually exclusive to a license's standard FRAME."
#   2. "All other gear for the license remains the same."
#   3. "When you choose one of these alternate frames at rank II, treat all your levels in that
#      license as HORUS levels for the purpose of Core Bonus access."
#
# The engine has no mutual-exclusivity system and no way to relabel a license's manufacturer at
# runtime, so - on the modkit author's recommendation - each variant is implemented as a CLONE of
# the base license: identical granted gear, our frame in place of theirs, filed under HORUS.
#
# That covers clause 2 by construction and clause 3 exactly and for free, because manufacturer
# ownership is decided by mirror path and pilot_core.gd counts license levels per manufacturer.
# Clause 1 it cannot cover at all. Each has a test below saying so.
#
# Adding the next variant frame is one row in VARIANTS. The Draugr is deliberately absent - it is
# wholly unique and clones nothing.
extends GutTest

## variant license -> { base license it clones, frame it must grant in place of the base's }
const VARIANTS := {
	&'li_erinyes': {&'clones': &'li_dusk_wing', &'grants': &'mf_erinyes'},
}

func test_every_variant_grants_exactly_its_base_licenses_gear():
	# Clause 2. The expectation is read off the vanilla license at runtime rather than hardcoded,
	# so if a modkit update changes what the base grants, the clone has drifted and this goes red.
	for variant_id:StringName in VARIANTS:
		var variant:UnlockTree = ContentLibrary.get_license_tree(variant_id)
		var base:UnlockTree = ContentLibrary.get_license_tree(VARIANTS[variant_id][&'clones'])
		if not _both_loaded(variant, variant_id, base, VARIANTS[variant_id][&'clones']): continue

		# Guard against a vacuous pass: if BOTH licenses somehow came back empty, comparing them
		# would be [] == [] and this test would go green on two broken files.
		var base_gear_count:int = 0
		for rank:int in [1, 2, 3]: base_gear_count += _gear_ids(base.get_rank(rank)).size()
		assert_gt(base_gear_count, 0, '%s actually grants gear to compare against.' % base.compcon_id)

		for rank:int in [1, 2, 3]:
			assert_eq(_gear_ids(variant.get_rank(rank)), _gear_ids(base.get_rank(rank)),
				'%s rank %d grants the same gear as %s.' % [variant_id, rank, base.compcon_id])

func test_every_variant_grants_only_its_own_frame():
	# The one thing that must NOT be cloned: the base license's frame.
	for variant_id:StringName in VARIANTS:
		var variant:UnlockTree = ContentLibrary.get_license_tree(variant_id)
		if not _loaded(variant, variant_id): continue

		var expected:Array[StringName] = [VARIANTS[variant_id][&'grants']]
		assert_eq(_frame_ids(variant), expected, '%s grants exactly %s.' % [variant_id, expected[0]])

func test_every_variant_grants_its_frame_at_rank_2():
	# The book says "at rank II", and get_primary_frame() - which the catalog UI and
	# UnlockTree.license_name() both go through - only ever looks at rank 2.
	for variant_id:StringName in VARIANTS:
		var variant:UnlockTree = ContentLibrary.get_license_tree(variant_id)
		if not _loaded(variant, variant_id): continue

		var primary:Frame = variant.get_primary_frame()
		assert_true(is_instance_valid(primary), '%s grants a frame at rank 2.' % variant_id)
		if is_instance_valid(primary):
			assert_eq(primary.compcon_id, VARIANTS[variant_id][&'grants'], 'And it is the variant.')

func test_every_variant_is_owned_by_horus():
	# Ownership comes from the mirror path - resgrp_man_horus globs **/horus/**.tres under
	# res://content - so this guards the folder a variant lives in as much as the resource itself.
	for variant_id:StringName in VARIANTS:
		assert_eq(Manufacturer.get_id_for(variant_id), &'horus', '%s is a HORUS license.' % variant_id)

func test_variant_license_levels_count_as_horus_for_core_bonuses():
	# Clause 3, and the whole reason the workaround is a manufacturer move rather than a
	# .tres_ext.gd on the base license. pilot_core.gd:283 resolves each license's manufacturer with
	# Manufacturer.get_id_for(tree.compcon_id) and sums ranks per manufacturer, so levels spent in
	# a HORUS-owned clone are HORUS levels - exactly what the book asks for, with no engine change.
	for variant_id:StringName in VARIANTS:
		var variant:UnlockTree = ContentLibrary.get_license_tree(variant_id)
		if not _loaded(variant, variant_id): continue
		var base_manufacturer := Manufacturer.get_id_for(VARIANTS[variant_id][&'clones'])

		var pilot := _pilot_with({variant_id: 3}, 3)
		var counts := pilot.get_manufacturer_license_counts()
		assert_eq(counts.get(&'horus', 0), 3, 'LL3 in %s is 3 HORUS levels.' % variant_id)
		assert_eq(counts.get(base_manufacturer, 0), 0, 'And 0 %s levels.' % base_manufacturer)
		assert_eq(pilot.get_available_cb_count(&'horus'), 1, 'Which buys a HORUS core bonus.')
		assert_eq(pilot.get_available_cb_count(base_manufacturer), 0, 'And no %s one.' % base_manufacturer)

func test_the_mutual_exclusivity_clause_is_not_enforced():
	# Clause 1, which the engine cannot express: nothing stops a pilot taking both the variant and
	# the license it clones, and doing so hands them both frames. This is a KNOWN, ACCEPTED
	# divergence from the book, pinned here rather than left implicit - if a future modkit gains a
	# mutual-exclusivity system this test goes red and we should implement the rule properly.
	#
	# It is not an exploit: both licenses cost their own levels, the duplicated gear is the same
	# kits, and core bonus totals are still capped at get_cb_max() = license_level / 3. Taking both
	# diversifies which manufacturers' core bonuses are reachable; it does not grant more of them.
	for variant_id:StringName in VARIANTS:
		var base_id:StringName = VARIANTS[variant_id][&'clones']
		var variant:UnlockTree = ContentLibrary.get_license_tree(variant_id)
		var base:UnlockTree = ContentLibrary.get_license_tree(base_id)
		if not _both_loaded(variant, variant_id, base, base_id): continue

		var pilot := _pilot_with({variant_id: 3, base_id: 3}, 6)
		var frames:Array[StringName] = []
		for progress:RankProgress in pilot.licenses:
			for frame:Frame in progress.get_unlocked_frames(): frames.append(frame.compcon_id)

		assert_true(frames.has(VARIANTS[variant_id][&'grants']), 'Holding both grants the variant.')
		assert_true(frames.size() == 2, 'And the base frame too - the rule is unenforced.')
		assert_eq(pilot.get_cb_max(), 2, 'Six license levels still cap core bonuses at two.')

# ============================== helpers ==============================

## A bare PilotCore holding the given licenses. get_manufacturer_license_counts and
## get_available_cb_counts read only `licenses`, `core_bonuses` and `license_level`, so this needs
## no gamemaster and no PilotCore.create() side effects.
func _pilot_with(ranks_by_license_id:Dictionary, license_level:int) -> PilotCore:
	var pilot := PilotCore.new()
	pilot.license_level = license_level
	for license_id:StringName in ranks_by_license_id:
		var progress := RankProgress.new()
		progress.tree = ContentLibrary.get_license_tree(license_id)
		progress.rank = ranks_by_license_id[license_id]
		pilot.licenses.append(progress)
	return pilot

func _gear_ids(unlock_rank:UnlockRank) -> Array[StringName]:
	var ids:Array[StringName] = []
	if unlock_rank == null: return ids
	for kit:Kit in unlock_rank.granted_gear: ids.append(kit.compcon_id)
	return ids

func _frame_ids(tree:UnlockTree) -> Array[StringName]:
	var ids:Array[StringName] = []
	for rank:int in [1, 2, 3]:
		var unlock_rank:UnlockRank = tree.get_rank(rank)
		if unlock_rank == null: continue
		for frame:Frame in unlock_rank.granted_frames: ids.append(frame.compcon_id)
	return ids

func _loaded(tree:UnlockTree, tree_id:StringName) -> bool:
	assert_true(is_instance_valid(tree), '%s is in the licenses index.' % tree_id)
	return is_instance_valid(tree)

func _both_loaded(a:UnlockTree, a_id:StringName, b:UnlockTree, b_id:StringName) -> bool:
	return _loaded(a, a_id) and _loaded(b, b_id)

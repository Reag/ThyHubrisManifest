# Copyright (c) 2026 Wickworks ♡ Lancer Tactics v1.3.3
# Clauses 1-2: "After hitting a target with a ranged attack, you may activate your core..."
#
# on_resolution, NOT on_hit. apply_on_hits (event_unit_attack.gd:83-88) runs BEFORE the weapon's own
# damage is applied -- the weapon's damage events are only QUEUED at that point and don't actually
# EXECUTE until event_unit_attack_declared.gd:199, which runs later, after the whole declared attack's
# per-target rolls have all resolved. Offering Mourning Call from on_hit meant it always struck a
# full-health target, so clause 7 ("if this damage destroys the target") almost never triggered --
# inverting a finisher into an ability that (almost) never finishes anything.
#
# on_resolution runs from event_unit_attack_declared.gd:211, AFTER core.execute_events(damage_events)
# at :199 -- i.e. after the weapon's own damage has actually landed. That's exactly the engine's own
# advice at that call site ("timings like Fold Space use this to exile after the heat is applied"),
# and it's what makes Mourning Call an actual finisher: the weapon wounds the target, then this hits
# for the kill.
#
# never on_crit -- event_unit_attack.gd calls apply_on_hits() and THEN apply_on_crits() on a critical
# hit (event_unit_attack.gd:85-93), so anything placed in on_crit would run IN ADDITION to on_hit/
# on_resolution, not instead of it. action_mourning_call.gd reads the crit off the attack summary
# instead.
#
# The ranged gate lives on buff_mourning_call.tres (BuffWeaponTypeOnHit.weapon_types_forbidden =
# [MELEE]) -- by the time this effect runs, that filter has already passed.
#
# `apply_on` (the @export on OnHitEffect, on_hit_effect.gd:12) is left at its default (ON_HIT) even
# though the trigger is now on_resolution: OnHitEffect.apply_on_resolutions (on_hit_effect.gd:106-112)
# calls on_resolution() unconditionally for every effect handed to it -- it never reads `apply_on`,
# unlike apply_on_hits/apply_on_crits, which gate should_abort()/apply_statuses_and_buffs() on it.
# This effect has empty statuses/buffs arrays, so `apply_on` has no observable effect either way;
# leaving the default avoids implying a distinction the field doesn't actually enforce on this path.
extends OnHitEffect

const KEENING_KIT_ID := &'cp_the_keening'
const MOURNING_CALL_ACTION_ID := &'action_mourning_call'

func on_resolution(activation:EventCore) -> void:
	var unit:Unit = activation.context.unit
	if not Unit.is_valid(unit): return

	var mourning_call := SpecificAction.from_id(unit, KEENING_KIT_ID, MOURNING_CALL_ACTION_ID)
	if not SpecificAction.is_valid(mourning_call): return

	# apply_on_resolutions runs once for the WHOLE declared attack (event_unit_attack_declared.gd:211),
	# not once per target the way apply_on_hits was -- so, unlike the old on_hit(activation,
	# attacked_unit) signature, we aren't handed a target and have to find one ourselves.
	#
	# At THIS stage `activation` is the event_unit_attack_declared core itself: EventUnitAttackDeclared.
	# get_required_context() lists Context.PROP.resource, its execute() reads
	# `var declared_summary:DeclaredAttackSummary = context.resource`, and apply_on_resolutions is
	# called with that same core -- so activation.context.resource IS the DeclaredAttackSummary
	# directly here. That's a different hop count than action_mourning_call.gd's activate(), where
	# (per that file's own comment) the summary sits one level further out, at
	# context.event.context.resource. Verified against THIS call chain rather than assumed to match.
	var summary = activation.context.resource # DeclaredAttackSummary
	if not DeclaredAttackSummary.is_valid(summary): return

	# Targets the weapon's own damage already killed (event_unit_attack_declared.gd:199 has already
	# run by the time apply_on_resolutions does) are correctly out of the running here: the trait
	# teleports the Banshee adjacent to a target, and a dead unit has no tile to be adjacent to.
	# Filter with Unit.is_valid rather than trusting the summary's hit list to have been pruned.
	var living_hit_units:Array[Unit] = Unit.filter_for_valid(summary.get_all_hit_units())
	if living_hit_units.is_empty(): return

	# Multiple targets: a single-target ranged weapon only ever produces one hit here, but nothing
	# stops an AoE weapon from hitting several, and the trait text only ever promises the Banshee
	# gets ONE finishing blow ("a target"). There's no fictional basis to prefer one surviving hit
	# target over another (lowest health, first rolled, etc. would all be arbitrary), so this just
	# takes the first one rather than pretending array order encodes a real choice. If a genuine
	# multi-target case turns up in play, that's a player-facing pick to add here -- not something to
	# fake silently.
	var attacked_unit:Unit = living_hit_units.front()

	# Don't ask the player to pay a core point for a teleport that cannot happen. The teleport
	# itself is Task 2's job; this only needs the check so the prompt is honest.
	if not _has_free_adjacent_tile(unit, attacked_unit): return

	var confirmed:bool = await choice_bus.quick_yesno(
		unit.tile(),
		tr('battle.confirm.use').format({action = Translate.action(mourning_call.gear.kit, mourning_call.action, 'name')})
	)
	if not Unit.is_valid(unit) or not confirmed: return

	# Pass attacked_unit explicitly as choose_and_use's target_unit_or_tiles. decompose_variant_targets
	# turns that into context.target_unit on the event_gear_activate it builds for the chosen action
	# (common_action_util.gd:595-598, 606-607, 714-715) -- action_mourning_call.gd's activate() now
	# reads that directly. (The old on_hit-stage code didn't need this: `activation` there WAS the
	# per-target event_unit_attack core, which carries its own target_unit. That core doesn't exist at
	# on_resolution's altitude -- see action_mourning_call.gd for the other half of this change.)
	await CommonActionUtil.choose_and_use(
		activation, mourning_call, [mourning_call], CommonActionUtil.choose_and_use_spend_action, attacked_unit
	)

# The teleport lands next to the TARGET, not next to the Banshee -- so the check has to walk
# target_unit's neighbours, not teleporting_unit's. (This was Defect 1: the old code checked
# teleporting_unit's own neighbours, which is nearly always free at ranged distance and
# validated nothing.)
#
# If teleporting_unit is ALREADY adjacent to target_unit, one of target_unit's adjacent tiles is
# teleporting_unit's own current tile. Occupation.calculate_for explicitly excludes a unit from
# blocking its own current tile (pathfinder.gd's "other_unit == unit: return false"), so that
# tile still reads as standable and this correctly returns true -- the teleport is then a no-op
# rather than "impossible", which is the right call: the Banshee doesn't need a free tile to
# stay exactly where it already is. Occupying_size (2+ frames) is likewise already handled by
# Occupation/is_tile_standable, so no extra size-specific logic is needed here.
func _has_free_adjacent_tile(teleporting_unit:Unit, target_unit:Unit) -> bool:
	var movement_type := MovementType.create_for_involuntary(teleporting_unit)
	movement_type.teleport = true
	var katamari := Katamari.create(teleporting_unit)
	for tile:Vector2i in UnitTile.get_adjacent_tiles(target_unit):
		if Pathfinder.is_tile_standable(teleporting_unit, tile, movement_type, katamari): return true
	return false

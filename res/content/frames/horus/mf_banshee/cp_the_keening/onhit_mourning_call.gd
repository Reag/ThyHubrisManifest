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

## The teleport's feasibility test and its landing set both live on the action itself, so the offer
## and the thing being offered can never drift apart -- see that file's "shared vocabulary" section.
const MourningCall := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/action_mourning_call.gd')

const KEENING_KIT_ID := &'cp_the_keening'
const MOURNING_CALL_ACTION_ID := &'action_mourning_call'

func on_resolution(activation:EventCore) -> void:
	var context := activation.context
	if not Unit.is_valid(context.unit): return

	# NOT `context.unit` - THAT MAY NOT BE THE BANSHEE. action_attack.gd:233 assigns
	# `specific.unit = get_attacker_relay(...)` as the FIRST line of every attack activation, and To
	# Bend Reality's relay buff swaps in the bend proxy standing on the tear. event_unit_attack_declared
	# then builds every downstream event with that proxy as context.unit (its own comment at :28 says
	# "may be a throughbolt round"), and this on-hit effect runs off that same core. So on a bent
	# attack `context.unit` is a dep_bend_proxy_banshee, which owns no cp_the_keening: the
	# SpecificAction.from_id below came back invalid and Mourning Call was silently never offered.
	#
	# Unit.get_attacker (unit.gd:276-283) is the engine's own undo for that swap - it returns self for
	# a unit carrying SET_ATTACK_ROOT and get_owner_unit_or_self() otherwise, and
	# TargetActionUtil.create_targeting_proxy (target_action_util.gd:284) calls
	# `proxy.state.set_owner(base_unit)`, so our proxy resolves back to the Banshee. The precedent is
	# one line below that comment: event_unit_attack_declared.gd:29 does exactly this to find the
	# `owner` it reads weapon mods and ONHIT_EFFECT buffs from - which is why this effect is reached
	# at all on a bend, and why reading context.unit raw here was inconsistent with the very call that
	# delivered us. On an ordinary attack get_attacker returns the attacker itself, so this is a
	# no-op there.
	var unit:Unit = context.unit.get_attacker(context)
	if not Unit.is_valid(unit): return

	var mourning_call := SpecificAction.from_id(unit, KEENING_KIT_ID, MOURNING_CALL_ACTION_ID)
	if not SpecificAction.is_valid(mourning_call): return

	# PLAYTEST FIX 6.3. action_mourning_call.tres sets consumes_cp = true, so with the core point
	# already spent the activation dies inside UnitAction with NO_CORE_POWER -- a console line and
	# nothing else. Before this check, that meant EVERY subsequent ranged hit for the rest of the
	# mission raised the prompt again and then did nothing at all when accepted.
	#
	# unit.core.has_core_power directly, NOT UnitAction.can_activate_gear: can_activate_gear also
	# consults Action.is_available_to_activate, and the planned gear-bar fix overrides exactly that to
	# false so Mourning Call stops rendering as a clickable no-op. Routing this gate through
	# can_activate_gear would then switch the whole trait off the moment that lands.
	if not unit.core.has_core_power: return

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

	# Don't ask for a core point for a teleport that cannot happen. This is the exact set activate()
	# will offer the player to land in, so an offer made here is always an offer that can be honoured
	# -- and it is also where GRAPPLED/SHUTDOWN are refused (playtest fix 6.5): the prose licenses
	# "even while IMMOBILIZED" and nothing more, but the involuntary MovementType that delivers that
	# waives all three at once. See MourningCall.landing_tiles / is_teleport_blocked.
	if MourningCall.landing_tiles(unit, attacked_unit).is_empty(): return

	# PLAYTEST FIX 6.4: only ASK a player. An AI Banshee was raising its own decision as a human
	# yes/no dialog -- the player was being asked whether the enemy should spend its core power.
	# Vanilla guards every one of these on is_player_controlled and gives the AI a flat default
	# (action_blinkspace_jump.gd:14, action_mag_parry.gd:29, action_consume_lock_on.gd:52-56); yes is
	# the default here, as it is there -- Mourning Call is a finisher an AI should take when offered.
	var confirmed:bool = true
	if unit.is_player_controlled():
		confirmed = await choice_bus.quick_yesno(
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
	# PLAYTEST FIX 6.1: choose_and_use_no_spend, NOT choose_and_use_spend_action.
	#
	# `using` and `chosen` are the SAME SpecificAction here -- this on-hit effect is not choosing
	# between weapons, it is offering exactly one action -- and choose_and_use bills them separately:
	# the child activation is flagged AS_FREEBIE and additionally carries a deferred_spend that spends
	# the parent non-freebie. With spend_action that meant UnitAction.spend ran TWICE for one
	# activation. unit.state.actions is inside spend()'s `if not as_freebie` guard so the QUICK was
	# charged once and the action-economy spec never noticed, but spend_core_power,
	# increment_action_usage_for_action, log_usage and popcorn_usage are all outside it -- two "-CP"
	# popups, two barks, two log lines, two recorded uses, every single time.
	#
	# no_spend makes the deferred parent spend a no-op; action_mourning_call.gd's activate() then does
	# the one real spend itself, explicitly stripping AS_FREEBIE so the QUICK the author chose is
	# still charged. See that file's activate() for the other half.
	# PLAYTEST FIX 8.2: open the offer window around the hand-off, and only around it.
	#
	# Mourning Call refuses to activate at any other time, which is what takes it off the gear bar --
	# clicked cold it has no target and does nothing. That refusal runs on THIS activation too:
	# event_gear_activate.check_specific_context calls UnitAction.can_activate_gear on the event
	# choose_and_use builds, and AS_FREEBIE does not exempt it. See action_mourning_call.gd's
	# is_available_to_activate for the full trace. Closed immediately afterwards, on every path,
	# including the one where the player declines inside choose_and_use.
	MourningCall.open_offer_window(mourning_call.gear)
	await CommonActionUtil.choose_and_use(
		activation, mourning_call, [mourning_call], CommonActionUtil.choose_and_use_no_spend, attacked_unit
	)
	MourningCall.close_offer_window(mourning_call.gear)

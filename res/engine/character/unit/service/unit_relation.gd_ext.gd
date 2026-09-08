# Script extension on the UnitRelation autoload. It carries TWO UNRELATED RULES, because a
# .gd_ext.gd's path IS its declaration - there is nowhere else either of them can live.
#
#   1. KRAKEN (mf_kraken)     - grappled characters count as adjacent; plus a tangibility workaround
#                               that is explicitly temporary. Both below, down to the EARTHSTEP banner.
#   2. NUCKELAVEE (Earthstep) - watchers standing in difficult terrain cannot OVERWATCH it.
#                               The last section of this file. NOT part of the workaround.
#
# Keep them fenced. Anything added later gets its own banner too.
#
# Makes characters the Kraken has grappled count as adjacent to it.
#
#   "Characters grappled this way count as though they are |adjacent| and within |Range 1| of the
#    Kraken."
#
# There is no vanilla hook for this - "adjacency_range" appears nowhere in engine/ - so adjacency
# has to be widened at its source. UnitRelation is an autoload, which is exactly the case Wickworks
# converted these services to autoloads for (see project.godot's autoload list and Godot #83542), so
# a script extension is the sanctioned route rather than replacing the file.
#
# UnitRelation.is_adjacent is defined as adjacent_characters(unit).has(other_unit), so widening this
# one function covers both halves of the sentence: the adjacency check and anything measuring Range
# 1 off it.
#
# Deliberately narrower than the third-party House Guard talent, which adds a blanket "everything
# within N counts as adjacent" buff hook. This keys on the grapple itself, so it can only ever
# affect a unit actually holding someone, and it composes with that mod rather than competing.
extends "res://engine/character/unit/service/unit_relation.gd"

## Kits whose grapples reach: gear that declares an attachment ignoring the adjacency requirement.
## Read off the passive rather than hardcoding mt_my_domain, so any later Kraken gear granting a
## reaching grapple - or another mod's - is covered by the same rule.
static func grapples_at_distance(gear:GearCore) -> bool:
	if not GearCore.is_valid(gear): return false
	return gear.get_passives_of_type(PassiveAttachment).any(
		func(passive:PassiveAttachment) -> bool:
			return passive.is_grapple and passive.ignores_adjacency_requirement
	)

## Both directions. Adjacency is symmetric everywhere else in the engine - is_adjacent(a, b) and
## is_adjacent(b, a) are the same question - so widening only the Kraken's view would leave a
## grappled character unable to swing back at something the Kraken counts as being in its face.
static func adjacent_characters(unit:Unit) -> Array[Unit]:
	var adjacent_units := super.adjacent_characters(unit)
	if not Unit.is_valid(unit): return adjacent_units

	# Characters we are holding.
	for grapple:SpecificAction in UnitCondition.get_outgoing_grapples(unit):
		if not grapples_at_distance(grapple.gear): continue
		_append_valid(adjacent_units, grapple.unit)

	# Whoever is holding us.
	for grapple:SpecificAction in UnitCondition.get_incoming_grapples(unit):
		if not grapples_at_distance(grapple.gear): continue
		_append_valid(adjacent_units, grapple.unit)

	return adjacent_units

static func _append_valid(units:Array[Unit], unit:Unit) -> void:
	if not Unit.is_valid(unit): return
	if units.has(unit): return
	units.append(unit)

# ============================================================================================
# TANGIBILITY. Everything from here down to the EARTHSTEP banner at the bottom of this file is a
# WORKAROUND for a limitation of modkit 1.3.3 and is meant to be deleted, not maintained. The
# Earthstep section below it is NOT part of this and must survive the removal.
#
# The faithful reading is that the Kraken genuinely holds both tangibility states, and that a
# character it has grappled genuinely gains INTANGIBLE for its turn. Neither can be expressed today,
# because applying or clearing the status runs UnitCondition.handle_intangibilty_changing
# (unit_condition.gd:256-288, reached from the apply path at :142 and the clear path at :206) which
# calls Katamari.dettach_everything UNCONDITIONALLY. A Kraken flipping status per turn would drop
# every prisoner every turn, and a prisoner given the status would be released by the act of
# receiving it. So nothing here touches the status; can_affect is widened instead.
#
# TO REMOVE THIS, once an engine can express dual tangibility - the Kraken genuinely holding both
# states, and a held character genuinely gaining INTANGIBLE for the length of its turn:
#   - STOP. THE WIDENED BRANCH IS NO LONGER THE KRAKEN'S ALONE. It now also carries the BANSHEE's
#     tear hook - the `if not tear_bridges(...)` line inside the `if not tangibility_line_is_bridged`
#     block - AND the grant half of the BANSHEE's bend rule - the
#     `or bend_proxy_tangibility_matches(...)` disjunct feeding that same
#     `tangibility_line_is_bridged` local - because GDScript permits only one can_affect per script
#     and the Banshee had nowhere else to put either. See the BANSHEE banner at the bottom of this
#     file. Deleting can_affect by following the steps below would silently take BOTH the tear window
#     and the bend rule's grant with it, and nothing at the deletion site would warn you. EXTRACT
#     both into the replacement first: they belong wherever "vanilla refused, and tangibility was the
#     only objection" is decided.
#   - the bend rule's REFUSAL half is NOT inside the widened branch - `bend_proxy_tangibility_differs`
#     is called from its own early-return near the top of can_affect, right after the self
#     short-circuit and before the cut-off guards, because it must run BEFORE super (super allows a
#     tangible proxy against a tangible target, and nothing downstream can take that back). Deleting
#     can_affect takes this line too. EXTRACT it into whatever now runs first in the replacement -
#     the check has no dependency on the Kraken machinery being deleted around it.
#   - delete can_affect outright: its self short-circuit, the bend refusal, both cut-off guards, the
#     widened branch and the bridged_by_the_black_sea local that exists only to feed that branch.
#     Delete tangibility_is_the_only_objection and is_reachable_from_the_black_sea with it; both are
#     can_affect helpers and have no other caller. Every pairing they arbitrate is answered by
#     vanilla's own can_affect once the statuses are real - the Kraken reaches the intangible because
#     it IS intangible, and a prisoner is cut off from its tangible allies for the same reason while
#     still reaching its captor and any intangible company. That is the whole of the workaround.
#   - do NOT delete counts_as_every_tangibility with them. It has two jobs, and only one is the
#     workaround. Inside can_affect it widens tangibility; inside cut_off_during_own_turn it answers a
#     RULES question - "is this character held by a Kraken that has the Tide up" - which is precisely
#     the question the replacement must ask before it applies INTANGIBLE to the prisoner. Inline it
#     into cut_off_during_own_turn, or rename it to what it actually tests (has_the_tide_up), and keep
#     it. Deleting it outright leaves cut_off_during_own_turn calling a function that is not there.
#   - cut_off_during_own_turn therefore MOVES rather than stays: it stops being a can_affect helper
#     and becomes the condition on which the replacement applies the status at the start of the
#     prisoner's turn and clears it at the end. Its is_taking_turn test is the same test either way.
#   - spec/test_the_all_consuming_tide.gd asserts the RULES rather than this mechanism, so it must
#     keep passing unchanged. If it does not, the replacement is not equivalent.
# ============================================================================================

const TIDE_BUFF_ID := &'buff_the_all_consuming_tide'

## The Tide's mark. Read through the buff rather than the frame so the rule follows the ability, not
## the chassis: a Kraken that has not raised the Tide is an ordinary character.
static func counts_as_every_tangibility(unit:Unit) -> bool:
	if not Unit.is_valid(unit): return false
	return UnitCondition.has_buff(unit, TIDE_BUFF_ID)

## The Kraken currently holding this character, if the character is taking its turn and that Kraken
## has the Tide up. Null otherwise.
##
## Ordered for cost, not for reading. can_affect runs inside AI targeting loops and per-tile
## filtering, and exactly one unit on the map has is_taking_turn set (unit_battle_state.gd:35), so
## testing that plain bool first discards almost every call before any grapple lookup runs.
static func cut_off_during_own_turn(unit:Unit) -> Unit:
	if not Unit.is_valid(unit): return null
	if not unit.state.is_taking_turn: return null
	for grapple:SpecificAction in UnitCondition.get_incoming_grapples(unit):
		if counts_as_every_tangibility(grapple.unit): return grapple.unit
	return null

## Vanilla refuses any interaction across the tangibility line (unit_relation.gd:397). The Tide
## exempts the Kraken from that line in both directions - it is asked as can_affect(a, b) and
## can_affect(b, a) at different call sites, and answering only one would let the Kraken strike
## something that could not strike back.
##
## Everything else is left to super, so no other pair of units on the map is affected.
static func can_affect(origin_unit:Unit, target_unit:Unit, ignore_invulnerability := false) -> bool:
	# Nothing is ever cut off from ITSELF. Left to the guards below, a cut-off prisoner asked about
	# itself would be refused - it is neither its own captor nor genuinely INTANGIBLE - where vanilla
	# says yes and so would the faithful implementation, since a really-INTANGIBLE prisoner has the
	# same tangibility on both sides of unit_relation.gd:397. The refusal would be silent and wide:
	# map_state.gd:320 filters a tile's unit list through this, so a self-including AoE would miss its
	# own caster; ai_action_decider.gd:386 would drop the self-entry from the AI's score dictionary;
	# tilepicker_compcon.gd:379 would omit the prisoner's own crosshair.
	#
	# Deferred to super rather than answered `true` outright: exile and invulnerability still refuse a
	# unit its own reach in vanilla, and this clause has no business changing that.
	if origin_unit == target_unit:
		return super.can_affect(origin_unit, target_unit, ignore_invulnerability)

	# BANSHEE (To Bend Reality). A bend is judged on the Banshee's tangibility, not the proxy's.
	# This must run before super, because super ALLOWS a tangible proxy against a tangible target and
	# there is no later hook that can take it back.
	if bend_proxy_tangibility_differs(origin_unit, target_unit): return false

	# A held character's turn is spent in the black sea: it may reach its captor, and anything else
	# that is itself intangible, and nothing at all besides. Symmetric, so its own allies cannot
	# reach in either.
	#
	# Each guard records whether it cleared the pairing directly, rather than leaving that fact to be
	# re-derived later from Unit.is_valid(..._captor). Reading the flag tells the truth only as long as
	# it is read after the guards that set it, and only for as long as neither guard below is reordered
	# or joined by a third - a coupling worth naming rather than leaving to be discovered by whoever
	# edits this next.
	var bridged_by_the_black_sea := false
	var origins_captor := cut_off_during_own_turn(origin_unit)
	if Unit.is_valid(origins_captor):
		if not is_reachable_from_the_black_sea(target_unit, origins_captor): return false
		bridged_by_the_black_sea = true
	var targets_captor := cut_off_during_own_turn(target_unit)
	if Unit.is_valid(targets_captor):
		if not is_reachable_from_the_black_sea(origin_unit, targets_captor): return false
		bridged_by_the_black_sea = true

	if not super.can_affect(origin_unit, target_unit, ignore_invulnerability):
		# The tangibility mismatch is the ONLY refusal the Tide overturns. Exile, invulnerability and
		# shard separation still stand, so this re-checks that everything else would have allowed it.
		if not tangibility_is_the_only_objection(origin_unit, target_unit, ignore_invulnerability):
			return false
		# A pairing the guards above already cleared still needs the same tangibility bridge the
		# Kraken gets for itself below - the guards only rule out FORBIDDEN pairings, they do not by
		# themselves cross the tangibility line. Reaching one's own captor needs no separate bridge:
		# cut_off_during_own_turn (above) only ever names a Kraken with the Tide buff up, so
		# counts_as_every_tangibility(target_unit) already covers that pairing on its own. The
		# black-sea bridge is load-bearing only for the other cleared case - a cut-off prisoner
		# reaching company that is genuinely INTANGIBLE rather than the Kraken.
		var tangibility_line_is_bridged := (
			counts_as_every_tangibility(origin_unit) or counts_as_every_tangibility(target_unit)
			or bridged_by_the_black_sea
			or bend_proxy_tangibility_matches(origin_unit, target_unit) # BANSHEE (To Bend Reality)
		)
		if not tangibility_line_is_bridged:
			# BANSHEE (Tear) hook. GDScript has no way to layer a second `can_affect` in this same
			# file - see the BANSHEE banner at the bottom of the file for why - so the tear check is
			# wired in HERE, at the one point that already means "the Tide did not bridge this pair
			# and tangibility is the only remaining objection". A tear only ever turns this `false`
			# into a `true`; it changes nothing about the Kraken's own rule above.
			if not tear_bridges(origin_unit, target_unit): return false
	return true

## What a cut-off character may still touch: the Kraken holding it, and anything genuinely INTANGIBLE.
##
## Missing information must never change the answer away from vanilla's - but which way that cashes
## out depends on which way a "yes" moves the outcome. tangibility_is_the_only_objection below
## LICENSES WIDENING: answering yes about a unit it knows nothing about would grant reach vanilla
## never granted, so it answers no. This helper is consulted only to DENY: answering no about a unit
## it knows nothing about would take away reach the guards above were about to allow, so it answers
## yes instead. That leaves the guard clause in can_affect unable to fire on missing information, and
## vanilla's own invalid-unit answer (unit_relation.gd:394, "return TRUE if we don't have enough
## information") is what actually decides the pairing.
##
## Answering yes on that invalid-unit path also makes the calling guard set bridged_by_the_black_sea,
## which is spurious but harmless: super.can_affect already answers true whenever either unit is
## invalid, so the branch that reads the flag is never reached for a pairing that got here this way.
static func is_reachable_from_the_black_sea(other_unit:Unit, captor:Unit) -> bool:
	if not Unit.is_valid(other_unit): return true
	if other_unit == captor: return true
	return other_unit.has_status(Lancer.STATUS.INTANGIBLE)

## Would can_affect have said yes but for the tangibility line? Mirrors unit_relation.gd:393-403 with
## that one comparison removed - except at line 394, where vanilla returns true for an invalid unit
## ("return TRUE if we don't have enough information") and this deliberately returns false instead:
## a predicate whose whole job is to license widening tangibility must not say yes on missing
## information. The divergence is currently unreachable - the sole call site below is gated behind
## `not super.can_affect(...)`, and vanilla already short-circuits to true for invalid units before
## this helper is ever consulted - so the inversion is defensive, not load-bearing.
static func tangibility_is_the_only_objection(origin_unit:Unit, target_unit:Unit, ignore_invulnerability:bool) -> bool:
	if not Unit.is_valid(origin_unit) or not Unit.is_valid(target_unit): return false
	if origin_unit.has_status(Lancer.STATUS.EXILED): return false
	if target_unit.has_status(Lancer.STATUS.EXILED): return false
	if not ignore_invulnerability and target_unit.has_status(Lancer.STATUS.INVULNERABLE): return false
	if origin_unit.state.in_global_shard != target_unit.state.in_global_shard:
		return origin_unit.state.in_effect_shards.any(target_unit.state.in_effect_shards.has)
	return true

# ================= END OF THE TANGIBILITY WORKAROUND. Everything below this line stays. ==========

# ============================================================================================
# EARTHSTEP (Nuckelavee). Characters standing in difficult terrain cannot OVERWATCH it.
#
#   "The Nuckelavee does not trigger |OVERWATCH| from characters in difficult terrain."
#
# The characters in the terrain are the WATCHERS. That is why this cannot be a MovementType flag:
# ignore_rxns is a property of the MOVER and cannot say "except from watchers whose footing is
# fouled". It is also why Buff.TO.ACTION_FORBIDDEN cannot do it - at that gate
# (reaction_bus.gd:120 -> can_activate_gear -> unit_action.gd:157) the SpecificAction carries the
# watcher, gear and action and NOT the mover, so a buff could only forbid overwatch outright.
#
# The seam has to see both units, and get_weapons_that_can_overwatch's signature already does:
# from_unit is the watcher, target_unit is the mover. action_overwatch.gd:21 gates on it being empty.
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-04-earthstep-design.md
# ============================================================================================

const PassiveEarthstep := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_nuckelavee/mt_earthstep/passive_earthstep.gd')

## Does this unit move like the Nuckelavee? Asked by type rather than by kit id so this engine-level
## file stays ignorant of any particular mod's content.
##
## get_all_gear(false) skips BASIC gear (loadout_core.gd:511-518), so the "any future gear" promise
## does not extend to a basic-loadout item. Nothing needs it to today.
static func has_earthstep(unit:Unit) -> bool:
	if not Unit.is_valid(unit): return false
	for gear:GearCore in unit.core.loadout.get_all_gear(false):
		if not gear.get_passives_of_type(PassiveEarthstep).is_empty(): return true
	return false

## Is this unit standing in difficult terrain? ANY occupied tile counts, matching Caustic Earth's
## occupied_tiles scan and vanilla's own dangerous-terrain loops (event_turn_end.gd:82,
## event_unit_move.gd:269). Only reachable by size-2+ units.
##
## Reads the MAP, not any particular gear's terrain zone - the rule is about the watcher's footing,
## whoever fouled it, so vanilla map terrain blinds exactly as Poisoned Soil's trail does.
static func is_footing_fouled(unit:Unit) -> bool:
	if not Unit.is_valid(unit): return false
	if not is_instance_valid(unit.map): return false
	# A hovering watcher is not standing in anything. The engine's own answer to "is this
	# character affected by difficult terrain" says so outright - MovementType.ignores_difficult_terrain()
	# (movement_type.gd:107-108) returns true when flying, and pathfinder.gd:97-98 skips difficult
	# terrain's extra cost on exactly that predicate.
	#
	# Load-bearing beyond the obvious case: MovementType.create sets `flying` from STATUS.FLYING OR
	# UnitCondition.is_in_zero_g (movement_type.gd:46), so without this a zero-g map would foul EVERY
	# watcher and turn Earthstep into map-wide overwatch immunity.
	#
	# unit.state.is_flying() is deliberately BROADER than the `flying` the pathfinder consults: it
	# also covers is_swimming (unit_battle_state.gd:251), which MovementType.create pointedly does
	# not use (movement_type.gd:45 says why). So a swimming watcher is exempt here where the
	# pathfinder would still charge it. That is the right answer for this rule - a swimmer is not
	# standing on anything either - but it is a divergence, not an accident.
	if unit.state.is_flying(): return false
	for tile:Vector2i in unit.occupied_tiles():
		if unit.map.get_surface_terrain_at(tile).difficult_terrain: return true
	return false

## Returns nothing when the watcher's footing is fouled and the mover has Earthstep.
##
## `use_normal_range_instead_of_threat` is the discriminator, and this is the ONE ASSUMPTION in the
## whole trait worth distrusting. The flag means "measure with normal weapon range rather than
## threat"; it does NOT mean "this is an overwatch". Using it as a proxy is a coincidence that holds
## across all fifteen call sites today: every caller passing the default FALSE is an overwatch-family
## reaction triggered by MOVEMENT - ms_overwatch (action_overwatch.gd:21,31), Semper Vigilo
## (action_semper_vigilo.gd:44), Eye of Midnight (action_eye_of_midnight_overwatch.gd:27,37) and the
## AI's threat model (ai_npc.gd:76) - while every caller passing TRUE is triggered by an ATTACK and
## must keep working: Punishment, Cover Me, Reflexive Blow, Flank, Fix and Flank, Instinct Mode.
##
## That the flag does not MEAN "is an overwatch" is not hypothetical: the sibling function
## get_weapons_that_can_react_against has movement-triggered callers passing `true`
## (action_covering_fire_attack.gd:41, action_moving_target.gd:48,61). They are correctly outside the
## overwatch family, but they are why this is an assumption rather than a fact.
##
## test_earthstep.gd's test_attack_triggered_reactions_are_not_suppressed pins this: a `true` call
## still returns weapons where a `false` call returns none. The day a vanilla addition breaks the
## split, that goes red rather than Punishment, Cover Me and Reflexive Blow silently dying.
##
## Suppressing the AI's threat model is a FEATURE, not collateral: NPCs stop routing around an
## overwatch that cannot fire.
##
## Conditions ordered cheapest-first: the flag is a free bool, is_footing_fouled is one to four
## dictionary lookups, and has_earthstep - which allocates an array per gear item via
## get_passives_of_type - runs only for a mover standing in someone's fouled ground.
static func get_weapons_that_can_overwatch(
	from_unit:Unit,
	target_unit:Unit,
	use_normal_range_instead_of_threat:bool = false
) -> Array[SpecificAction]:
	if (
		not use_normal_range_instead_of_threat
		and is_footing_fouled(from_unit)
		and has_earthstep(target_unit)
	):
		return [] as Array[SpecificAction]
	return super.get_weapons_that_can_overwatch(from_unit, target_unit, use_normal_range_instead_of_threat)

# ============================================================================================
# BANSHEE (Tear, and To Bend Reality below it). A tear is a window between tangible and intangible
# space; a bend is a targeting relay that must never launder an attack across that same line. Both
# rules key off tangibility and both had nowhere else to live, for the same reason - see the
# INTEGRATION NOTE below.
#
#   "They are visible to both tangible and INTANGIBLE characters, and act as a window between
#    tangible and intangible space."
#
# vanilla refuses any interaction across the tangibility line (unit_relation.gd:397). A tear
# overturns that for one pairing, in both directions, when the line between them routes through it.
#
# UNIVERSAL by agreement: any character routes through any tear, including enemies shooting the
# Banshee through its own. So this deliberately does NOT check whether either unit is a Banshee.
#
# NOTE this file already carries the Kraken's tangibility workaround, which widens the same
# function. The Tear composes with it exactly as claimed below: tear_bridges is consulted only
# where the Kraken's own branch already means "tangibility is the only remaining objection", and it
# only ever turns that NO into a YES, never the reverse.
#
# The bend does NOT share that shape, and this note used to claim it did before To Bend Reality was
# added - a maintainer reading the two together would have concluded every rule fenced by this
# banner is grant-only, which stopped being true the moment bend_proxy_tangibility_differs shipped.
# That refusal deliberately turns a vanilla YES (a tangible proxy against a tangible target) into a
# NO, because a bend must never launder an attack across the tangibility line - see its own doc
# comment below. It composes with the Kraken's Tide by its own exemption, not by sharing the Tear's
# one-directional shape: see bend_proxy_tangibility_differs below for why a party that
# counts_as_every_tangibility is let out of the refusal.
#
# INTEGRATION NOTE, a deviation from the original task brief: the brief called for a second
# top-level `can_affect` in this file, chaining to the Kraken's via `super.can_affect`. GDScript
# refuses that outright with a parse error - "Function can_affect has the same name as a previously
# declared function" (verified: it silently killed the WHOLE extension, taking the Kraken's own
# suite down with it) - because two functions of that name would live in the SAME script/class, not
# in a super/subclass pair. There is only one `can_affect` per script, and this file already has one
# (the Kraken's, above).
#
# So `tear_bridges` below is called from INSIDE the Kraken's `can_affect`, at the single point that
# already means "the Tide did not bridge this pairing and tangibility is the only remaining
# objection" - see the one added line there. That preserves the brief's intended order (the Kraken's
# widening runs first; a tear is only consulted if the Kraken did not already allow the pairing)
# without a second function of the same name, and it is the reason this section has no `can_affect`
# of its own.
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-06-banshee-tear-design.md
# ============================================================================================

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')

## Would can_affect have said yes but for the tangibility line, with a tear bridging it? Called from
## the Kraken's can_affect above, at the point where every other objection has already been ruled
## out and tangibility is the last thing standing between the pair.
##
## Ordered for cost. can_affect runs inside AI targeting loops and per-tile filtering, so the cheap
## status comparison runs before any tear lookup, and a map with no tears pays almost nothing.
##
## EYE HEIGHT, and why both directions are asked. routes_between measures its FIRST leg from the
## height it is handed and its second from the tear's own terrain, so the height it gets is the
## viewer's. Until 2026-09-08 this passed none, which measured the first leg from the ground while the
## LOS seam (unit_tile.gd_ext.gd, both overrides) passed UnitTile.effective_height - so can_affect and
## the targeting overlay could disagree about the same pair over a low wall: the crosshair appeared and
## the shot was refused, or the reverse.
##
## Passing the height fixes that but makes the call ASYMMETRIC, because the two units need not stand
## at the same height - and can_affect is asked as can_affect(a,b) at one call site and can_affect(b,a)
## at another (map_state.gd:320, ai_action_decider.gd:386, tilepicker_compcon.gd:379). A pair the
## engine believes can shoot only one way is a real defect, not a rounding error. So both directions
## are asked, each measured from its own viewer, and either one bridging is enough. That is the same
## shape TearRouting._tears_on_the_line uses for the collinearity term and for the same reason.
##
## NO RANGE CAP HERE, DELIBERATELY, AND IT IS A KNOWN GAP. Clause 7 ("an attack cannot travel more
## than half its maximum range after passing through a tear") needs a weapon, and can_affect has none
## in scope - it is a permission question about a PAIR, asked by AoE filters and AI scorers that have
## no attack in hand at all. Nothing here can enforce it; see the range-cap coverage note on
## unit_tile.gd_ext.gd's get_tiles_within for what does and what does not.
static func tear_bridges(origin_unit:Unit, target_unit:Unit) -> bool:
	if not Unit.is_valid(origin_unit) or not Unit.is_valid(target_unit): return false
	# Only ever relevant across the line. A same-tangibility pair is vanilla's business.
	if origin_unit.has_status(Lancer.STATUS.INTANGIBLE) == target_unit.has_status(Lancer.STATUS.INTANGIBLE): return false
	if not is_instance_valid(origin_unit.map): return false
	var map:MapState = origin_unit.map
	var origin_tile:Vector2i = origin_unit.tile()
	var target_tile:Vector2i = target_unit.tile()
	return (
		TearRouting.routes_between(map, origin_tile, target_tile, UnitTile.effective_height(origin_unit, true, origin_tile))
		or TearRouting.routes_between(map, target_tile, origin_tile, UnitTile.effective_height(target_unit, true, target_tile))
	)

## TO BEND REALITY. A bend never crosses the tangibility line - "instead of changing an attack's
## tangibility" is a restriction, not flavour. The relay proxy carries no status of its own, so both
## sides of that judgement have to be made on EFFECTIVE tangibility.
static func bend_proxy_tangibility_matches(origin_unit:Unit, target_unit:Unit) -> bool:
	if not (TearRouting.is_bend_proxy(origin_unit) or TearRouting.is_bend_proxy(target_unit)): return false
	return TearRouting.effective_tangibility(origin_unit) == TearRouting.effective_tangibility(target_unit)

## The refusal half. Needed as its own test because vanilla can_affect ANSWERS TRUE for a tangible
## proxy against a tangible target, so the widening hook inside can_affect - which only ever runs
## after `not super.can_affect(...)` - is never consulted for that pairing.
##
## Exempts either party being counts_as_every_tangibility (the Kraken's Tide) before comparing
## EFFECTIVE tangibility. Without this, a bend is judged more harshly than a direct attack against
## the exact same Kraken: TearRouting.effective_tangibility knows nothing about the Tide, so it
## reads the Kraken's real, untouched status - meaning an INTANGIBLE Banshee's proxy reads intangible
## while a Tide-raised Kraken still reads tangible, and this function would refuse the pairing right
## here, before super.can_affect or the widened branch below ever run. The SAME Banshee attacking the
## SAME Kraken directly, with no proxy, is allowed: super refuses on the identical raw mismatch, and
## then counts_as_every_tangibility(target_unit) bridges it a few lines down. Routing the interaction
## through a bend would flip the answer for no reason a player could name - a Kraken with the Tide up
## counts as every tangibility, so it should match whatever the far end of a bend is, exactly as it
## matches a direct attacker. The grant half (bend_proxy_tangibility_matches) needs no matching
## exemption: it feeds a disjunction in can_affect that already ORs in
## counts_as_every_tangibility(origin_unit) and counts_as_every_tangibility(target_unit) directly, so
## the Tide bridges a bend's grant on its own without this function's help.
static func bend_proxy_tangibility_differs(origin_unit:Unit, target_unit:Unit) -> bool:
	if not (TearRouting.is_bend_proxy(origin_unit) or TearRouting.is_bend_proxy(target_unit)): return false
	if counts_as_every_tangibility(origin_unit) or counts_as_every_tangibility(target_unit): return false
	return TearRouting.effective_tangibility(origin_unit) != TearRouting.effective_tangibility(target_unit)

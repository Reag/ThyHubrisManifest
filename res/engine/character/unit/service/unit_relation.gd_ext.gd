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
# TANGIBILITY. Everything below this line is a WORKAROUND for a limitation of modkit 1.3.3 and is
# meant to be deleted, not maintained.
#
# The faithful reading is that the Kraken genuinely holds both tangibility states, and that a
# character it has grappled genuinely gains INTANGIBLE for its turn. Neither can be expressed today,
# because applying or clearing the status runs UnitCondition.handle_intangibilty_changing
# (unit_condition.gd:256-288, reached from the apply path at :142 and the clear path at :206) which
# calls Katamari.dettach_everything UNCONDITIONALLY. A Kraken flipping status per turn would drop
# every prisoner every turn, and a prisoner given the status would be released by the act of
# receiving it. So nothing here touches the status; can_affect is widened instead.
#
# TO REMOVE THIS, once an engine can express dual tangibility:
#   - delete counts_as_every_tangibility, tangibility_is_the_only_objection, and can_affect's widened
#     branch (that is the whole workaround)
#   - keep cut_off_during_own_turn and is_reachable_from_the_black_sea: they are a real game rule,
#     not a workaround, and would simply be reimplemented by applying INTANGIBLE to held characters
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
	# A held character's turn is spent in the black sea: it may reach its captor, and anything else
	# that is itself intangible, and nothing at all besides. Symmetric, so its own allies cannot
	# reach in either.
	#
	# Each guard records whether it cleared the pairing, rather than leaving that fact to be
	# re-derived later from Unit.is_valid(..._captor). That local is only a correct proxy for
	# "already vetted" as long as it is read after the guard that computed it, and only for as long as
	# neither guard below is reordered or joined by a third - a coupling worth naming rather than
	# leaving to be discovered by whoever edits this next.
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
		)
		if not tangibility_line_is_bridged:
			return false
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

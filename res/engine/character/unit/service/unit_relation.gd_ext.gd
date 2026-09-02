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

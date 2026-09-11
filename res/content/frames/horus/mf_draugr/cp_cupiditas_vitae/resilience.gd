# Resilience - the Draugr's charge pool, and the only reader/writer of it.
#
#   "The Draugr has charges called Resilience, up to a maximum of 1 + its missing structure."
#
# The store is a vanilla PassiveDieCounter on cp_cupiditas_vitae, keyed "resilience", wired exactly
# as the Apocalypse Rail wires its own (cp_apocalypse_rail.tres:16-20). Going through the vanilla
# passive rather than raw GearCore state is what gets the number onto the action bar, into tooltips
# (passive_die_counter.gd:72), into the battle log and popcorn on every change (:47-53), into
# unit.update_attached_fx() (:44), and into {resilience} interpolation in effect text
# (buff.gd:190-196). None of that would exist behind a hand-rolled counter.
#
# THE CAP IS VARIABLE AND THE ENGINE'S IS NOT. PassiveDieCounter.update_value_core clamps to a fixed
# max_value (:63-67), so the .tres sets max_value = 8 purely as a hard ceiling (4 structure means the
# rules' cap can never exceed 4 today; 8 leaves room for a bonus-structure frame) and the real
# "1 + missing structure" is enforced here, on the way in.
#
# No EventCore parameter: update_value needs none, and it logs through the passive's own static
# battle_log. Callers in reactions pass the unit they already have.
extends RefCounted

const KIT_ID := &'cp_cupiditas_vitae'
const KEY := 'resilience'

static func gear(unit:Unit) -> GearCore:
	if not Unit.is_valid(unit): return null
	return unit.get_gear(KIT_ID)

## The PassiveDieCounter, or null when this unit has no core power (or a future variant drops it).
static func counter(unit:Unit) -> PassiveDieCounter:
	var core := gear(unit)
	if not GearCore.is_valid(core): return null
	return core.get_die_counter_passive()

static func count(unit:Unit) -> int:
	var die := counter(unit)
	if die == null: return 0
	return die.get_current(gear(unit))

## "up to a maximum of 1 + its missing structure". unit.get_structure_max() is unit.gd:312 (core max
## plus any state bonus); current.structure is decremented by event_unit_structure.gd:39.
static func maximum(unit:Unit) -> int:
	if not Unit.is_valid(unit): return 0
	return 1 + maxi(0, unit.get_structure_max() - unit.core.current.structure)

## Bank n, clamped by the variable cap. Returns the new count.
##
## maxi(current, ...) is deliberate: repairing structure LOWERS the cap, and a gain arriving after
## that must not quietly confiscate points banked while the Draugr was hurt. A gain only ever adds
## or does nothing.
static func gain(unit:Unit, n:int = 1) -> int:
	var die := counter(unit)
	if die == null or n <= 0: return count(unit)
	var core := gear(unit)
	var current:int = die.get_current(core)
	die.update_value(unit, core, maxi(current, mini(current + n, maximum(unit))))
	return die.get_current(core)

## Spend n. min_value = 0 in the .tres, so this stops at empty. Returns the new count.
static func spend(unit:Unit, n:int = 1) -> int:
	var die := counter(unit)
	if die == null or n <= 0: return count(unit)
	var core := gear(unit)
	die.decrease(unit, core, n)
	return die.get_current(core)

# The Carrion Beast's reach: "When targeting characters with INFECTION, your SENSORS increase by 5."
#
# ONE PLACE ANSWERS "IS THAT WITHIN MY SENSORS?" FOR THE WHOLE FRAME. The engine has no per-target
# Sensors hook: Unit.get_sensor_range() (unit.gd:305) and UnitCore.get_sensor_range()
# (unit_core.gd:404, "no bonus to this") both take no target at all. So every +5 in this mod is
# applied by its caller, and the only defence against the rule drifting between callers is that they
# all come here. Current callers: action_ceaseless_death.gd (the kill filter), onhit_spreading_stain.gd
# (the candidate sweep), passive_atrophy.gd (the aura) and buff_carrion_beast_reach.gd (the tiles).
#
# THE BONUS NEEDS THE SYSTEM, INTACT. A system that has been shot off does nothing, which is what
# gear.is_intact() means (gear_core.gd). unit.get_gear (unit.gd:220-225) also searches "nontrad"
# gear, so a Carrion Beast granted by something other than the loadout still counts.
#
# NO LINE OF SIGHT ANYWHERE HERE. Sensors is a detection range, not a firing line - the rest of the
# mod already treats it that way (onhit_spreading_stain.gd's sweep passes require_los = false and
# says why). Adding LOS here would silently change three existing behaviours.
#
# No class_name (lancer-tactics-gdscript skill); callers preload this file by its full path.
extends RefCounted

const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')

const KIT_ID := &'ms_carrion_beast'
const BONUS := 5

## Is the Carrion Beast equipped and working?
static func has_carrion_beast(draugr:Unit) -> bool:
	if not Unit.is_valid(draugr): return false
	var gear:GearCore = draugr.get_gear(KIT_ID)
	return GearCore.is_valid(gear) and gear.is_intact()

## This Draugr's effective SENSORS against ONE target.
static func sensors_against(draugr:Unit, target:Unit) -> int:
	if not Unit.is_valid(draugr): return 0
	var reach:int = draugr.get_sensor_range()
	if Unit.is_valid(target) and Infection.is_infected(target) and has_carrion_beast(draugr):
		reach += BONUS
	return reach

## The widest this Draugr's Sensors could be right now, whoever the target turns out to be. This is a
## SEARCH radius, never an answer: collect with it, then filter with within_sensors.
static func max_reach(draugr:Unit) -> int:
	if not Unit.is_valid(draugr): return 0
	return draugr.get_sensor_range() + (BONUS if has_carrion_beast(draugr) else 0)

## "within SENSORS", for this mod, everywhere.
static func within_sensors(draugr:Unit, target:Unit) -> bool:
	if not Unit.is_valid(draugr) or not Unit.is_valid(target): return false
	return UnitRelation.distance_between(draugr, target) <= sensors_against(draugr, target)

## Every infected character this Draugr can currently reach.
##
## get_characters_within (unit_relation.gd:34-43) already drops the Draugr itself, drops MARKERS
## (get_units_within, :48 and :57) and keeps only is_character(). The marker exclusion is
## load-bearing wherever the result reaches a prompt: choose_unit highlights a marker's tile and then
## cannot resolve the click, hanging the game with no cancel (memory marker-units-cannot-be-picked).
static func infected_in_reach(draugr:Unit) -> Array[Unit]:
	var found:Array[Unit] = []
	if not Unit.is_valid(draugr) or not is_instance_valid(draugr.map): return found
	found = UnitRelation.get_characters_within(
		draugr, max_reach(draugr), false,
		func(other:Unit) -> bool:
			return Infection.is_infected(other) and within_sensors(draugr, other)
	)
	return found

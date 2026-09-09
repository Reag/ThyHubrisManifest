# INFECTION: the Draugr's status. Rules text lives in localization (gear.buff_infection.effect).
#
# One buff_infection per victim carries the count in its BuffCore state under COUNT_KEY. This
# script is the only reader and writer of that key - every trait, system and spec goes through
# here, so the storage can change without touching them. No class_name (lancer-tactics-gdscript
# skill); callers preload this file.
#
# Why a buff and not a field beside UnitBattleState.burn: that class has a class_name and cannot
# be script-extended. Why one buff with a count and not N stacked copies: N copies render as N
# identical icons with no number (status_info.gd), and a single BuffCore.state int is trivial to
# decrement from a reaction.
extends RefCounted

const BUFF_ID := &'buff_infection'
const COUNT_KEY := 'infection'
## Marker passed through the end-of-turn Systems check so a buff can recognise the Infection
## check (unit_hasecheck.gd unpack_flags_and_statuses files a StringName under against_statuses).
## The engine's EventService.SAVE_FLAG enum cannot be extended from a mod, and reusing its
## CLEAR_BURN flag would let anti-burn gear help against Infection, which the rules do not say.
const CHECK_FLAG := &'reag_infection'

static func get_core(unit:Unit) -> BuffCore:
	if not Unit.is_valid(unit): return null
	return UnitCondition.get_buff(unit, BUFF_ID)

static func count(unit:Unit) -> int:
	var core := get_core(unit)
	if not BuffCore.is_valid(core): return 0
	return core.get_state(COUNT_KEY, 0)

static func is_infected(unit:Unit) -> bool: return count(unit) > 0

## Mark n Infection without the heat. Applies the buff if the target has none. Synchronous.
static func mark(event:EventCore, target:Unit, n:int, from_gear:GearCore = null) -> BuffCore:
	var core := get_core(target)
	if not BuffCore.is_valid(core): core = UnitCondition.apply_buff_id(event, target, BUFF_ID, from_gear)
	core.set_state(COUNT_KEY, core.get_state(COUNT_KEY, 0) + n)
	target.update_token()
	return core

## Apply n Infection: mark it, then the target takes n heat immediately (the rules' order).
## Tech-immune and biological targets are refused, the same way the engine refuses tech buffs.
static func apply(event:EventCore, target:Unit, n:int, from_gear:GearCore = null) -> void:
	if n <= 0 or not Unit.is_valid(target): return
	if UnitCondition.is_immune_to_tech(target): return
	mark(event, target, n, from_gear)
	var heat := {unit = target, number = n, category = Lancer.DAMAGE_TYPE.HEAT}
	if event != null and event.is_block_valid():
		await event.execute_event(&'event_unit_damage', heat)
	else: # no live block (a spec's dummy event, or a caller outside any event): the level runs it
		await X.current_level().execute_event(&'event_unit_damage', heat)

static func clear(event:EventCore, unit:Unit) -> void:
	var core := get_core(unit)
	if BuffCore.is_valid(core): UnitCondition.clear_buff(event, unit, core)

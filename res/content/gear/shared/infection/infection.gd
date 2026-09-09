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
#
# No from_gear, on purpose. A BuffCore.from_gear makes the engine clear the buff when that gear's
# owner dies (event_service.gd:71) or the gear is destroyed (event_gear_destroy.gd:42), and one
# buff here carries EVERY source's count, so the Draugr dying would wipe a victim's whole stack.
# Infection is a plague, not a maintained link; it outlives whoever applied it.
extends RefCounted

const BUFF_ID := &'buff_infection'
const COUNT_KEY := 'infection'
## Marker carried by the end-of-turn Systems check so a buff can recognise the Infection check: a
## StringName in flags_and_statuses lands in the roll context's `array` (unit_hasecheck.gd
## unpack_flags_and_statuses). buff_infection.gd calls UnitHasecheck.handle_check directly because
## the make_*_check wrappers drop that array on both engines. The engine's EventService.SAVE_FLAG enum
## cannot be extended from a mod, and reusing its CLEAR_BURN flag would let anti-burn gear help
## against Infection, which the rules do not say.
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
static func mark(event:EventCore, target:Unit, n:int) -> BuffCore:
	if n <= 0: return get_core(target)
	var core := get_core(target)
	if not BuffCore.is_valid(core): core = UnitCondition.apply_buff_id(event, target, BUFF_ID)
	core.set_state(COUNT_KEY, core.get_state(COUNT_KEY, 0) + n)
	target.update_token()
	return core

## Apply n Infection: mark it first, so anything reacting to the heat already sees the new count,
## then the target takes n heat. The rules list heat first; nothing observable depends on the order
## except that reaction visibility, which is why marking wins.
## Tech-immune and biological targets are refused, the same way the engine refuses tech buffs.
static func apply(event:EventCore, target:Unit, n:int) -> void:
	if n <= 0 or not Unit.is_valid(target): return
	if UnitCondition.is_immune_to_tech(target): return
	mark(event, target, n)
	var heat := {unit = target, number = n, category = Lancer.DAMAGE_TYPE.HEAT}
	if event != null and event.is_block_valid():
		await event.execute_event(&'event_unit_damage', heat)
	else: # no live block (a spec's dummy event, or a caller outside any event): the level runs it
		var level := X.current_level()
		if level != null: await level.execute_event(&'event_unit_damage', heat)

static func clear(event:EventCore, unit:Unit) -> void:
	var core := get_core(unit)
	if BuffCore.is_valid(core): UnitCondition.clear_buff(event, unit, core)

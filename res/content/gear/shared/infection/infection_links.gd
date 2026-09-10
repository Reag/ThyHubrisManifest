# Linked effects: "that effect instead lasts until the target clears INFECTION".
#
# Symptom binds a tech effect it did not create; Spreader binds its own slow. The list of bound
# effects lives in the Infection BuffCore's state under LINKS_KEY, so it dies with the Infection and
# is serialized with it - design 2026-09-09-draugr-design.md section 1, "Linked effects".
#
# WHY A SIBLING FILE AND NOT STATICS ON buff_infection.gd (plan decision D1): infection.gd is frozen
# and this is not its business; buff_infection.gd is the file the ENGINE instantiates, and every
# other caller in this mod preloads a plain static helper rather than a Buff script. The dependency
# runs one way - buff_infection.gd -> here -> infection.gd - so there is no cycle.
#
# RECORDS ARE STRINGS, NOT REFERENCES. BuffCore.state is serialized wholesale (buff_core.gd:45). A
# buff is identified by BuffCore.persistent_id (unique per application, buff_core.gd:15/29); a
# StatusCondition carries no id at all, so it is type + source - the same known gap Face Thy
# Judgement documents (action_face_thy_judgement.gd:98-117), stated rather than hidden.
extends RefCounted

const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')

## Infection BuffCore state: Array[String] of records.
const LINKS_KEY := 'links'

# ---------------------------------------------------------------- records

static func record_for(effect) -> String:
	if effect is StatusCondition: return 'status|%s|%s' % [effect.type, effect.source]
	if effect is BuffCore: return 'buff|%s' % effect.persistent_id
	return ''

static func records(unit:Unit) -> Array[String]:
	var core := Infection.get_core(unit)
	if not BuffCore.is_valid(core): return []
	return core.get_state_string_array(LINKS_KEY)

static func is_linked(unit:Unit, effect) -> bool:
	var record := record_for(effect)
	if record.is_empty(): return false
	return records(unit).has(record)

# ---------------------------------------------------------------- linking

## Tie one effect's lifetime to this unit's Infection. Returns false when there is no Infection to
## tie it to - the caller applies the Infection FIRST and then links.
##
## A status is switched to MANUAL here and now: StatusCondition.until is per-instance
## (status_condition.gd:6, and unit_condition.gd:15-17 modifies these resources in place precisely
## because "they're all unique"), so nothing in clear_status_until (unit_condition.gd:350-362) can
## match it again. A buff cannot be touched the same way - Buff.until is on the SHARED resource
## (buff.gd:119) - so it is held open one turn at a time by extend_tracked, below.
static func link(unit:Unit, effect) -> bool:
	var core := Infection.get_core(unit)
	if not BuffCore.is_valid(core): return false
	var record := record_for(effect)
	if record.is_empty(): return false
	if core.get_state_string_array(LINKS_KEY).has(record): return true # already bound; one record only
	if effect is StatusCondition: effect.until = Lancer.UNTIL.MANUAL
	core.append_to_array_state(LINKS_KEY, record)
	return true

# ---------------------------------------------------------------- lifetime

## "lasts until the end of their next turn", read off a live effect.
##
## Mirrors end_turn_for_statuses (unit_condition.gd:33-49): a buff's remaining life is the shared
## resource's `until` combined with the per-instance turn_count, so END_OF_NEXT_TURN with turn_count
## still 0 is the one that dies at the end of the NEXT turn; the same buff at turn_count >= 1 is
## dying at the end of THIS one, which the rules text excludes.
static func expires_at_end_of_next_turn(effect) -> bool:
	if effect is StatusCondition: return effect.until == Lancer.UNTIL.END_OF_NEXT_TURN
	if effect is BuffCore:
		match effect.base.until:
			Lancer.UNTIL.END_OF_THIS_TURN: return effect.turn_count == -1
			Lancer.UNTIL.END_OF_NEXT_TURN: return effect.turn_count == 0
	return false

## Buy every tracked BUFF one more turn, and drop records for effects that are no longer there.
## Called once per holder's end-of-turn PRE, from buff_infection.gd, BEFORE anything expires
## (event_turn_end.gd:17 vs :40). Statuses need nothing: link() already made them MANUAL.
static func extend_tracked(unit:Unit) -> void:
	var core := Infection.get_core(unit)
	if not BuffCore.is_valid(core): return
	var kept:Array[String] = []
	for record:String in core.get_state_string_array(LINKS_KEY):
		if record.begins_with('buff|'):
			var buff := find_buff(unit, record.substr(5))
			if not BuffCore.is_valid(buff): continue # gone; stop tracking it
			# MANUAL and START_OF_TURN buffs are not on a turn clock; decrementing would be noise.
			if [Lancer.UNTIL.END_OF_THIS_TURN, Lancer.UNTIL.END_OF_NEXT_TURN].has(buff.base.until):
				buff.turn_count -= 1
			kept.append(record)
		elif find_status(unit, record) != null:
			kept.append(record)
	# NOT core.set_state: BuffCore.set_state asserts on Arrays (buff_core.gd:138-140).
	core.state[LINKS_KEY] = kept

## Everything bound to the Infection ends with it. Called from buff_infection.gd's on_clear, which
## the engine runs while the Infection buff is still on the unit (unit_condition.gd:980) - clearing
## OTHER buffs from inside on_clear is vanilla's own move (buff_transfix_assassin_stunned.gd:23).
static func clear_all(event:EventCore, unit:Unit) -> void:
	var core := Infection.get_core(unit)
	if not BuffCore.is_valid(core): return
	var linked_buffs:Array[BuffCore] = []
	for record:String in core.get_state_string_array(LINKS_KEY):
		if record.begins_with('buff|'):
			var buff := find_buff(unit, record.substr(5))
			if BuffCore.is_valid(buff): linked_buffs.append(buff)
			continue
		var status := find_status(unit, record)
		if status != null: UnitCondition.clear_specific_status(event, unit, status)
	core.state[LINKS_KEY] = [] as Array[String]
	if not linked_buffs.is_empty(): UnitCondition.clear_buffs(event, unit, linked_buffs)

# ---------------------------------------------------------------- lookups

static func find_buff(unit:Unit, persistent_id:String) -> BuffCore:
	for buff:BuffCore in unit.state.buffs:
		if String(buff.persistent_id) == persistent_id: return buff
	return null

static func find_status(unit:Unit, record:String) -> StatusCondition:
	var parts := record.split('|')
	if parts.size() != 3: return null
	for status:StatusCondition in unit.state.statuses:
		if String(status.type) == parts[1] and String(status.source) == parts[2]: return status
	return null

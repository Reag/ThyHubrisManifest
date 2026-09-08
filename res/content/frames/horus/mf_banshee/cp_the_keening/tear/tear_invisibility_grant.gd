# CLAUSE 6's DELIVERY: "Attacks that pass through a tear treat targets as INVISIBLE."
#
# The PREDICATE lives in buff_tear_invisibility.gd. This file is only about getting that predicate
# onto the units that need to be carrying it, and it exists as its own file because the hand-out
# happens from TWO places that cannot see each other: action_tear.gd (when a tear is placed) and
# unit_tile.gd_ext.gd (whenever the map's occupancy changes). Duplicating it was how the two halves
# would drift.
#
# Plain RefCounted on purpose. unit_tile.gd_ext.gd is a ModLoader script extension installed onto an
# autoload very early in boot; preloading a bare script from there is the shape already proven by
# tear_routing.gd, and it avoids dragging a Resource subclass into that load.
#
# ------------------------------------------------------------------------------------------------
# WHY THE BUFF IS APPLIED WITH NO SOURCE GEAR, which is the whole point of the 2026-09-08 fix.
#
# It used to be applied with `from_gear = context.gear` (the Banshee's cp_the_keening), which made
# the BANSHEE its owner. Two engine behaviours then tore it back off at exactly the wrong moments:
#
#   1. WHISPERING STRIPPED IT. UnitCondition.handle_intangibilty_changing (unit_condition.gd:256-288)
#      runs on every tangibility change and does two sweeps: it clears buffs ON the changing unit
#      whose owner's tangibility no longer matches (guarded by `Unit.is_valid(buff_owner)` at :263),
#      and it calls clear_outgoing_buffs_from_unit for every unit whose tangibility now differs
#      (:270). So the Banshee going INTANGIBLE - the single move that makes clause 6 matter - cleared
#      clause 6 off every tangible character on the map.
#   2. THE BANSHEE'S DEATH CLEARED IT, while its tears stayed open. Same mechanism: death runs the
#      outgoing sweep with due_to_owner_dying.
#
# A source-less buff is invisible to both. `apply_buff` stores `from_gear = &''` when handed a null
# gear (unit_condition.gd:694-699), BuffCore.get_owner_unit returns null outright on an empty
# from_gear (buff_core.gd:102-105) so sweep 1's is_valid guard skips it, and
# clear_buffs_owned_by only clears `core.from_gear == gear_id` for a REAL gear's persistent_id
# (unit_condition.gd:1014-1020), which an empty StringName never equals.
#
# Nothing else needed the owner. Checked, not assumed: Buff.check_if_prohibited returns false
# outright with no owner gear (buff.gd:231-233), UnitCondition.telegraph_relevant_buffs skips
# ownerless buffs (unit_condition.gd:1047-1050 - and this buff is hide_from_player anyway),
# consume_buffs works off get_holder_unit which scans the map rather than the source
# (buff_core.gd:129-133), and apply_buff_alt's own logging already branches on
# `buff_core.from_gear.is_empty()`. The buff is INERT - a predicate granting nothing at rest - so it
# has no business being owned by anyone in the first place.
# ------------------------------------------------------------------------------------------------
extends RefCounted

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')

## Fetched from ContentLibrary by id, NOT loaded by path. A load() returns a fresh Resource whose
## compcon_id has never been assigned - that happens during ContentLibrary indexing - so applying it
## produced a buff that has_buff could never find again.
const BUFF_ID := &'buff_tear_invisibility'

## RE-ENTRANCY, since the hand-out is driven from UnitTile.update_tracking_and_statuses and applying
## a buff could in principle drive that same function again. It does not, and the reason is a
## consequence of the very null-source fix above: apply_buff_alt only asks for a tracking update when
## the buff's OWNER GEAR carries a PassiveAura (unit_condition.gd:762-766), an ownerless buff has no
## owner gear, so post_apply_buff_cache_update is handed `false` and update_cached_values_and_token(null)
## reaches UnitTile.move_to with update_statuses FALSE (unit_tile.gd:10-12). The loop is not closed.
##
## No guard flag, deliberately. One was written and removed: a static bool would strand `true` on any
## error inside the loop and silently disable clause 6 for the rest of the session - the exact failure
## tear_routing.gd's `_computing` note describes, and it has no equivalent of that file's invalidate()
## to reset it from. And it would be buying little: even if a future engine change did close the loop,
## the has_buff check below means each unit is given the buff at most once, so a re-entrant call
## terminates after one extra pass rather than recursing without bound.

## Hand clause 6's predicate to every character on the map that is not already carrying it.
##
## Handed to EVERY character, not just the Banshee, because routing is universal by design: an enemy
## may shoot the Banshee's ally through the Banshee's own tear, and get_invisibility_summary only
## reads the buff off the two units in that pair (unit_condition.gd:453). Deployables and markers are
## skipped - clause 6 says "targets", and a tear is not a character.
##
## Cheap despite the breadth: the buff carries no state, so what is handed out is a predicate rather
## than a condition, and each unit is only ever given one.
static func hand_out(map:MapState, event:EventCore) -> void:
	if not is_instance_valid(map) or not is_instance_valid(event): return
	if not is_instance_valid(ContentLibrary.get_buff(BUFF_ID)): return
	for unit:Unit in map.get_all_units():
		if not Unit.is_valid(unit): continue
		if not unit.is_character(): continue
		if UnitCondition.has_buff(unit, BUFF_ID): continue
		UnitCondition.apply_buff_id(event, unit, BUFF_ID, null) # null: see the header

## The same hand-out, but skipped entirely when no tear is open so a tear-free map pays nothing.
##
## This is the form the unit_tile.gd_ext.gd hook wants: that override runs on essentially every
## occupancy change in the game, including in missions where no Banshee exists. tear_tiles is a
## single cached pass over the unit list and is the cheapest available "is any of this relevant".
##
## The event is optional here because update_tracking_and_statuses' own `event` defaults to null
## (unit_tile.gd:15) while apply_buff_id needs one. Standing in the same dummy the engine itself
## builds two lines later (unit_tile.gd:17) is better than declining: declining would put us back
## where we started, with a unit spawned via a null-event call site never getting clause 6.
static func hand_out_if_any_tear_is_open(map:MapState, event:EventCore = null) -> void:
	if not is_instance_valid(map): return
	if TearRouting.tear_tiles(map).is_empty(): return
	if not is_instance_valid(event): event = EventCore.create(&'event_delay', {number = 0})
	hand_out(map, event)

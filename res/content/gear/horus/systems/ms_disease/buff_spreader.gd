# The Spreader contagion, and the slow that comes with it.
#
#   "Your target ... is SLOWED for as long as they have INFECTION. While they have INFECTION, any
#    character that starts their turn adjacent to the target, or moves adjacent to them for the
#    first time in a round, must make a SYSTEMS check or take 1 INFECTION."
#
# This buff sits on the VICTIM. The slow is applies_statuses in the .tres; the aura is the reaction
# below. Its lifetime is UNTIL.MANUAL and action_spreader binds it to the victim's Infection, so
# infection_links.gd clears it the moment the Infection goes - exactly "for as long as they have
# INFECTION", with no turn clock to keep in step.
#
# WHY A PLAIN Buff. does_buff_trigger (reaction_bus.gd:125-139) has no availability gate at all - no
# action economy, no reaction point, no per-round limit - which is what "any character" needs. NOT a
# BuffReactionSelf: that archetype demands the triggering unit BE the holder
# (action_reaction_self.gd:11-15), and here it is somebody else. Vanilla's precedent for the shape is
# buff_drain_systems_specter.gd, carrying the same [step, new_turn] pair at the same default POST.
#
# NO from_gear. A BuffCore.from_gear attribution is a lifetime: the engine clears attributed buffs
# when the owner dies (event_service.gd:71) and when the gear is destroyed (event_gear_destroy.gd:42).
# Infection deliberately outlives its source (infection.gd:13-16), and so must the slow tied to it -
# a Draugr dying must not cure its victims.
extends Buff

const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')

## Vanilla's shared "this unit has already been affected this round" marker: a hidden
## UNTIL.START_OF_TURN buff on the AFFECTED unit (content/gear/shared/buff_track_affection.tres),
## which therefore clears at that unit's own next turn start - unit_condition.gd:15-21, run from
## event_turn_start.gd:76, ahead of the NEW_TURN POST reactions queued at :56. Read
## action_reaction_on_coming_within.gd:86-104 for the original.
const TRACKED_AFFECTIONS_BUFF := &'buff_track_affection'
const TRACKED_AFFECTIONS_KEY := 'from_kit'
const KIT_ID := &'ms_disease'

func get_required_triggering_context() -> Array[Context.PROP]:
	return [Context.PROP.unit]

func triggers_on_event(core:BuffCore, unit:Unit, triggering_event:EventCore) -> bool:
	var mover:Unit = triggering_event.context.unit
	if not Unit.is_valid(mover) or mover == unit: return false
	if not mover.is_character(): return false # "any character"; markers and objects are not
	if not UnitRelation.is_adjacent(mover, unit): return false
	if UnitCondition.is_immune_to_tech(mover): return false # Infection is a data virus
	if not Infection.is_infected(unit): return false # "while they have INFECTION"
	return not has_already_been_affected(unit, mover)

## The marker names the HOLDER as well as the kit (plan decision D6). Two Spreader victims are two
## separate effects, so a character standing between them owes two checks - which is what vanilla's
## own once_per_round_is_specific_to_gear flag exists to express
## (action_reaction_on_coming_within.gd:32-34). This buff has no gear, so the holder's persistent id
## stands in for the gear id.
static func marker_for(holder:Unit) -> String:
	return '%s:%s' % [KIT_ID, holder.core.persistent_id]

static func has_already_been_affected(holder:Unit, mover:Unit) -> bool:
	var marker := marker_for(holder)
	for buff:BuffCore in UnitCondition.get_buffs(mover, TRACKED_AFFECTIONS_BUFF):
		if buff.get_state(TRACKED_AFFECTIONS_KEY, '') == marker: return true
	return false

# No is_infected re-check here: when the Infection clears, InfectionLinks.clear_all removes this
# buff, get_holder_unit finds nobody, and event_buff_activate refuses the queued activation
# (event_buff_activate.gd:17-19).
func activate(core:BuffCore, activation:EventCore) -> void:
	# NOTE: deliberately does NOT call super. Buff.activate's default clears the buff from the unit
	# (buff.gd:254-255); this one lives as long as the Infection does.
	var holder:Unit = activation.context.unit
	var triggering:EventCore = activation.context.event
	if not Unit.is_valid(holder) or triggering == null: return
	var mover:Unit = triggering.context.unit
	if not Unit.is_valid(mover): return
	# Re-check: triggers_on_event ran at queue time and a step can have moved them apart since.
	if not UnitRelation.is_adjacent(mover, holder): return
	if has_already_been_affected(holder, mover): return

	# The marker lasts until the affected unit's next turn start (buff_track_affection.tres, until =
	# START_OF_TURN), which is vanilla's reading of "first time in a round".
	var tracker := UnitCondition.apply_buff_id(activation, mover, TRACKED_AFFECTIONS_BUFF)
	if BuffCore.is_valid(tracker): tracker.set_state(TRACKED_AFFECTIONS_KEY, marker_for(holder))

	# A CHECK, not a save - the rules text says check, and no marker flag rides along, so the
	# make_*_check wrapper is safe here (it discards flags_and_statuses, unit_hasecheck.gd:29-30;
	# that is only a problem when a flag matters, as it does for the Infection check itself).
	var passed:bool = await UnitHasecheck.make_systems_check(activation, mover, 10, null, false)
	if activation.abort_without_unit(mover): return
	if passed: return
	await Infection.apply(activation, mover, 1)

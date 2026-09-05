# The Desperate Clawing Hands Of The Dead, bullet 1: what waits for anyone knocked down in the muck.
#
#   "Hostile characters take |1d6 AP KINETIC| when knocked |PRONE| in |difficult terrain|, and must
#    make a |HULL save| or become |IMMOBILIZED| until the end of their next turn."
#
# Triggers on STATUSES_CHANGED. UnitCondition.on_status_apply (unit_condition.gd:166) queues a virtual
# event_unit_apply_status carrying {unit = victim, category = status}, at PRE timing for an APPLIED
# status - POST is removal (reaction_bus.gd:30). So context.category is what was applied.
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-04-clawing-hands-design.md
extends ActionReaction

## Bookkeeping, not an ability the pilot uses - the core power's own rows carry the text.
func show_in_tooltip(_kit:Kit) -> bool: return false


const ClawingHands := preload('./buff_the_desperate_clawing_hands.gd')
const DAMAGE_DICE:String = '1d6'

func get_required_triggering_context() -> Array[Context.PROP]:
	return [Context.PROP.unit, Context.PROP.category]

func triggers_on_event(unit:Unit, _gear:GearCore, triggering_event:EventCore) -> bool:
	if not ClawingHands.is_active(unit): return false
	if triggering_event.context.category != Lancer.STATUS.PRONE: return false

	var victim:Unit = triggering_event.context.unit
	if not Unit.is_valid(victim) or not victim.is_character(): return false
	# "Hostile characters" - bullet 1 is hostile-only, unlike bullet 3's widening.
	if not UnitRelation.are_enemies(unit, victim): return false

	# The GROUND, not the character: see is_difficult_ground's own note for why the pathfinder's
	# definition cannot be used here.
	for tile:Vector2i in victim.occupied_tiles():
		if ClawingHands.is_difficult_ground(unit.map, tile): return true
	return false

func activate(context:Context, activation:EventCore) -> void:
	var victim:Unit = activation.context.event.context.unit
	var specific := SpecificAction.from_context(context)
	if not Unit.is_valid(victim): return

	activation.queue_events([build_damage_event(specific, victim)] as Array[EventCore])

	# The save gates the IMMOBILIZED and nothing else - the damage above is unconditional.
	var made_save:bool = await UnitHasecheck.make_save(activation, victim, specific, Lancer.HASE.HULL)
	if made_save: return
	# NOT "the damage may have finished it" - the damage above is only QUEUED as a child block and
	# resolves after this method returns. The guard is still worth having for a different reason: the
	# save is a real awaited event, and anything reacting to it could have removed the victim while we
	# were suspended.
	if not Unit.is_valid(victim): return
	# `source` = the gear's persistent_id, as all four vanilla IMMOBILIZED applications pass
	# (action_omni_harpoon.gd:57 and friends). Without it the status is unattributed in the battle log
	# and invisible to any source-keyed clear. No await: UnitCondition.apply_status contains none.
	UnitCondition.apply_status(activation, victim, Lancer.STATUS.IMMOBILIZED, Lancer.UNTIL.END_OF_NEXT_TURN, specific.gear.persistent_id)

## The hands are TERRAIN, not an attacker - the same reasoning as Caustic Earth's own damage event,
## whose header explains it at length. No damager attributed, so no friendly-fire bark and nothing to
## shoot back at. AP per the ability text.
func build_damage_event(specific:SpecificAction, victim:Unit) -> EventCore:
	return EventCore.create(&'event_unit_damage', {
		unit = victim,
		number = Dice.roll_string(DAMAGE_DICE),
		category = Lancer.DAMAGE_TYPE.KINETIC,
		gear = specific.gear,
		action = specific.action,
		flags = [EventService.DAMAGE_FLAG.AP],
	})

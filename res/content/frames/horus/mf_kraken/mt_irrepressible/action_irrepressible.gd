# Irrepressible's price.
#
#   "If an effect would prevent the Kraken from taking a |reaction| (like |grapple|), it may take
#    |1 HEAT| to use a reaction anyway."
#
# The permissions themselves are always on - three buffs on mt_irrepressible, plus
# unit_action.gd_ext.gd for the one case vanilla cannot express. This watcher is the "take 1 HEAT"
# half: it charges after the fact, once, for an activation that only happened BECAUSE of those
# permissions.
#
# Charging on use rather than up front means the Kraken never pays for a turn in which it was not
# actually held or jammed. The trade is that there is no confirmation - the heat simply follows the
# action - so the log line is the only notice the player gets.
extends ActionReaction

const TO_IRREPRESSIBLE := &'irrepressible'
const HEAT_COST := 1
const BOOST_ID := &'ms_boost'

func get_required_triggering_context() -> Array[Context.PROP]:
	return [Context.PROP.unit, Context.PROP.action]

func triggers_on_event(unit:Unit, gear:GearCore, triggering_event:EventCore) -> bool:
	var triggering := triggering_event.context
	if not Unit.is_valid(triggering.unit): return false
	if triggering.unit != unit: return false # our own activations only
	return was_rescued(unit, triggering)

## Would this activation have been refused, had Irrepressible not been on the frame?
##
## Asked of the state the unit is in right now rather than by re-running the gates, because by the time
## this fires the permissions are already in place and every gate answers "yes, fine".
func was_rescued(unit:Unit, triggering:Context) -> bool:
	var action:Action = triggering.action
	if not Action.is_valid(action): return false

	# Held, and doing something a grapple stops: a real reaction, or a boost. This is the whole of
	# it - see the note on JAMMED below.
	if unit.has_status(Lancer.STATUS.GRAPPLED):
		if action.consumes_reaction(): return true
		if is_boost(triggering): return true

	# Nothing here for JAMMED, deliberately. Grappling while jammed needs no help - vanilla's
	# action_grapple.gd overrides is_jammable() to false, so every mech can already do it. And a
	# jammed unit cannot activate a jammable action at all, so there is no "used it anyway" case for
	# this watcher to charge for. See test_irrepressible for both.
	return false

func is_boost(triggering:Context) -> bool:
	if not GearCore.is_valid(triggering.gear): return false
	if not Kit.is_valid(triggering.gear.kit): return false
	return triggering.gear.kit.compcon_id == BOOST_ID

func activate(context:Context, activation:EventCore) -> void:
	var kraken:Unit = context.unit
	if activation.abort_when(not Unit.is_valid(kraken)): return

	UnitAction.gain_self_heat_alt(
		HEAT_COST, SpecificAction.from_context(context), activation)

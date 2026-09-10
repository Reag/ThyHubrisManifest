# The Ceaseless Death, gain half A.
#
#   "1/turn, it gains 1 Resilience when a hostile character within SENSORS is destroyed or loses a
#    structure."
#
# EVERY QUESTION IS ASKED IN triggers_on_event, ON PURPOSE. ReactionBus.trigger_occurred - and
# therefore this method - is called SYNCHRONOUSLY by EventCore.queue_reaction_events
# (event_core.gd:59-68), which event_unit_die.gd calls at :81, one line before
# EventService.remove_unit_from_game at :83. activate() runs later, off the block queue, by which
# time the victim has no occupied tiles and UnitRelation.distance_between answers Tile's 1000
# sentinel from anywhere. So "hostile", "a character" and "within SENSORS" are all decided here,
# while the corpse is still standing, and activate() only banks the point.
#
# Unit.is_active() (unit.gd:105-113) reads core.frame.stat.health, the FRAME stat - and
# event_unit_die.gd:76 zeroes current.health, not that - so is_character() is still true at :81.
# test_a_hostile_killed_outright_banks_a_point_through_the_death_trigger is the standing proof: it
# queues event_unit_die directly, with no preceding structure event, so only the death trigger can
# be paying out the point it asserts.
#
# 1/TURN IS THE ENGINE'S OWN COUNTER, not gear state. UnitAction.every_new_turn_refresh clears
# gear.uses_this_turn for every unit on the map at every turn start (unit_action.gd:67-70, called
# from event_turn_start.gd:42-43), and can_activate_gear consults is_under_per_turn_limit
# (:115, :167-168) before this reaction is ever offered. All that is needed is the soft limit below
# plus the spend_actions call in activate. The .tres gives this action its OWN usage_group: those
# counters are keyed by usage group, defaulting to the KIT id (gear_core.gd:166-168), so without one
# this, the start-of-turn gain, Plague-Vent and the Efficient refund would share one allowance.
#
# The default soft limit would be 99, not 1: a reaction with consumes_rxn = false costs
# Lancer.ACTION.RXN, i.e. zero, and action.gd:161-163 exempts free-cost actions from the repeat-
# action rule. The override is load-bearing.
#
# get_required_triggering_context() DELIBERATELY RETURNS EMPTY. A [Context.PROP.unit] entry looks
# like the obvious thing to require, but ActionReaction.check_required_triggering_context
# (action_reaction.gd:83-87) re-checks it against the TRIGGERING event's own context - here, the
# death event's context.unit, i.e. the victim - when the reaction's queued event_gear_activate
# block finally executes, via Context.is_property_present(PROP.unit) (context.gd:146), which
# defaults units_have_to_be_on_map = true. For `death` specifically, event_unit_die.gd:81 queues
# that reaction block and only THEN, at :83, calls EventService.remove_unit_from_game - so by the
# time the queued block runs, the victim is off the map and this re-check fails, silently aborting
# the activation ("ABORT event_gear_activate ... specific: invalid") with no Resilience gained.
# `structured` never surfaced this because it doesn't remove anyone from the map. Nothing here
# needs the requirement anyway: triggers_on_event below already validates the subject unit fully,
# at queue time, while it is still guaranteed valid.
extends ActionReaction

const Resilience := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/cp_cupiditas_vitae/resilience.gd')
const DraugrReach := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/draugr_reach.gd')

func get_per_turn_soft_limit(specific:SpecificAction) -> int: return 1

func triggers_on_event(unit:Unit, gear:GearCore, triggering_event:EventCore) -> bool:
	var subject:Unit = triggering_event.context.unit
	if not Unit.is_valid(subject) or subject == unit: return false
	if not subject.is_character(): return false # deployables, markers and wrecks are not characters
	if not UnitRelation.are_enemies(unit, subject): return false
	# "within SENSORS" is the frame's own definition, not the raw stat: the Carrion Beast widens it
	# by 5 against a character carrying INFECTION (draugr_reach.gd). Asked here, like every other
	# question in this method, while the corpse is still on the map - see the file header.
	return DraugrReach.within_sensors(unit, subject)

func activate(context:Context, activation:EventCore) -> void:
	spend_actions(activation) # records the usage; this is what makes it 1/turn
	Resilience.gain(context.unit, 1)

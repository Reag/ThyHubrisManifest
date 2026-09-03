# Drag To The Depths - the shared gate and cost behind the core power's three free options.
#
#   "While |IMMOBILIZED|, you may expend your base movement to:
#    • |Grapple|.
#    • Pull a character within |SENSORS| 2 spaces towards you (|HULL| save resists)
#    • Move a character you are grappling 3 spaces in any direction."
#
# The three options target completely differently - an adjacent enemy, anything within SENSORS,
# somebody already held - so each is its own action rather than a sub-menu on one. The engine's
# sub-menu mechanism could not have carried them anyway: VariantActionGroup composes callables onto
# a single Action duplicate, which is why the Blackbeard's cable can retune Grapple but nothing in
# vanilla swaps in three targeting shapes.
#
# Extends ActionSystemTargetUnit rather than ActionSystem so Pull and Reposition inherit the whole
# targeting flow - ask_for_targets, a spend_actions call at the right moment, and an
# activate_for_target override point. Grapple does not target and overrides get_target_requirements
# to say so.
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-02-kraken-design.md
extends ActionSystemTargetUnit

## Only while the movement is worthless, and only if none of it has been spent.
##
## UnitCondition.is_immobilized rather than has_status(IMMOBILIZED): it is the disjunction of the
## status, SHUTDOWN, and GRAPPLED-while-not-the-larger-party, and it is the same predicate
## pathfinder.gd:330 uses to deny movement outright. The GRAPPLED arm is the one the frame plays -
## it is how My Domain hands Drag its opening.
##
## The speed test is the strict reading of "expend your base movement": the price is the whole
## allowance, so a Kraken that walked into position before being pinned has already spent it.
func is_available_to_activate(unit:Unit, gear:GearCore) -> bool:
	if not Unit.is_valid(unit): return false
	if not UnitCondition.is_immobilized(unit): return false
	return unit.core.current.speed == unit.core.get_speed_max()

## Pay the movement on top of the normal action spend.
##
## Nothing else needs to enforce one-per-turn: zeroing the speed closes is_available_to_activate
## behind us for every option at once, which is why the three keep distinct usage_groups instead of
## sharing one. Boost cannot refill it either - is_boost_prohibited refuses any immobilized unit.
func spend_actions(activation:EventCore) -> void:
	super(activation)
	var specific := SpecificAction.from_context(activation.context)
	if not SpecificAction.is_valid(specific): return
	specific.unit.core.current.speed = 0

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

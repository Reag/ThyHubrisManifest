# Copyright (c) 2026 Wickworks ♡ Lancer Tactics v1.3.3
# Clauses 1-2's hand-off target: onhit_mourning_call.gd offers this via CommonActionUtil.choose_and_use
# after a ranged hit. For now this only pays its own cost (the quick action + the core point, via
# consumes_cp on the .tres) -- the teleport, the tangibility flip, the damage and the crit rider are
# Task 2.
extends ActionSystem

func activate(context:Context, activation:EventCore) -> void:
	# mirrors action_castigate.gd / action_unstable_system.gd: call spend_actions() ourselves so the
	# deferred_spend chain from choose_and_use actually runs before we're done.
	spend_actions(activation)

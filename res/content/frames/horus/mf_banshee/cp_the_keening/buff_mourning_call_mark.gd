# Copyright (c) 2026 Wickworks ♡ Lancer Tactics v1.3.3
# Clause 7's mark: "if this damage destroys the target, they leave behind no wreckage."
#
# action_mourning_call.gd applies this to the TARGET immediately before dealing its own damage, and
# clears it again immediately afterwards (if the target survived). It carries no logic of its own --
# a pure marker, hidden from the player -- because the reaction that actually strips the wreck lives
# on the BANSHEE instead (action_mourning_call_wreckless.gd, on cp_the_keening), which
# checks the DYING unit for this buff during DEATH:PRE. See that file for why the reaction sits
# there rather than here.
#
# It is this mark, and not the reaction's location, that scopes the wrecklessness to THIS one kill:
# without it, a DEATH:PRE reaction on the Banshee would strip LEAVES_WRECK from every death in the
# game it could see, regardless of who or what caused it. spec/test_mourning_call.gd's "killed by
# anything else still leaves a wreck" test is the gate that would catch that mistake.
extends Buff

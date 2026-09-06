# TO TWIST TRUTH's delivery: a probabilistic equivalent to "you may reroll the INVISIBILITY check".
# See D:\DEV\lancer-tactics-claude\specs\2026-09-06-banshee-remaining-traits-design.md, "To Twist
# Truth" section, for the full writeup of why the literal reroll cannot be built:
# AttackUtil.check_if_invisibility_forces_miss (engine/utils/attack_util.gd:58-76) ends in a bare
# `return Dice.roll_d6() <= 3` - no event, no context, no buff consult - and both attack_util.gd and
# unit_condition.gd are confirmed-dead script-extension seams in this project (a .gd_ext.gd installs
# cleanly and never runs). The author approved this buff as the probabilistic equivalent instead.
#
# THE ARITHMETIC - spelled out so a future maintainer does not "fix" the coin flip into something
# deterministic and silently double the miss rate:
#   - Vanilla forces a miss on d6 <= 3: a flat 50%.
#   - A literal "you may reroll, keep the result that misses" only STILL misses when BOTH the
#     original roll and the reroll come up low: 0.5 * 0.5 = 25%.
#   - This buff instead IGNORES invisibility outright (no miss-check runs at all) on d6 <= 3 - 50% of
#     the Banshee's attacks - and on the other 50% the ordinary vanilla check runs unmodified, which
#     itself misses on 50% of ITS rolls: 0.5 * 0.5 = 25%. Identical distribution to the literal
#     reroll, reached by a different (but actually engine-reachable) route.
# Replacing the 50/50 flip with "always ignore invisibility" would drop the miss rate to 0% instead of
# the intended 25% - do not simplify this into a deterministic ignore.
extends Buff

func check_if_passive_applies(core:BuffCore, context:Context) -> bool:
	# The Banshee's OWN attacks only. UnitCondition.get_invisibility_summary
	# (unit_condition.gd:446-469) asks BOTH the attacker (context.unit) and the target
	# (context.target_unit) for their IGNORE_INVISIBLE buffs, so without this gate the trait would
	# also fire when the Banshee is the one being shot AT - halving the chance an attack against an
	# INVISIBLE Banshee misses, which is not what the trait is for.
	if core.get_owner_unit(context.map) != context.unit: return false
	return Dice.roll_d6() <= 3

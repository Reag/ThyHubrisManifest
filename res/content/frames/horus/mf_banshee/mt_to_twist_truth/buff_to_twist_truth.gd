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

## Only roll when invisibility is actually in play - i.e. when
## UnitCondition.get_invisibility_summary would otherwise compute `is_invisible = true` for this
## attack. THIS IS NOT MERELY AN OPTIMISATION: Dice.roll_d6() has an observable side effect beyond
## its return value - it pops one entry off the shared Dice.CHEAT_ROLL_QUEUE whenever that queue is
## non-empty (dice.gd:33-35), and that queue is also how OTHER specs pin exact rolls for their own
## attacks. A roll on every attack, invisible target or not, silently eats one queued value per
## Banshee attack and desyncs every roll after it for whoever queued them - this is exactly what
## made spec/test_to_bend_reality.gd flake. Skipping the roll when it cannot matter is therefore
## required for correctness of the wider test suite (and the game's shared RNG stream generally),
## not just a speed-up - do not "simplify" this back into an unconditional roll.
func check_if_passive_applies(core:BuffCore, context:Context) -> bool:
	# The Banshee's OWN attacks only. UnitCondition.get_invisibility_summary
	# (unit_condition.gd:446-469) asks BOTH the attacker (context.unit) and the target
	# (context.target_unit) for their IGNORE_INVISIBLE buffs, so without this gate the trait would
	# also fire when the Banshee is the one being shot AT - halving the chance an attack against an
	# INVISIBLE Banshee misses, which is not what the trait is for.
	if core.get_owner_unit(context.map) != context.unit: return false

	# THE GATE. get_invisibility_summary (unit_condition.gd:446-469) computes `is_invisible` from
	# TWO sources - the target's Lancer.STATUS.INVISIBLE, and Buff.TO.TREAT_AS_INVISIBLE buffs on
	# EITHER party (e.g. buff_tear_invisibility, which is how the Banshee's own tear-attacks reach
	# this trait - the target carries no INVISIBLE status at all in that case). Mirror both sources
	# here: if neither is present, nothing in this attack is going to consult IGNORE_INVISIBLE
	# buffs at all, so the roll cannot change anything - don't make it.
	#
	# NO RECURSION: TREAT_AS_INVISIBLE is a different Buff.TO key from IGNORE_INVISIBLE, so
	# UnitCondition.get_buffs_to below does not re-enter this function. Confirmed by reading
	# buff_tear_invisibility.gd, the only TREAT_AS_INVISIBLE buff in this mod - its
	# check_if_passive_applies only calls TearRouting.attack_routes_through_tear, never
	# UnitCondition.get_buffs_to or anything IGNORE_INVISIBLE-related.
	var invisibility_in_play := context.target_unit.has_status(Lancer.STATUS.INVISIBLE)
	if not invisibility_in_play:
		for party:Unit in [context.unit, context.target_unit]:
			if not Unit.is_valid(party): continue
			if not UnitCondition.get_buffs_to(party, Buff.TO.TREAT_AS_INVISIBLE, context).is_empty():
				invisibility_in_play = true
				break
	if not invisibility_in_play: return false

	return Dice.roll_d6() <= 3

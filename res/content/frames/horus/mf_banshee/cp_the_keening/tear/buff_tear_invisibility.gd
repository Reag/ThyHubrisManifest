# Clause 6: "Attacks that pass through a tear treat targets as INVISIBLE."
#
# WHY A BUFF, when a hook at the attack itself would be tidier. Invisibility is consumed in exactly
# one place - AttackUtil.check_if_invisibility_forces_miss, called from event_unit_attack.gd:158 -
# and a script extension on attack_util.gd installs cleanly and NEVER RUNS. Probed and confirmed;
# it joins unit_action.gd and unit_condition.gd on this project's known-bad list. There is nowhere
# to stand between "attack declared" and "invisibility consulted", so the answer has to be in place
# before the attack starts, which means a buff on one of the two units.
#
# get_invisibility_summary reads TREAT_AS_INVISIBLE buffs on EITHER party (unit_condition.gd:452),
# and hands check_if_passive_applies the Context carrying both - which is the whole reason clause 6
# can be expressed this way at all.
#
# THE BUFF IS INERT AT REST. It carries no state and grants nothing on its own: the condition below
# recomputes, per attack, whether that exact pair is routed through a tear. A unit carrying this is
# not "invisible" in any sense until someone attacks it through a tear. That is what keeps the
# footprint acceptable despite the buff being handed out broadly.
extends Buff

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')

## Asked once per attack, with the attacker as context.unit and the target as context.target_unit.
##
## Note this is called for the buff on EITHER unit with the SAME context, so it must be written from
## the context's point of view rather than the carrier's - `core` is deliberately unused.
func check_if_passive_applies(core:BuffCore, context:Context) -> bool:
	if context == null: return false

	# A BEND IS AN ATTACK THROUGH A TEAR BY CONSTRUCTION, so clause 6 applies to it without any
	# geometry being consulted. action_attack.gd:233 relays a bent attack through a proxy standing ON
	# the chosen tear, and every downstream event carries that proxy as context.unit.
	#
	# Nothing here worked on a bend before. The routing question below is asked about the PAIR, and
	# TearRouting.is_cross_tangible reads raw INTANGIBLE status - the proxy has none of its own
	# (create_targeting_proxy gives it faction and owner and nothing else), so for the ordinary bend
	# (tangible Banshee, tangible target) it answered "not cross-tangible" and clause 6 went quiet,
	# while for a both-INTANGIBLE bend the proxy's laundered tangibility made it answer yes by
	# accident. Neither reading is the rule.
	#
	# get_attacker is NOT the fix at this site, and that is worth spelling out because it is at the
	# other two. Resolving the proxy back to the Banshee gives a pair that To Bend Reality guarantees
	# is SAME-tangibility (unit_relation.gd_ext.gd refuses a bend across the line), so
	# is_cross_tangible would still be false and clause 6 would still never fire. The bend does not
	# need its route rediscovered - the player picked the tear it goes through.
	if TearRouting.is_bend_proxy(context.unit): return true

	return TearRouting.attack_routes_through_tear(context.unit, context.target_unit)

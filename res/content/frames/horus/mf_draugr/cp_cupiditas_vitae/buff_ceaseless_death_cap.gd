# The one-shot damage cap The Ceaseless Death applies to itself mid-instance.
#
#   "...it reduces all remaining damage to 1..."
#
# A clone of the Napoleon's Flash Aegis (buff_flash_aegis.tres) in everything but the number:
# BuffResistDamage with cap_instead_of_resist and is_onetime, so DamageModifications.create picks it
# up at damage_modifications.gd:62-70 as a FLAG.CAP and event_unit_damage.gd:73-77 consumes it in
# the same preblock.
#
# THE NUMBER IS DYNAMIC, WHICH IS THE ENTIRE REASON THIS IS A SUBCLASS RATHER THAN A PLAIN .tres.
# The engine caps at event_unit_damage.gd:93-94 and only subtracts OVERSHIELD afterwards, inside
# damage() at :215-218. A flat cap of 1 would therefore be spent entirely on overshield and let
# nothing reach health at all - the opposite of "after OVERSHIELD is reduced ... reduce all
# remaining damage to 1". Capping to overshield + 1 means overshield absorbs what it can and exactly
# one point lands. With no overshield it degenerates to 1, which is the common case.
#
# get_values is called from damage_modifications.gd:64 with the DAMAGE context, whose `unit` is the
# unit being damaged (event_unit_damage.gd:45-46) - i.e. the Draugr. Note that the same context's
# target_unit is the damage SOURCE (damage_modifications.gd:46), so reading `unit` is not a
# coin-flip between the two. Reading the overshield live rather than storing it at application time
# matters: the preblock recomputes modifications at :62-63 AFTER the PRE reactions, so a reaction
# that granted overshield between the two passes is honoured.
#
# The applying/refusing decision (SHREDDED, NO_REDUCE) is taken by buff_ceaseless_death.gd BEFORE
# this buff is ever created. See that file's header for why it cannot be taken here.
extends BuffResistDamage

func get_values(core:BuffCore, context:Context) -> Context:
	var cap:int = 1
	if Unit.is_valid(context.unit): cap += maxi(0, context.unit.state.overshield)
	return Context.create({number = cap, flags = [BuffResistDamage.FLAG.CAP]})

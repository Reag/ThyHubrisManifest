# The All-Consuming Tide - the scene-long mark the rest of the core power hangs off.
#
#   "For the rest of the |scene|, ..."
#
# Carries no behaviour of its own yet beyond being detectable. Everything else in the core power asks
# UnitCondition.has_buff(unit, 'buff_the_all_consuming_tide'), so this resource is the single switch
# for the whole ability, and clearing it turns all of it off at once.
#
# until = MANUAL is "rest of the scene". Buff.is_cleared_on_owner_death() defaults true (buff.gd:184),
# which is what stops the Tide outliving the Kraken - pinned by a spec rather than trusted, because
# the failure would be silent and permanent.
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-02-kraken-design.md
extends Buff

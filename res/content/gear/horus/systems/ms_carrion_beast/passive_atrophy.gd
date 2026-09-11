# The aura that plants buff_atrophy. It exists only to make sure the marker is PRESENT; every
# decision about whether Atrophy actually applies is made at roll time, in the buff.
#
# THE FOOTPRINT IS DELIBERATELY WIDER THAN THE RULE (plan decision D2). Gating on "infected" here is
# the obvious reading and is wrong: auras are only re-evaluated inside
# UnitTile.update_tracking_and_statuses (passive_aura.gd:24), and applying INFECTION does not trigger
# one - unit_condition.gd:714 only schedules a tracking update when the applied buff's OWNER GEAR
# carries a PassiveAura, and Infection deliberately has no from_gear at all. A unit that became
# infected without moving would never receive the marker. So we plant on everyone within max_reach
# and let buff_atrophy.check_if_passive_applies, which runs per roll and cannot go stale, do the
# real work.
#
# CONSEQUENCE, ACCEPTED (plan decision D7): a Draugr whose SENSORS GROW mid-scene keeps a stale
# footprint until the next tracking update - which any move, spawn, death or status change provides.
# A Draugr whose SENSORS SHRINK is already correct, because the roll-time gate re-tests
# within_sensors regardless of what the aura believes.
#
# DIRECT SUBCLASS OF PassiveAura, and it has to stay one: Kit.is_passive_of_type only goes one layer
# deep (kit.gd:161-165), so an intermediate class would make this passive invisible to both
# get_passives_of_type and loadout_core.gd:298-301's has_passive_type - i.e. the gear would never
# reach loadout.auras and nothing would run at all, silently.
extends PassiveAura

const DraugrReach := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/draugr_reach.gd')

## Replaces the aura_range/elevation/LOS geometry wholesale: the reach is a stat, not an export, and
## SENSORS is a detection range with no line-of-sight requirement (see draugr_reach.gd's header).
func is_within_range(moving_unit:Unit, aura_unit:Unit) -> bool:
	if not Unit.is_valid(moving_unit) or not Unit.is_valid(aura_unit): return false
	return UnitRelation.distance_between(aura_unit, moving_unit) <= DraugrReach.max_reach(aura_unit)

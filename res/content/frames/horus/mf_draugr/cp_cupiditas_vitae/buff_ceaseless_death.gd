# The Ceaseless Death, the spending half.
#
#   "After OVERSHIELD is reduced, if the Draugr would take damage while it has Resilience, it
#    reduces all remaining damage to 1 and loses 1 Resilience. If the Draugr is SHREDDED or the
#    damage would ignore RESISTANCE, it takes the damage as normal and still loses 1 Resilience."
#
# A permanent, hidden buff handed to the Draugr by a PassiveBuffApplicator on cp_cupiditas_vitae,
# reacting to DAMAGE at PRE timing. A buff rather than an ActionReaction on purpose: reaction buffs
# are gated by does_buff_trigger (reaction_bus.gd:125-139), which asks only about the trigger, the
# timing and this script - no action economy, no per-round limit, no gear availability. This has to
# fire on EVERY qualifying damage instance, which is what the rules describe, and an ActionReaction
# would have to fight three separate limiters to say the same thing.
#
# ==================== WHERE THIS SITS IN THE DAMAGE PIPELINE ====================
# event_unit_damage.gd:
#   :52      prelim DamageModifications (no cap buff exists yet)
#   :59      DAMAGE / PRE reactions  <-- activate() runs HERE
#   :62-67   modifications recomputed; the cap buff applied one line ago is collected
#   :73-77   one-shot buffs consumed (our cap among them)
#   :93-94   damage_amount = mini(damage_amount, capped_damage)
#   :215-218 overshield subtracted, then health
#
# ==================== WHY THE TWO EXCEPTIONS ARE CODED HERE ====================
# damage_modifications.gd:
#   :59     NO_REDUCE  -> EARLY RETURN, before the cap is collected at :62
#   :62-70  RESIST_DAMAGE buffs collected; FLAG.CAP lowers capped_damage
#   :73-77  SHREDDED   -> EARLY RETURN, AFTER the cap has already been collected
#   :113    buffs_to_consume assigned -- UNREACHABLE on either early-return path
# So: SHREDDED does NOT bypass a cap in this engine (the rules say it must), and on BOTH exception
# paths a cap buff we applied would never be consumed and would silently cap the NEXT instance
# instead. Refusing to apply it is the only correct move, and it has to be decided here, before the
# buff exists - BuffResistDamage.check_if_passive_applies runs at :62, after the NO_REDUCE return
# has already been taken, so it can never see that flag.
#
# HEAT is not damage in Lancer, and Infection is delivered as HEAT (infection.gd:56-58). Skipping it
# in triggers_on_event rather than in the cap buff's own filter is deliberate: the POINT must not be
# spent either.
#
# The counter is decremented BEFORE the branch, because both branches spend it.
extends Buff

const Resilience := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/cp_cupiditas_vitae/resilience.gd')

const CAP_BUFF_ID := &'buff_ceaseless_death_cap'

func get_required_triggering_context() -> Array[Context.PROP]:
	return [Context.PROP.unit]

func triggers_on_event(core:BuffCore, unit:Unit, triggering_event:EventCore) -> bool:
	var context := triggering_event.context
	if context.unit != unit: return false # only our own damage
	# category_int defaults to 0 = KINETIC when the event carried no type (context.gd:26-28), so
	# this is safe on an untyped instance and excludes only real HEAT.
	if context.category_int == Lancer.DAMAGE_TYPE.HEAT: return false
	# "if the Draugr would take damage": nothing to cap when Overshield (or armor, already folded
	# into the preliminary number at event_unit_damage.gd:52-56) absorbs the whole instance.
	if context.number <= maxi(0, unit.state.overshield): return false
	# A multi-damage-type attack is several damage events; the engine keeps our one-shot cap alive
	# across them (SKIP_CONSUMING_RESIST_BUFFS, event_unit_attack_declared.gd:260). One point covers
	# the whole attack: while the cap is still on us, do not spend again.
	if not UnitCondition.get_buffs(unit, CAP_BUFF_ID).is_empty(): return false
	return Resilience.count(unit) > 0

func activate(core:BuffCore, activation:EventCore) -> void:
	# NOTE: deliberately does NOT call super. Buff.activate's default clears the buff from the unit
	# (buff.gd:254-255); this one is permanent for as long as the core power is intact.
	var unit:Unit = activation.context.unit
	var triggering:EventCore = activation.context.event
	if not Unit.is_valid(unit) or triggering == null: return
	if Resilience.count(unit) <= 0: return # another PRE reactor may have drained it first

	Resilience.spend(unit, 1)
	if takes_it_as_normal(unit, triggering.context): return
	UnitCondition.apply_buff_id(activation, unit, CAP_BUFF_ID, core.get_owner_gear(activation.context.map))

## "If the Draugr is SHREDDED or the damage would ignore RESISTANCE". Both are read off the
## TRIGGERING context, not this activation's own - the flags live on the damage event.
func takes_it_as_normal(unit:Unit, damage_context:Context) -> bool:
	if unit.has_status(Lancer.STATUS.SHREDDED): return true
	return damage_context.flags.has(EventService.DAMAGE_FLAG.NO_REDUCE)

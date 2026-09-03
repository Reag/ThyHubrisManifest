# The reach My Domain opens, for exactly as long as it is open.
#
#   "The Kraken can |Grapple| characters at least partially within any |Bursts| centered on itself."
#
# The Kraken makes a real Grapple attack per character, and action_grapple is melee: its reach is
# threat range, which is 1. A burst is wider than that, so something has to carry the attack out to
# the characters the burst actually caught.
#
# The vanilla answer is the Blackbeard's mt_grapple_cable, whose buff_grapple_cable_threat is a
# BuffWeaponTypeBonus to ACTION_RANGE / THREAT_RANGE that only applies to action_grapple. It is
# consumed at action_attack_weapon.gd:189 through BuffBonus.get_bonus_for_subtype, and because
# overrides is set that takes the MAX of the weapon's own threat and this bonus
# (buff_weapon_type_bonus.gd:11-12) - so the Blackbeard makes the genuine, full Grapple attack and
# the buff only extends how far it reaches. This is the same mechanism.
#
# ONE DELIBERATE DIFFERENCE from the Blackbeard. Its buff is always on, applied by a
# PassiveBuffApplicator on the trait, because a Blackbeard may Grapple at 5 whenever it likes. My
# Domain's reach is conditional - it is earned by a burst - so an always-on buff would hand the
# Kraken a ranged Grapple as an ordinary Quick action, which the trait does not grant. This one is
# applied by action_my_domain when the trait resolves, sized to the characters that burst caught,
# and cleared again when the activation finishes.
#
# Hence the reach living in BuffCore state rather than in bonus_value: one Kraken's two bursts are
# two different reaches, and bonus_value is a property of the shared ContentLibrary resource that
# every Kraken on the map would see.
extends BuffWeaponTypeBonus

const REACH_KEY := 'reach' ## how far this activation has to carry, in spaces
const GRAPPLE_ACTION := &'action_grapple'

## Size this instance to the activation that opened it.
func bind(core:BuffCore, reach:int) -> void:
	core.set_state(REACH_KEY, reach)

## The basic Grapple and nothing else. super still runs, so the melee/basic filters declared on the
## resource are live rather than decorative - the Blackbeard replaces its check outright, which
## leaves the same keys inert on its own .tres.
func check_if_passive_applies(core:BuffCore, context:Context) -> bool:
	if not super.check_if_passive_applies(core, context): return false
	return context.action.get_id() == GRAPPLE_ACTION

## bonus_value is the floor, not the value. get_bonus_for_subtype takes the max of this and the
## weapon's own threat, so an unbound instance reports 0 and leaves an ordinary Grapple exactly as
## it was rather than shortening it.
func get_values(core:BuffCore, context:Context) -> Context:
	return Context.create({
		number = maxi(int(core.get_state(REACH_KEY, 0)), bonus_value),
		category = bonus_subtype,
		flags = [BuffBonus.FLAG.OVERRIDES] if overrides else [],
	})

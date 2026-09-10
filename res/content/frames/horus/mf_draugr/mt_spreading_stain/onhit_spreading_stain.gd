# The Spreading Stain. "1/round, on a critical hit against a target with INFECTION, the Draugr may
# apply 1 INFECTION to another character within SENSORS."
#
# An OnHitEffect at on_crit, injected onto every attack the Draugr makes by buff_spreading_stain
# (BuffWeaponTypeOnHit, Buff.TO.ONHIT_EFFECT), which mt_spreading_stain hands out through a
# PassiveBuffApplicator. The engine collects those buffs per attack roll at event_unit_attack.gd:47-49
# and calls on_crit for each at :89-93, after apply_on_hits and only when roll.crit - i.e. BEFORE the
# declared attack rolls damage, so the infection read here is the one the target already had, not one
# The Seeping Rot is about to add.
#
# WHY THE WEAPON-ONLY ARCHETYPE IS NOT A BUG. BuffWeaponTypeOnHit's base only accepts a context whose
# action is an ActionAttackWeapon (buff_weapon_type.gd:25-31), so a tech attack never reaches this
# effect - but no tech attack can CRIT either: ActionAttack.can_crit returns false
# (action_attack.gd:48), only ActionAttackWeapon overrides it to true (:246), and attack_roll.gd:73
# gates crit on it. Measured 2026-09-09: a natural 20 from ms_fragment_signal logs "hit!" while the
# same 20 from mw_tactical_melee_weapon logs "crit!". If sub-project 4's Disease is meant to crit, its
# ActionAttackTech subclass must override can_crit AND this buff must become a plain Buff carrying the
# same effects array - the two changes only make sense together, and neither is testable alone.
#
# 1/ROUND IS KEYED BY ROUND, not by a bool. A plain "used" flag would never reset; a turn-keyed one
# would reset twice in a round when something grants a second LINKED turn. Same two-part shape as
# passive_acid_spill.is_armed and action_bind_thy_flesh's LAST_ROUND_KEY. The state lives on the
# trait's own GearCore, which is reached from the Draugr rather than from context.gear - context.gear
# is the WEAPON that just critted, and keying on it would give one spread per weapon.
#
# The stamp is only written once a character has actually been picked: "may apply" means a declined
# prompt costs nothing.
extends OnHitEffect

const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')
const Compat := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/reag_compat.gd')
const DraugrReach := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/draugr_reach.gd')

const TRAIT_ID := &'mt_spreading_stain'
## Gear state: the round this trait last spread.
const SPREAD_ROUND_KEY := 'spreading_stain_round'

func on_crit(activation:EventCore, attacked_unit:Unit) -> void:
	var context := activation.context
	if not Unit.is_valid(context.unit) or not Unit.is_valid(attacked_unit): return

	# NOT context.unit raw. An attack relayed through a targeting proxy carries the PROXY here
	# (action_attack.gd:233 assigns specific.unit = get_attacker_relay(...)); Unit.get_attacker
	# (unit.gd:276-282) is the engine's own undo, and event_unit_attack_declared.gd:29 uses it for
	# exactly this. The mod has already been bitten by reading context.unit raw - see
	# spec/test_bend_composition.gd's header.
	var draugr:Unit = context.unit.get_attacker(context)
	if not Unit.is_valid(draugr): return
	if not Infection.is_infected(attacked_unit): return

	var gear:GearCore = draugr.get_gear(TRAIT_ID)
	if not GearCore.is_valid(gear): return
	var this_round:int = context.map.game_core.round_count
	if gear.get_state(SPREAD_ROUND_KEY, -1) == this_round: return

	var candidates:Array[Unit] = spread_candidates(draugr, attacked_unit)
	if candidates.is_empty(): return

	var chosen:Unit = await pick_victim(draugr, candidates)
	if activation.abort_without_unit(draugr): return
	if not Unit.is_valid(chosen) or not candidates.has(chosen): return

	gear.set_state(SPREAD_ROUND_KEY, this_round)
	await Infection.apply(activation, chosen, 1)

## Every other character the Draugr's Sensors reach. LOS is deliberately NOT required: Sensors is a
## detection range and Unit.get_sensor_range() (unit.gd:305) takes no target at all.
##
## get_characters_within (unit_relation.gd:34-43) already drops the Draugr itself, drops MARKERS
## (get_units_within, :48 and :57) and keeps only is_character(). The marker exclusion is
## load-bearing: choose_unit highlights a marker's tile and then cannot resolve the click, hanging
## the game with no cancel (spec/test_tear_pick.gd). Tech-immune characters are filtered here rather
## than left to Infection.apply, which would refuse them silently after the player had already picked.
static func spread_candidates(draugr:Unit, exclude:Unit) -> Array[Unit]:
	# SWEEP WIDE, THEN FILTER. draugr_reach.max_reach is the widest SENSORS could be for anyone
	# (the Carrion Beast's +5 applies only against a character already carrying INFECTION), so it is
	# a search radius and never an answer; within_sensors decides per candidate. Collecting at the
	# raw stat instead would drop every infected character the Carrion Beast can actually see.
	return UnitRelation.get_characters_within(
		draugr, DraugrReach.max_reach(draugr), false,
		func(other:Unit) -> bool:
			return (
				other != exclude and
				not UnitCondition.is_immune_to_tech(other) and
				DraugrReach.within_sensors(draugr, other)
			)
	)

## The player picks; the AI takes the nearest hostile and is never prompted. Vanilla guards its
## optional effects on is_player_controlled and gives the AI a flat default
## (action_blinkspace_jump.gd:14, action_mag_parry.gd:29); this mod does the same at
## onhit_mourning_call.gd:117-124.
##
## Goes through reag_compat, never choice_bus directly (CLAUDE.md). The SpecificAction handed to the
## shim carries the Draugr and the trait gear but no action - mt_spreading_stain is a passive-only
## Kit - which is all the info panel uses.
func pick_victim(draugr:Unit, candidates:Array[Unit]) -> Unit:
	if not draugr.is_player_controlled(): return nearest_hostile(draugr, candidates)
	return await Compat.choose_unit_with_brochure(
		SpecificAction.from_id(draugr, TRAIT_ID),
		candidates,
		tr('gear.mt_spreading_stain.name'),
		tr('gear.mt_spreading_stain.effect')
	)

## Nearest by UnitRelation.distance_between (unit_relation.gd:13-25, which is the 3D-aware distance
## the rest of the engine uses). Allies are never chosen automatically: the text permits "another
## character", but an AI infecting its own side is a bug, not a flourish.
static func nearest_hostile(draugr:Unit, candidates:Array[Unit]) -> Unit:
	var best:Unit = null
	var best_distance:int = -1
	for other:Unit in candidates:
		if not UnitRelation.are_enemies(draugr, other): continue
		var distance:int = UnitRelation.distance_between(draugr, other)
		if best == null or distance < best_distance:
			best = other
			best_distance = distance
	return best

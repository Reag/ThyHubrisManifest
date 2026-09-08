# TO BEND REALITY's delivery. A VARIANT_ACTIONS buff sees every action the pilot activates
# (action.gd:187-198), and check_if_passive_applies receives a Context carrying context.action - so
# the gate can be "is this a kinetic weapon attack" rather than "is this my gear". That is the whole
# answer to reaching an arbitrary weapon the pilot happens to have equipped.
extends Buff

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')

const VARIANT_KEY := &'to_bend_reality'
## Marks the WRAPPER object itself (see get_values below). generate_composed_action only ever
## appends VARIANT_KEY to the `composed` action it is about to discard - our variant callable
## returns a brand-new object in its place, and that new object's modified_by_variants starts
## empty (seeded from the .tres). So VARIANT_KEY can only ever land on the FOLLOWUP (the pilot's
## weapon duplicate, which keeps it - see get_values). A distinct key is needed to mark the
## wrapper, mirroring buff_throughbolt_rounds.gd's modified_line.modified_by_variants assignment.
const REPLACEMENT_KEY := &'to_bend_reality_replacement'

## Assigned in the .tres, the way wm_throughbolt_rounds assigns throughbolt_line - a hardcoded
## preload path would break the moment the file moves.
@export var bend_action:ActionAttackWeapon

func is_buff_context_valid_for_passive(core:BuffCore, context:Context) -> bool:
	return context.map != null and Action.is_valid(context.action) and Action.is_valid(bend_action)

func check_if_passive_applies(core:BuffCore, context:Context) -> bool:
	var action = context.action
	if not (action is ActionAttackWeapon): return false
	# Never offer the bend on a bend. Two keys are checked because two different objects can be
	# "already a bend": REPLACEMENT_KEY marks the wrapper ITSELF (this action IS a bend, refuse to
	# wrap the wrapper), and VARIANT_KEY marks the FOLLOWUP (this action has already had a bend
	# applied to it - the followup is what actually carries VARIANT_KEY, per generate_composed_action;
	# see REPLACEMENT_KEY's comment above for why the wrapper never does).
	if action.modified_by_variants.has(VARIANT_KEY) or action.modified_by_variants.has(REPLACEMENT_KEY):
		return false
	# NOT A WEAPON AT ALL. Ram, Grapple and Improvised Attack are ActionAttackWeapons with the
	# default KINETIC damage type, so the damage gate below happily let them through - and the bend
	# then dead-ended, because all three have aim_range 0 / threat 1 and bendable_tear_tiles could
	# never offer a tear inside that. WEAPON_SIZE.NONE is the engine's own marker for these: it is
	# what action_attack_weapon.gd:107 keys "lancer.actiontype.attack_basic" off, and in vanilla only
	# those three plus the Black Witch's field projector and Throughbolt's own wrapper carry it. The
	# prose says "when attacking with a kinetic WEAPON"; a basic attack is not one.
	if action.weapon_size == Lancer.WEAPON_SIZE.NONE: return false
	# ALL the damage types, not just the primary one. get_damage_type answers only for the base roll,
	# so a weapon that lists KINETIC in additional_damage_values - a kinetic slug with a secondary
	# explosive charge, say - was refused the bend despite being kinetic in exactly the way the prose
	# means. get_all_damage_types is the engine's own union of the two (action_attack_weapon.gd:96-100).
	if not action.get_all_damage_types(context.gear).has(Lancer.DAMAGE_TYPE.KINETIC): return false
	# No tear, nothing to bend through. Cheapest meaningful gate, and it keeps the menu clean.
	return not TearRouting.tear_tiles(context.map).is_empty()

## THE AIMING HUD'S PROFILE. choice_bus.show_using_action is handed the COMPOSED action during the
## tear pick (target_action_util.gd:172), and that is the wrapper - whose own .tres carries no weapon
## profile at all. So the readout said "Main Rifle", "Quick" and no damage dice while the player was
## aiming a SUPERHEAVY railgun. Damage always resolved correctly (activate() re-points the context at
## the followup before delegating); only the readout lied.
##
## Copied fields, not delegating getters: type_description, get_action_type, get_damage_dice,
## get_glossary_tags and get_weapon_tags all read these members directly off `self`, and several are
## reached through paths (SpecificAction rebuilt from a context, the gear bar) that never see this
## script's overrides in a form we could intercept cleanly. Assignment onto a fresh duplicate is
## also the safe operation here - see action_bend_reality.gd's shared-subresource banner.
##
## range_pattern is DELIBERATELY NOT COPIED. get_target_requirements is overridden on the wrapper to
## return the tear-tile set with no pattern, so copying a LINE/CONE pattern here would only make the
## tilepicker draw the weapon's AoE preview over a pick that is a single tear tile, and would make
## ranged_distance start answering for a range budget the wrapper does not own.
func mirror_weapon_profile(wrapper:ActionAttackWeapon, weapon:ActionAttackWeapon) -> void:
	wrapper.damage_type = weapon.damage_type
	wrapper.damage_dice = weapon.damage_dice
	wrapper.additional_damage_values = weapon.additional_damage_values.duplicate()
	wrapper.weapon_size = weapon.weapon_size # drives get_action_type: QUICK vs FULL for a SUPERHEAVY
	wrapper.weapon_type = weapon.weapon_type
	wrapper.aim_range = weapon.aim_range
	wrapper.threat = weapon.threat
	wrapper.thrown = weapon.thrown
	wrapper.tags = weapon.tags.duplicate()
	wrapper.knockback = weapon.knockback
	wrapper.reliable_damage = weapon.reliable_damage
	wrapper.attack_accuracy = weapon.attack_accuracy
	wrapper.attack_bonus = weapon.attack_bonus
	wrapper.self_heat_dice = weapon.self_heat_dice
	wrapper.icon_override = weapon.icon_override
	wrapper.flavor_override = weapon.flavor_override

func get_values(core:BuffCore, context:Context) -> Context:
	var group := VariantActionGroup.create(
		VARIANT_KEY,
		tr('gear.mt_to_bend_reality.name'),
		tr('gear.mt_to_bend_reality.effect'),
		null,
		true, # blankable - the player can always shoot normally instead
		true, # logged
	)
	# COMPOSE LATE, AND DETERMINISTICALLY. Both this group and vanilla's THROWN group used to sit at
	# priority 0, and get_sorted_variant_groups uses Util.sort_custom, which is not stable - so the
	# order in which they composed varied. Bend-first silently discarded the throw (the thrown
	# variant then set threat = 0 on the WRAPPER, whose followup kept its full melee threat);
	# thrown-first stacked the two reaches. Sitting after THROWN (0) makes thrown-first the only
	# order: the throw is applied to the pilot's weapon, and the bend then wraps a genuine thrown
	# weapon whose get_target_range reads `thrown` - which is the field activate() now narrows.
	#
	# swap_out MINUS ONE, not swap_out. Throughbolt's own group takes Priority.VARIANT_ACTION.swap_out
	# with the comment "this comes after all other variants" (buff_throughbolt_rounds.gd), and two
	# replacing variants tied at the same number would reintroduce exactly the instability this line
	# exists to remove. One below it keeps Throughbolt's stated contract intact.
	group.priority = Priority.VARIANT_ACTION.swap_out - 1
	group.append(VariantAction.create(
		VARIANT_KEY,
		tr('gear.mt_to_bend_reality.variant.name'),
		tr('gear.mt_to_bend_reality.variant.effect'),
		null,
		func(modified_weapon:ActionAttackWeapon):
			var bend:ActionAttackWeapon = bend_action.create_duplicate_for_variant()
			bend.modified_by_variants = [REPLACEMENT_KEY] # mark the WRAPPER, since composed's own key never survives (see REPLACEMENT_KEY above)
			bend.followup_attack = modified_weapon
			mirror_weapon_profile(bend, modified_weapon) # so the aiming HUD reads the real gun
			return bend # RETURNING an action replaces the original with this one
	))
	return Context.create({ object = group })

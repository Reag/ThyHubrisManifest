# TO BEND REALITY's delivery. A VARIANT_ACTIONS buff sees every action the pilot activates
# (action.gd:187-198), and check_if_passive_applies receives a Context carrying context.action - so
# the gate can be "is this a kinetic weapon attack" rather than "is this my gear". That is the whole
# answer to reaching an arbitrary weapon the pilot happens to have equipped.
extends Buff

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')

const VARIANT_KEY := &'to_bend_reality'

## Assigned in the .tres, the way wm_throughbolt_rounds assigns throughbolt_line - a hardcoded
## preload path would break the moment the file moves.
@export var bend_action:ActionAttackWeapon

func is_buff_context_valid_for_passive(core:BuffCore, context:Context) -> bool:
	return context.map != null and Action.is_valid(context.action) and Action.is_valid(bend_action)

func check_if_passive_applies(core:BuffCore, context:Context) -> bool:
	var action = context.action
	if not (action is ActionAttackWeapon): return false
	# Never offer the bend on a bend. The wrapper IS an ActionAttackWeapon and would otherwise
	# qualify to wrap itself.
	if action.modified_by_variants.has(VARIANT_KEY): return false
	if action.get_damage_type(context.gear) != Lancer.DAMAGE_TYPE.KINETIC: return false
	# No tear, nothing to bend through. Cheapest meaningful gate, and it keeps the menu clean.
	return not TearRouting.tear_tiles(context.map).is_empty()

func get_values(core:BuffCore, context:Context) -> Context:
	var group := VariantActionGroup.create(
		VARIANT_KEY,
		tr('gear.mt_to_bend_reality.name'),
		tr('gear.mt_to_bend_reality.effect'),
		null,
		true, # blankable - the player can always shoot normally instead
		true, # logged
	)
	group.append(VariantAction.create(
		VARIANT_KEY,
		tr('gear.mt_to_bend_reality.name'),
		tr('gear.mt_to_bend_reality.effect'),
		null,
		func(modified_weapon:ActionAttackWeapon):
			var bend:ActionAttackWeapon = bend_action.create_duplicate_for_variant()
			bend.followup_attack = modified_weapon
			return bend # RETURNING an action replaces the original with this one
	))
	return Context.create({ object = group })

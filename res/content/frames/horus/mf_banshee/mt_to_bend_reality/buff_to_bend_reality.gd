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
		tr('gear.mt_to_bend_reality.variant.name'),
		tr('gear.mt_to_bend_reality.variant.effect'),
		null,
		func(modified_weapon:ActionAttackWeapon):
			var bend:ActionAttackWeapon = bend_action.create_duplicate_for_variant()
			bend.modified_by_variants = [REPLACEMENT_KEY] # mark the WRAPPER, since composed's own key never survives (see REPLACEMENT_KEY above)
			bend.followup_attack = modified_weapon
			return bend # RETURNING an action replaces the original with this one
	))
	return Context.create({ object = group })

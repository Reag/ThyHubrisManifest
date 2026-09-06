# THROWAWAY SPIKE - deleted in Task 10. Proves the VARIANT_ACTIONS -> SET_ATTACK_RELAY chain.
extends Buff

const RELAY_TILE := Vector2i(8, 1)

static var spike_proxy:Unit = null

func check_if_passive_applies(core:BuffCore, context:Context) -> bool:
	if not (context.action is ActionAttackWeapon): return false
	return context.action.get_damage_type(context.gear) == Lancer.DAMAGE_TYPE.KINETIC

func get_values(core:BuffCore, context:Context) -> Context:
	var group := VariantActionGroup.create(&'spike_bend', 'Spike Bend', '', null, true, false)
	group.append(VariantAction.create(
		&'spike_bend', 'Spike Bend', '', null,
		func(modified_weapon:ActionAttackWeapon):
			return modified_weapon # no modification; we only care that the entry appears
	))
	return Context.create({ object = group })

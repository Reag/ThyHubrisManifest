# Points the attack's origin at the proxy standing on the chosen tear. action_attack.gd:233 assigns
# specific.unit from this BEFORE targeting, so range, line of sight, cover and the AoE origin all
# move to the tear.
extends Buff

const PROXY_KEY := 'proxy_id'

func get_bend_proxy(core:BuffCore, context:Context) -> Unit:
	return context.map.get_unit_by_id(core.get_state(PROXY_KEY, &''))

func is_buff_context_valid_for_passive(core:BuffCore, context:Context) -> bool:
	return context.map != null and Unit.is_valid(get_bend_proxy(core, context)) and Action.is_valid(context.action)

func check_if_passive_applies(core:BuffCore, context:Context) -> bool:
	return context.action.modified_by_variants.has(&'to_bend_reality')

func get_values(core:BuffCore, context:Context) -> Context:
	return Context.create({ unit = get_bend_proxy(core, context) })

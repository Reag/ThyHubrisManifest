# Releasing every chain when the shackle is destroyed.
#
#   "The targeted character cannot move away from the chain until it makes a HULL check as a quick
#    action, or the object is moved or destroyed."
#
# Destroying the anchor is the way the Erinyes' OWN blasts end a chain: the shackle stands inside
# the pattern it came from, so the next BLAST at a chained character hits it too, and a Grenade
# Launcher kills a 10 HP object in a few shots. Before this the anchor died and buff_bind_thy_flesh
# stayed on everyone it held - no restriction, no burn from Know Thy Sins, just a dead icon - and
# action_bind_thy_flesh skips anyone still carrying the buff, so those characters could never be
# caught again. Reported from play on a Grenade Launcher build.
#
# Lives on the ANCHOR's kit, like the exploding barrel's death reaction, so it fires for every way
# the shackle can die and needs nothing from the Erinyes. DEATH at PRE timing: the anchor is still
# on the map, which is what makes it findable from each chain's recorded anchor id.
extends ActionReactionSelf

const CHAIN_BUFF_ID := &'buff_bind_thy_flesh'
const ANCHOR_KEY := 'anchor'

## Housekeeping, not a rule the player needs to read; the kit's effect text already says the chain
## ends when the object is destroyed.
func show_in_tooltip(kit:Kit) -> bool: return false

func triggers_on_event(unit:Unit, gear:GearCore, triggering_event:EventCore) -> bool:
	if not super.triggers_on_event(unit, gear, triggering_event): return false # our own death only
	return not chains_held_by(unit).is_empty()

## Every chain on the map that names this anchor, keyed by the character carrying it.
func chains_held_by(anchor:Unit) -> Dictionary[Unit, Array]:
	var held:Dictionary[Unit, Array] = {}
	if not is_instance_valid(anchor.map): return held
	var anchor_id := String(anchor.core.persistent_id)
	for unit:Unit in anchor.map.get_all_units():
		for buff:BuffCore in unit.state.buffs:
			if buff.base.compcon_id != CHAIN_BUFF_ID: continue
			if buff.get_state(ANCHOR_KEY, '') != anchor_id: continue
			held.get_or_add(unit, ([] as Array[BuffCore])).append(buff)
	return held

func activate(context:Context, activation:EventCore) -> void:
	var anchor:Unit = context.unit
	var held := chains_held_by(anchor)
	if activation.abort_when(held.is_empty()): return

	# Cleared against the death event itself rather than this activation, so that
	# buff_bind_thy_flesh.on_clear can see the anchor is already on its way out and does not queue a
	# second death for it when the last chain goes.
	var death:EventCore = context.event
	for unit:Unit in held.keys():
		UnitCondition.clear_buffs(death, unit, held[unit])

# Clause 1: "Create a void tear in a free space within SENSORS."
#
# Almost all of this is vanilla ActionSystemDeploy: deploy_to_sensors covers "within SENSORS" with no
# code, and the free-space requirement is standard deployment targeting. The only thing this subclass
# adds is the cap.
#
# The cap exists because tear routing costs one cached full-map sweep per tear, and the per-viewer
# union grows with tear count - 99 tears on a 30x30 map measured 370 ms. MAX_TEARS lives in
# tear_routing.gd so the cost and the limit on it stay in one file.
extends ActionSystemDeploy

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')

## Fetched from ContentLibrary by id, NOT loaded by path. A load() returns a fresh Resource whose
## compcon_id has never been assigned - that happens during ContentLibrary indexing - so applying it
## produced a buff that has_buff could never find again. The id also keeps this honest about the
## filename prefix rule: buff_ is what files this under get_buff at all.
const BUFF_ID := &'buff_tear_invisibility'


## Refuse the action outright at the cap rather than silently closing the oldest tear. Closing one
## the player placed deliberately, without being asked, is worse than being told no.
func is_available_to_activate(unit:Unit, gear:GearCore) -> bool:
	if not super.is_available_to_activate(unit, gear): return false
	return TearRouting.open_tears(unit.map).size() < TearRouting.MAX_TEARS

## Hooked at PLACEMENT rather than after activate(), which is the only correct place.
##
## place_deployable queues the spawn as an EVENT (action_system_deploy.gd:125-127) and returns; the
## tear does not exist on the map until that event resolves, well after activate() has finished. An
## earlier version compared open_tears() before and after `await super.activate(...)` to detect a
## placement - those counts are ALWAYS equal, so the cache was never invalidated on creation and the
## clause 6 buff was never handed out. Nothing in the suite noticed, because every routing spec
## places its tears directly rather than through this action.
##
## place_deployable_followup is vanilla's own extension point for exactly this, and it fires once per
## tear actually placed - including on redeploys.
func place_deployable_followup(context:Context, activation:EventCore, spawn_event:EventCore, deployable:Unit) -> void:
	super.place_deployable_followup(context, activation, spawn_event, deployable)

	var map:MapState = context.unit.map if Unit.is_valid(context.unit) else context.map
	if not is_instance_valid(map): return

	# A new tear changes what every tear-routed query answers, and the caches are keyed on tile.
	TearRouting.invalidate(map)
	_hand_out_tear_invisibility(map, context, activation)

## CLAUSE 6's delivery. "Attacks that pass through a tear treat targets as INVISIBLE."
##
## The buff has to be in place BEFORE an attack starts, because the only place invisibility is
## consumed (AttackUtil.check_if_invisibility_forces_miss, from event_unit_attack.gd:158) sits on a
## DEAD extension seam - probed and confirmed. There is no hook between "attack declared" and
## "invisibility consulted", so the answer must already be on one of the two units.
##
## Handed to EVERY character, not just the Banshee, because routing is universal by design: an enemy
## may shoot the Banshee's ally through the Banshee's own tear, and get_invisibility_summary only
## reads the buff off the two units in that pair.
##
## Cheaper than it looks, and this is what makes the breadth acceptable: the buff is INERT. It grants
## nothing until its condition finds that exact attacker/target pair routed through a tear, so what
## is handed out is a predicate, not a state. Nobody is "invisible" at rest.
##
## Deployables and markers are skipped - clause 6 says "targets", and a tear is not a character.
func _hand_out_tear_invisibility(map:MapState, context:Context, activation:EventCore) -> void:
	if not is_instance_valid(ContentLibrary.get_buff(BUFF_ID)): return
	for unit:Unit in map.get_all_units():
		if not Unit.is_valid(unit): continue
		if not unit.is_character(): continue
		if UnitCondition.has_buff(unit, BUFF_ID): continue
		UnitCondition.apply_buff_id(activation, unit, BUFF_ID, context.gear)

# Clause 1: "Create a void tear in a free space within SENSORS."
#
# Almost all of this is vanilla ActionSystemDeploy: deploy_to_sensors covers "within SENSORS" with no
# code, and the free-space requirement is standard deployment targeting. This subclass adds three
# things: the tear cap, an exemption from vanilla's refusal to deploy while INTANGIBLE, and clause
# 6's buff hand-out at placement. Each is documented at its own function below.
#
# The cap exists because tear routing costs one cached full-map sweep per tear, and the per-viewer
# union grows with tear count - 99 tears on a 30x30 map measured 370 ms. MAX_TEARS lives in
# tear_routing.gd so the cost and the limit on it stay in one file.
extends ActionSystemDeploy

const TearRouting := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_routing.gd')
const TearInvisibilityGrant := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/cp_the_keening/tear/tear_invisibility_grant.gd')


## Refuse the action outright at the cap rather than silently closing the oldest tear. Closing one
## the player placed deliberately, without being asked, is worse than being told no.
##
## DELIBERATELY NOT CHAINING TO SUPER (playtest fix 8.3). ActionSystemDeploy.is_available_to_activate
## is three lines (action_system_deploy.gd:20-23) and does not call ITS super either, so nothing is
## lost by restating it - and its first line is `if unit.has_status(INTANGIBLE): return false`, which
## is wrong for this action. That refusal is a sensible default for dropping a physical drone or mine
## while phased out of the world, but clause 1 carries no tangibility condition, and a window between
## tangible and intangible space is precisely the thing an INTANGIBLE Banshee should be able to open.
## Without this the frame's own Whispering locked its own core power out.
##
## The rest of super IS kept: disable_while_deployed is restated below so a later edit setting it on
## action_tear.tres still works. (It is currently false, so this is insurance, not behaviour.)
func is_available_to_activate(unit:Unit, gear:GearCore) -> bool:
	if not Unit.is_valid(unit): return false
	if disable_while_deployed and not UnitAction.get_deployables_from(unit, gear, deployable_frame.compcon_id).is_empty(): return false
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

	# CLAUSE 6's delivery. The buff has to be in place BEFORE an attack starts, because the only
	# place invisibility is consumed (AttackUtil.check_if_invisibility_forces_miss, from
	# event_unit_attack.gd:158) sits on a DEAD extension seam - probed and confirmed. There is no
	# hook between "attack declared" and "invisibility consulted", so the answer must already be on
	# one of the two units.
	#
	# THIS IS NO LONGER THE ONLY HAND-OUT. It used to be, and that was bug 1 of three: units that
	# arrived after the tear - reinforcements, drones, deployed allies - never got it, so clause 6
	# simply did not exist for them. unit_tile.gd_ext.gd's update_tracking_and_statuses override now
	# re-runs the same hand-out on every occupancy change. This call stays because it makes the buff
	# present the instant the tear lands rather than at the next map event.
	TearInvisibilityGrant.hand_out(map, activation)

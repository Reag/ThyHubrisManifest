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

## Refuse the action outright at the cap rather than silently closing the oldest tear. Closing one
## the player placed deliberately, without being asked, is worse than being told no.
func is_available_to_activate(unit:Unit, gear:GearCore) -> bool:
	if not super.is_available_to_activate(unit, gear): return false
	return TearRouting.open_tears(unit.map).size() < TearRouting.MAX_TEARS

func activate(context:Context, activation:EventCore) -> void:
	# Count before and after rather than trusting the base class's return value or exceptions: a
	# cancelled or invalid target, or a level exit, can make super.activate() abort having placed
	# nothing, and however it signals that internally is not something this file should have to know.
	var tears_before := TearRouting.open_tears(context.map).size()
	await super.activate(context, activation)
	var tears_after := TearRouting.open_tears(context.map).size()
	# Only invalidate when a tear actually changed what every tear-routed query answers. The cache
	# is keyed on tile, but rebuilding it is the expensive sweep the cache exists to avoid - no
	# point paying that cost for an activation that placed nothing.
	if tears_after != tears_before:
		TearRouting.invalidate(context.map)

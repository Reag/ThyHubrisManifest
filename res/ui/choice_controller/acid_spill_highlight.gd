# Shows which movement endpoints would trigger Acid Spill's terrain clause, BEFORE the player
# commits to a movement.
#
# ADDITIVE BY DESIGN. This overrides no base-game method: it listens to the same ChoiceBus signal
# the movement tilepicker listens to, and paints a Rangemesh channel the movement tilepicker does not
# use. If it fails to install, the highlight is missing and nothing else changes.
#
# Why it is safe to take Rangemesh.TYPE.ACTIVATE: tilepicker_movement.gd uses MOVE and BOOST for the
# range (via tilepicker.gd:130-136), AOE for the Ramjet straight-line preview, and SIGHT for LOS.
# ACTIVATE is touched only by tilepicker_compcon.gd and tilepicker_ability.gd, which are never active
# during a movement pick. We hide it on resolve regardless.
#
# Why PREDICTIVE rather than gated on the armed flag: the boost is not always taken as a separate
# action first. tilepicker.gd:130 offers boost-range tiles whenever the unit can boost, and picking
# one spends the boost as part of the move - so at highlight time the frame may not be armed yet.
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-04-acid-spill-design.md
extends Node

const CP_ID := &'cp_truth_in_filth'

static var choice_bus:ChoiceBus = load("res://ui/choice_controller/choice_bus.tres")
static var effect_bus:EffectsControllerBus = load("res://engine/gamemaster/effects_controller/effects_controller_bus.tres")

func _ready() -> void:
	choice_bus.on_choose_move_tile.connect(_on_choose_move_tile)

func _on_choose_move_tile(request:ChoiceRequest, unit, pathfinder, _can_cancel:bool) -> void:
	if not (unit is Unit) or not (pathfinder is Pathfinder): return
	# Unqualified: statics are callable without a prefix from inside their own script, and this file
	# has no class_name to qualify with.
	var qualifying:Array[Vector2i] = qualifying_endpoints(unit, pathfinder)
	if qualifying.is_empty(): return

	effect_bus.show_range(qualifying, Rangemesh.TYPE.ACTIVATE, ShrinkwrapStyle.VALID)
	# One-shot: the picker can be reopened many times in a turn and we must not stack connections.
	request.on_resolved.connect(_clear, CONNECT_ONE_SHOT)

func _clear() -> void:
	effect_bus.hide_range(Rangemesh.TYPE.ACTIVATE)

## Every reachable endpoint that a straight-line charge of at least boost speed could stop on.
##
## The straightness test is AoeCalculator.line, the same function passive_acid_spill.is_straight_full_speed
## uses and the same one the pathfinder uses for Ramjet - so the preview cannot disagree with what
## actually resolves. Boost speed likewise comes from UnitAction.get_boost_speed, which is what
## action_acid_spill_arm.gd records.
static func qualifying_endpoints(unit:Unit, pathfinder:Pathfinder) -> Array[Vector2i]:
	var qualifying:Array[Vector2i] = []
	if not Unit.is_valid(unit): return qualifying
	if not GearCore.is_valid(unit.core.loadout.get_by_compcon_id(CP_ID)): return qualifying
	if pathfinder.map == null: return qualifying

	var origin:Vector2i = pathfinder.origin_tile
	var boost_speed:int = UnitAction.get_boost_speed(unit)

	for tile:Vector2i in pathfinder.valid_destinations:
		var path:Array[Pathfinder.Step] = pathfinder.path_to(tile)
		if path.size() < boost_speed: continue
		var tiles:Array[Vector2i] = []
		for step:Pathfinder.Step in path: tiles.append(step.tile)
		if AoeCalculator.line(origin, tile, tiles.size(), pathfinder.map.shape) == tiles:
			qualifying.append(tile)

	return qualifying

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
# during a movement pick. Nothing is painted when no endpoint qualifies, so there is nothing to clear
# in that case - _clear only ever runs when show_range actually ran first.
#
# Why PREDICTIVE rather than gated on the armed flag: the boost is not always taken as a separate
# action first. tilepicker.gd:130 offers boost-range tiles whenever the unit can boost, and picking
# one spends the boost as part of the move - so at highlight time the frame may not be armed yet.
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-04-acid-spill-design.md
extends Node

const CP_ID := &'cp_truth_in_filth'

const AcidSpill := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_nuckelavee/cp_truth_in_filth/passive_acid_spill.gd')

static var choice_bus:ChoiceBus = load("res://ui/choice_controller/choice_bus.tres")
static var effect_bus:EffectsControllerBus = load("res://engine/gamemaster/effects_controller/effects_controller_bus.tres")

func _ready() -> void:
	choice_bus.on_choose_move_tile.connect(_on_choose_move_tile)

# The fifth parameter exists because the signal disagrees with itself: choice_bus.gd:99 DECLARES
# on_choose_move_tile with four parameters, but :102 EMITS it with five (valid_targets appended).
# Godot 4 errors when a connected callable has fewer parameters than the emit supplies - "Method
# expected 4 argument(s), but called with 5" - so a four-parameter handler here is not merely
# incomplete, it is never invoked at all, on every single movement pick. Vanilla's own receiver,
# tilepicker_movement.handle_activate, already carries the fifth parameter (defaulted, unused) for
# exactly this reason; this handler mirrors that shape.
func _on_choose_move_tile(request:ChoiceRequest, unit, pathfinder, _can_cancel:bool, _valid_targets:Array[Vector2i] = []) -> void:
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

## Every reachable, BUDGETED endpoint that a straight-line charge of at least boost speed could stop on.
##
## The straightness test is AoeCalculator.line, the same function passive_acid_spill.is_straight_full_speed
## uses and the same one the pathfinder uses for Ramjet - so the preview cannot disagree with what
## actually resolves. Boost speed likewise comes from UnitAction.get_boost_speed, which is what
## action_acid_spill_arm.gd records.
static func qualifying_endpoints(unit:Unit, pathfinder:Pathfinder) -> Array[Vector2i]:
	var qualifying:Array[Vector2i] = []
	if not Unit.is_valid(unit): return qualifying
	var gear:GearCore = unit.core.loadout.get_by_compcon_id(CP_ID)
	if not GearCore.is_valid(gear): return qualifying
	if pathfinder.map == null: return qualifying

	var origin:Vector2i = pathfinder.origin_tile
	var boost_speed:int = UnitAction.get_boost_speed(unit)
	# Safe only because pathfinder.gd:490 happens to exclude the origin tile from valid_destinations,
	# which is an incidental engine fact rather than a guarantee of this file's - make the zero case
	# explicit rather than relying on it.
	if boost_speed <= 0: return qualifying
	# A move with no boost at all - Ramjet absent, no BOOST_DISTANCE buff - satisfies
	# path.size() >= boost_speed on any full-speed straight move, since boost_speed then just equals
	# the frame's base move speed. Nothing arms and no terrain is laid in that case, so do not
	# highlight it. can_boost also covers IMMOBILIZED/SLOWED; is_armed covers a boost already spent
	# earlier this round (can_boost would be false again, but the charge still qualifies).
	if not (UnitAction.can_boost(unit) or AcidSpill.is_armed(gear, unit.map.game_core.round_count)):
		return qualifying

	for tile:Vector2i in pathfinder.valid_destinations:
		# valid_destinations is UNBUDGETED: pathfinder.gd:487-507 builds it from
		# Tile.get_all_within(origin, max(8, speed_with_boost), ...) filtered only for "has a path"
		# and "is a legal endpoint" - no movement budget applied. movable_tiles/boostable_tiles are
		# the budget-limited sets the tilepicker actually paints; skipping tiles outside both here
		# fixes reachability, and folds path COST (difficult terrain included) into the check for free,
		# since a too-expensive tile is excluded from these sets even if it is geometrically close enough.
		if not (pathfinder.is_movable(tile) or pathfinder.is_boostable(tile)): continue
		var path:Array[Pathfinder.Step] = pathfinder.path_to(tile)
		if path.size() < boost_speed: continue
		var tiles:Array[Vector2i] = []
		for step:Pathfinder.Step in path: tiles.append(step.tile)
		if AoeCalculator.line(origin, tile, tiles.size(), pathfinder.map.shape) == tiles:
			qualifying.append(tile)

	return qualifying

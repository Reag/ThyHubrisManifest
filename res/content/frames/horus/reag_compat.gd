# Compatibility layer between the 1.3.3 and 1.4.0 choice-bus APIs. Every prompt this mod makes that
# the two engines disagree on goes through here.
# Design: D:\DEV\lancer-tactics-claude\specs\2026-09-08-modkit-140-dual-compat-design.md
#
# RULE: no version-specific class is ever NAMED in this file - BrochureCore (1.4.0) and
# InformationalBrochure (1.3.3) would each fail to PARSE on the other engine, and a script that
# fails to parse takes every action that preloads it down with it, silently. They are reached via
# load() on a script path, and the bus is kept UNTYPED so member access resolves at runtime.
#
# Things that did NOT change and need no shim: choice_bus.choose_unit(units, can_cancel, specific),
# choice_bus.quick_yesno(tile, title, desc), choice_bus.telegraph_trait(...), effect_bus.show_range(...),
# effect_bus.show_target_line(...). Action scripts inherit `choice_bus` from Action/Buff/OnHitEffect,
# whose static var already points at the right path on each engine.
extends RefCounted

const BUS_140 := 'res://engine/choices/choice_bus.tres'
const BUS_133 := 'res://ui/choice_controller/choice_bus.tres'
const EFFECT_BUS := 'res://engine/gamemaster/effects_controller/effects_controller_bus.tres'
const BROCHURE_CORE_140 := 'res://engine/choices/brochure_core.gd'
const INFO_BROCHURE_133 := 'res://ui/choice_controller/informational_brochure/informational_brochure.gd'

## Mod-private request types (1.4.0). Every vanilla receiver filters on its own type, so these reach
## only our own picker (TILE_SET_TYPE) or nobody at all except the "any"-typed info panels (INFO_TYPE).
const TILE_SET_TYPE := &'reag_tile_set'
const INFO_TYPE := &'reag_info'

static var _bus = null       # untyped on purpose
static var _effect_bus = null

static func is_140() -> bool:
	return ResourceLoader.exists(BUS_140)

static func bus():
	if _bus == null: _bus = load(BUS_140 if is_140() else BUS_133)
	return _bus

static func effect_bus():
	if _effect_bus == null: _effect_bus = load(EFFECT_BUS)
	return _effect_bus

# ------------------------------------------------------------------ multiple choice

## Shows a menu and returns the chosen index, or -1 if the player cancelled / skipped.
## `choices` items are either a String or {text:String, disabled_reason:String} (a non-empty
## disabled_reason greys the option out and shows the reason). `desc` may be a translation key: both
## brochures auto-translate it. 1.4.0 requires the SpecificAction; 1.3.3 ignores it.
static func multiple_choice(specific:SpecificAction, choices:Array, title:String, desc:String = 'battle.multiple_choice.prompt', subtitle:String = '', can_cancel:bool = true) -> int:
	if is_140():
		var brochure = load(BROCHURE_CORE_140).create({title = title, description = desc, subtitle = subtitle, choices = choices})
		return await bus().choose_from_multiple_choice_for({brochure = brochure, using = specific, can_voluntarily_cancel = can_cancel})
	# 1.3.3: the brochure takes MultipleChoiceOption objects or plain Strings.
	var option_class = load(INFO_BROCHURE_133).MultipleChoiceOption
	var options:Array = []
	for choice in choices:
		if choice is Dictionary: options.append(option_class.create(str(choice.get('text', '')), str(choice.get('disabled_reason', ''))))
		else: options.append(choice)
	return await bus().choose_from_multiple_choice(options, title, desc, subtitle, can_cancel)

# ------------------------------------------------------------------ yes / no

## Yes/no with the two info panels: `using` lights the action panel, `whois` the unit panel. On
## 1.4.0 those are request parameters; on 1.3.3 they are the show_/hide_ bracket around the prompt.
static func yesno(tile:Vector2i, title:String, desc:String = '', using:SpecificAction = null, whois:Unit = null, encourage_yes:bool = true) -> bool:
	if is_140():
		return await bus().quick_yesno_for({
			tile = tile, title = title, description = desc, encourage_yes = encourage_yes,
			using = using, whois = whois,
		})
	if using != null: bus().show_using_action(using)
	if whois != null: bus().show_whois(whois)
	var answer:bool = await bus().quick_yesno(tile, title, desc, encourage_yes)
	if using != null: bus().hide_using_action()
	if whois != null: bus().hide_whois()
	return answer

# ------------------------------------------------------------------ whois marker (no question asked)

## Raise the whois panel on `unit` without asking anything, until hide_whois(handle). Returns a handle
## to hand back. 1.4.0: a request of a type nobody answers, which the "any"-typed WhoIsPanel shows for
## as long as it lives (and which the NEXT request's arrival deactivates - as the next targeting
## request also ended the 1.3.3 info pile). 1.3.3: choice_bus.show_whois, not awaited, like vanilla.
static func show_whois(unit:Unit):
	if is_140():
		var request = bus().create_request(INFO_TYPE, {whois = unit})
		bus().on_choice_request.emit(request) # tell the panels; deliberately NOT wait_for_response
		return request
	bus().show_whois(unit)
	return null

static func hide_whois(handle) -> void:
	if is_140():
		if handle != null and not handle.resolved: bus().end_request(handle)
		return
	bus().hide_whois()

# ------------------------------------------------------------------ pick one tile from a fixed set

## "Here is a list of tiles; pick one." Returns Tile.INVALID when nothing was offered or the player
## cancelled. 1.3.3: choose_target_tiles. 1.4.0 deleted that prompt; the mod reinstates it as
## reag_tile_set_picker (installed by choice_controller.tscn_ext.gd), answered here through the two
## public bus calls the vanilla *_for helpers use.
static func pick_tile_from(specific:SpecificAction, tiles:Array[Vector2i]) -> Vector2i:
	if tiles.is_empty(): return Tile.INVALID
	if is_140():
		var request = bus().create_request(TILE_SET_TYPE, {tiles = tiles, using = specific})
		await bus().wait_for_response(request)
		if request.aborted: return Tile.INVALID
		var picked:Array = request.response_data.target_tiles
		return picked[0] if not picked.is_empty() else Tile.INVALID
	var plan = await bus().choose_target_tiles(specific, tiles)
	if plan == null or plan.target_tiles.is_empty(): return Tile.INVALID
	return plan.target_tiles.front()

# ------------------------------------------------------------------ observing movement picks

## Calls on_pick(request, unit, pathfinder) every time a movement pick opens for the player. The
## wrapper is disconnected when the node that owns `on_pick` leaves the tree, so it is safe to call
## from a per-game node.
##
## TORN DOWN ON on_pick's OWNER EXITING THE TREE, and that guard is load-bearing, not tidiness. The
## adapter below is a bare closure with no bound object of its own - Godot only auto-disconnects a
## signal connection when the CONNECTED CALLABLE is itself bound to an Object (e.g. a plain
## `object.method` reference), and a lambda literal created inside a static function captures no
## such `self`. Without this, a caller whose node is freed and recreated - exactly what every spec
## does once per test via a fresh game - leaves one dangling connection per cycle on this bus, which
## is a `static var` and outlives every one of them. Measured 2026-09-08: omitting this crashed the
## Godot process with an access violation at GUT shutdown, after every test had already passed,
## every time a spec exercised a node connected this way more than once in a run.
static func connect_move_pick(on_pick:Callable) -> void:
	var wrapped:Callable
	if is_140():
		wrapped = func(request) -> void:
			if request.type == &'move_tile': on_pick.call(request, request.params.unit, request.params.pathfinder)
		bus().on_choice_request.connect(wrapped)
	else:
		# choice_bus.gd:99 declares four parameters and :102 emits five (valid_targets appended); a
		# four-parameter handler is never invoked, so the fifth is declared and ignored.
		wrapped = func(request, unit, pathfinder, _can_cancel, _valid_targets = []) -> void:
			on_pick.call(request, unit, pathfinder)
		bus().on_choose_move_tile.connect(wrapped)

	var owner_obj = on_pick.get_object()
	if owner_obj is Node:
		owner_obj.tree_exiting.connect(func() -> void:
			if is_140(): bus().on_choice_request.disconnect(wrapped)
			else: bus().on_choose_move_tile.disconnect(wrapped)
		, CONNECT_ONE_SHOT)

# ------------------------------------------------------------------ effects bus renames

static func hide_target_lines() -> void:
	if is_140(): effect_bus().hide_target_lines()
	else: effect_bus().hide_target_line()

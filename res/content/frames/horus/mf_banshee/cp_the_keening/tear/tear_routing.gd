# Tear routing for the Banshee. The brain behind clauses 3, 4 and 5.
#
# DELIBERATELY NOT A SCRIPT EXTENSION. The two .gd_ext.gd shims on unit_relation.gd and unit_tile.gd
# do nothing but delegate here, so every rule below is testable without an extension having to fire.
# This project has three confirmed cases of extensions that install cleanly and never run, so a
# testable brain is worth the indirection.
#
# HARD CONSTRAINT: nothing on the can_affect path may consult buffs. can_affect delegates to this
# file, and aura buff delivery is itself gated on can_affect (passive_aura.gd:68), so a buff lookup
# in the routing, geometry or tangibility code closes a real cycle. Ask about tears, geometry and
# tangibility STATUS - nothing else. THE ONE EXCEPTION is choose_tear, a verb-time pick reached only
# from an action's activate (Tear Move, Tear Close, Mourning Call) and never from can_affect: its
# is_player_controlled() call reads buff_hand_over_control (unit.gd:252), and that is fine THERE.
#
# THE RULE, after the agreed terrain relaxation and the 2026-09-08 collinearity correction:
#
#     routes(a, b) = tear IS ON THE LINE a<->b AND los(a -> tear) AND los(tear -> b)
#         for some open tear
#         AND exactly one of a, b is INTANGIBLE
#
# THE COLLINEARITY TERM IS NOT DECORATION - it is the difference between two abilities. Clauses 4
# and 5 say "if the LINE passes through a tear"; To Bend Reality says the Banshee may "use tears to
# change an attack's TRAJECTORY". Until 2026-09-08 this file implemented only the two LOS legs, which
# is a BENT path - To Bend Reality's rule - so on open ground an intangible Banshee could shoot very
# nearly anything a tear could see. Playtest found it ("I was able to attack a unit that was clearly
# not in a line from the tear"), and the real cost was that the core power and the signature trait
# stopped being distinguishable. See _tears_on_the_line, and note bends_within_range keeps the bent
# path on purpose.
#
# That second line was missing until the final review, and its absence was a real bug rather than a
# technicality. Clause 4 is "INTANGIBLE characters can draw line of sight to TANGIBLE targets if the
# line passes through a tear"; clause 5 is the mirror. BOTH require a tangibility mismatch, and
# nothing in the text grants a tangible pair anything. Without the check, an open tear was a free
# corner-peek for every unit on the map, on both teams - proven with a failing spec before this fix.
#
# The design's claim that "direction matters only to can_affect, which is a permission question, not
# a geometric one" was wrong. can_affect only ever REFUSES across the tangibility line, so a
# same-tangibility pair was never gated by it, and widening the geometry universally handed them
# sight that nothing took back. The rule is about PAIRS, and the gate has to live wherever the pair
# is known.
extends RefCounted

## Lowered from 99 on the 2026-09-06 measurements: 99 tears on a 30x30 map is 370 ms of sweep.
## Tunable - a starting value, not a ceiling.
const MAX_TEARS := 15

const TEAR_FRAME_ID := &'dep_tear_banshee'

## The bend proxy's frame. TBR relays an attack through a proxy standing on a tear, and that proxy
## must be tellable from every other targeting proxy on the map - see effective_tangibility.
const BEND_PROXY_FRAME_ID := &'dep_bend_proxy_banshee'

## Sentinel for "no explicit eye height given, fall back to the cached terrain-level sweep".
const NO_HEIGHT := -1

## map instance id -> (tile -> the tiles visible from it), at TERRAIN height.
##
## The outer level exists because a single GUT run creates many MapStates, and tile (2,2) on one map
## is not tile (2,2) on another - a bare tile-keyed dictionary would let a stale entry from an
## earlier map answer a query against a later one.
##
## STALENESS: entries depend on map.elevation_with_units and map.does_dynamic_zone_block_sight, both
## of which change when units move or smoke is laid. unit_tile.gd_ext.gd therefore invalidates on
## UnitTile.update_tracking_and_statuses, which the engine runs after moves, spawns and deaths. See
## that override for what is still not covered.
static var _visibility_cache:Dictionary = {}

## map instance id -> Array[Vector2i] of every open tear's tile on that map.
static var _tear_tile_cache:Dictionary = {}

## map instance id -> (persistent_id -> Unit). is_tile_in_los receives only a `whos_asking` id, but
## the pair rule needs the viewer's tangibility, so the id has to be resolved back to a unit. Doing
## that with a linear scan per call would be O(units) on a path the engine already calls a
## bottleneck; this makes it O(1) after the first miss.
static var _unit_by_id_cache:Dictionary = {}

## REENTRANCY GUARD, and it is load-bearing rather than defensive.
##
## unit_tile.gd_ext.gd overrides is_tile_in_los to consult this file. This file computes visibility
## with UnitTile.get_tiles_in_los_alt, which calls UnitTile.is_tile_in_los - the overridden one.
## Without this flag that is unbounded recursion: routing -> sweep -> override -> routing.
##
## While a sweep is in flight, routing answers "no tear route". That is correct, not a compromise:
## the sweep computes the ORDINARY line of sight the routing rule is built on top of, and letting a
## tear widen its own input would make the geometry self-referential.
##
## GDScript has no try/finally, so a throw inside the sweep would strand this true and silently kill
## all tear routing for the rest of the session. invalidate() resets it for that reason.
static var _computing := false

# ---------------------------------------------------------------------------- the pair rule

static func is_tear(unit:Unit) -> bool: return _frame_id(unit) == TEAR_FRAME_ID
static func is_bend_proxy(unit:Unit) -> bool: return _frame_id(unit) == BEND_PROXY_FRAME_ID

## Tangibility as it should be JUDGED, which is not always the tangibility a unit carries.
##
## TargetActionUtil.create_targeting_proxy spawns a unit with NO statuses - it inherits faction and
## owner and nothing else - so an attack relayed through a bend proxy is always tangible however the
## Banshee stands. can_affect reads has_status straight off the unit (unit_relation.gd:397), so
## without this a bend would launder tangibility in BOTH directions: refusing an INTANGIBLE Banshee
## its INTANGIBLE target, and permitting it a tangible one that To Bend Reality forbids.
##
## Reading through rather than applying the status is deliberate. UnitCondition.apply_status for
## INTANGIBLE runs handle_intangibilty_changing (unit_condition.gd:256-288), which strips buffs,
## detaches the katamari, plays an FX on unit.token.Bumper and queues valid-spot movement - far too
## much for a stand-in that lives for one activation. event_unit_intangible is not a lighter door:
## it CALLS apply_status at :34 and exists only for a reaction PRE hook.
static func effective_tangibility(unit:Unit) -> bool:
	if not Unit.is_valid(unit): return false
	if is_bend_proxy(unit):
		var owner_unit:Unit = unit.get_owner_unit()
		if Unit.is_valid(owner_unit): return owner_unit.has_status(Lancer.STATUS.INTANGIBLE)
	return unit.has_status(Lancer.STATUS.INTANGIBLE)

## Exactly one of the two is INTANGIBLE. The whole of clauses 4 and 5's precondition, in one place so
## both seams and any later caller ask the same question.
static func is_cross_tangible(a:Unit, b:Unit) -> bool:
	if not Unit.is_valid(a) or not Unit.is_valid(b): return false
	return a.has_status(Lancer.STATUS.INTANGIBLE) != b.has_status(Lancer.STATUS.INTANGIBLE)

## Every unit on the map whose tangibility differs from the viewer's - i.e. everyone this viewer
## could legitimately reach through a tear. Tears themselves are excluded: a tear is scenery, not
## something you route sight TO.
static func cross_tangible_units(map:MapState, viewer:Unit) -> Array[Unit]:
	var found:Array[Unit] = []
	if not is_instance_valid(map) or not Unit.is_valid(viewer): return found
	# A BEND PROXY IS NOT A WINDOW. To Bend Reality relays an attack through a proxy standing on a
	# tear, and that attack is governed by the trait's own rule - same tangibility, combined range -
	# not by the tear window's. Returning nothing here takes TWO of the window's THREE seams off a
	# bend: the LOS sweep (get_tiles_in_los, above) and the clause-7 range policing in
	# unit_tile.gd_ext.gd's get_tiles_within, both of which iterate this function. The THIRD seam -
	# unit_tile.gd_ext.gd's is_tile_in_los override - does not call this function at all (it asks
	# is_cross_tangible directly, since it only ever has one candidate pair to judge), so it carries
	# its own bend-proxy exclusion at the top of that override instead.
	if is_bend_proxy(viewer): return found
	for unit:Unit in map.get_all_units():
		if not Unit.is_valid(unit): continue
		if unit == viewer: continue
		if is_tear(unit): continue
		if is_cross_tangible(viewer, unit): found.append(unit)
	return found

# ---------------------------------------------------------------------------- tears

static func open_tears(map:MapState) -> Array[Unit]:
	if not is_instance_valid(map): return []
	var tears:Array[Unit] = []
	for unit:Unit in map.get_all_units():
		if not Unit.is_valid(unit): continue
		if is_tear(unit): tears.append(unit)
	return tears

static func tear_tiles(map:MapState) -> Array[Vector2i]:
	if not is_instance_valid(map): return []
	var map_id := map.get_instance_id()
	if _tear_tile_cache.has(map_id): return _tear_tile_cache[map_id]
	var tiles:Array[Vector2i] = []
	for tear:Unit in open_tears(map): tiles.append(tear.tile())
	_tear_tile_cache[map_id] = tiles
	return tiles

## Every open tear this UNIT owns. Ownership matters: routing is universal by design, but "who may
## reach in and drag a tear around" is not - nobody may move a tear they didn't place.
##
## Extracted from action_tear_move.gd's private _movable_tears (clause 8's own move verb) so it and
## Mourning Call's wider relocation (clause 9, action_mourning_call.gd's _maybe_relocate_tear) answer
## "which tears are mine" identically, rather than maintaining two copies of the same ownership check
## that could quietly drift apart.
static func owned_tears(unit:Unit) -> Array[Unit]:
	var mine:Array[Unit] = []
	if not Unit.is_valid(unit) or not is_instance_valid(unit.map): return mine
	for tear:Unit in open_tears(unit.map):
		if tear.state.is_owned_by(unit): mine.append(tear)
	return mine

# ---------------------------------------------------------------------------- picking a tear

## Loaded lazily rather than as a plain `static var ... = load(...)` (the shape every engine file
## uses). This script is preloaded by unit_tile.gd_ext.gd and unit_relation.gd_ext.gd, which
## ModLoader installs during mod_main's _init - far earlier than any engine script's own static
## initialisers run - and a static var initialiser would drag camera_bus.tres into that window for
## no benefit. Prompts go through Compat, which loads its bus lazily for the same reason.
const Compat := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/reag_compat.gd')
static var _camera_bus:CameraBus

static func _camera() -> CameraBus:
	if _camera_bus == null: _camera_bus = load('res://engine/level/camera/camera_bus.tres')
	return _camera_bus

## "Which of my tears?" - the ONE implementation, shared by clause 8's two verbs
## (action_tear_move.gd, action_tear_close.gd) and clause 9's relocation
## (action_mourning_call.gd's _maybe_relocate_tear).
##
## A TILE PICK, NEVER A UNIT PICK, AND THAT IS THE WHOLE POINT OF THIS FUNCTION EXISTING.
## All three sites used choice_bus.choose_unit(tears) until 2026-09-08, and all three were dead
## clicks in play. tilepicker_unit.gd builds its clickable set straight from each candidate's
## occupied_tiles() (lines 26-28), so a tear's tile lights up and looks pickable - but it resolves
## the click through get_pickable_units_at_tile (lines 87-90), which calls
## map.get_all_units_at_tile(tile) with include_markers defaulting to FALSE (map_state.gd:314-318).
## A tear is Frame.ENTITY.MARKER, so that list is always empty, and line 78-79 is a bare
## `if units_at_tile.is_empty(): pass` - no pick, no cancel, no feedback. The action hangs forever
## waiting for a choice that cannot arrive. The player reported it as "I can't seem to move the void
## tears"; action_bend_reality.gd had already documented the same trap and dodged it by targeting
## tiles, and this is that dodge made reusable.
##
## Compat.pick_tile_from offers the tile set as given (tilepicker_ability on 1.3.3, our own picker on 1.4.0)
## (update_tiles_in_range overrides it wholesale) and never asks what unit is standing there:
## tilepicker_compcon.handle_pressed_tile only ever uses the unit lookup to FILL IN pick.unit, and
## appends the pick regardless of whether it found one. So a marker's tile picks cleanly.
##
## Returns null when there is nothing to pick or the player cancelled - callers must treat null as
## an abort, not as "the first one".
static func choose_tear(specific:SpecificAction, tears:Array[Unit]) -> Unit:
	var candidates:Array[Unit] = []
	for tear:Unit in tears:
		if Unit.is_valid(tear): candidates.append(tear)
	if candidates.is_empty(): return null
	# ONE CANDIDATE, NO PROMPT. There is nothing to decide, and a prompt here is pure friction - it
	# was also, until this rewrite, an unanswerable one, which is how the single-tear case (much the
	# commonest) reproduced the bug every time.
	if candidates.size() == 1: return candidates.front()
	if not SpecificAction.is_valid(specific): return null

	# AI-CONTROLLED, NO PROMPT. fateofman's Cascades hands a cascading player mech to the AI and its
	# Cascade Personalities then runs every system on the mech through the AI. Its safety scan skips
	# an action whose script text contains a literal `choice_bus.` with no `is_player_controlled` -
	# a RAW text match, comments included (cascade_system_action_ai.gd:129-138, 1.43.0) - and it
	# cannot see our Compat. shim at all. Tear Move and Tear Close happen to be skipped TODAY because
	# their headers mention choice_bus.choose_unit in a comment; reword those comments, or hand the
	# mech to an AI that does not run the scan (GM Mode), and this prompt would be awaited forever.
	# So the guard is a defence, not a patch for a hang seen in play. Kill Host's shape
	# (action_kill_host.gd:135): decide here. The nearest tear is the default a player most often
	# picks; ties go to list order. spec/test_ai_safe_prompts.gd pins both halves. Design 2026-09-28 §4.
	if not specific.unit.is_player_controlled(): return nearest_tear(specific.unit, candidates)

	var tiles:Array[Vector2i] = []
	for tear:Unit in candidates:
		for tile:Vector2i in tear.occupied_tiles():
			if not tiles.has(tile): tiles.append(tile)
	if tiles.is_empty(): return null

	_camera().show_all_tiles(tiles, true)
	var picked:Vector2i = await Compat.pick_tile_from(specific, tiles)
	if picked == Tile.INVALID: return null
	return tear_at_tile(candidates, picked)

## The candidate closest to `unit` by UnitRelation.distance_between; ties resolve to the earlier
## entry, so the result is deterministic for a given list. Null for an empty or all-invalid list.
static func nearest_tear(unit:Unit, candidates:Array[Unit]) -> Unit:
	var best:Unit = null
	var best_distance:int = -1
	for tear:Unit in candidates:
		if not Unit.is_valid(tear): continue
		var distance:int = UnitRelation.distance_between(unit, tear)
		if best == null or distance < best_distance:
			best = tear
			best_distance = distance
	return best

## Resolve a picked tile back to one of `candidates`.
##
## Matches against the candidate list we already hold rather than asking the map, DELIBERATELY. The
## obvious `map.get_all_units_at_tile(tile)` is the exact call that made the unit pick dead, and
## even its `include_markers = true` form would answer with tears this caller has no business
## moving - somebody else's, or one outside the offered set. The list is the authority.
static func tear_at_tile(candidates:Array[Unit], tile:Vector2i) -> Unit:
	for tear:Unit in candidates:
		if not Unit.is_valid(tear): continue
		if tear.occupied_tiles().has(tile): return tear
	return null

# ---------------------------------------------------------------------------- collinearity

## Which of `candidates` lie ON THE LINE between the two tiles. The geometric half of clauses 4 and 5.
##
## Uses AoeCalculator.line_full - the engine's OWN line, the one LINE weapons fire down
## (range_pattern.gd:60) and the one the pathfinder walks for straight movement (pathfinder.gd:578,
## 678, 718) - so "on the line" means the same thing here as everywhere a player can see a line drawn.
## STRICT: no tolerance ring, no fudge. Author decision, 2026-09-08. The tear-move verb is free
## precisely so the player can line a tear up rather than being handed slack.
##
## BOTH DIRECTIONS, AND THAT IS LOAD-BEARING. AoeCalculator.line walks rings outward from the ORIGIN
## and keeps one tile per ring by angular proximity, so line(a,b) and line(b,a) need not contain the
## same tiles - a tie between two equally-angled tiles in a ring breaks whichever way the ring happens
## to be ordered. can_affect is asked as can_affect(a,b) at one call site and can_affect(b,a) at
## another (see unit_relation.gd_ext.gd's tear_bridges), and an asymmetric answer would let a
## character be shot by something it cannot shoot back at. Accepting a tear found on EITHER line makes
## the predicate symmetric by construction, which is why this returns a union rather than testing one
## direction. test_tear_routing.gd pins the symmetry directly.
##
## The union also settles the degenerate ends for free: line() starts at ring 1, so it never contains
## its own origin - a tear UNDER the viewer is missing from line(viewer, target) but present as the
## endpoint of line(target, viewer), and vice versa for a tear under the target. Standing in the
## window counts, in both directions.
##
## Takes the candidates rather than reading tear_tiles itself so callers can apply their own cheap
## rejects first - the two line walks are O(distance^2) via Tile.get_rings, so a caller with an
## arithmetic filter to hand should run it before paying for them.
static func _tears_on_the_line(map:MapState, from_tile:Vector2i, to_tile:Vector2i, candidates:Array[Vector2i]) -> Array[Vector2i]:
	var on_line:Array[Vector2i] = []
	if candidates.is_empty(): return on_line
	# AoeCalculator.line dereferences map_shape for its playability test, so a MapState without one
	# would crash rather than answer. Declining is the safe direction: it falls back to vanilla
	# geometry, exactly as the is_tile_in_los seam does when it cannot identify the viewer.
	if map.shape == null: return on_line
	var forward := AoeCalculator.line_full(from_tile, to_tile, map.shape)
	var backward := AoeCalculator.line_full(to_tile, from_tile, map.shape)
	for tear_tile:Vector2i in candidates:
		if forward.has(tear_tile) or backward.has(tear_tile): on_line.append(tear_tile)
	return on_line

## Is this one tile on the line between two others? The public face of _tears_on_the_line, for specs
## and for any caller that already knows which tear it means.
static func is_on_the_line(map:MapState, from_tile:Vector2i, to_tile:Vector2i, tile:Vector2i) -> bool:
	if not is_instance_valid(map): return false
	var candidates:Array[Vector2i] = [tile]
	return not _tears_on_the_line(map, from_tile, to_tile, candidates).is_empty()

# ---------------------------------------------------------------------------- routing

## Does some open tear bridge these two tiles? PURE GEOMETRY - it asks nothing about tangibility, so
## every caller must apply the pair rule itself. unit_relation.gd_ext.gd's tear_bridges already does;
## unit_tile.gd_ext.gd does it by only ever asking about cross-tangible units' tiles.
##
## `from_height` is the VIEWER's eye height. Vanilla line of sight measures from
## UnitTile.effective_height (floor plus the unit's own body), while the cached sweep below is
## computed at raw terrain elevation - so passing NO_HEIGHT here quietly measures the first leg from
## the ground and makes routing under-permissive over low walls. Pass the real height when you have
## it; is_tile_in_los is handed one, and get_tiles_in_los can compute one.
static func routes_between(map:MapState, from_tile:Vector2i, to_tile:Vector2i, from_height:int = NO_HEIGHT) -> bool:
	if _computing: return false # see _computing
	if not is_instance_valid(map): return false
	var tiles := tear_tiles(map)
	if tiles.is_empty(): return false # fast path: no open tear, no route, no sweep.
	# COLLINEARITY FIRST, then sight. "The line passes through a tear" is a geometric precondition on
	# the pair, not a second sight check - see _tears_on_the_line. Both LOS legs are kept behind it:
	# they carry the agreed terrain relaxation and reuse the visibility cache, and a tear on the line
	# behind a wall is still a tear you cannot see through.
	for tear_tile:Vector2i in _tears_on_the_line(map, from_tile, to_tile, tiles):
		if not _sees_from(map, from_tile, tear_tile, from_height): continue
		# The second leg is measured from the TEAR, whose own eye height is the terrain it sits on -
		# so the cached terrain-level sweep is the right answer here, not an approximation.
		if _sees(map, tear_tile, to_tile): return true
	return false

## The tiles this viewer may see through a tear: the occupied tiles of cross-tangible units it can
## route to, and nothing else.
##
## Deliberately NOT "every tile any tear can see". That was the periscope bug - it granted sight of
## empty ground and of same-tangibility units alike. It is also cheaper this way: the work is
## O(cross-tangible units) rather than O(map area).
static func tiles_visible_via_tears(map:MapState, viewer:Unit, from_tile:Vector2i, from_height:int = NO_HEIGHT) -> PackedInt64Array:
	var reachable := Tile.create_blank_bitwise_array()
	if _computing: return reachable # see _computing
	if not is_instance_valid(map) or not Unit.is_valid(viewer): return reachable
	if tear_tiles(map).is_empty(): return reachable
	for other:Unit in cross_tangible_units(map, viewer):
		for tile:Vector2i in other.occupied_tiles():
			if routes_between(map, from_tile, tile, from_height):
				Tile.add_to_bitwise_array(reachable, tile)
	return reachable

## CLAUSE 7's rule: "An attack cannot travel more than half its maximum range after passing through
## a tear."
##
## The text caps the post-tear leg and is silent on the total. Agreed reading (2026-09-06): a tear
## REDIRECTS reach rather than extending it, so the whole route must also fit inside the weapon's
## normal range. Both conditions:
##
##     dist(shooter -> tear) + dist(tear -> target) <= max_range
##     dist(tear -> target)                        <= half of max_range
##
## Util.half is the engine's own halving and rounds UP (Util.half(1) == 1), so an odd range is
## generous to the shooter - consistent with how the rest of the engine halves things.
##
## Ordered for cost deliberately: the two distance comparisons are arithmetic on tiles, while each
## _sees call can trigger a full-map sweep. Cheap rejects first.
static func routes_within_range(map:MapState, from_tile:Vector2i, to_tile:Vector2i, from_height:int, max_range:int) -> bool:
	if _computing: return false
	if not is_instance_valid(map): return false
	var tiles := tear_tiles(map)
	if tiles.is_empty(): return false
	var half:int = Util.half(max_range)
	var affordable:Array[Vector2i] = []
	for tear_tile:Vector2i in tiles:
		var after:int = Tile.distance(tear_tile, to_tile)
		if after > half: continue
		if Tile.distance(from_tile, tear_tile) + after > max_range: continue
		affordable.append(tear_tile)
	# The same collinearity precondition routes_between applies - this is the tear WINDOW with a range
	# budget bolted on, not a second geometry. Run after the arithmetic, before the sweeps: the two
	# line walks are O(distance^2) and the distance comparisons are two subtractions.
	for tear_tile:Vector2i in _tears_on_the_line(map, from_tile, to_tile, affordable):
		if not _sees_from(map, from_tile, tear_tile, from_height): continue
		if _sees(map, tear_tile, to_tile): return true
	return false

## A REFERENCE PREDICATE for TO BEND REALITY's range rule: "The combined distance must be within
## the weapon's range." NO PRODUCTION CALLER - the shipped range budget is enforced instead by
## action_bend_reality.gd's bendable_tear_tiles (the tear pick's own distance filter) together with
## the narrowed aim_range/range_pattern activate() applies to the followup. This function exists so
## the rule itself can be pinned down and tested independently of that mechanism; only
## test_to_bend_reality.gd calls it directly. Do not delete it as dead code on that account -
## re-pointing the tests at the production path instead is a bigger change than a docstring fix
## should carry.
##
## Same shape as routes_within_range with the half-range cap REMOVED and NO COLLINEARITY TERM, and
## deliberately a separate function rather than a parameterised one. Clause 7 belongs to the tear
## window and TBR is a different mode; keeping them apart means neither can drift when the other is
## edited.
##
## THE MISSING COLLINEARITY TERM IS THE WHOLE POINT OF THIS FUNCTION, not an oversight to be tidied
## up the next time the two are read side by side. To Bend Reality is the ability that "uses tears to
## change an attack's TRAJECTORY" - a bent path is exactly what it buys, and the player pays a core
## power and a tear pick for it. The tear window (routes_between, routes_within_range) requires the
## tear to sit ON the line, because clauses 4 and 5 say the line passes THROUGH it. Conflating the two
## is the 2026-09-07 playtest bug; do not re-conflate them by "fixing" this to match its neighbour.
##
## Note this asks nothing about tangibility. The same-tangibility precondition lives in can_affect,
## where the pair is known - see unit_relation.gd_ext.gd's bend_proxy_tangibility_differs.
##
## Ordered for cost, like its neighbour: arithmetic on tiles first, since each _sees call can trigger
## a full-map sweep.
static func bends_within_range(map:MapState, from_tile:Vector2i, to_tile:Vector2i, from_height:int, max_range:int) -> bool:
	if _computing: return false # see _computing
	if not is_instance_valid(map): return false
	var tiles := tear_tiles(map)
	if tiles.is_empty(): return false
	for tear_tile:Vector2i in tiles:
		if Tile.distance(from_tile, tear_tile) + Tile.distance(tear_tile, to_tile) > max_range: continue
		if not _sees_from(map, from_tile, tear_tile, from_height): continue
		if _sees(map, tear_tile, to_tile): return true
	return false

## Plain, UNROUTED line of sight between two tiles - no tear waypoint, just the ordinary sweep (or a
## height-aware check when from_height is given). A thin wrapper around _sees_from rather than a
## reimplementation, so it shares that function's cache and inherits this file's _computing guard.
##
## Exists because the bend pick's FIRST leg (Banshee -> candidate tear) must be ordinary sight, never
## sight bent through some OTHER open tear. action_bend_reality.gd's bendable_tear_tiles used to test
## a candidate tear by calling bends_within_range with the tear as both waypoint and destination,
## relying on los(tear -> tear) being trivially true so only the from -> tear leg actually mattered.
## That reasoning breaks the moment more than one tear is open: bends_within_range loops over EVERY
## open tear as a candidate waypoint, so a second tear W could bridge sight to a tear T the Banshee
## cannot actually see (banshee -> W -> T), offering T for the pick even though the real first leg
## (banshee -> T, unrouted) is blocked. MAX_TEARS is 15, so more than one open tear is the normal
## case, not an edge one. Use this helper for any "can the viewer plainly see this tile" question that
## must not itself be tear-routed.
static func sees_between(map:MapState, from_tile:Vector2i, to_tile:Vector2i, from_height:int = NO_HEIGHT) -> bool:
	if _computing: return false # see _computing
	if not is_instance_valid(map): return false
	return _sees_from(map, from_tile, to_tile, from_height)

## CLAUSE 6's predicate: "Attacks that pass through a tear treat targets as INVISIBLE."
##
## Deliberately the SAME question clauses 4 and 5 ask, so the two can never drift apart. That is not
## just tidiness - it is the reason the predicate is correct. A cross-tangible pair has NO ordinary
## interaction at all: can_affect refuses them outright unless a tear bridges the pair. So for any
## pair this returns true for, the attack is necessarily going through the tear; there is no second
## route it could have taken instead.
##
## The eye height is the ATTACKER's, matching how the seam measures the viewer's leg.
static func attack_routes_through_tear(attacker:Unit, target:Unit) -> bool:
	if not is_cross_tangible(attacker, target): return false
	if not is_instance_valid(attacker.map): return false
	var from_tile:Vector2i = attacker.tile()
	var height:int = UnitTile.effective_height(attacker, true, from_tile)
	return routes_between(attacker.map, from_tile, target.tile(), height)

## Resolve a `whos_asking` persistent id back to its unit. See _unit_by_id_cache.
static func unit_with_persistent_id(map:MapState, persistent_id:StringName) -> Unit:
	if not is_instance_valid(map) or persistent_id == &'': return null
	var map_id := map.get_instance_id()
	var by_id:Dictionary = _unit_by_id_cache.get(map_id, {})
	var cached = by_id.get(persistent_id)
	if Unit.is_valid(cached): return cached
	for unit:Unit in map.get_all_units():
		if not Unit.is_valid(unit): continue
		by_id[unit.core.persistent_id] = unit
	_unit_by_id_cache[map_id] = by_id
	cached = by_id.get(persistent_id)
	return cached if Unit.is_valid(cached) else null

# ---------------------------------------------------------------------------- cache

## Drop every cache for one map. Call whenever a tear opens, moves or closes, when terrain changes,
## or when units move - see the staleness note on _visibility_cache.
##
## Also resets _computing. A throw inside the sweep would otherwise strand that flag true and
## silently disable all tear routing for the rest of the session, with nothing to indicate why;
## GDScript has no try/finally to do it at the throw site.
static func invalidate(map:MapState) -> void:
	_computing = false
	if not is_instance_valid(map):
		_visibility_cache.clear()
		_tear_tile_cache.clear()
		_unit_by_id_cache.clear()
		return
	var map_id := map.get_instance_id()
	_visibility_cache.erase(map_id)
	_tear_tile_cache.erase(map_id)
	_unit_by_id_cache.erase(map_id)

static func _frame_id(unit:Unit) -> StringName:
	if not Unit.is_valid(unit): return &''
	if unit.core == null or unit.core.frame == null: return &''
	return unit.core.frame.compcon_id

static func _visibility_of(map:MapState, tile:Vector2i) -> PackedInt64Array:
	var map_id := map.get_instance_id()
	var by_tile:Dictionary = _visibility_cache.get(map_id, {})
	if by_tile.has(tile): return by_tile[tile]
	_computing = true
	var visible := UnitTile.get_tiles_in_los_alt(map, tile)
	_computing = false
	by_tile[tile] = visible
	_visibility_cache[map_id] = by_tile
	return visible

static func _sees(map:MapState, from_tile:Vector2i, to_tile:Vector2i) -> bool:
	return Tile.in_bitwise_array(_visibility_of(map, from_tile), to_tile)

## Like _sees, but measured from a specific eye height rather than from the terrain. Uncached by
## design: it runs once per tear for the viewer's leg only, and caching per (tile, height) pair would
## cost more to key than the call saves.
static func _sees_from(map:MapState, from_tile:Vector2i, to_tile:Vector2i, from_height:int) -> bool:
	if from_height == NO_HEIGHT: return _sees(map, from_tile, to_tile)
	_computing = true
	var seen := UnitTile.is_tile_in_los_alt(map, from_height, to_tile, from_tile)
	_computing = false
	return seen

# COMPAT: what this mod does when a third-party mod has redefined a word on one of our cards.
#
# Pins the DECISIONS taken where a third-party mechanism meets one of ours - not "must compose",
# which would remove the author's judgement, but whichever way the ruling went. What it buys is that
# a third-party update moving the mechanism goes RED here, instead of silently invalidating a ruling
# written in prose.
#
# Registry of contested seams, read at DESIGN time:
# skills/lancer-tactics-content-authoring/references/compat-seams.md
# Design: specs/2026-09-16-mod-compatibility-design.md
#
# EVERY ASSERTION HERE PRINTS WHEN IT SKIPS. A resident mod is a convention, not a guarantee, and a
# silent skip reads green while testing nothing.
extends GutTest

const FrameIsolation := preload('res://testkit/frame_isolation.gd')
const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')

const TALENTS_MOD := 'gavstarb-talents_1st_party'
## House Guard rank 1: a hidden buff, adjacency_range = 2, only_to_allies.
const HOUSE_GUARD_BUFF := &'buff_front_rank_adjacency_range'
## The helper the talents mod adds to UnitRelation; its presence is this file's mod check.
const TALENTS_HELPER := &'get_adjacency_range_alt'

const DISEASE := &'ms_disease'
const SPREADER := &'action_spreader'

# The Draugr infects the VICTIM; the MOVER stands two tiles from the victim - one tile outside
# vanilla adjacency, and exactly the ring House Guard pulls in.
const DRAUGR_TILE := Vector2i(0, 0)
const VICTIM_TILE := Vector2i(2, 2)
const TWO_TILES_OUT := Vector2i(4, 4) # Chebyshev 2 from (2,2)

var game:Gamemaster
var draugr:Unit


func before_each() -> void:
	game = SpecFactory.setup_gamemaster(self)
	draugr = fresh(DRAUGR_TILE, Faction.AI_ENEMY)
	draugr.core.equip_system(DISEASE)
	draugr.core.full_repair()

func after_each() -> void:
	Dice.CHEAT_ROLL_QUEUE.clear()


# ---------------------------------------------------------------- fixture helpers

## Same shape as test_spreader.gd's _fresh, which this file deliberately mirrors.
func fresh(tile:Vector2i, faction:Faction.SIDE) -> Unit:
	var unit := SpecFactory.create_unit(game.map, tile, faction)
	FrameIsolation.isolate_frame(unit)
	unit.core.frame.stat.heat = 30
	unit.core.full_repair()
	unit.core.current.heat = 0
	return unit

## A unit the Spreader is guaranteed to land on.
func victim(faction:Faction.SIDE) -> Unit:
	var unit := fresh(VICTIM_TILE, faction)
	unit.core.frame.stat.edef = -10
	return unit

func spread_onto(unit:Unit) -> void:
	Dice.CHEAT_ROLL_QUEUE.append(20)
	await SpecFactory.use(game, draugr, DISEASE, SPREADER, unit)

func give_house_guard(unit:Unit) -> void:
	SpecFactory.apply_buff(unit, HOUSE_GUARD_BUFF)

func talents_adjacency_available() -> bool:
	return UnitRelation.has_method(TALENTS_HELPER)

## Announce the skip rather than passing quietly. gut.p AND pass_test - pass_test alone does not
## print its message at the default log level, so a skip would read as a silent green.
func skipped_without_talents() -> bool:
	if talents_adjacency_available(): return false
	var message := 'SKIPPED: %s is not resident, so House Guard cannot widen anything. Restore the residency set with restore-links.ps1.' % TALENTS_MOD
	gut.p(message)
	pass_test(message)
	return true


# ===================== THE SEAM: HOUSE GUARD WIDENS is_adjacent =====================

## THE SPREADER IS THE ONLY PLACE IN THIS MOD THAT CAN SEE THE WIDENING.
##
## Measured 2026-09-16 across every .gd in res/: buff_spreader.gd is the ONLY file that calls
## UnitRelation.is_adjacent (:42 and :73). Everything else measures a radius itself -
## distance_between or get_characters_within - and House Guard overrides neither, so no other card
## in this mod can be reached by it. This test is the guard on that claim: if a future card starts
## asking is_adjacent, the seam surface grows and this file needs a new row.
##
## Reddened by: any new is_adjacent / adjacent_characters caller under res/.
func test_the_spreader_is_still_this_mods_only_adjacency_consumer() -> void:
	var callers:Array[String] = []
	for path in gd_files_under('res://unpacked/Reag-ThyHubris/res/content'):
		var text := FileAccess.get_file_as_string(path)
		if text.contains('UnitRelation.is_adjacent') or text.contains('UnitRelation.adjacent_characters'):
			callers.append(path.get_file())
	assert_eq(callers, ['buff_spreader.gd'] as Array[String],
		'buff_spreader.gd is the only content file reading vanilla adjacency.')

func gd_files_under(dir:String) -> Array[String]:
	var found:Array[String] = []
	var handle := DirAccess.open(dir)
	if handle == null: return found
	for file_name in handle.get_files():
		if file_name.get_extension() == 'gd': found.append(dir.path_join(file_name))
	for sub_dir in handle.get_directories():
		found.append_array(gd_files_under(dir.path_join(sub_dir)))
	return found


# ===================== THE RULING =====================

## RULING, 2026-09-16: THE SPREADER RESPECTS WIDENED ADJACENCY, AND NO CODE CHANGES.
##
## Three reasons, in order of weight:
##
##  1. It is the ENGINE's answer, not ours. buff_spreader asks UnitRelation.is_adjacent, the vanilla
##     helper; House Guard widens that helper deliberately. Refusing the widening would mean either
##     calling the talents mod's own get_adjacency_range_alt (a third-party dependency inside a core
##     mechanic) or hand-rolling a distance check in place of the engine's - both worse.
##  2. VANILLA TAKES THE SAME WIDENING ON THE SAME CALL. buff_drain_systems_specter.gd:18 - the file
##     buff_spreader.gd was modelled on, and says so in its header - is
##     `UnitRelation.is_adjacent(triggering_unit, unit)`, identical shape and identical argument
##     order. If widened adjacency reaching the Spreader is wrong, it is wrong for the Specter too.
##     Diverging would make our card behave differently from the vanilla card it copies, under the
##     same mod - which is the real inconsistency.
##  3. The exposure is narrow and thematic. House Guard's buff is only_to_allies, so the widening
##     pulls in the MOVER'S OWN ALLIES and nobody else - see the two tests below. A House Guard
##     pilot catches their own infected ally's disease from one tile further out. House Guard is a
##     talent about standing close to allies; this is that, with a cost.
##
## These two tests are the ruling. If it is ever reversed, they invert.

## The ordinary case - an ENEMY victim - is untouched, because the buff is only_to_allies.
##
## An untouched CHEAT_ROLL_QUEUE is the real assertion: a zero Infection count would also be
## produced by a check that ran and passed, so the count alone cannot tell "never triggered" from
## "triggered and got lucky".
func test_house_guard_does_not_widen_the_spreader_toward_an_enemy_victim() -> void:
	if skipped_without_talents(): return
	var infected := victim(Faction.AI_ENEMY)
	var mover := fresh(TWO_TILES_OUT, Faction.PLAYER)
	give_house_guard(mover)
	await spread_onto(infected)

	Dice.CHEAT_ROLL_QUEUE.append(1) # would be a failed Systems check, if one were ever asked for
	await SpecFactory.start_turn(game, mover)

	assert_eq(Infection.count(mover), 0, 'An enemy two tiles out still does not infect.')
	assert_false(Dice.CHEAT_ROLL_QUEUE.is_empty(), 'And no check was rolled at all.')

## The narrow case that DOES widen: the infected unit is the mover's own ally.
func test_house_guard_widens_the_spreader_toward_an_infected_ally() -> void:
	if skipped_without_talents(): return
	var infected := victim(Faction.PLAYER)
	var mover := fresh(TWO_TILES_OUT, Faction.PLAYER)
	give_house_guard(mover)
	await spread_onto(infected)

	Dice.CHEAT_ROLL_QUEUE.append(1) # failed Systems check
	await SpecFactory.start_turn(game, mover)

	assert_eq(Infection.count(mover), 1, 'RULED: House Guard carries the contagion one tile further.')
	assert_true(Dice.CHEAT_ROLL_QUEUE.is_empty(), 'A check was rolled.')

## The control: identical setup without the talent, so the test above cannot pass for the wrong
## reason. Two tiles is two tiles.
func test_without_house_guard_the_same_ally_is_out_of_reach() -> void:
	if skipped_without_talents(): return
	var infected := victim(Faction.PLAYER)
	var mover := fresh(TWO_TILES_OUT, Faction.PLAYER)
	await spread_onto(infected)

	Dice.CHEAT_ROLL_QUEUE.append(1)
	await SpecFactory.start_turn(game, mover)

	assert_eq(Infection.count(mover), 0, 'Without the talent, two tiles out is untouched.')
	assert_false(Dice.CHEAT_ROLL_QUEUE.is_empty(), 'No check was rolled.')


# ===================== THE ASYMMETRY, WHICH IS NOT OURS =====================

## HOUSE GUARD MAKES is_adjacent ASYMMETRIC, AND OUR OWN unit_relation.gd_ext.gd SAYS IT IS NOT.
##
## is_adjacent(a, b) is adjacent_characters(a).has(b) (unit_relation.gd:7-8), so ONLY the first
## argument's buffs widen it. Put House Guard on the victim instead of the mover and nothing widens:
## the mover asks its own adjacency, and the mover has no talent.
##
## That matters beyond this test, because our own unit_relation.gd_ext.gd carries the comment
## "Adjacency is symmetric everywhere else in the engine - is_adjacent(a, b) and is_adjacent(b, a)
## are the same question", which is true of VANILLA and false while the talents mod is installed.
## The comment was corrected on 2026-09-16 rather than the code: Thy Hubris widens BOTH directions
## for at-distance grapples, deliberately, which is the symmetric thing to do - it is House Guard
## that takes the one-directional shortcut.
func test_the_widening_is_one_directional_so_the_victims_talent_does_nothing() -> void:
	if skipped_without_talents(): return
	var infected := victim(Faction.PLAYER)
	var mover := fresh(TWO_TILES_OUT, Faction.PLAYER)
	give_house_guard(infected) # on the VICTIM this time, not the mover
	await spread_onto(infected)

	Dice.CHEAT_ROLL_QUEUE.append(1)
	await SpecFactory.start_turn(game, mover)

	assert_eq(Infection.count(mover), 0, 'The victim having the talent widens nothing.')
	assert_false(Dice.CHEAT_ROLL_QUEUE.is_empty(), 'No check was rolled.')

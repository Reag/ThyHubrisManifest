# Plague-Vent Dispersal - the placement half of the core power.
#
#   "Flood a |BLAST 2| centered within |RANGE 2| with sickly fog until the end of your next turn.
#    Hostile characters in the area must make a |SYSTEMS save|, taking 2 |INFECTION| on a failure or
#    1 on a success."   (gear.cp_cupiditas_vitae.action_plague_vent_dispersal.effect)
#
# An ActionSystemDeploy subclass (action_type = PROTOCOL, consumes_cp) placing dep_plague_fog, a
# MARKER deployable built on vanilla's smoke-cloud recipe: mt_plague_fog carries a PassiveTerrainZone
# with a BLAST 2 range pattern and the fx, and mt_expiration kills it at the end of the owner's next
# turn (buff_expiration.gd:16-48, keyed on get_owner_unit_or_self).
#
# TWO SETUP GATES, both of which look like broken content when missed:
#   - A PROTOCOL is refused unless unit.state.is_using_protocols, which only event_turn_start opens
#     (unit_action.gd:141). Without SpecFactory.start_turn every activation dies with
#     "[ Gear not available ] reason : protocol".
#   - consumes_cp is refused unless unit.core.has_core_power (unit_action.gd:145). It defaults true
#     on a fresh UnitCore (unit_core.gd:30), so the spec only has to CLEAR it to test the negative.
#
# NO PROMPT IS EXPECTED ANYWHERE. Supplying target tiles turns off player_decides
# (target_action_util.gd:192-194), which is how vanilla's smoke grenade behaves too. The watcher
# below asserts that rather than assuming it - a silent prompt here would hang the whole suite.
#
# Dice: UnitHasecheck rolls one d20 per save (no accuracy dice, since nothing here adds a mod), so
# CHEAT_ROLL_QUEUE takes one value per hostile in the blast, in map order. 1 fails, 20 passes.
extends GutTest

const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')
const PlagueFog := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/cp_cupiditas_vitae/plague_fog.gd')
const PromptWatcher := preload('res://testkit/prompt_watcher.gd')
const DRAUGR_FRAME := 'res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/mf_draugr.tres'

const CORE_POWER := &'cp_cupiditas_vitae'
const PROTOCOL := &'action_plague_vent_dispersal'
const CENTRE := Vector2i(2, 2)

var game:Gamemaster
var draugr:Unit
var watcher:PromptWatcher

func before_each():
	game = SpecFactory.setup_gamemaster(self, false, SpecFactory.create_combat(Landscape.create_default(Vector2i(20, 20))))
	draugr = SpecFactory.create_unit(game.map, Vector2i(2, 0))
	draugr.core.change_mech_frame(load(DRAUGR_FRAME))
	SpecFactory.apply_passive_buffs(draugr)
	draugr.core.frame.stat.heat = 20
	draugr.core.current.heat = 0
	watcher = add_child_autoqfree(PromptWatcher.new())

func after_each():
	Dice.CHEAT_ROLL_QUEUE.clear()

func _enemy_at(tile:Vector2i, faction:Faction.SIDE = Faction.AI_ENEMY) -> Unit:
	var unit := SpecFactory.create_unit(game.map, tile, faction)
	unit.core.frame.stat.health = 40
	unit.core.full_repair()
	unit.core.current.heat = 0
	return unit

## Open the protocol phase, then vent at CENTRE (two tiles from the Draugr at (2, 0)).
func _vent(rolls:Array = [], tile:Vector2i = CENTRE) -> void:
	await SpecFactory.start_turn(game, draugr)
	Dice.CHEAT_ROLL_QUEUE.append_array(rolls)
	await SpecFactory.use(game, draugr, CORE_POWER, PROTOCOL, [tile])

func _fogs() -> Array[Unit]:
	return PlagueFog.all_on(game.map)

func test_the_protocol_places_one_fog_at_the_target_tile():
	await _vent()
	var fogs := _fogs()
	assert_eq(fogs.size(), 1, 'Exactly one cloud, at the tile that was picked.')
	if fogs.is_empty(): return
	assert_eq(fogs[0].tile(), CENTRE, 'And it is centred there.')
	assert_true(fogs[0].state.is_owned_by(draugr), 'The Draugr owns it, which is what mt_expiration keys on.')

func test_it_spends_the_core_power():
	assert_true(draugr.core.has_core_power, 'Fixture: the Draugr starts with its core power.')
	await _vent()
	assert_false(draugr.core.has_core_power, 'consumes_cp.')

func test_it_cannot_be_used_without_a_core_power():
	draugr.core.has_core_power = false
	await _vent()
	assert_eq(_fogs().size(), 0, 'No core power, no fog. (Look for "reason : NO_CORE_POWER" in the log.)')

func test_it_asks_the_player_nothing():
	# Supplied tiles bypass choose_compcon_plan entirely. If this ever regresses, the suite hangs
	# rather than failing, so the assertion is cheap insurance on a real risk.
	await _vent()
	assert_eq(watcher.prompts.size(), 0, 'No choice-bus request of any kind was raised.')

func test_a_hostile_in_the_blast_that_fails_its_save_takes_two_infection():
	var victim := _enemy_at(Vector2i(2, 3)) # one tile from the centre: inside BLAST 2
	await _vent([1])
	assert_eq(Infection.count(victim), 2, 'Failed SYSTEMS save: 2 INFECTION.')

func test_a_hostile_in_the_blast_that_passes_its_save_takes_one():
	var victim := _enemy_at(Vector2i(2, 3))
	await _vent([20])
	assert_eq(Infection.count(victim), 1, 'Passed SYSTEMS save: 1 INFECTION.')

func test_a_hostile_outside_the_blast_takes_nothing():
	var bystander := _enemy_at(Vector2i(2, 6)) # four tiles from the centre: outside BLAST 2
	await _vent([1])
	assert_eq(Infection.count(bystander), 0, 'BLAST 2 is BLAST 2.')

func test_an_ally_in_the_blast_takes_nothing():
	var friend := _enemy_at(Vector2i(2, 3), Faction.PLAYER)
	await _vent([1])
	assert_eq(Infection.count(friend), 0, '"Hostile characters in the area" - the Draugr does not gas its own.')

func test_the_draugr_itself_takes_nothing():
	# It stands two tiles from the centre, i.e. inside its own Blast 2.
	await _vent([1])
	assert_eq(Infection.count(draugr), 0, 'It is not hostile to itself.')

func test_the_helper_answers_who_is_standing_in_it():
	var inside := _enemy_at(Vector2i(2, 3))
	var outside := _enemy_at(Vector2i(2, 6))
	await _vent([20])
	var fogs := _fogs()
	if fogs.is_empty(): return fail_test('a fog was placed.')
	assert_true(PlagueFog.covers(fogs[0], inside), 'One tile out is covered.')
	assert_false(PlagueFog.covers(fogs[0], outside), 'Four tiles out is not.')
	assert_true(PlagueFog.owner_is_inside(fogs[0]), 'And the Draugr, two tiles out, is standing in its own cloud.')

func test_it_lasts_until_the_end_of_the_draugrs_next_turn():
	# mt_expiration: the owner's turn START stamps STARTED_TURN_KEY, the owner's turn END then kills
	# it (buff_expiration.gd:34-45). Placed during turn N it therefore survives the end of N.
	await _vent([20])
	assert_eq(_fogs().size(), 1, 'Fixture: placed.')
	await SpecFactory.end_turn(game, draugr)
	assert_eq(_fogs().size(), 1, 'Still there at the end of the turn it was placed on.')
	await SpecFactory.start_turn(game, draugr)
	assert_eq(_fogs().size(), 1, 'And through the whole of the next turn.')
	await SpecFactory.end_turn(game, draugr)
	assert_eq(_fogs().size(), 0, 'It dies at the end of the Draugr\'s next turn.')

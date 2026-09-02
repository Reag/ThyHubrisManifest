# DHIYED Observation - the Erinyes' core power.
#
# The two abilities themselves are still stubs; what is implemented is the EFFICIENT tag, which the
# source book applies to core powers that are refunded at the end of combat.
#
# Refunding happens on the unit's next spawn rather than at combat_end - the approach
# fateofman-imi_alt_frames takes for the Tritton's Fusillade. Same net effect, since the point of
# Efficient is that the core power is there for the NEXT scene, and it survives scene endings that
# never reach the mech.
extends GutTest

const CORE_POWER_ID := &'cp_dhiyed_observation'

var game:Gamemaster
var erinyes:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	erinyes = SpecFactory.create_unit(game.map, Vector2i(0, 0))
	erinyes.core.equip_system(CORE_POWER_ID)

func test_a_spent_core_power_is_refunded_for_the_next_scene():
	erinyes.core.has_core_power = false
	await game.execute_event(&'event_unit_spawn', {unit = erinyes, target_tiles = [erinyes.tile()]})
	assert_true(erinyes.core.has_core_power, 'Efficient handed the core power back.')

func test_an_unspent_core_power_is_left_alone():
	# Guards against the refund reaction firing pointlessly every time anything spawns.
	erinyes.core.has_core_power = true
	await game.execute_event(&'event_unit_spawn', {unit = erinyes, target_tiles = [erinyes.tile()]})
	assert_true(erinyes.core.has_core_power, 'Still there, and nothing needed doing.')

func test_punishment_is_never_pressed_as_a_button():
	# "no action required": it is spent by the engine when the player accepts the offer during a
	# roll, never clicked, so it reports itself unavailable and hides rather than sitting in the
	# action bar as a button that appears to do nothing.
	var kit:Kit = ContentLibrary.get_kit(CORE_POWER_ID)
	if not Kit.is_valid(kit): return fail_test('%s loaded.' % CORE_POWER_ID)
	var gear:GearCore = erinyes.get_gear(CORE_POWER_ID)
	for action:Action in kit.actions:
		if action.get_id() != &'action_punishment': continue
		assert_false(action.is_available_to_activate(erinyes, gear), 'It is spent, not activated.')
		return
	fail_test('action_punishment is on the kit.')

# ============================== Punishment ==============================
# One CHEAT_D20_ROLL buff covers both bullets, because
# Dice.roll_d20_with_player_interventions is called from attack_roll.gd AND unit_hasecheck.gd.
# The spec responder accepts every offer (chosen_multiple_choice_index defaults to 0), so these read
# as "the player said yes".

const BLAST_WEAPON := &'mw_rocket_propelled_grenade'
const GRENADE_KIT := &'ms_pattern_b_hex_charges'
const GRENADE_ACTION := &'action_frag_grenade'

func _enemy(tile:Vector2i) -> Unit:
	return SpecFactory.create_unit(game.map, tile, Faction.AI_ENEMY)

## Equipping a kit does not apply its passive buffs - buff_punishment only exists on the unit once
## the passives have been run. full_repair happens inside, so core power is set afterwards.
func _arm(unit:Unit, has_core:bool) -> void:
	SpecFactory.apply_passive_buffs(unit)
	unit.core.has_core_power = has_core

func test_punishment_turns_our_attack_into_a_crit():
	var enemy := _enemy(Vector2i(4, 4))
	erinyes.core.equip_system(BLAST_WEAPON)
	_arm(erinyes, true)
	SpecFactory.start_turn(game, erinyes)
	var health_before:int = enemy.core.current.health

	Dice.CHEAT_ROLL_QUEUE.append_array([2, 2, 2, 2]) # would miss outright, let alone crit
	await SpecFactory.use_solo(game, erinyes, BLAST_WEAPON, [enemy.tile()])

	assert_false(erinyes.core.has_core_power, 'Accepting the offer spent the core power.')
	assert_lt(enemy.core.current.health, health_before, 'And the attack landed.')

func test_punishment_forces_a_target_to_fail_its_save():
	var enemy := _enemy(Vector2i(4, 4))
	erinyes.core.equip_system(GRENADE_KIT)
	_arm(erinyes, true)
	SpecFactory.start_turn(game, erinyes)

	Dice.CHEAT_ROLL_QUEUE.append_array([20, 20, 20, 20]) # would sail past any save target
	await SpecFactory.use(game, erinyes, GRENADE_KIT, GRENADE_ACTION, [enemy.tile()])

	assert_false(erinyes.core.has_core_power, 'Accepting the offer spent the core power.')

func test_nothing_is_offered_without_a_core_power():
	var enemy := _enemy(Vector2i(4, 4))
	erinyes.core.equip_system(BLAST_WEAPON)
	_arm(erinyes, false)
	SpecFactory.start_turn(game, erinyes)
	var health_before:int = enemy.core.current.health

	Dice.CHEAT_ROLL_QUEUE.append_array([2, 2, 2, 2])
	await SpecFactory.use_solo(game, erinyes, BLAST_WEAPON, [enemy.tile()])

	assert_eq(enemy.core.current.health, health_before, 'The 2 missed, as it should have.')

func test_it_does_not_meddle_with_someone_elses_attack():
	# Every d20 in the game passes through the intervention hook, so the buff has to keep its hands
	# off rolls that are none of the Erinyes' business.
	var attacker := _enemy(Vector2i(4, 4))
	var victim := _enemy(Vector2i(5, 4))
	attacker.core.equip_system(BLAST_WEAPON)
	_arm(erinyes, true)
	SpecFactory.start_turn(game, attacker)

	Dice.CHEAT_ROLL_QUEUE.append_array([2, 2, 2, 2])
	await SpecFactory.use_solo(game, attacker, BLAST_WEAPON, [victim.tile()])

	assert_true(erinyes.core.has_core_power, 'Our core power is untouched by an enemy attack.')

func test_it_does_not_sabotage_our_own_save():
	# The Erinyes forcing a 1 on a save IT has to make would be a spectacular own goal. The offer is
	# gated on us being the one forcing the save and somebody else being the one rolling.
	var thrower := _enemy(Vector2i(4, 4))
	thrower.core.equip_system(GRENADE_KIT)
	_arm(erinyes, true)
	SpecFactory.start_turn(game, thrower)

	Dice.CHEAT_ROLL_QUEUE.append_array([20, 20, 20, 20])
	await SpecFactory.use(game, thrower, GRENADE_KIT, GRENADE_ACTION, [erinyes.tile()])

	assert_true(erinyes.core.has_core_power, 'We did not spend our core power against ourselves.')

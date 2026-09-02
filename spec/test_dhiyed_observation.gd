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

func test_punishment_cannot_be_spent_while_it_is_a_stub():
	# It shows in the action bar greyed out so the name can be checked in game, but a core power that
	# costs CP and does nothing should not be activatable.
	var kit:Kit = ContentLibrary.get_kit(CORE_POWER_ID)
	if not Kit.is_valid(kit): return fail_test('%s loaded.' % CORE_POWER_ID)
	var gear:GearCore = erinyes.get_gear(CORE_POWER_ID)
	for action:Action in kit.actions:
		if action.get_id() != &'action_punishment': continue
		assert_false(action.is_available_to_activate(erinyes, gear), 'Punishment is inert for now.')
		return
	fail_test('action_punishment is on the kit.')

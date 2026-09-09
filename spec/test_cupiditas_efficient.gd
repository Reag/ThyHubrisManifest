# CUPIDITAS VITAE is Efficient: the core point comes back for the next scene.
#
# A copy of the Erinyes' action_dhiyed_observation_efficient - an ActionReaction on unit_spawn that
# restores has_core_power. Refunding on the unit's NEXT SPAWN rather than on combat_end is
# fateofman-imi_alt_frames' trick, and it survives a scene ending in ways that never reach the mech:
# destroyed, exited, or a campaign save/load between scenes.
#
# Unconditional on purpose: a mech has exactly one core power, so restoring the point on spawn
# cannot hand back anything that was spent on something else.
extends GutTest

const DRAUGR_FRAME := 'res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/mf_draugr.tres'

const CORE_POWER := &'cp_cupiditas_vitae'
const PROTOCOL := &'action_plague_vent_dispersal'
const EFFICIENT := &'action_cupiditas_vitae_efficient'

var game:Gamemaster
var draugr:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self, false, SpecFactory.create_combat(Landscape.create_default(Vector2i(20, 20))))
	draugr = SpecFactory.create_unit(game.map, Vector2i(2, 0))
	draugr.core.change_mech_frame(load(DRAUGR_FRAME))
	SpecFactory.apply_passive_buffs(draugr)
	draugr.core.frame.stat.heat = 20
	draugr.core.current.heat = 0

func after_each():
	Dice.CHEAT_ROLL_QUEUE.clear()

func test_the_refund_is_on_the_core_power():
	var kit:Kit = ContentLibrary.get_kit(CORE_POWER)
	if not Kit.is_valid(kit): return fail_test('%s loaded.' % CORE_POWER)
	var action_ids:Array[StringName] = []
	for action:Action in kit.actions: action_ids.append(action.get_id())
	assert_true(action_ids.has(EFFICIENT), 'The Efficient refund is one of the core power actions.')

func test_spending_the_core_power_and_spawning_again_gets_it_back():
	await SpecFactory.start_turn(game, draugr)
	Dice.CHEAT_ROLL_QUEUE.append_array([20])
	await SpecFactory.use(game, draugr, CORE_POWER, PROTOCOL, [Vector2i(2, 2)])
	assert_false(draugr.core.has_core_power, 'Fixture: Plague-Vent spent it.')
	await game.execute_event('event_unit_spawn', {unit = draugr, target_tiles = [Vector2i(6, 6)]})
	assert_true(draugr.core.has_core_power, 'And the next scene starts with it back.')

func test_a_spawn_with_the_core_power_intact_changes_nothing():
	assert_true(draugr.core.has_core_power, 'Fixture: unspent.')
	await game.execute_event('event_unit_spawn', {unit = draugr, target_tiles = [Vector2i(6, 6)]})
	assert_true(draugr.core.has_core_power, 'Still there, and nothing was logged about it.')

func test_the_efficient_glossary_term_is_registered_and_written():
	# GlossaryItem.find_key_from_label refuses a key whose .desc is missing (glossary_item.gd:203-206),
	# so both rows are load-bearing; and the term is not in vanilla's own glossary list, so mod_main
	# has to append it or |efficient| renders as plain text everywhere in the mod.
	assert_true(GlossaryItem.cached_term_keys.has(&'lancer.term.efficient'),
		'mod_main.gd registered the term.')
	assert_ne(tr('lancer.term.efficient'), 'lancer.term.efficient', 'It has a label.')
	assert_ne(tr('lancer.term.efficient.desc'), 'lancer.term.efficient.desc', 'And a description.')
	assert_eq(GlossaryItem.find_key_from_label('efficient'), 'lancer.term.efficient',
		'And the label resolves back to the key, which is what turns |efficient| into a link.')

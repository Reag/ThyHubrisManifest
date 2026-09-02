# Know Thy Sins.
#
#   "When a chained character starts their turn, they take |1 BURN| for each condition and status
#    they have."
#
# Rides the chain from Bind Thy Flesh: the condition is simply "is this character chained to one of
# our anchors", so this trait has no trigger machinery of its own beyond reacting to the turn start.
#
# Note it requires the anchor to still be STANDING, not merely for the buff to be present. Destroying
# the anchor ends the chain, and a character should not keep burning for a shackle that is no longer
# there.
extends GutTest

const TRAIT_ID := &'mt_know_thy_sins'
const BIND_TRAIT_ID := &'mt_bind_thy_flesh'
const CHAIN_BUFF_ID := &'buff_bind_thy_flesh'
const ANCHOR_FRAME_ID := &'dep_chain_erinyes'

var game:Gamemaster
var erinyes:Unit
var victim:Unit
var anchor:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	erinyes = SpecFactory.create_unit(game.map, Vector2i(0, 0))
	erinyes.core.equip_system(BIND_TRAIT_ID)
	erinyes.core.equip_system(TRAIT_ID)
	victim = SpecFactory.create_unit(game.map, Vector2i(3, 3), Faction.AI_ENEMY)
	anchor = await _spawn_anchor(Vector2i(2, 2))

func _spawn_anchor(tile:Vector2i) -> Unit:
	var anchor_core := UnitCore.create(erinyes.get_faction(), ContentLibrary.get_mech_frame(ANCHOR_FRAME_ID))
	var spawned := Unit.create(anchor_core)
	UnitAction.set_deployable_owner(spawned, erinyes, erinyes.get_gear(BIND_TRAIT_ID))
	await game.execute_event(&'event_unit_spawn', {unit = spawned, target_tiles = [tile]})
	return spawned

func _chain(unit:Unit) -> void:
	var chain_buff:Buff = ContentLibrary.get_buff(CHAIN_BUFF_ID)
	var buff_core := UnitCondition.apply_buff(SpecFactory.dummy_event(), unit, chain_buff, erinyes.get_gear(BIND_TRAIT_ID))
	chain_buff.bind(buff_core, anchor, unit)

func _give_statuses(unit:Unit, statuses:Array) -> void:
	for status:StringName in statuses: SpecFactory.apply(unit, status)

## Burn taken over the turn start, ignoring whatever was already smouldering.
func _burn_from_starting_turn(unit:Unit) -> int:
	unit.set_current_burn(0)
	await SpecFactory.start_turn(game, unit)
	return unit.state.burn

func test_a_chained_character_burns_once_for_each_status():
	_chain(victim)
	_give_statuses(victim, [&'impaired', &'slowed', &'jammed'])
	assert_eq(await _burn_from_starting_turn(victim), 3, 'Three statuses, three burn.')

func test_the_burn_tracks_the_number_of_statuses():
	_chain(victim)
	_give_statuses(victim, [&'impaired'])
	assert_eq(await _burn_from_starting_turn(victim), 1, 'One status, one burn.')

func test_a_chained_character_with_no_statuses_does_not_burn():
	_chain(victim)
	assert_eq(await _burn_from_starting_turn(victim), 0, 'Nothing to answer for, nothing to burn.')

func test_an_unchained_character_does_not_burn():
	_give_statuses(victim, [&'impaired', &'slowed'])
	assert_eq(await _burn_from_starting_turn(victim), 0, 'Statuses alone are not enough; it must be chained.')

func test_it_stops_once_the_chain_is_broken():
	_chain(victim)
	_give_statuses(victim, [&'impaired', &'slowed'])
	assert_eq(await _burn_from_starting_turn(victim), 2, 'Burning while chained.')

	UnitCondition.clear_buff_id(SpecFactory.dummy_event(), victim, CHAIN_BUFF_ID)
	assert_eq(await _burn_from_starting_turn(victim), 0, 'And not once it is free.')

func test_it_stops_once_the_anchor_is_destroyed():
	# "or the object is moved or destroyed" ends the chain, so it should end the burning too.
	_chain(victim)
	_give_statuses(victim, [&'impaired', &'slowed'])
	assert_eq(await _burn_from_starting_turn(victim), 2, 'Burning while the shackle stands.')

	await game.execute_event(&'event_unit_die', {unit = anchor})
	assert_eq(await _burn_from_starting_turn(victim), 0, 'Nothing binds it once the shackle is gone.')

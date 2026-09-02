# Bind Thy Flesh - the trigger.
#
#   "When the Erinyes creates an area pattern (such as a LINE or BURST), and a character is hit by
#    or fails a save against the effect, the Erinyes may create a Chain on an object within the
#    area."
#
# The chain itself is specced in test_bind_thy_flesh.gd; these cover only what makes one appear.
# The trait is an ActionReaction on attack_declared, the way mt_skirmisher reacts to its own attack,
# and reads DeclaredAttackSummary off the triggering context: all_attacked_tiles for the pattern,
# attack_rolls for who was hit.
#
# Attacks are fired with a vanilla BLAST 2 weapon (the GMS rocket propelled grenade) rather than
# Erinyes gear, because the trait keys off the *pattern*, not off any particular weapon.
extends GutTest

const TRAIT_ID := &'mt_bind_thy_flesh'
const BUFF_ID := &'buff_bind_thy_flesh'
const BLAST_WEAPON := &'mw_rocket_propelled_grenade'
const SINGLE_TARGET_WEAPON := &'mw_assault_rifle'
const ANCHOR_FRAME_ID := &'dep_chain_erinyes'

var game:Gamemaster
var erinyes:Unit
var enemy_near:Unit
var enemy_far:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	erinyes = SpecFactory.create_unit(game.map, Vector2i(0, 0))
	erinyes.core.equip_system(TRAIT_ID)
	# Both inside a BLAST 2 centred on (4,4), and durable enough to survive it - a crit from the
	# grenade one-shots a stock Everest, and a dead character cannot be chained.
	enemy_near = _tough_enemy(Vector2i(4, 4))
	enemy_far = _tough_enemy(Vector2i(3, 4))
	SpecFactory.start_turn(game, erinyes)

func _tough_enemy(tile:Vector2i) -> Unit:
	var enemy := SpecFactory.create_unit(game.map, tile, Faction.AI_ENEMY)
	enemy.core.current.health = 100
	return enemy

## Fire a weapon at a tile with every attack roll forced to hit.
func _fire(weapon_id:StringName, at_tile:Vector2i) -> void:
	erinyes.core.equip_system(weapon_id)
	Dice.CHEAT_ROLL_QUEUE.append_array([20, 20, 20, 20])
	await SpecFactory.use_solo(game, erinyes, weapon_id, [at_tile])

func _chain_count() -> int:
	var chained:int = 0
	for unit:Unit in game.map.get_all_units():
		if UnitCondition.has_buff(unit, BUFF_ID): chained += 1
	return chained

func _anchors() -> Array[Unit]:
	var anchors:Array[Unit] = []
	for unit:Unit in game.map.get_all_units():
		if Frame.is_valid(unit.core.frame) and unit.core.frame.compcon_id == ANCHOR_FRAME_ID:
			anchors.append(unit)
	return anchors

func test_an_area_pattern_chains_the_characters_it_hits():
	assert_eq(_chain_count(), 0, 'Nobody is chained to begin with.')
	await _fire(BLAST_WEAPON, enemy_near.tile())
	assert_eq(_chain_count(), 2, 'Both characters the blast caught were chained, not just one.')

func test_everyone_caught_chains_to_a_single_shared_anchor():
	# The user's rule: every character hit is chained, all to the same point.
	await _fire(BLAST_WEAPON, enemy_near.tile())
	assert_eq(_anchors().size(), 1, 'Exactly one anchor was created for the pattern.')
	assert_eq(_anchor_id_of(enemy_near), _anchor_id_of(enemy_far), 'And both are tethered to it.')

func _anchor_id_of(unit:Unit) -> String:
	for buff:BuffCore in unit.state.buffs:
		if buff.base.compcon_id == BUFF_ID: return buff.get_state('anchor', '')
	return ''

func test_the_anchor_is_inside_the_pattern():
	await _fire(BLAST_WEAPON, enemy_near.tile())
	var anchors := _anchors()
	if anchors.is_empty(): return fail_test('An anchor was created.')
	assert_lte(Tile.distance(anchors[0].tile(), enemy_near.tile()), 2,
		'The anchor sits within the blast it came from.')

func test_a_single_target_attack_does_not_chain():
	# "creates an area pattern" is the condition; a plain rifle shot must not trigger it.
	await _fire(SINGLE_TARGET_WEAPON, enemy_near.tile())
	assert_eq(_chain_count(), 0, 'No chain from a single-target attack.')
	assert_eq(_anchors().size(), 0, 'And no anchor.')

func test_a_second_blast_does_not_re_leash_an_already_chained_character():
	# buff_bind_thy_flesh does not stack, so a second application would REPLACE the first
	# (unit_condition.gd:721) and silently re-measure the leash at the new distance. The trigger
	# skips characters that are already chained so the first chain is the one that sticks.
	await _fire(BLAST_WEAPON, enemy_near.tile())
	var first_leash:int = _leash_of(enemy_near)
	assert_gte(first_leash, 0, 'The first blast chained it.')

	await _fire(BLAST_WEAPON, enemy_near.tile())
	assert_eq(_leash_of(enemy_near), first_leash, 'The second blast left the original leash alone.')

func _leash_of(unit:Unit) -> int:
	for buff:BuffCore in unit.state.buffs:
		if buff.base.compcon_id == BUFF_ID: return buff.get_state('leash', -1)
	return -1

# ============================ the chain visual ============================
# Feedback matters here: without a drawn chain there is nothing on screen saying the trait fired,
# and the anchor is the thing the enemy has to shoot to break it.

func _chain_lines_from(anchor:Unit) -> Array:
	var gear:GearCore = anchor.core.loadout.get_by_compcon_id(&'mt_chain_erinyes')
	if not GearCore.is_valid(gear): return []
	var passive:Passive = gear.kit.passives.front() if not gear.kit.passives.is_empty() else null
	if passive == null: return []
	return passive.get_attached_fx(gear, anchor)

func test_the_anchor_draws_one_chain_per_bound_character():
	await _fire(BLAST_WEAPON, enemy_near.tile())
	var anchors := _anchors()
	if anchors.is_empty(): return fail_test('An anchor was created.')
	assert_eq(_chain_lines_from(anchors[0]).size(), 2, 'One chain drawn to each of the two bound characters.')

func test_the_anchor_draws_nothing_before_anyone_is_bound():
	# Guards against the passive drawing to every unit on the map rather than to its own chains.
	await _fire(BLAST_WEAPON, enemy_near.tile())
	var anchors := _anchors()
	if anchors.is_empty(): return fail_test('An anchor was created.')

	for unit:Unit in game.map.get_all_units():
		UnitCondition.clear_buff_id(SpecFactory.dummy_event(), unit, BUFF_ID)
	assert_eq(_chain_lines_from(anchors[0]).size(), 0, 'No chains once nobody is bound.')

func test_the_anchor_is_visible():
	# It starts as an object the player has to be able to see and shoot; a blank sprite would make
	# the whole effect invisible.
	var frame:Frame = ContentLibrary.get_mech_frame(ANCHOR_FRAME_ID)
	if not Frame.is_valid(frame): return fail_test('%s loaded.' % ANCHOR_FRAME_ID)
	assert_false(frame.sprites.is_empty(), 'The anchor has a sprite.')
	if frame.sprites.is_empty(): return
	# Frame.SPRITE_DEPLOYABLE_DEFAULT and get_default_sprite() both went away in modkit 1.3.3, so
	# this names the sprite we chose instead of comparing against the engine's fallback.
	assert_true(frame.sprites.front().resource_path.contains('celestial_shackle'),
		'And it is the shackle, not the blank it started with.')

# ============================ anchor cleanup ============================
# An anchor nobody is chained to is just litter on the battlefield.

## Break a chain the way the game does - the chained character spends its quick action on the HULL
## check, forced to pass. Clearing the buff through SpecFactory.dummy_event() instead would not do:
## on_clear queues the anchor's death onto the event it is given, and a dummy event never runs it.
func _clear_chain(unit:Unit) -> void:
	for specific:SpecificAction in UnitAction.get_situational_actions(unit):
		if specific.gear.kit.compcon_id != &'mt_chain_erinyes': continue
		Dice.CHEAT_ROLL_QUEUE.append(20) # pass the HULL check
		await SpecFactory.use_specific(game, specific)
		return
	fail_test('%s was offered an escape action.' % unit.core.get_mech_name())

func test_the_anchor_survives_while_anyone_is_still_bound():
	await _fire(BLAST_WEAPON, enemy_near.tile())
	assert_eq(_anchors().size(), 1, 'An anchor was created.')

	await _clear_chain(enemy_near)
	assert_eq(_anchors().size(), 1, 'It stays while the second character is still chained.')

func test_the_anchor_goes_when_the_last_chain_does():
	await _fire(BLAST_WEAPON, enemy_near.tile())
	if _anchors().is_empty(): return fail_test('An anchor was created.')

	await _clear_chain(enemy_near)
	await _clear_chain(enemy_far)
	assert_eq(_anchors().size(), 0, 'The anchor left with the last chain.')

func test_the_anchor_goes_when_the_last_chained_character_dies():
	# The other way a chain ends. Buffs are not necessarily cleared through clear_buff when their
	# holder leaves the map, so this is the case most likely to leave litter behind.
	await _fire(BLAST_WEAPON, enemy_near.tile())
	if _anchors().is_empty(): return fail_test('An anchor was created.')

	await game.execute_event(&'event_unit_die', {unit = enemy_near})
	await game.execute_event(&'event_unit_die', {unit = enemy_far})
	assert_eq(_anchors().size(), 0, 'No anchor left once everyone it held is gone.')

func test_two_characters_chained_to_one_anchor_can_both_break_free_in_the_same_turn():
	# The escape lives on the shared anchor gear, and Action's per-turn limit is recorded against
	# the GEAR rather than the unit. At the defaults a QUICK action is 1/turn, so the first
	# character to break free consumed the allowance for everyone chained to that anchor and the
	# rest were stuck until the next round. Regression guard for the lifted limit.
	await _fire(BLAST_WEAPON, enemy_near.tile())
	await _clear_chain(enemy_near)
	assert_false(UnitCondition.has_buff(enemy_near, BUFF_ID), 'The first character broke free.')
	await _clear_chain(enemy_far)
	assert_false(UnitCondition.has_buff(enemy_far, BUFF_ID), 'And so did the second, in the same turn.')

# ======================== the save half of the condition ========================
# "...and a character is hit by OR FAILS A SAVE against the effect". Grenades and other area systems
# never make an attack roll - a frag grenade is an ActionSystemGrenade dealing damage through
# queue_damage_events_with_save_for_half - so attack_declared never fires and only the forced_save
# path catches them. Found in manual play: a thrown grenade chained nobody while a LINE attack did.

const GRENADE_KIT := &'ms_pattern_b_hex_charges'
const GRENADE_ACTION := &'action_frag_grenade'

## Throw a grenade at a tile with every save forced to fail (1s) rather than every attack forced to hit.
func _throw_grenade(at_tile:Vector2i) -> void:
	erinyes.core.equip_system(GRENADE_KIT)
	Dice.CHEAT_ROLL_QUEUE.append_array([1, 1, 1, 1, 1, 1])
	await SpecFactory.use(game, erinyes, GRENADE_KIT, GRENADE_ACTION, [at_tile])

func test_a_grenade_chains_the_characters_that_fail_its_save():
	assert_eq(_chain_count(), 0, 'Nobody is chained to begin with.')
	await _throw_grenade(enemy_near.tile())
	assert_gt(_chain_count(), 0, 'Failing the save against a blast chains you.')

func test_a_grenade_makes_only_one_anchor_for_everyone_it_catches():
	# One save event fires per character, so without grouping by activation each failed save would
	# drop its own shackle.
	await _throw_grenade(enemy_near.tile())
	assert_eq(_anchors().size(), 1, 'One anchor for the whole grenade.')

func test_everyone_a_grenade_catches_shares_the_one_anchor():
	await _throw_grenade(enemy_near.tile())
	if _chain_count() < 2: return pending('The blast only caught one character; nothing to share.')
	assert_eq(_anchor_id_of(enemy_near), _anchor_id_of(enemy_far), 'Both chained to the same anchor.')

func test_a_chained_character_is_offered_only_its_own_anchors_escape():
	# Seen in play: a Blackbeard tethered once had three break-free actions, one from every anchor
	# standing on the map. ActionSystemClearBuff matches the buff by id alone, and its optional
	# "applied by this gear" filter is no help - our chains are applied by the Erinyes' trait, not
	# by any anchor - so every anchor offered its escape to every chained character.
	await _fire(BLAST_WEAPON, enemy_near.tile())
	assert_eq(_anchors().size(), 1, 'The blast made an anchor.')

	# A second anchor from some other effect, spawned directly so the test is about cross-talk
	# rather than about weapon reload rules.
	var other_core := UnitCore.create(erinyes.get_faction(), ContentLibrary.get_mech_frame(ANCHOR_FRAME_ID))
	var other_anchor := Unit.create(other_core)
	await game.execute_event(&'event_unit_spawn', {unit = other_anchor, target_tiles = [Vector2i(0, 4)]})
	assert_eq(_anchors().size(), 2, 'Two anchors are standing.')

	var offered:Array = UnitAction.get_situational_actions(enemy_near).filter(
		func(specific:SpecificAction) -> bool: return specific.gear.kit.compcon_id == &'mt_chain_erinyes')
	assert_eq(offered.size(), 1, 'Only the anchor it is actually chained to offers a way out.')

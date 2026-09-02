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
	assert_ne(frame.get_default_sprite(), Frame.SPRITE_DEPLOYABLE_DEFAULT, 'And it is not the missing-frame placeholder.')

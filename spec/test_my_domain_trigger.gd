# My Domain - the trigger.
#
#   "The Kraken can |Grapple| characters at least partially within any |Bursts| centered on itself."
#
# The grapple, the adjacency and the tether are specced in test_my_domain.gd; these cover only what
# makes one happen.
#
# Fired with the ENCLAVE-Pattern Support Shield, a vanilla HA system that is a self-centred BURST 3
# (pattern = 4, value = 3 on action_enclave_pattern_support_shield.tres). It is not chosen at
# random: it sits at rank 1 of the Saladin license, which li_kraken clones, so this is gear the
# Kraken genuinely fields rather than a contrivance.
#
# BLAST is the control. The trait names BURST specifically, and the two are different shapes in this
# engine - a burst is built from the acting unit's own tiles, a blast is placed on a point - so a
# blast must not trigger it however many characters it catches.
extends GutTest

const ModChoiceResponder := preload('res://testkit/mod_choice_responder.gd')

const TRAIT_ID := &'mt_my_domain'
const TETHER_BUFF_ID := &'buff_my_domain_tether'
const BURST_SYSTEM := &'ms_enclave_pattern_support_shield' ## self-centred BURST 3
const BLAST_WEAPON := &'mw_rocket_propelled_grenade'       ## BLAST 2, placed on a point

const KRAKEN_TILE := Vector2i(0, 0)
const INSIDE_BURST := Vector2i(2, 0)      ## within BURST 3 of the Kraken
const ALSO_INSIDE_BURST := Vector2i(0, 2) ## and so is this
const OUTSIDE_BURST := Vector2i(9, 9)     ## comfortably beyond it

var game:Gamemaster
var responder:ModChoiceResponder
var kraken:Unit
var near_enemy:Unit
var other_near_enemy:Unit
var far_enemy:Unit

func before_each():
	# add_responder = false: we install our own, which records the prompts it was shown.
	game = SpecFactory.setup_gamemaster(self, false, null, {}, false)
	responder = add_child_autoqfree(ModChoiceResponder.new())

	kraken = SpecFactory.create_unit(game.map, KRAKEN_TILE)
	kraken.core.equip_system(TRAIT_ID)
	near_enemy = _tough_enemy(INSIDE_BURST)
	other_near_enemy = _tough_enemy(ALSO_INSIDE_BURST)
	far_enemy = _tough_enemy(OUTSIDE_BURST)
	SpecFactory.start_turn(game, kraken)

func _tough_enemy(tile:Vector2i) -> Unit:
	var enemy := SpecFactory.create_unit(game.map, tile, Faction.AI_ENEMY)
	enemy.core.current.health = 100 # a dead character cannot be grappled
	return enemy

func _use_burst() -> void:
	kraken.core.equip_system(BURST_SYSTEM)
	await SpecFactory.use_solo(game, kraken, BURST_SYSTEM)

func _use_blast(at_tile:Vector2i) -> void:
	kraken.core.equip_system(BLAST_WEAPON)
	Dice.CHEAT_ROLL_QUEUE.append_array([20, 20, 20, 20])
	await SpecFactory.use_solo(game, kraken, BLAST_WEAPON, [at_tile])

## Everyone the Kraken is currently holding.
func _held() -> Array[StringName]:
	var held:Array[StringName] = []
	for grapple:SpecificAction in UnitCondition.get_outgoing_grapples(kraken):
		if Unit.is_valid(grapple.unit): held.append(grapple.unit.core.persistent_id)
	return held

func _is_held(unit:Unit) -> bool:
	return _held().has(unit.core.persistent_id)

## Only OUR prompts. The responder records every yes/no the turn produced, and the gear being fired
## has its own confirmations, so counting all of them measures the wrong thing.
func _my_domain_prompts() -> Array:
	var mine:Array = []
	for prompt:Dictionary in responder.yesno_prompts:
		if str(prompt.get('title', '')) == tr('gear.mt_my_domain.name'): mine.append(prompt)
	return mine

# ============================== the burst ==============================

func test_a_burst_grapples_the_characters_it_catches():
	assert_eq(_held().size(), 0, 'Nobody is held to begin with.')
	await _use_burst()
	assert_true(_is_held(near_enemy), 'The character caught in the burst was grappled.')

func test_it_grapples_everyone_caught_not_just_one():
	# The agreed reading: the whole burst, not a single pick.
	await _use_burst()
	assert_eq(_held().size(), 2, 'Both characters inside the burst were grappled.')

func test_it_leaves_characters_outside_the_burst_alone():
	# Guards the AoE actually being consulted rather than "every enemy on the map".
	await _use_burst()
	assert_false(_is_held(far_enemy), 'The character well outside it was not grappled.')

func test_each_grappled_character_gets_a_tether():
	await _use_burst()
	assert_true(UnitCondition.has_buff(near_enemy, TETHER_BUFF_ID), 'One is tethered.')
	assert_true(UnitCondition.has_buff(other_near_enemy, TETHER_BUFF_ID), 'And so is the other.')

func test_a_blast_does_not_trigger_it():
	# The control. A BLAST 2 on the near enemy catches characters just as a burst does, but the
	# trait names BURST, and a blast is not centred on the Kraken.
	await _use_blast(near_enemy.tile())
	assert_eq(_held().size(), 0, 'A blast grapples nobody.')
	assert_eq(_my_domain_prompts().size(), 0, 'And the player is not even asked.')

# ============================== the "may" ==============================

func test_the_player_is_asked_once_for_the_whole_burst():
	# One decision per burst rather than one per character - two characters are caught here, so a
	# per-character walk would show two prompts.
	await _use_burst()
	assert_eq(_my_domain_prompts().size(), 1, 'Asked exactly once.')

func test_declining_grapples_nobody():
	# "can Grapple" is a may. Backing out has to leave the board untouched.
	responder.yesno_queue = [false]
	await _use_burst()
	assert_eq(_held().size(), 0, 'Saying no grappled nobody.')
	assert_false(UnitCondition.has_buff(near_enemy, TETHER_BUFF_ID), 'And tethered nobody.')

# ============================== who gets caught ==============================

func test_it_does_not_grapple_allies():
	# A deliberate narrowing of "characters": one confirmation for the whole burst means a blanket
	# yes would otherwise cost an ally its reactions and its boost. Recorded here so the decision is
	# visible rather than implicit, and so reversing it is a spec change.
	var ally := SpecFactory.create_unit(game.map, Vector2i(1, 0))
	ally.core.current.health = 100
	await _use_burst()
	assert_false(_is_held(ally), 'An ally standing in the burst is not grabbed.')

# Not covered here: firing a second burst to prove someone already held is not grabbed twice. The
# ENCLAVE shield sets disable_when_buff_is_applied, so it cannot be used again in one combat, and
# there is no second self-centred BURST on the Saladin license to reach for. The filter itself is
# in characters_caught via currently_held.

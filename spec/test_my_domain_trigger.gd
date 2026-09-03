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
#
# Every grapple here is a real contested attack that can miss, so each one wants a fixed roll:
# _use_burst takes the rolls to hand out, one per character it will ask about, front to back. A 20
# lands and a 1 does not.
extends GutTest

const ModChoiceResponder := preload('res://testkit/mod_choice_responder.gd')

const TRAIT_ID := &'mt_my_domain'
const TETHER_BUFF_ID := &'buff_my_domain_tether'
const GRAPPLE_KIT := &'mw_grapple'
const GRAPPLE_ACTION := &'action_grapple'
const BURST_SYSTEM := &'ms_enclave_pattern_support_shield' ## self-centred BURST 3
const BLAST_WEAPON := &'mw_rocket_propelled_grenade'       ## BLAST 2, placed on a point

const KRAKEN_TILE := Vector2i(0, 0)
const INSIDE_BURST := Vector2i(2, 0)      ## within BURST 3 of the Kraken
const ALSO_INSIDE_BURST := Vector2i(0, 2) ## and so is this
const OUTSIDE_BURST := Vector2i(9, 9)     ## comfortably beyond it

var game:Gamemaster
var responder:DomainWatcher
var kraken:Unit
var near_enemy:Unit
var other_near_enemy:Unit
var far_enemy:Unit

## The ordinary responder, plus a reading of how far the Kraken's Grapple carried at the moment it
## was asked about a character. That question is only ever asked while the trait is resolving, so it
## is the one window in which the reach the burst earned is observable from outside.
class DomainWatcher:
	extends 'res://testkit/mod_choice_responder.gd'

	var prompt_title:String = ''  ## only our own prompts; the gear being fired has its own
	var sample:Callable           ## returns the reach to record
	var reach_when_asked:Array[int] = []

	func choose_yesno(request:ChoiceRequest, tile:Vector2i, title:String, desc:String, encourage_yes:bool):
		if title == prompt_title and sample.is_valid(): reach_when_asked.append(sample.call())
		await super.choose_yesno(request, tile, title, desc, encourage_yes)

func before_each():
	# add_responder = false: we install our own, which records the prompts it was shown.
	game = SpecFactory.setup_gamemaster(self, false, null, {}, false)
	responder = add_child_autoqfree(DomainWatcher.new())
	responder.prompt_title = tr('gear.mt_my_domain.name')
	responder.sample = _grapple_reach

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

## Fire the burst, with one fixed roll per grapple the trait will attempt. Two by default, because
## two characters stand inside the burst and both are taken unless a test says otherwise.
func _use_burst(rolls:Array = [20, 20]) -> void:
	kraken.core.equip_system(BURST_SYSTEM)
	Dice.CHEAT_ROLL_QUEUE.append_array(rolls)
	await SpecFactory.use_solo(game, kraken, BURST_SYSTEM)

func _use_blast(at_tile:Vector2i) -> void:
	kraken.core.equip_system(BLAST_WEAPON)
	Dice.CHEAT_ROLL_QUEUE.append_array([20, 20, 20, 20])
	await SpecFactory.use_solo(game, kraken, BLAST_WEAPON, [at_tile])

## Everyone the Kraken is currently holding.
func _held() -> Array[StringName]:
	var held:Array[StringName] = []
	for grapple:SpecificAction in UnitCondition.get_outgoing_grapples(kraken):
		if Unit.is_valid(grapple.unit): Util.append_nonduplicate(held, grapple.unit.core.persistent_id)
	return held

func _is_held(unit:Unit) -> bool:
	return _held().has(unit.core.persistent_id)

## How far the Kraken's own Grapple currently carries, in spaces. get_target_range is the engine's
## own answer to "could it reach that", so this reads whatever the board actually allows rather than
## anything about how the reach is granted.
func _grapple_reach() -> int:
	var specific := SpecificAction.from_id(kraken, GRAPPLE_KIT, GRAPPLE_ACTION)
	if not SpecificAction.is_valid(specific): return -1
	return specific.action.get_target_range(specific)

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

# ============================== the attack ==============================

func test_a_grapple_that_misses_takes_nobody():
	# The grapple is a Grapple: a contested attack that can fail. A 1 fails any attack roll worth
	# the name, and a failed grab has to leave the character exactly where the burst found it.
	await _use_burst([1, 1])
	assert_eq(_held().size(), 0, 'Neither attack landed, so nobody is held.')
	assert_false(UnitCondition.has_buff(near_enemy, TETHER_BUFF_ID), 'One is untethered.')
	assert_false(UnitCondition.has_buff(other_near_enemy, TETHER_BUFF_ID), 'And so is the other.')

func test_a_character_that_gets_away_does_not_spare_the_rest():
	# Each character is its own attack, so one of them slipping the grab must not carry the rest of
	# the burst out with it.
	await _use_burst([1, 20])
	assert_eq(_my_domain_prompts().size(), 2, 'Both were still asked about.')
	assert_eq(_held().size(), 1, 'And the one the landed attack caught was taken.')

func test_the_tether_follows_the_grapple_that_landed():
	# The tether marks who is in the domain. It has to follow the attack that actually hit rather
	# than everyone the trait made an attempt on.
	await _use_burst([1, 20])
	var tethered:int = 0
	for enemy:Unit in [near_enemy, other_near_enemy]:
		if UnitCondition.has_buff(enemy, TETHER_BUFF_ID): tethered += 1
	assert_eq(tethered, 1, 'One landed grapple, one tether.')
	assert_eq(_held().size(), 1, 'And one character held.')

# ============================== the reach ==============================

func test_it_reaches_the_characters_its_burst_caught():
	# "characters at least partially within any Bursts" is wider than a mech can ordinarily reach to
	# Grapple, so the trait has to carry the attack out to them. Without this the rule would quietly
	# mean "characters it could have grabbed anyway", which is nobody a burst adds.
	assert_lt(_grapple_reach(), UnitRelation.distance_between(kraken, near_enemy),
		'They stand further off than an ordinary Grapple reaches.')

	await _use_burst()
	assert_false(responder.reach_when_asked.is_empty(), 'The trait asked about somebody.')
	if responder.reach_when_asked.is_empty(): return
	assert_gte(responder.reach_when_asked.max(), UnitRelation.distance_between(kraken, near_enemy),
		'While the domain was open, its Grapple reached that far.')

func test_the_reach_does_not_outlive_the_domain():
	# The reach is earned by a burst and lasts only as long as that burst is being resolved. A
	# Kraken left able to Grapple across a room as an ordinary Quick action would be a silent, scene
	# long grant the trait never makes.
	var ordinary_reach := _grapple_reach()
	await _use_burst()
	assert_eq(_grapple_reach(), ordinary_reach,
		'Afterwards its Grapple reaches exactly as far as any other mechs.')
	assert_lt(_grapple_reach(), UnitRelation.distance_between(kraken, near_enemy),
		'Which is not far enough to have reached across that burst.')

# ============================== the "may" ==============================

func test_the_player_is_asked_once_per_character():
	# One question per character, not one for the burst. Every extra character in the katamari
	# raises the size the grapple has to beat to hold, so taking everyone on offer can be worse than
	# taking one - which makes it a per-target decision.
	await _use_burst()
	assert_eq(_my_domain_prompts().size(), 2, 'Both caught characters were asked about separately.')

func test_each_prompt_names_the_character_it_is_about():
	# A per-character prompt that does not say who is useless, and the camera move that goes with it
	# is only meaningful if the text agrees with what is on screen.
	await _use_burst()
	var names:Array[String] = []
	for prompt:Dictionary in _my_domain_prompts(): names.append(str(prompt.get('desc', '')))
	assert_eq(names.size(), 2, 'Two prompts to check.')
	if names.size() < 2: return

	assert_ne(names[0], names[1], 'The two prompts do not say the same thing.')
	for name:String in names:
		assert_true(
			name.contains(near_enemy.core.get_pilot_or_mech_name()) or
			name.contains(other_near_enemy.core.get_pilot_or_mech_name()),
			'Each prompt names one of the characters caught: %s' % name)

func test_declining_everyone_grapples_nobody():
	# "can Grapple" is a may. Backing out of every one has to leave the board untouched.
	responder.yesno_queue = [false, false]
	await _use_burst()
	assert_eq(_held().size(), 0, 'Saying no to both grappled nobody.')
	assert_false(UnitCondition.has_buff(near_enemy, TETHER_BUFF_ID), 'And tethered nobody.')

func test_it_can_take_one_and_leave_the_other():
	# The whole point of the change: grabbing fewer characters is sometimes the better play, so a
	# partial yes has to be possible rather than all-or-nothing.
	responder.yesno_queue = [true, false]
	await _use_burst()
	assert_eq(_held().size(), 1, 'Exactly one of the two was taken.')

	# And the one taken is the one that was tethered - not both, and not the other.
	var tethered:int = 0
	for enemy:Unit in [near_enemy, other_near_enemy]:
		if UnitCondition.has_buff(enemy, TETHER_BUFF_ID): tethered += 1
	assert_eq(tethered, 1, 'And exactly one tether was drawn.')

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

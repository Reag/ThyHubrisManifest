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
# _use_burst takes the rolls to hand out, one per character it will attack, front to back. A 20
# lands and a 1 does not.
#
# THE "MAY" IS THE GRAPPLE'S OWN TARGETING. The trait no longer asks a yes/no question before each
# attack - it opens the Grapple's targeting on that character, and the player takes the offer by
# confirming the target or declines it by cancelling. So the specs below read the targeting rather
# than a prompt: DomainWatcher records every targeting the trait opened and who it was handed, and
# cancel_offers_for says which of those the player backs out of.
extends GutTest

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
var marker:MarkerWatcher
var kraken:Unit
var near_enemy:Unit
var other_near_enemy:Unit
var far_enemy:Unit

## What the board is currently saying about who. The trait names the character it is offering by
## raising the whois panel and drawing a line to it, and both are bus signals - so a spec can watch
## them the same way a player watches the screen.
class MarkerWatcher:
	extends Node

	static var choice_bus:ChoiceBus = load('res://ui/choice_controller/choice_bus.tres')
	static var effect_bus:EffectsControllerBus = load('res://engine/gamemaster/effects_controller/effects_controller_bus.tres')

	var named:Unit = null      ## who the whois panel is naming, null while it is down
	var line_drawn:bool = false

	func _ready() -> void:
		choice_bus.on_show_whois.connect(_named)
		choice_bus.on_hide_whois.connect(_unnamed)
		effect_bus.on_show_target_line.connect(_line_shown)
		effect_bus.on_hide_target_line.connect(_line_hidden)

	func _named(unit) -> void: named = unit if Unit.is_valid(unit) else null
	func _unnamed() -> void: named = null
	func _line_shown(_start, _end, _flavor, _hide_prev) -> void: line_drawn = true
	func _line_hidden() -> void: line_drawn = false

## The ordinary responder, plus a record of the Grapple targeting the trait opened: who each one was
## handed, what the board was saying about who at that moment, and how far the Kraken's Grapple
## carried. That targeting is the trait's own offer - taking it is the yes, cancelling it is the no -
## and it is only ever opened while the trait is resolving, so it is also the one window in which the
## reach the burst earned is observable from outside.
class DomainWatcher:
	extends 'res://testkit/mod_choice_responder.gd'

	var grapple_kit:StringName = &''    ## only the trait's own Grapple; the gear being fired asks its own questions
	var grapple_action:StringName = &''
	var marker:MarkerWatcher            ## what the board was showing when each offer opened
	var sample:Callable                 ## returns the reach to record

	var grapple_targets:Array[Unit] = []    ## the character each offer was about, in order
	var named_when_asked:Array[Unit] = []   ## and who the board named while it was open
	var reach_when_asked:Array[int] = []

	## Characters whose offer the player backs out of. Answered by queueing an aborted plan for the
	## request that is about to pop it, rather than by position, so a test can name the character it
	## is declining instead of counting.
	var cancel_offers_for:Array[Unit] = []

	func choose_compcon_plan(
		request:ChoiceRequest,
		specific:SpecificAction,
		pathfinder:Pathfinder,
		mandatory_target_unit:Unit = null,
		reaction_to:SpecificAction = null,
	):
		if is_the_traits_grapple(specific):
			grapple_targets.append(mandatory_target_unit)
			named_when_asked.append(marker.named if is_instance_valid(marker) else null)
			if sample.is_valid(): reach_when_asked.append(sample.call())
			if cancel_offers_for.has(mandatory_target_unit):
				chosen_plan_queue.push_front(CompconPlan.create_aborted())
		await super.choose_compcon_plan(request, specific, pathfinder, mandatory_target_unit, reaction_to)

	func is_the_traits_grapple(specific:SpecificAction) -> bool:
		if not SpecificAction.is_valid(specific): return false
		return specific.gear.kit.compcon_id == grapple_kit and specific.action.get_id() == grapple_action

func before_each():
	# add_responder = false: we install our own, which records the targeting it was shown.
	game = SpecFactory.setup_gamemaster(self, false, null, {}, false)
	marker = add_child_autoqfree(MarkerWatcher.new())
	responder = add_child_autoqfree(DomainWatcher.new())
	responder.grapple_kit = GRAPPLE_KIT
	responder.grapple_action = GRAPPLE_ACTION
	responder.marker = marker
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

## Every character the trait offered a Grapple against, in the order it offered them. Only the
## trait's own targeting: the gear being fired does its own asking, so counting every choice the turn
## produced would measure the wrong thing.
func _grapple_offers() -> Array[Unit]:
	return responder.grapple_targets

func _name_of(unit:Unit) -> String:
	return unit.core.get_pilot_or_mech_name() if Unit.is_valid(unit) else 'nobody'

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
	assert_eq(_grapple_offers().size(), 0, 'And the player is never offered a grapple.')

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
	assert_eq(_grapple_offers().size(), 2, 'Both were still offered.')
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

# ============================== the hold ==============================

func test_the_domain_keeps_what_it_caught():
	# "Characters grappled this way count as though they are |adjacent|" - so a hold made across a
	# burst has to survive the engine's own adjacency check, which drops any attachment between
	# characters standing more than a space apart and runs on every movement anywhere on the map.
	# Nothing else here forces that check, so without it the trait can look entirely correct in a
	# spec and hold nobody by the time the next character takes a step.
	await _use_burst()
	assert_eq(_held().size(), 2, 'Both were taken.')
	assert_gt(UnitRelation.distance_between(kraken, near_enemy), 1,
		'And they stand further off than a hold ordinarily survives.')

	UnitTile.update_tracking_and_statuses(game.map)

	assert_eq(_held().size(), 2, 'The domain still holds them after an adjacency check.')
	assert_true(UnitCondition.has_buff(near_enemy, TETHER_BUFF_ID), 'Tether and all.')

# ============================== the reach ==============================

func test_it_reaches_the_characters_its_burst_caught():
	# "characters at least partially within any Bursts" is wider than a mech can ordinarily reach to
	# Grapple, so the trait has to carry the attack out to them. Without this the rule would quietly
	# mean "characters it could have grabbed anyway", which is nobody a burst adds.
	assert_lt(_grapple_reach(), UnitRelation.distance_between(kraken, near_enemy),
		'They stand further off than an ordinary Grapple reaches.')

	await _use_burst()
	assert_false(responder.reach_when_asked.is_empty(), 'The trait offered a grapple against somebody.')
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
	# One offer per character, not one for the burst. Every extra character in the katamari raises
	# the size the grapple has to beat to hold, so taking everyone on offer can be worse than taking
	# one - which makes it a per-target decision, and the Grapple's targeting is where it is made.
	await _use_burst()
	assert_eq(_grapple_offers().size(), 2, 'Both caught characters were offered separately.')

func test_each_offer_is_about_the_character_it_was_opened_for():
	# The rule the old per-character prompt text carried: you are asked about THIS character, not
	# merely asked twice. With no prompt to read, what makes an offer specific is the mandatory
	# target the Grapple is handed - so read that, and require both caught characters by name.
	await _use_burst()
	var offered := _grapple_offers()
	assert_eq(offered.size(), 2, 'Two offers to check.')
	if offered.size() < 2: return

	for target:Unit in offered:
		assert_true(Unit.is_valid(target),
			'Each offer is about a named character rather than a free pick of the board.')
	assert_ne(offered[0], offered[1], 'The two offers are about different characters.')
	assert_true(offered.has(near_enemy), 'One of them is the character standing here: %s' % _name_of(near_enemy))
	assert_true(offered.has(other_near_enemy), 'And the other is the one standing there: %s' % _name_of(other_near_enemy))

func test_the_character_being_offered_is_marked_on_screen():
	# The targeting restricts what can be CLICKED and says nothing about WHO, so on a board with
	# several characters in the burst an unmarked offer is "click one of them". The trait has to name
	# the character while its offer is open - and take the name down again when the domain closes.
	await _use_burst()
	var offered := _grapple_offers()
	var named := responder.named_when_asked
	assert_eq(offered.size(), 2, 'Two offers to check.')
	assert_eq(named.size(), offered.size(), 'Each of them had the board saying something about who.')
	if named.size() != offered.size(): return

	for i:int in offered.size():
		assert_true(named[i] == offered[i],
			'Offer %d named %s, the character it was about (named: %s).'
			% [i + 1, _name_of(offered[i]), _name_of(named[i])])

	assert_null(marker.named, 'And nobody is left named once the domain closes.')
	assert_false(marker.line_drawn, 'Nor any line left drawn across the board.')

func test_declining_everyone_grapples_nobody():
	# "can Grapple" is a may, and cancelling the Grapple's targeting is how it is declined. Backing
	# out of every one has to leave the board untouched.
	responder.cancel_offers_for.append(near_enemy)
	responder.cancel_offers_for.append(other_near_enemy)
	await _use_burst()
	assert_eq(_grapple_offers().size(), 2, 'Both were still offered.')
	assert_eq(_held().size(), 0, 'Cancelling both grappled nobody.')
	assert_false(UnitCondition.has_buff(near_enemy, TETHER_BUFF_ID), 'And tethered nobody.')

func test_it_can_take_one_and_leave_the_other():
	# The whole point of the change: grabbing fewer characters is sometimes the better play, so a
	# partial yes has to be possible rather than all-or-nothing. It also pins that a cancel declines
	# exactly ONE character - if it aborted the reaction, the offer after it would never open.
	responder.cancel_offers_for.append(other_near_enemy)
	await _use_burst()
	assert_eq(_grapple_offers().size(), 2, 'Both were offered, the cancel notwithstanding.')
	assert_eq(_held().size(), 1, 'Exactly one of the two was taken.')
	assert_true(_is_held(near_enemy), 'And it is the one whose targeting was taken.')
	assert_false(_is_held(other_near_enemy), 'Not the one that was cancelled.')

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

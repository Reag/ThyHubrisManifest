# Symptom - the first of Disease's two Invade options.
#
#   "Your target takes 2 INFECTION instead of Invade's normal heat. Choose one tech effect currently
#    affecting the target that lasts until the end of their next turn (other than STUNNED). That
#    effect instead lasts until the target clears INFECTION."
#
# get_damage_dice returns '' so the standard 2 heat at action_attack_tech.gd:17 never rolls - the
# only heat the target takes is the 2 that Infection itself deals.
#
# WHAT COUNTS AS A "TECH EFFECT". Face Thy Judgement's enumeration
# (action_face_thy_judgement.gd:78-96, :180-184): a status or buff whose recorded SOURCE resolves to
# gear that UnitAction.is_tech accepts. A status applied with an EMPTY source is not tech, which is
# why this fixture hands SpecFactory.apply the ms_disease gear's own persistent_id - ms_disease is
# itself tech, carrying two ActionAttackTech actions. A weapon's gear id is the negative control.
#
# The pick is a real choice-bus request on 1.4.0, observed with testkit/prompt_watcher.gd and
# answered by SpecFactory's own responder. Never connect to bus signals.
extends GutTest

const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')
const InfectionLinks := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection_links.gd')
const PromptWatcher := preload('res://testkit/prompt_watcher.gd')

const DISEASE := &'ms_disease'
const SYMPTOM := &'action_symptom'

var game:Gamemaster
var draugr:Unit
var target:Unit
var disease:GearCore
var watcher:PromptWatcher

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	draugr = SpecFactory.create_unit(game.map, Vector2i(0, 0), Faction.PLAYER)
	disease = draugr.core.equip_system(DISEASE)
	draugr.core.full_repair()
	draugr.core.frame.stat.heat = 30
	draugr.core.current.heat = 0
	target = SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	target.core.frame.stat.edef = -10 # a cheated 20 always lands
	target.core.frame.stat.heat = 30
	target.core.full_repair()
	target.core.current.heat = 0
	watcher = add_child_autoqfree(PromptWatcher.new())

func after_each():
	Dice.CHEAT_ROLL_QUEUE.clear()

func invade() -> void:
	Dice.CHEAT_ROLL_QUEUE.append(20)
	await SpecFactory.use(game, draugr, DISEASE, SYMPTOM, target)

## A tech effect on the target: a real StatusCondition whose source is a real tech gear.
func tech_status(status:StringName, until:Lancer.UNTIL) -> StatusCondition:
	SpecFactory.apply(target, status, until, disease.persistent_id)
	return UnitCondition.get_status(target, status)

func offers() -> Array[Dictionary]:
	return watcher.kinds(PromptWatcher.KIND.multiple_choice)

func offered_texts() -> Array:
	if offers().is_empty(): return []
	var texts:Array = []
	for choice in offers().front().choices: texts.append(choice.text)
	return texts

func test_symptom_applies_two_infection_and_none_of_the_invades_own_heat():
	# get_damage_dice -> '' is the whole point of "instead of Invade's normal heat": 2, not 4.
	await invade()
	assert_eq(Infection.count(target), 2, 'Two Infection.')
	assert_eq(target.core.current.heat, 2, 'Two heat, from the Infection alone.')

func test_symptom_offers_a_tech_effect_that_expires_at_the_end_of_the_targets_next_turn():
	tech_status(Lancer.STATUS.IMPAIRED, Lancer.UNTIL.END_OF_NEXT_TURN)
	await invade()
	assert_eq(offers().size(), 1, 'One menu opened.')
	assert_eq(offered_texts().size(), 1, 'With one effect on it: %s' % [offered_texts()])

func test_stunned_is_never_offered():
	tech_status(Lancer.STATUS.STUNNED, Lancer.UNTIL.END_OF_NEXT_TURN)
	await invade()
	assert_eq(offers().size(), 0, 'The one exclusion the rules name.')

func test_an_effect_from_a_non_tech_source_is_never_offered():
	# The same status, sourced to a weapon instead. UnitAction.is_tech reads the whole kit
	# (unit_action.gd:567-571), so a plain melee weapon is the clean negative.
	var weapon := draugr.core.equip_system(&'mw_tactical_melee_weapon')
	SpecFactory.apply(target, Lancer.STATUS.IMPAIRED, Lancer.UNTIL.END_OF_NEXT_TURN, weapon.persistent_id)
	await invade()
	assert_eq(offers().size(), 0, 'Not a tech effect.')

func test_an_effect_expiring_at_the_end_of_this_turn_is_never_offered():
	tech_status(Lancer.STATUS.IMPAIRED, Lancer.UNTIL.END_OF_THIS_TURN)
	await invade()
	assert_eq(offers().size(), 0, 'Already on its way out; the rules name the next turn.')

func test_the_chosen_effect_is_bound_to_the_infection():
	var status := tech_status(Lancer.STATUS.IMPAIRED, Lancer.UNTIL.END_OF_NEXT_TURN)
	await invade()
	assert_true(InfectionLinks.is_linked(target, status), 'Recorded against the Infection.')
	assert_eq(status.until, Lancer.UNTIL.MANUAL, 'And it stopped expiring on its own.')

func test_the_bound_effect_survives_the_targets_end_of_turn():
	tech_status(Lancer.STATUS.IMPAIRED, Lancer.UNTIL.END_OF_NEXT_TURN)
	await invade()
	Dice.CHEAT_ROLL_QUEUE.append(1) # the Infection check fails, so the Infection stays
	await SpecFactory.pass_turn(game, target)
	assert_true(target.has_status(Lancer.STATUS.IMPAIRED), 'Still impaired.')
	assert_true(Infection.is_infected(target), 'Because it is still infected.')

func test_clearing_the_infection_ends_the_bound_effect():
	tech_status(Lancer.STATUS.IMPAIRED, Lancer.UNTIL.END_OF_NEXT_TURN)
	await invade()
	Dice.CHEAT_ROLL_QUEUE.append(20) # the check passes; Infection clears
	await SpecFactory.pass_turn(game, target)
	assert_false(Infection.is_infected(target), 'Infection cleared.')
	assert_false(target.has_status(Lancer.STATUS.IMPAIRED), 'And the effect ended with it.')

func test_nothing_is_asked_when_the_target_carries_nothing_bindable():
	await invade()
	assert_eq(offers().size(), 0, 'No menu.')
	assert_eq(Infection.count(target), 2, 'The Infection still lands.')

func test_an_ai_draugr_binds_the_first_effect_without_a_prompt():
	# Vanilla guards its optional prompts on is_player_controlled and gives the AI a flat default;
	# this mod does the same at onhit_spreading_stain.gd:89-96.
	var ai_draugr := SpecFactory.create_unit(game.map, Vector2i(2, 0), Faction.AI_ENEMY)
	var ai_disease := ai_draugr.core.equip_system(DISEASE)
	ai_draugr.core.full_repair()
	var victim := SpecFactory.create_unit(game.map, Vector2i(3, 0), Faction.PLAYER)
	victim.core.frame.stat.edef = -10
	victim.core.frame.stat.heat = 30
	victim.core.full_repair()
	SpecFactory.apply(victim, Lancer.STATUS.IMPAIRED, Lancer.UNTIL.END_OF_NEXT_TURN, ai_disease.persistent_id)
	var status := UnitCondition.get_status(victim, Lancer.STATUS.IMPAIRED)
	Dice.CHEAT_ROLL_QUEUE.append(20)
	await SpecFactory.use(game, ai_draugr, DISEASE, SYMPTOM, victim)
	assert_eq(offers().size(), 0, 'The AI is never asked.')
	assert_true(InfectionLinks.is_linked(victim, status), 'It took the first one anyway.')

func test_symptom_is_once_per_round():
	# gear.ms_disease.effect: "Each may be used 1/round". get_per_round_hard_limit -> 1 with its own
	# usage_group; ActionAttackTech.get_per_turn_soft_limit is 99 for invades, so the round cap is the
	# only thing saying it. event_gear_activate prints "[ Gear not available ] reason : PER_ROUND".
	await invade()
	assert_eq(Infection.count(target), 2, 'First use landed.')
	Dice.CHEAT_ROLL_QUEUE.clear()
	Dice.CHEAT_ROLL_QUEUE.append(20)
	await SpecFactory.use(game, draugr, DISEASE, SYMPTOM, target)
	assert_eq(Infection.count(target), 2, 'The second use in the same round was refused.')

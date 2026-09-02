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

# ========================= Face Thy Judgement =========================
# Reacts to END_TURN at PRE, where the statuses that are about to expire are still inspectable and
# carry their own `until`. Extending is a one-line mutation to END_OF_NEXT_TURN, which is exactly how
# new_turn_for_statuses walks durations back the other way.
#
# Statuses are applied here with a source of ms_lock_on's gear, a real tech action, so that
# "the effect of a tech action" is satisfied honestly rather than by a test-only shortcut.

const TECH_KIT := &'ms_lock_on' ## tech as an ActionSystem with is_tech
const TECH_ATTACK_KIT := &'ms_fragment_signal' ## tech as an ActionAttackTech

func _chained_victim(tile:Vector2i) -> Unit:
	var victim := SpecFactory.create_unit(game.map, tile, Faction.AI_ENEMY)
	var anchor_core := UnitCore.create(erinyes.get_faction(), ContentLibrary.get_mech_frame(&'dep_chain_erinyes'))
	var anchor := Unit.create(anchor_core)
	UnitAction.set_deployable_owner(anchor, erinyes, erinyes.get_gear(&'mt_bind_thy_flesh'))
	await game.execute_event(&'event_unit_spawn', {unit = anchor, target_tiles = [Vector2i(1, 1)]})

	var chain_buff:Buff = ContentLibrary.get_buff(&'buff_bind_thy_flesh')
	var buff_core := UnitCondition.apply_buff(SpecFactory.dummy_event(), victim, chain_buff, erinyes.get_gear(&'mt_bind_thy_flesh'))
	chain_buff.bind(buff_core, anchor, victim)
	return victim

## Apply a status that expires at the end of this turn, sourced from a real tech action's gear.
func _expiring_tech_status(victim:Unit, status:StringName, from_kit := TECH_KIT) -> void:
	var tech_gear:GearCore = erinyes.get_gear(from_kit)
	SpecFactory.apply(victim, status, Lancer.UNTIL.END_OF_THIS_TURN, tech_gear.persistent_id)

func _until_of(unit:Unit, status:StringName) -> int:
	for condition:StatusCondition in unit.state.statuses:
		if condition.type == status: return condition.until
	return -1

func test_an_expiring_tech_effect_is_extended_to_the_next_turn():
	erinyes.core.equip_system(&'mt_bind_thy_flesh')
	erinyes.core.equip_system(TECH_KIT)
	var victim := await _chained_victim(Vector2i(2, 2))
	_expiring_tech_status(victim, &'impaired')

	SpecFactory.start_turn(game, victim)
	SpecFactory.end_turn(game, victim)
	assert_true(victim.has_status(&'impaired'), 'It survived the end of the turn.')

func test_an_effect_from_a_tech_attack_is_extended():
	# A tech ATTACK is an ActionAttackTech, which descends from ActionAttack - not from ActionSystem.
	# So a source check written against ActionSystem alone reads the commonest tech in the game as
	# non-tech. Reported from play: a chained enemy hit with Fragment Signal ended its turn and the
	# reaction was never offered. The engine's own UnitAction.is_tech covers both shapes.
	erinyes.core.equip_system(&'mt_bind_thy_flesh')
	erinyes.core.equip_system(TECH_ATTACK_KIT)
	var victim := await _chained_victim(Vector2i(2, 2))
	_expiring_tech_status(victim, &'impaired', TECH_ATTACK_KIT)

	SpecFactory.start_turn(game, victim)
	SpecFactory.end_turn(game, victim)
	assert_true(victim.has_status(&'impaired'), 'A tech attack is a tech action.')

func test_stunned_is_never_extended():
	erinyes.core.equip_system(&'mt_bind_thy_flesh')
	erinyes.core.equip_system(TECH_KIT)
	var victim := await _chained_victim(Vector2i(2, 2))
	_expiring_tech_status(victim, &'stunned')

	SpecFactory.start_turn(game, victim)
	SpecFactory.end_turn(game, victim)
	assert_false(victim.has_status(&'stunned'), 'Stunned expired as normal - the ability excludes it.')

func test_an_unchained_character_keeps_its_normal_durations():
	erinyes.core.equip_system(&'mt_bind_thy_flesh')
	erinyes.core.equip_system(TECH_KIT)
	var bystander := SpecFactory.create_unit(game.map, Vector2i(2, 2), Faction.AI_ENEMY)
	_expiring_tech_status(bystander, &'impaired')

	SpecFactory.start_turn(game, bystander)
	SpecFactory.end_turn(game, bystander)
	assert_false(bystander.has_status(&'impaired'), 'Nothing to extend on someone we have not chained.')

func test_an_effect_cannot_be_extended_twice():
	erinyes.core.equip_system(&'mt_bind_thy_flesh')
	erinyes.core.equip_system(TECH_KIT)
	var victim := await _chained_victim(Vector2i(2, 2))
	_expiring_tech_status(victim, &'impaired')

	SpecFactory.start_turn(game, victim)
	SpecFactory.end_turn(game, victim)
	assert_true(victim.has_status(&'impaired'), 'Extended once.')

	# Second turn: start converts END_OF_NEXT_TURN back to END_OF_THIS_TURN, end should clear it.
	SpecFactory.start_turn(game, victim)
	SpecFactory.end_turn(game, victim)
	assert_false(victim.has_status(&'impaired'), 'And not a second time.')

# --- end to end, the way it actually happens in play ---
# The cases above hand the status straight to the victim. These fire a REAL tech attack from a real
# piece of gear, because both bugs found from play reports lived in the gap between the two.

const TECH_ATTACK_ALLY_KIT := &'ms_fragment_signal'

func _ally_with(kit_id:StringName, tile:Vector2i) -> Unit:
	var ally := SpecFactory.create_unit(game.map, tile)
	ally.core.equip_system(kit_id)
	return ally

func _land_tech_attack(ally:Unit, victim:Unit) -> void:
	await SpecFactory.start_turn(game, ally)
	Dice.CHEAT_ROLL_QUEUE.append_array([20, 20, 20, 20])
	await SpecFactory.use_solo(game, ally, TECH_ATTACK_ALLY_KIT, [victim])
	await SpecFactory.end_turn(game, ally)

func _take_a_turn(unit:Unit) -> void:
	await SpecFactory.start_turn(game, unit)
	await SpecFactory.end_turn(game, unit)

func test_a_real_tech_attack_from_an_ally_is_extended():
	# The ability says "the effect of a tech action" without caring whose, and in play the tech
	# usually comes from a teammate. Fragment Signal is an ActionAttackTech, the shape that used to
	# read as non-tech.
	erinyes.core.equip_system(&'mt_bind_thy_flesh')
	var ally := _ally_with(TECH_ATTACK_ALLY_KIT, Vector2i(1, 0))
	var victim := await _chained_victim(Vector2i(2, 2))

	await _land_tech_attack(ally, victim)
	assert_true(victim.has_status(&'impaired'), 'The tech attack landed.')
	await _take_a_turn(victim)
	assert_true(victim.has_status(&'impaired'), 'And the Erinyes extended it.')

## A round boundary: the counter moves and the Erinyes takes its turn, which is what resets its
## 1/round reaction allowance. event_round_new also handles music, banners and combat-end checks,
## so the spec moves only the value the ability actually reads.
func _next_round() -> void:
	game.map.game_core.round_count += 1
	await _take_a_turn(erinyes)

func test_a_later_application_of_the_same_status_is_extendable_again():
	# "An effect cannot be extended more than once" is about one EFFECT. A status carries nothing to
	# tell one application from the next, so the record is keyed by status TYPE - and if that record
	# outlives the effect, the character can never have that status extended again all scene.
	erinyes.core.equip_system(&'mt_bind_thy_flesh')
	var ally := _ally_with(TECH_ATTACK_ALLY_KIT, Vector2i(1, 0))
	var victim := await _chained_victim(Vector2i(2, 2))

	await _next_round()
	await _land_tech_attack(ally, victim)
	await _take_a_turn(victim)
	assert_true(victim.has_status(&'impaired'), 'Extended in the first round.')

	await _next_round()
	await _take_a_turn(victim)
	assert_false(victim.has_status(&'impaired'), 'And expired at the end of the next turn, once.')

	await _next_round()
	await _land_tech_attack(ally, victim)
	await _take_a_turn(victim)
	assert_true(victim.has_status(&'impaired'), 'A fresh effect is extendable, type notwithstanding.')

func test_spending_punishment_does_not_disable_face_thy_judgement():
	# Both halves of the core power are actions on ONE kit, and a gear's per-round counter is keyed
	# by usage group, which defaults to the KIT id (gear_core.gd:166-168). So Punishment and Face Thy
	# Judgement shared one allowance, and since Face Thy Judgement is a 1/round reaction, accepting a
	# Punishment offer left it unavailable - reason "per_round" - for the rest of the round. In play
	# that is most rounds, which is why the reaction looked like it never fired at all.
	erinyes.core.equip_system(&'mt_bind_thy_flesh')
	erinyes.core.equip_system(BLAST_WEAPON)
	var ally := _ally_with(TECH_ATTACK_ALLY_KIT, Vector2i(1, 0))
	var victim := await _chained_victim(Vector2i(2, 2))
	var bystander := _enemy(Vector2i(4, 4))

	_arm(erinyes, true)
	await SpecFactory.start_turn(game, erinyes)
	Dice.CHEAT_ROLL_QUEUE.append_array([2, 2, 2, 2])
	await SpecFactory.use_solo(game, erinyes, BLAST_WEAPON, [bystander.tile()])
	assert_false(erinyes.core.has_core_power, 'Punishment was spent this round.')
	await SpecFactory.end_turn(game, erinyes)

	await _land_tech_attack(ally, victim)
	await _take_a_turn(victim)
	assert_true(victim.has_status(&'impaired'), 'Face Thy Judgement still had its reaction.')

# --- and the same for buffs, which is most of what tech gear actually applies ---

const TECH_BUFF := &'buff_bolster'
const NON_TECH_KIT := &'mw_assault_rifle'

func _apply_buff_from(victim:Unit, buff_id:StringName, source_kit:StringName) -> void:
	SpecFactory.apply_buff(victim, buff_id, erinyes.get_gear(source_kit))

func _has_buff(unit:Unit, buff_id:StringName) -> bool:
	return UnitCondition.has_buff(unit, buff_id)

func test_an_expiring_tech_buff_is_extended():
	# The Erinyes' own Viral Logic Suite applies buffs rather than statuses, so a version of this
	# ability that only looked at statuses would never fire on its own tech.
	erinyes.core.equip_system(&'mt_bind_thy_flesh')
	erinyes.core.equip_system(TECH_KIT)
	var victim := await _chained_victim(Vector2i(2, 2))
	_apply_buff_from(victim, TECH_BUFF, TECH_KIT)

	SpecFactory.start_turn(game, victim)
	SpecFactory.end_turn(game, victim)
	assert_true(_has_buff(victim, TECH_BUFF), 'The tech buff survived the end of the turn.')

func test_a_non_tech_buff_is_left_to_expire():
	# Control for the test above: same buff, same timing, source gear that has no tech action.
	erinyes.core.equip_system(&'mt_bind_thy_flesh')
	erinyes.core.equip_system(NON_TECH_KIT)
	var victim := await _chained_victim(Vector2i(2, 2))
	_apply_buff_from(victim, TECH_BUFF, NON_TECH_KIT)

	SpecFactory.start_turn(game, victim)
	SpecFactory.end_turn(game, victim)
	assert_false(_has_buff(victim, TECH_BUFF), 'Nothing to extend - it did not come from tech.')

func test_a_buff_cannot_be_extended_twice():
	erinyes.core.equip_system(&'mt_bind_thy_flesh')
	erinyes.core.equip_system(TECH_KIT)
	var victim := await _chained_victim(Vector2i(2, 2))
	_apply_buff_from(victim, TECH_BUFF, TECH_KIT)

	SpecFactory.start_turn(game, victim)
	SpecFactory.end_turn(game, victim)
	assert_true(_has_buff(victim, TECH_BUFF), 'Extended once.')

	SpecFactory.start_turn(game, victim)
	SpecFactory.end_turn(game, victim)
	assert_false(_has_buff(victim, TECH_BUFF), 'And not a second time.')

# --- the prompt the player actually reads ---
# dice.gd renders the choice buttons from the roll values themselves, so they read "20" and "1" and
# no content change can alter that. The meaning has to live in the title and description instead.

func test_the_punishment_prompts_are_written():
	for which:String in ['crit', 'save']:
		var key := 'gear.cp_dhiyed_observation.action_punishment.prompt.%s' % which
		assert_ne(tr(key), key, '%s resolves to real text.' % key)

func test_the_prompt_describes_the_effect_being_offered():
	# The wrong half of the ability would be a confusing thing to read while deciding.
	var enemy := _enemy(Vector2i(4, 4))
	erinyes.core.equip_system(BLAST_WEAPON)
	_arm(erinyes, true)
	var buff:Buff = ContentLibrary.get_buff(&'buff_punishment')
	var buff_core:BuffCore = null
	for candidate:BuffCore in erinyes.state.buffs:
		if candidate.base.compcon_id == &'buff_punishment': buff_core = candidate
	assert_true(BuffCore.is_valid(buff_core), 'The Erinyes carries the Punishment buff.')
	if not BuffCore.is_valid(buff_core): return

	var attack_context := Context.create({unit = erinyes, map = game.map, resource = DeclaredAttackSummary.new()})
	assert_true(buff.prompt_key(buff_core, attack_context).ends_with('.crit'), 'Attacks offer the crit line.')

	var save_context := Context.create({unit = erinyes, target_unit = enemy, map = game.map, category = Lancer.HASE.AGI})
	assert_true(buff.prompt_key(buff_core, save_context).ends_with('.save'), 'Forced saves offer the save line.')

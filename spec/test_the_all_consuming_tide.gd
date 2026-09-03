# The All-Consuming Tide - the Kraken's core power activation.
#
#   "For the rest of the |scene|, the Kraken counts as both tangible and |INTANGIBLE|, and characters
#    you have |GRAPPLED| are |INTANGIBLE| during their turn. Characters of your choice are pulled 1
#    space toward you at the beginning of their turn. Hostile characters within your |SENSORS| treat
#    movement away from you as |difficult terrain|. If a character collides with you, you may expend
#    your |OVERWATCH| to attempt to |Grapple| the character as a |reaction|."
#
# Design notes live in D:\DEV\lancer-tactics-claude\specs\2026-09-02-kraken-design.md.
#
# THESE SPECS ASSERT THE RULES, NOT THE MECHANISM. The tangibility clauses are a workaround for an
# engine limitation and are meant to be deleted when a future modkit makes the faithful reading
# possible. Every assertion here is phrased as what the ability does - "the Kraken can attack an
# intangible unit" - so a faithful reimplementation passes this file unchanged. Do not rewrite these
# to assert that can_affect returned a particular value.
extends GutTest

const CORE_POWER_ID := &'cp_the_endless_black_sea'
const TIDE_ACTION := &'action_the_all_consuming_tide'
const TIDE_BUFF_ID := &'buff_the_all_consuming_tide'

const KRAKEN_TILE := Vector2i(0, 0)

var game:Gamemaster
var kraken:Unit
var gear:GearCore

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	kraken = SpecFactory.create_unit(game.map, KRAKEN_TILE)
	gear = kraken.core.equip_system(CORE_POWER_ID)
	# A core power action reports itself unavailable without this (unit_action.gd:145).
	kraken.core.has_core_power = true

func _raise_the_tide() -> void:
	await SpecFactory.use(game, kraken, CORE_POWER_ID, TIDE_ACTION)

func _tide_is_up() -> bool:
	return UnitCondition.has_buff(kraken, TIDE_BUFF_ID)

# ============================== raising it ==============================

func test_raising_the_tide_marks_the_kraken_for_the_rest_of_the_scene():
	assert_false(_tide_is_up(), 'It starts down.')
	await _raise_the_tide()
	assert_true(_tide_is_up(), 'The Tide is up.')

func test_raising_the_tide_spends_the_core_power():
	await _raise_the_tide()
	assert_false(kraken.core.has_core_power, 'The core power is spent.')

func test_the_tide_cannot_be_raised_twice():
	await _raise_the_tide()
	var action:Action = ContentLibrary.get_kit(CORE_POWER_ID).get_action(TIDE_ACTION)
	if not Action.is_valid(action): return fail_test('%s is on the kit.' % TIDE_ACTION)
	assert_false(action.is_available_to_activate(kraken, gear), 'It cannot be raised again.')

func test_the_tide_dies_with_the_kraken():
	# until = MANUAL means "rest of the scene", which must not outlive its owner. The failure this
	# guards is silent and permanent - see the design doc's risks - so it is pinned rather than
	# assumed from the default.
	await _raise_the_tide()
	assert_true(_tide_is_up(), 'Up while it lives.')
	await game.execute_event(&'event_unit_die', {unit = kraken})
	assert_false(_tide_is_up(), 'And gone with it.')

# ============================== the Kraken counts as both ==============================
# Phrased as the RULE throughout. A future modkit may let the Kraken genuinely hold both tangibility
# states; these assertions must pass unchanged when it does.

## A unit that is really INTANGIBLE, by the vanilla status. Nothing in this feature ever applies that
## status itself - see the design doc - but the world contains units that have it, and the Tide is
## about being able to reach them.
func _spawn_intangible(tile:Vector2i, faction:Faction.SIDE = Faction.AI_ENEMY) -> Unit:
	var ghost := SpecFactory.create_unit(game.map, tile, faction)
	SpecFactory.apply(ghost, Lancer.STATUS.INTANGIBLE)
	return ghost

func test_the_kraken_can_reach_an_intangible_character():
	var ghost := _spawn_intangible(Vector2i(2, 0))
	assert_false(UnitRelation.can_affect(kraken, ghost), 'It cannot, before the Tide.')
	await _raise_the_tide()
	assert_true(UnitRelation.can_affect(kraken, ghost), 'The Tide lets it reach the intangible.')

func test_an_intangible_character_can_reach_the_kraken():
	# can_affect is asked from both sides and they are separate calls. Widening only the Kraken's view
	# would leave it able to strike something that cannot strike back.
	var ghost := _spawn_intangible(Vector2i(2, 0))
	await _raise_the_tide()
	assert_true(UnitRelation.can_affect(ghost, kraken), 'And the intangible can reach back.')

func test_the_kraken_still_reaches_tangible_characters():
	# "BOTH tangible and intangible" - the point is that nothing is given up.
	var solid := SpecFactory.create_unit(game.map, Vector2i(2, 0), Faction.AI_ENEMY)
	await _raise_the_tide()
	assert_true(UnitRelation.can_affect(kraken, solid), 'Still reaches the solid world.')
	assert_true(UnitRelation.can_affect(solid, kraken), 'And is still reachable from it.')

# ============================== the controls ==============================
# can_affect backs AI targeting, reactions, auras and per-tile unit filtering, so a mistake here
# misbehaves for every unit on the map. These two tests are the blast-radius guard and are not
# optional.

func test_the_tide_changes_nothing_between_two_unrelated_characters():
	var solid := SpecFactory.create_unit(game.map, Vector2i(2, 0), Faction.AI_ENEMY)
	var ghost := _spawn_intangible(Vector2i(3, 0))
	await _raise_the_tide()
	assert_false(UnitRelation.can_affect(solid, ghost),
		'A bystander still cannot touch an intangible one.')
	assert_false(UnitRelation.can_affect(ghost, solid),
		'And it still cannot touch back.')

func test_without_the_tide_the_kraken_is_an_ordinary_character():
	var ghost := _spawn_intangible(Vector2i(2, 0))
	var solid := SpecFactory.create_unit(game.map, Vector2i(3, 0), Faction.AI_ENEMY)
	assert_false(_tide_is_up(), 'The Tide is down.')
	assert_false(UnitRelation.can_affect(kraken, ghost), 'No reach into the intangible.')
	assert_true(UnitRelation.can_affect(kraken, solid), 'And ordinary reach otherwise.')

# The Tide overturns the tangibility line and nothing else. These three pin that every other
# can_affect refusal still stands, so a future vanilla change cannot silently widen the Kraken's
# reach through this override.

func test_the_tide_does_not_reach_the_exiled():
	# Exile refuses regardless of tangibility - the Tide does not touch it.
	var exile := SpecFactory.create_unit(game.map, Vector2i(2, 0), Faction.AI_ENEMY)
	SpecFactory.apply(exile, Lancer.STATUS.EXILED)
	await _raise_the_tide()
	assert_false(UnitRelation.can_affect(kraken, exile), 'The Tide does not reach the exiled.')

func test_the_tide_does_not_reach_the_invulnerable():
	# Same guard, for invulnerability.
	var invulnerable := SpecFactory.create_unit(game.map, Vector2i(2, 0), Faction.AI_ENEMY)
	SpecFactory.apply(invulnerable, Lancer.STATUS.INVULNERABLE)
	await _raise_the_tide()
	assert_false(UnitRelation.can_affect(kraken, invulnerable),
		'The Tide does not reach the invulnerable.')

func test_the_tide_does_not_cross_a_shard_boundary():
	# Same guard, for shard separation - sharing no shard still refuses, Tide or not.
	var other := SpecFactory.create_unit(game.map, Vector2i(2, 0), Faction.AI_ENEMY)
	other.state.in_global_shard = false
	await _raise_the_tide()
	assert_false(UnitRelation.can_affect(kraken, other), 'The Tide does not cross a shard boundary.')

# ============================== held characters are cut off ==============================
# The rule: while it is their turn, a character the Kraken has grappled may only interact with the
# Kraken, or with anything that is itself INTANGIBLE. Symmetric - their own allies cannot reach them
# either. This is a real game rule rather than a workaround: a faithful implementation would apply
# INTANGIBLE to the prisoner and get the same result.

const MY_DOMAIN_ID := &'mt_my_domain'

## Grapple through My Domain's gear, whose attachment holds at range.
func _hold(prey:Unit) -> void:
	var domain := kraken.core.equip_system(MY_DOMAIN_ID)
	Katamari.attach_units(SpecFactory.dummy_event(), kraken, prey, domain.persistent_id)

## The engine marks exactly one unit as taking its turn (unit_battle_state.gd:35).
func _its_turn(unit:Unit) -> void:
	unit.state.is_taking_turn = true

func test_a_held_character_cannot_reach_its_own_ally_on_its_turn():
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	var friend := SpecFactory.create_unit(game.map, Vector2i(2, 0), Faction.AI_ENEMY)
	await _raise_the_tide()
	_hold(prey)
	_its_turn(prey)
	assert_false(UnitRelation.can_affect(prey, friend), 'It cannot reach its ally.')

func test_a_held_characters_ally_cannot_reach_it_on_its_turn():
	# Symmetric, by design decision - it cuts both ways and that is the intent.
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	var friend := SpecFactory.create_unit(game.map, Vector2i(2, 0), Faction.AI_ENEMY)
	await _raise_the_tide()
	_hold(prey)
	_its_turn(prey)
	assert_false(UnitRelation.can_affect(friend, prey), 'And the ally cannot reach it.')

func test_a_held_character_can_still_reach_the_kraken_on_its_turn():
	# The exemption that makes this a rule rather than a paralysis.
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	await _raise_the_tide()
	_hold(prey)
	_its_turn(prey)
	assert_true(UnitRelation.can_affect(prey, kraken), 'It can still fight the Kraken.')
	assert_true(UnitRelation.can_affect(kraken, prey), 'And the Kraken can still work on it.')

func test_a_held_character_can_reach_an_intangible_bystander_on_its_turn():
	# It is intangible in the fiction, so intangible company is reachable. Included deliberately:
	# a faithful implementation would permit this naturally, so matching it now keeps the eventual
	# swap behaviour-identical.
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	var ghost := _spawn_intangible(Vector2i(3, 0))
	await _raise_the_tide()
	_hold(prey)
	_its_turn(prey)
	assert_true(UnitRelation.can_affect(prey, ghost), 'It can reach the intangible.')
	assert_true(UnitRelation.can_affect(ghost, prey), 'And be reached by it.')

func test_a_held_character_is_reachable_normally_when_it_is_not_its_turn():
	# is_taking_turn is load-bearing: outside its own turn the prisoner is an ordinary target, which
	# is what lets the Kraken's allies finish it off.
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	var friend := SpecFactory.create_unit(game.map, Vector2i(2, 0), Faction.AI_ENEMY)
	await _raise_the_tide()
	_hold(prey)
	assert_false(prey.state.is_taking_turn, 'It is not its turn.')
	assert_true(UnitRelation.can_affect(friend, prey), 'So it is an ordinary target.')

func test_an_unheld_character_is_untouched_by_this_rule():
	# The control: being on the map while the Tide is up is not enough.
	var loose := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	var friend := SpecFactory.create_unit(game.map, Vector2i(2, 0), Faction.AI_ENEMY)
	await _raise_the_tide()
	_its_turn(loose)
	assert_true(UnitRelation.can_affect(loose, friend), 'A character nobody holds acts freely.')

func test_a_character_held_without_the_tide_is_untouched_by_this_rule():
	# The other control: the grapple alone does not do this, the Tide does.
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	var friend := SpecFactory.create_unit(game.map, Vector2i(2, 0), Faction.AI_ENEMY)
	_hold(prey)
	_its_turn(prey)
	assert_false(_tide_is_up(), 'The Tide is down.')
	assert_true(UnitRelation.can_affect(prey, friend), 'An ordinary grapple cuts nobody off.')

func test_a_prisoner_is_freed_when_the_kraken_dies():
	# The silent-and-permanent failure the design doc names: a character cut off from the whole map
	# for the rest of the mission because the thing holding it stopped existing.
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	var friend := SpecFactory.create_unit(game.map, Vector2i(2, 0), Faction.AI_ENEMY)
	await _raise_the_tide()
	_hold(prey)
	_its_turn(prey)
	assert_false(UnitRelation.can_affect(prey, friend), 'Cut off while held.')

	await game.execute_event(&'event_unit_die', {unit = kraken})
	# Vanilla answers TRUE for an invalid unit too, so without this the assert below would pass just
	# as happily if the death event had taken the prisoner down with its captor.
	assert_true(Unit.is_valid(prey), 'The prisoner outlives its captor.')
	assert_true(UnitRelation.can_affect(prey, friend), 'And free once the Kraken is gone.')

# ============================== the undertow ==============================
# "Characters of your choice are pulled 1 space toward you at the beginning of their turn."
#
# Scoped to hostiles within SENSORS: the clause names no range, but the sentence after it establishes
# SENSORS as the Tide's zone. Prompted per character, like My Domain, because each pull changes the
# board and so is a per-target judgement. The spec responder answers yes by default; set
# chosen_yesnos to false to decline.

func _start_turn_for(unit:Unit) -> void:
	await game.execute_event(&'event_turn_start', {unit = unit})

func test_a_hostile_in_sensors_is_dragged_a_space_closer_at_its_turn_start():
	var prey := SpecFactory.create_unit(game.map, Vector2i(3, 0), Faction.AI_ENEMY)
	await _raise_the_tide()
	await _start_turn_for(prey)
	assert_eq(prey.tile(), Vector2i(2, 0), 'Dragged one space towards the Kraken.')

func test_declining_leaves_it_where_it_stands():
	# "of your choice" has to mean no as well as yes.
	var prey := SpecFactory.create_unit(game.map, Vector2i(3, 0), Faction.AI_ENEMY)
	await _raise_the_tide()
	SpecFactory.current_responder.chosen_yesnos = false # decline (defaults true, spec_factory.gd:373)
	await _start_turn_for(prey)
	assert_eq(prey.tile(), Vector2i(3, 0), 'It held its ground.')

func test_an_ally_is_never_dragged():
	var friend := SpecFactory.create_unit(game.map, Vector2i(3, 0), Faction.PLAYER)
	await _raise_the_tide()
	await _start_turn_for(friend)
	assert_eq(friend.tile(), Vector2i(3, 0), 'Allies are not prey.')

func test_a_hostile_outside_sensors_is_never_dragged():
	# Sensor range is shrunk on the unit rather than the frame: frame.stat is a shared resource and
	# mutating it would leak into every later test in the file.
	#
	# Shrunk AFTER raising the Tide, not before: applying buff_the_all_consuming_tide runs
	# update_cached_values_and_token on the Kraken (unit_condition.gd's post_apply_buff_cache_update),
	# which clears and rebuilds state.stat_bonus from scratch (unit_battle_state.gd:229). Setting the
	# override first would just have the buff application silently wipe it before the reaction ever
	# checks it.
	var prey := SpecFactory.create_unit(game.map, Vector2i(3, 0), Faction.AI_ENEMY)
	await _raise_the_tide()
	kraken.state.stat_bonus.sensor_range = -(kraken.get_sensor_range() - 1)
	assert_eq(kraken.get_sensor_range(), 1, 'Sensors shrunk to 1.')
	await _start_turn_for(prey)
	assert_eq(prey.tile(), Vector2i(3, 0), 'Out of the Tide, out of reach.')

func test_a_character_immune_to_knockback_is_not_dragged():
	# Drag To The Depths' Pull (action_drag_pull.gd) refuses the same characters, because
	# generate_pull_events performs no immunity check of its own and event_unit_move.gd exempts the
	# primary mover - nothing downstream would catch this otherwise. Both pulls on this core power
	# share that mechanism, so a character immune to one is immune to the other.
	# buff_fortress_knockback is vanilla's plain, unconditional KNOCKBACK_IMMUNITY buff - see
	# test_drag_to_the_depths.gd's identical fixture.
	var prey := SpecFactory.create_unit(game.map, Vector2i(3, 0), Faction.AI_ENEMY)
	await _raise_the_tide()
	SpecFactory.apply_buff(prey, &'buff_fortress_knockback')
	await _start_turn_for(prey)
	assert_eq(prey.tile(), Vector2i(3, 0), 'Immune to the knockback, immune to the drag.')

func test_nothing_is_dragged_before_the_tide_is_raised():
	var prey := SpecFactory.create_unit(game.map, Vector2i(3, 0), Faction.AI_ENEMY)
	assert_false(_tide_is_up(), 'The Tide is down.')
	await _start_turn_for(prey)
	assert_eq(prey.tile(), Vector2i(3, 0), 'So nothing pulls.')

func test_the_undertow_still_drags_while_the_kraken_is_itself_grappled():
	# consumes_rxn = false is why: a reaction that never spends the reaction point never reaches
	# can_take_reactions (action_reaction.gd:49), so it keeps working even while the Kraken is the one
	# held - which, under its own Tide, it usually is. Same GRAPPLED-on-the-Kraken setup as
	# test_irrepressible.gd.
	var prey := SpecFactory.create_unit(game.map, Vector2i(3, 0), Faction.AI_ENEMY)
	await _raise_the_tide()
	SpecFactory.apply(kraken, Lancer.STATUS.GRAPPLED)
	await _start_turn_for(prey)
	assert_eq(prey.tile(), Vector2i(2, 0), 'Held or not, the undertow still pulls.')

# ============================== the seize ==============================
# "If a character collides with you, you may expend your OVERWATCH to attempt to Grapple the
# character as a reaction."
#
# event_unit_collide carries the moving unit and the TILE collided with - never the unit collided
# with - so the trigger tests the Kraken's own footprint. Collisions here are forced-movement stops,
# per the trigger's own comment, which is what "collides with you" means.

## DEVIATION FROM THE BRIEF: event_unit_collide.gd declares `event` (the move event that caused the
## collision) as required context (get_required_context, content/events/event_unit_collide.gd) and
## the engine enforces that before the event ever runs (event_block.gd:118, "invalid context! |
## missing props: event") - so without it the event aborts before reactions are even considered: the
## two positive seize tests fail outright, and the two negative ones pass vacuously, both for lack of
## anything to react to. The brief's version of this helper omitted `event`. The real call site
## (event_unit_move.gd's execute_collision_event) passes the enclosing move event; SpecFactory.dummy_event()
## is this file's existing stand-in for "an EventCore the check only needs to be non-null" (see _hold
## above), so it is used here too.
func _collide_into(mover:Unit, tile:Vector2i) -> void:
	await game.execute_event(&'event_unit_collide', {
		unit = mover, target_tiles = [tile] as Array[Vector2i], event = SpecFactory.dummy_event(),
	})

func _is_held(prey:Unit) -> bool:
	for grapple:SpecificAction in UnitCondition.get_outgoing_grapples(kraken):
		if grapple.unit == prey: return true
	return false

func test_colliding_with_the_kraken_lets_it_seize():
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	await _raise_the_tide()
	Dice.CHEAT_ROLL_QUEUE.append(20)
	await _collide_into(prey, KRAKEN_TILE)
	assert_true(_is_held(prey), 'The Tide caught it.')

func test_the_seize_spends_the_krakens_reaction():
	# "expend your OVERWATCH" - in an engine where Overwatch is itself a reaction, that is the
	# reaction point.
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	await _raise_the_tide()
	var reactions_before:int = kraken.core.current.reactions
	Dice.CHEAT_ROLL_QUEUE.append(20)
	await _collide_into(prey, KRAKEN_TILE)
	assert_eq(kraken.core.current.reactions, reactions_before - 1, 'It cost the reaction.')

func test_a_collision_elsewhere_is_not_the_krakens_business():
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	await _raise_the_tide()
	var reactions_before:int = kraken.core.current.reactions
	await _collide_into(prey, Vector2i(4, 4))
	assert_false(_is_held(prey), 'Collisions across the map are nothing to do with it.')
	# No CHEAT_ROLL_QUEUE here, so a regression that fired the reaction anyway would resolve a real
	# contested roll and could still leave _is_held false by chance. This does not: the seize spends
	# the reaction whether or not the grapple lands, so an unspent reaction proves it never fired.
	assert_eq(kraken.core.current.reactions, reactions_before,
		'And it did not even reach for its reaction.')

func test_nothing_is_seized_before_the_tide_is_raised():
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	assert_false(_tide_is_up(), 'The Tide is down.')
	Dice.CHEAT_ROLL_QUEUE.append(20)
	await _collide_into(prey, KRAKEN_TILE)
	assert_false(_is_held(prey), 'So nothing is seized.')

# ============================== the reach cap ==============================
# "Hostile characters within your SENSORS treat movement away from you as difficult terrain."
#
# There is no cost seam in this engine - extra_cost is written only inside
# Pathfinder.Occupation.calculate_for, which consults no buff, and Pathfinder carries a class_name so
# it cannot be extended. What ships is a REACH CAP: a hostile may not END its move more than half its
# remaining speed further from the Kraken than it started. Faithful about direction, permissive about
# cost. This is the clause the user has said may be dropped if it reads badly in play.
#
# Reads the allowed set straight off the buff, the way test_bind_thy_flesh reads the chain's.

func _allowed_tiles_for(mover:Unit) -> Array[Vector2i]:
	var buff:BuffCore = UnitCondition.get_buffs(kraken, TIDE_BUFF_ID)[0]
	var context := Context.create({
		unit = mover,
		map = game.map,
		resource = MovementType.create(mover, true, true),
	})
	if not buff.base.check_if_passive_applies(buff, context): return []
	var values := buff.base.get_values(buff, context)
	return Tile.from_bitwise_array(values.object, game.map.size)

func test_a_hostile_cannot_retreat_further_than_half_its_remaining_speed():
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	prey.core.current.speed = 4
	await _raise_the_tide()

	var allowed := _allowed_tiles_for(prey)
	assert_true(allowed.has(Vector2i(3, 0)), 'Two spaces further out is still allowed.')
	assert_false(allowed.has(Vector2i(4, 0)), 'Three is not.')

func test_the_cap_is_measured_against_movement_still_left():
	# Difficult terrain charges against what you have left, so a unit that already moved gets less
	# retreat, not the same amount. Using max speed here would quietly refund spent movement.
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	prey.core.current.speed = 2
	await _raise_the_tide()

	var allowed := _allowed_tiles_for(prey)
	assert_true(allowed.has(Vector2i(2, 0)), 'One space further out is allowed.')
	assert_false(allowed.has(Vector2i(3, 0)), 'Two is not, on half the budget.')

func test_closing_with_the_kraken_is_never_capped():
	# The whole point of choosing this approximation: it is directional. Coming closer stays free.
	var prey := SpecFactory.create_unit(game.map, Vector2i(3, 0), Faction.AI_ENEMY)
	prey.core.current.speed = 4
	await _raise_the_tide()

	var allowed := _allowed_tiles_for(prey)
	assert_true(allowed.has(Vector2i(1, 0)), 'It may close all the way in.')

func test_allies_are_not_capped():
	var friend := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.PLAYER)
	friend.core.current.speed = 4
	await _raise_the_tide()
	assert_true(_allowed_tiles_for(friend).is_empty(), 'The Tide does not restrain its own side.')

func test_nothing_is_capped_before_the_tide_is_raised():
	# _allowed_tiles_for cannot run here - it indexes UnitCondition.get_buffs(kraken, TIDE_BUFF_ID)[0],
	# which does not exist before the Tide is raised. So rather than restate "no buff, no restriction"
	# a second time, this asks the same question the pathfinder itself asks: pathfinder.gd:340-350
	# loops every character's MOVEMENT_RESTRICTION buffs against whoever is moving. Same prey
	# placement and speed as the positive tests above, so the Tide is the only variable.
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	prey.core.current.speed = 4
	assert_false(_tide_is_up(), 'The Tide is down.')

	var restriction_context := Context.create({unit = prey, resource = MovementType.create(prey, true, true)})
	var restriction_buffs:Array[BuffCore] = []
	for check_unit:Unit in game.map.get_all_characters():
		restriction_buffs.append_array(
			UnitCondition.get_buffs_to(check_unit, Buff.TO.MOVEMENT_RESTRICTION, restriction_context))
	assert_true(restriction_buffs.is_empty(), 'Nothing restricts its retreat before the Tide is up.')

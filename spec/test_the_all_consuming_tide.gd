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
const IRREPRESSIBLE_ID := &'mt_irrepressible'

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

func test_a_held_character_can_still_act_on_itself_on_its_turn():
	# Cut off from the map is not cut off from oneself. A character always reaches itself, and a great
	# deal quietly hangs off that: an area effect centred on the caster, the AI's own entry in its
	# score table, the crosshair drawn on its own tile. Losing it would show up as none of those
	# working rather than as anything to do with the Tide.
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	await _raise_the_tide()
	_hold(prey)
	_its_turn(prey)
	assert_true(UnitRelation.can_affect(prey, prey), 'It can still act on itself.')

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

func test_a_hostile_already_against_the_kraken_is_dragged_into_it():
	# The best question the Tide asks, not a wasted one. A character with its back to the Kraken has
	# nowhere left to be dragged except INTO the Kraken, and being driven into the Kraken is a
	# collision - which is the opening the seize exists to take. Under the Tide this is the common
	# case, not a corner one, so skipping it would keep the two halves of the core power from ever
	# meeting.
	#
	# Earlier this file asserted the opposite: that the Tide leaves such a character alone and does not
	# even ask. That reading treated the last space as worthless because nobody ends up standing
	# anywhere new. It is worth everything - the Tide gets its hands on them.
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	await _raise_the_tide()
	Dice.CHEAT_ROLL_QUEUE.append(20)

	await _start_turn_for(prey)
	assert_eq(prey.tile(), Vector2i(1, 0), 'It cannot be moved into the Kraken, only slammed against it.')
	assert_true(_is_held(prey), 'And the Tide takes hold of what it drags into itself.')

func test_a_hostile_beside_the_kraken_but_several_floors_up_is_dragged_down_into_it():
	# Height is no shelter. A mech on a rooftop right beside the Kraken is inside the Tide - the sensor
	# check that scopes the undertow measures in three dimensions on purpose - and the drag hauls it
	# against the Kraken exactly as it would at ground level, reaction and all.
	#
	# Same shape as the case above, reached from height instead of from flat range, and kept because it
	# is the one arrangement where a distance measured one way and a pull performed another way used to
	# disagree. Read through the reaction rather than through the hold: a grapple five floors up is a
	# contest the Kraken can lose on its merits, and what is being pinned here is that the drag reached
	# the Kraken at all.
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	SpecFactory.set_tiles_elevation(game.map, 5, [Vector2i(1, 0)])
	await _raise_the_tide()
	Dice.CHEAT_ROLL_QUEUE.append(20)

	var reactions_before:int = kraken.core.current.reactions
	await _start_turn_for(prey)
	assert_eq(kraken.core.current.reactions, reactions_before - 1,
		'The Tide reaches up, drags it into itself, and grabs for it.')

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

const SEIZE_ACTION := &'action_tide_seize'

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

func test_the_seize_still_fires_while_the_kraken_is_itself_grappled():
	# Under its own Tide the Kraken is usually holding somebody and being held in turn, so this is its
	# ordinary state rather than an edge case. Unlike the undertow, the seize spends the reaction, and
	# spending a reaction is exactly what being GRAPPLED takes away - Irrepressible is the frame's
	# answer to that, and it is equipped here because the frame carries it. Without this the clause
	# would be dead precisely when the Tide is working.
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	kraken.core.equip_system(IRREPRESSIBLE_ID)
	SpecFactory.apply_passive_buffs(kraken) # before the Tide: this repairs the Kraken, and would undo it
	await _raise_the_tide()
	SpecFactory.apply(kraken, Lancer.STATUS.GRAPPLED)
	Dice.CHEAT_ROLL_QUEUE.append(20)
	await _collide_into(prey, KRAKEN_TILE)
	assert_true(_is_held(prey), 'Held or not, the Tide still takes what runs into it.')

func test_nothing_is_seized_before_the_tide_is_raised():
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	assert_false(_tide_is_up(), 'The Tide is down.')
	Dice.CHEAT_ROLL_QUEUE.append(20)
	await _collide_into(prey, KRAKEN_TILE)
	assert_false(_is_held(prey), 'So nothing is seized.')

# ================= the seize, from movement that actually happened =================
# Every test above hands the seize a collision that the spec announced. That is enough to pin what the
# seize DOES and nothing at all about whether anything on this frame ever produces a collision to hand
# it - and for a while nothing did: the Kraken's own pulls stopped politely one space short of whatever
# was in the way, so the clause was unreachable in play while reading green here. These drive real
# characters into the Kraken with real forced movement and let the collision arrive on its own.
#
# The seize is the only reaction on the board that answers a collision - every vanilla one refuses any
# collision its own gear did not cause - so it is also the instrument these read the collision with.
# What is being pinned is the collision; the grapple is just how it becomes visible.

func test_a_forced_move_that_runs_into_something_is_a_collision():
	# The contract everything below rests on, stated once on its own: when forced movement drives a
	# character into something it cannot enter, the stop is a COLLISION - a thing the board can answer -
	# and not merely a shorter journey. This one owes nothing to the Kraken's own gear; it is a plain
	# shove of the sort anything on the map might deal out.
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	await _raise_the_tide()
	Dice.CHEAT_ROLL_QUEUE.append(20)

	var shove := MovementType.create_for_involuntary(prey)
	shove.straight_line = true
	shove.must_move_max_possible = true
	await game.execute_event(&'event_unit_move', {
		unit = prey,
		array = Pathfinder.straight_path_to(KRAKEN_TILE, prey.tile(), 1, game.map.shape),
		resource = shove,
	})

	assert_eq(prey.tile(), Vector2i(1, 0), 'It could not enter the space, so it stopped against it.')
	assert_true(_is_held(prey), 'And stopping against the Kraken is a collision the Tide can answer.')

func test_the_undertow_drags_a_character_in_and_the_tide_seizes_it():
	# The two halves of the core power, meeting. The undertow hauls a hostile a space closer every turn;
	# when the only space closer is the Kraken's own, the drag becomes a collision and the seize takes
	# it. Nothing here announces a collision - the turn start does all of it.
	var prey := SpecFactory.create_unit(game.map, Vector2i(2, 0), Faction.AI_ENEMY)
	await _raise_the_tide()
	Dice.CHEAT_ROLL_QUEUE.append(20)

	await _start_turn_for(prey) # dragged from two out to one out; nothing to hit yet
	assert_eq(prey.tile(), Vector2i(1, 0), 'First turn it is dragged to the Kraken.')
	assert_false(_is_held(prey), 'Open ground is not a collision.')

	Dice.CHEAT_ROLL_QUEUE.append(20)
	await _start_turn_for(prey) # now the only way closer is through the Kraken
	assert_true(_is_held(prey), 'The next drag runs it into the Kraken, and the Tide takes it.')

func test_a_character_pulled_into_the_kraken_is_seized():
	# Drag To The Depths' Pull is the frame's other forced movement, and it answers to the same rule:
	# two spaces of travel that run out of room end against the Kraken, and that is a collision. The
	# HULL save is failed here so there is a pull to speak of at all.
	var prey := SpecFactory.create_unit(game.map, Vector2i(2, 0), Faction.AI_ENEMY)
	SpecFactory.apply(kraken, Lancer.STATUS.IMMOBILIZED) # Drag's own gate: only while pinned
	kraken.core.current.speed = kraken.core.get_speed_max()
	await _raise_the_tide()
	Dice.CHEAT_ROLL_QUEUE.append(1) # a 1 fails any save worth the name
	Dice.CHEAT_ROLL_QUEUE.append(20)

	await SpecFactory.use(game, kraken, CORE_POWER_ID, &'action_drag_pull', [prey])

	assert_eq(prey.tile(), Vector2i(1, 0), 'Dragged as far as the Kraken and stopped against it.')
	assert_true(_is_held(prey), 'And the Tide took hold of it on impact.')

func test_the_tide_takes_nothing_new_from_a_prisoner_it_throws_at_itself():
	# The one forced movement on this frame the seize can never answer, and it is a rule rather than an
	# oversight: Reposition throws only characters the Kraken is ALREADY holding, and the seize only
	# answers collisions against the Kraken. So the throw slams a prisoner home, and the Tide finds it
	# has nothing to take that it does not already have.
	#
	# Irrepressible is equipped so the Kraken genuinely has a reaction to spend - holding somebody makes
	# it GRAPPLED, which would otherwise take its reactions away and let this pass for the wrong reason.
	var prey := SpecFactory.create_unit(game.map, Vector2i(3, 0), Faction.AI_ENEMY)
	kraken.core.equip_system(IRREPRESSIBLE_ID)
	SpecFactory.apply_passive_buffs(kraken) # before the Tide: this repairs the Kraken, and would undo it
	_hold(prey)
	await _raise_the_tide()
	SpecFactory.apply(kraken, Lancer.STATUS.IMMOBILIZED) # Drag's own gate: only while pinned
	kraken.core.current.speed = kraken.core.get_speed_max()

	var reactions_before:int = kraken.core.current.reactions
	assert_eq(reactions_before, 1, 'It has a reaction to spend.')
	await SpecFactory.use(game, kraken, CORE_POWER_ID, &'action_drag_reposition', [prey, KRAKEN_TILE])

	assert_eq(prey.tile(), Vector2i(1, 0), 'Thrown at the Kraken, it stops hard against it.')
	# Stopped, not delivered: two spaces of travel and then a Kraken. A prisoner that was routed into
	# the Kraken's space and tidied back out again would sit on the same tile having covered more.
	assert_eq(prey.state.spaces_moved_this_turn, 2, 'Two spaces of it, and then no more.')
	assert_true(_is_held(prey), 'It never got loose, so there was nothing to re-take.')
	assert_eq(kraken.core.current.reactions, reactions_before,
		'And the Kraken kept its reaction rather than grabbing at what it already had.')

func test_the_tide_does_not_offer_to_grapple_a_character_it_already_holds():
	# The rule: the Tide never asks about taking something it already has. Found in playtest - a
	# prisoner thrown into the Kraken by Drag collides with it, and the seize put a grapple prompt on
	# screen for a character that could not be grappled, because action_grapple refuses anyone in the
	# grappler's own katamari.
	#
	# Asserted at the trigger, which is the only place "was it OFFERED" is visible: once the reaction
	# activates, a grapple that cannot land and a grapple that was declined look identical from the
	# board - same reactions, same holds - which is exactly how this survived a suite that already
	# covered the outcome.
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	var loose := SpecFactory.create_unit(game.map, Vector2i(0, 1), Faction.AI_ENEMY)
	await _raise_the_tide()
	_hold(prey)

	assert_true(_is_held(prey), 'setup: the Kraken is holding it.')
	assert_true(Katamari.create(kraken).all_units.has(prey), 'setup: and it is in the katamari.')

	var seize:Action = ContentLibrary.get_kit(CORE_POWER_ID).get_action(SEIZE_ACTION)
	if not Action.is_valid(seize): return fail_test('%s is on the kit.' % SEIZE_ACTION)

	assert_false(_seize_offers_itself_for(seize, prey),
		'It does not reach for a character it is already holding.')
	assert_true(_seize_offers_itself_for(seize, loose),
		'But it still reaches for one it is not.')

## Would the seize answer a collision brought about by this character?
func _seize_offers_itself_for(seize:Action, mover:Unit) -> bool:
	var collision := EventCore.create(&'event_unit_collide', {
		unit = mover,
		target_tiles = [KRAKEN_TILE] as Array[Vector2i],
		event = SpecFactory.dummy_event(),
	})
	return seize.triggers_on_event(kraken, gear, collision)

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

## The movement type is the one the pathfinder would be planning; pass a different one to ask about a
## different kind of move.
func _allowed_tiles_for(mover:Unit, movement_type:MovementType = null) -> Array[Vector2i]:
	var buff:BuffCore = UnitCondition.get_buffs(kraken, TIDE_BUFF_ID)[0]
	var context := Context.create({
		unit = mover,
		map = game.map,
		resource = movement_type if MovementType.is_valid(movement_type) else MovementType.create(mover, true, true),
	})
	if not buff.base.check_if_passive_applies(buff, context): return []
	var values := buff.base.get_values(buff, context)
	return Tile.from_bitwise_array(values.object, game.map.size)

## The same collection pathfinder.gd:340-350 loops over for every character's restriction buffs
## against `mover` - used to prove the buff is actually wired to Buff.TO.MOVEMENT_RESTRICTION and not
## merely present on the Kraken. _allowed_tiles_for above calls the buff's methods directly and would
## stay green even if `to = &"movement_restriction"` were deleted from the .tres; this does not.
func _restriction_buffs_for(mover:Unit) -> Array[BuffCore]:
	var restriction_context := Context.create({unit = mover, resource = MovementType.create(mover, true, true)})
	var restriction_buffs:Array[BuffCore] = []
	for check_unit:Unit in game.map.get_all_characters():
		restriction_buffs.append_array(
			UnitCondition.get_buffs_to(check_unit, Buff.TO.MOVEMENT_RESTRICTION, restriction_context))
	return restriction_buffs

func test_a_hostile_cannot_retreat_further_than_half_its_remaining_speed():
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	prey.core.current.speed = 4
	await _raise_the_tide()

	# The wiring check: this is the query the pathfinder itself runs before it ever asks get_values
	# for tiles. Without it, deleting `to = &"movement_restriction"` from the .tres would leave the
	# assertions below meaningless - they call the buff's methods directly, not through the pathfinder.
	assert_false(_restriction_buffs_for(prey).is_empty(),
		"The pathfinder's own restriction query finds the Tide once it is up.")

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

func test_an_odd_budget_rounds_down():
	# Difficult terrain costs double, so an odd budget does not buy a full extra space of retreat:
	# speed 3 covers exactly one space, not two. Rounding up (Util.half) would over-grant here.
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	prey.core.current.speed = 3
	await _raise_the_tide()

	var allowed := _allowed_tiles_for(prey)
	assert_true(allowed.has(Vector2i(2, 0)), 'One space further out is allowed.')
	assert_false(allowed.has(Vector2i(3, 0)), 'Two is not, on an odd budget.')

func test_closing_with_the_kraken_is_never_capped():
	# The whole point of choosing this approximation: it is directional. Coming closer stays free.
	var prey := SpecFactory.create_unit(game.map, Vector2i(3, 0), Faction.AI_ENEMY)
	prey.core.current.speed = 4
	await _raise_the_tide()

	var allowed := _allowed_tiles_for(prey)
	assert_true(allowed.has(Vector2i(1, 0)), 'It may close all the way in.')

func test_circling_the_kraken_at_the_same_range_is_never_capped():
	# The other half of the directional claim: the cap only fires on tiles further from the Kraken
	# than the mover started, so a tile at the SAME range - off to the side rather than toward or away
	# - is free too. A plain radius leash would pass this trivially, but so would a bug that banned
	# every tile off the direct retreat line; this pins that circling specifically stays open.
	#
	# Speed 0, so the cap is the baseline exactly and the tile sits precisely on it. At any higher
	# speed the same-range tile clears with spaces to spare and would pass for a cap that was not
	# directional at all.
	var prey := SpecFactory.create_unit(game.map, Vector2i(3, 0), Faction.AI_ENEMY)
	prey.core.current.speed = 0
	await _raise_the_tide()

	var allowed := _allowed_tiles_for(prey)
	assert_true(allowed.has(Vector2i(0, 3)), 'Circling at the same range from the Kraken stays free.')

func test_a_forced_move_is_not_capped():
	# The clause the cap stands in for taxes movement as difficult terrain, and difficult terrain does
	# not touch a character being thrown, flown or teleported - so neither does this. It is the one
	# place the approximation errs restrictive if left unchecked, and the gear it would cost is the
	# Kraken's own: Drag To The Depths' Reposition moves a prisoner exactly this way, and its "3 spaces
	# in any direction" must stay 3 spaces while the Tide is up.
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	prey.core.current.speed = 4
	await _raise_the_tide()

	assert_false(_allowed_tiles_for(prey).is_empty(), 'Its own retreat is capped.')
	assert_true(_allowed_tiles_for(prey, MovementType.create_for_involuntary(prey)).is_empty(),
		'But being thrown is not something the Tide bogs down.')

func test_allies_are_not_capped():
	var friend := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.PLAYER)
	friend.core.current.speed = 4
	await _raise_the_tide()
	assert_true(_allowed_tiles_for(friend).is_empty(), 'The Tide does not restrain its own side.')

func test_nothing_is_capped_before_the_tide_is_raised():
	# _allowed_tiles_for cannot run here - it indexes UnitCondition.get_buffs(kraken, TIDE_BUFF_ID)[0],
	# which does not exist before the Tide is raised. So rather than restate "no buff, no restriction"
	# a second time, this asks the same question the pathfinder itself asks via _restriction_buffs_for:
	# pathfinder.gd:340-350 loops every character's MOVEMENT_RESTRICTION buffs against whoever is
	# moving. Same prey placement and speed as the positive tests above, so the Tide is the only
	# variable, and the same helper the wiring assertion above uses, so the two are symmetrical.
	var prey := SpecFactory.create_unit(game.map, Vector2i(1, 0), Faction.AI_ENEMY)
	prey.core.current.speed = 4
	assert_false(_tide_is_up(), 'The Tide is down.')

	assert_true(_restriction_buffs_for(prey).is_empty(), 'Nothing restricts its retreat before the Tide is up.')

# ------------------ the cap must never GIVE a character movement ------------------
# A reach cap is a subtraction, and the question a playtester cannot answer from the board is whether
# it is only ever that. pathfinder.gd:340-350 reads a MOVEMENT_RESTRICTION buff's `boolean` to decide
# whether its tile array is INTERSECTED against where the character may go or MERGED into it - and
# merged, the Tide would be a licence for every hostile in SENSORS to walk anywhere it reaches. The
# tests above cannot see that: they ask the buff what it permits, and a buff that permits too much
# looks exactly like a buff that permits the right amount. So these ask real pathfinders, the same
# call the move chooser makes when a character's turn opens (phase_ui_player_action.gd:126).
#
# They need somewhere to run to, and the shared spec map is 5x5, so they build a wider one of their
# own - the way test/unit/ai/test_ai_movement_heatmap.gd:14 does. A fresh gamemaster, so the odd map
# is not handed to the next test.

const WIDE_MAP := Vector2i(15, 5)

func _on_a_wider_map() -> void:
	game = SpecFactory.setup_gamemaster(self, true, SpecFactory.create_combat(Landscape.create_default(WIDE_MAP)))
	kraken = SpecFactory.create_unit(game.map, KRAKEN_TILE)
	gear = kraken.core.equip_system(CORE_POWER_ID)
	kraken.core.has_core_power = true

func _prey_at(tile:Vector2i) -> Unit:
	return SpecFactory.create_unit(game.map, tile, Faction.AI_ENEMY)

## Turn start is what hands a character its speed and its Boost (unit_action.gd:74-82), so a character
## that has not had one has nothing to retreat with. The undertow is declined: it drags on the
## Kraken's authority, and these tests count ground the character covered on its own.
func _its_own_turn(mover:Unit) -> void:
	SpecFactory.current_responder.chosen_yesnos = false
	await SpecFactory.start_turn(game, mover)
	SpecFactory.current_responder.chosen_yesnos = true

## Everywhere the game would actually offer this character, Boost included.
func _move_options(mover:Unit, include_boost:bool = true) -> Pathfinder:
	return await Pathfinder.generate_for_standard_move(
		mover, MovementType.create_for_standard_move(mover), include_boost)

func _tiles_offered_only_by(options:Pathfinder, and_not_by:Pathfinder) -> Array[Vector2i]:
	var only_here:Array[Vector2i] = []
	for tile:Vector2i in options.reachable_tiles:
		if not and_not_by.is_reachable(tile): only_here.append(tile)
	return only_here

func _furthest_it_may_end_from_the_kraken(options:Pathfinder) -> int:
	var furthest:int = 0
	for tile:Vector2i in options.reachable_tiles: furthest = maxi(furthest, Tile.distance(KRAKEN_TILE, tile))
	return furthest

func test_the_cap_takes_tiles_away_and_never_hands_one_back():
	# The whole worry, in one pair of assertions: raising the Tide must shut tiles, and must not open
	# a single one that was shut to a character before it rose.
	#
	# Which of the two catches a mis-declared cap is worth knowing. Flipping the buff's `boolean` to
	# true - the exact "accidentally grants movement" mistake - is caught by the SECOND assertion, not
	# the first: pathfinder.gd:352-353 merges added tiles into the CANDIDATE set and then filters that
	# set by budget, zone and interior anyway, so merging can only re-offer tiles the character could
	# already afford. A restriction buff in this engine can lose its restriction; it cannot hand out
	# reach. The first assertion pins that engine guarantee, which this clause leans on entirely.
	_on_a_wider_map()
	var prey := _prey_at(Vector2i(5, 0))
	await _its_own_turn(prey)

	var before_the_tide := await _move_options(prey)
	await _raise_the_tide()
	var under_the_tide := await _move_options(prey)

	var opened := _tiles_offered_only_by(under_the_tide, before_the_tide)
	var shut := _tiles_offered_only_by(before_the_tide, under_the_tide)
	assert_true(opened.is_empty(), 'The Tide opens no tile that was shut before it rose: %s' % [opened])
	assert_false(shut.is_empty(), 'And it does shut some, so the question above is a real one.')

func test_nothing_the_cap_leaves_open_costs_more_than_the_character_can_pay():
	# The other half of "it cannot grant movement". A tile the cap leaves open must still be one the
	# character can afford to walk to: the clause edits where a character may end up, never the
	# movement that buys the trip.
	_on_a_wider_map()
	var prey := _prey_at(Vector2i(5, 0))
	await _raise_the_tide()
	await _its_own_turn(prey)

	var options := await _move_options(prey)
	assert_false(options.reachable_tiles.is_empty(), 'It has somewhere to go, so the two checks below look at something.')
	var unaffordable:Array[Vector2i] = []
	for tile:Vector2i in options.reachable_tiles:
		if options.get_path_cost(options.path_to(tile)) > options.max_budget: unaffordable.append(tile)
	assert_true(unaffordable.is_empty(), 'Everywhere still offered is somewhere it can walk to: %s' % [unaffordable])

	var beyond_its_speed:Array[Vector2i] = []
	for tile:Vector2i in options.movable_tiles:
		if options.get_path_cost(options.path_to(tile)) > prey.core.current.speed: beyond_its_speed.append(tile)
	assert_true(beyond_its_speed.is_empty(),
		'And nothing is offered as a plain move that costs more than its speed: %s' % [beyond_its_speed])

func test_closing_and_then_pulling_back_out_is_a_move_and_a_boost_not_a_refund():
	# What a playtester counts from the board: a character crosses its whole speed toward the Kraken
	# and then half of it again on the way out - about one and a half speeds of ground in a single
	# turn - and cannot tell whether the Tide gave it something. It did not. That is a move and a
	# Boost, two separate grants of movement, and the cap SHORTENED the second leg from four spaces to
	# two. Without the Tide the same character covers eight.
	_on_a_wider_map()
	var prey := _prey_at(Vector2i(9, 0))
	await _raise_the_tide()
	await _its_own_turn(prey)
	assert_eq(prey.tile(), Vector2i(9, 0), 'It starts its turn where it stood.')
	assert_eq(prey.get_speed_max(), 4, 'A speed of four, which is what the counts below are one and a half of.')

	await SpecFactory.move(game, prey, Vector2i(5, 0), MovementType.create_for_standard_move(prey))
	assert_eq(prey.tile(), Vector2i(5, 0), 'Closing is never capped, so it crosses its whole speed inward.')

	await SpecFactory.use_solo(game, prey, &'ms_boost')
	var boosted := await _move_options(prey, false)
	assert_false(boosted.is_reachable(Vector2i(9, 0)), 'A whole Boost of retreat is not on offer.')
	assert_true(boosted.is_reachable(Vector2i(7, 0)), 'Half of one is.')

	await SpecFactory.move(game, prey, Vector2i(7, 0), MovementType.create_for_standard_move(prey))
	assert_eq(prey.tile(), Vector2i(7, 0), 'Two spaces back out.')
	assert_eq(prey.state.spaces_moved_this_turn, 6, 'Six spaces on a speed of four - the one and a half that gets counted.')
	assert_lte(prey.state.spaces_moved_this_turn, prey.get_speed_max() * 2,
		'And never more ground than its move and its Boost would have bought with no Tide at all.')

func test_closing_in_never_buys_a_longer_way_back_out():
	# The cap measures from wherever the character stands when the question is asked, and a character
	# may split its move - so in principle a retreat could be bought by walking in first and having
	# the mark re-measured from closer. It cannot: every space spent closing is a space not spent
	# leaving, and the mark comes in with it.
	_on_a_wider_map()
	var prey := _prey_at(Vector2i(5, 0))
	await _raise_the_tide()
	await _its_own_turn(prey)

	var straight_out := await _move_options(prey, false)
	var furthest_straight_out := _furthest_it_may_end_from_the_kraken(straight_out)

	await SpecFactory.move(game, prey, Vector2i(3, 0), MovementType.create_for_standard_move(prey))
	assert_eq(prey.tile(), Vector2i(3, 0), 'It walked two spaces in.')

	var after_closing := await _move_options(prey, false)
	assert_lt(_furthest_it_may_end_from_the_kraken(after_closing), furthest_straight_out,
		'Walking in first leaves it a shorter way out, not a longer one.')

func test_a_retreat_taken_a_space_at_a_time_still_costs_a_space_at_a_time():
	# A character may move, act, and move again, and the cap re-measures from wherever it stands each
	# time - so a retreat taken one space at a time is measured against a mark that slides out with it,
	# and buys three spaces on a speed of four where a single dash buys two. That is the approximation
	# sitting looser than the clause it stands for, and it is the direction everything else here errs
	# in too. What it must never do is conjure ground: three spaces of retreat cost three spaces of
	# movement, and the fourth space of speed buys nothing at all.
	_on_a_wider_map()
	var prey := _prey_at(Vector2i(5, 0))
	await _raise_the_tide()
	await _its_own_turn(prey)

	for x:int in [6, 7, 8, 9]:
		await SpecFactory.move(game, prey, Vector2i(x, 0), MovementType.create_for_standard_move(prey))

	assert_eq(prey.tile(), Vector2i(8, 0), 'Three spaces out one at a time, and then the cap holds it.')
	assert_eq(prey.state.spaces_moved_this_turn, 3, 'Three spaces of retreat cost three spaces of movement.')
	assert_lte(prey.state.spaces_moved_this_turn, prey.get_speed_max(),
		'Splitting the move up buys reach, never ground.')

# My Domain - the grapple that reaches, and the adjacency it grants.
#
#   "The Kraken can |Grapple| characters at least partially within any |Bursts| centered on itself.
#    Characters grappled this way count as though they are |adjacent| and within |Range 1| of the
#    Kraken."
#
# Design notes live in D:\DEV\lancer-tactics-claude\specs\2026-09-02-kraken-design.md.
#
# These specs cover the grapple in isolation - the attachment, the adjacency extension and the
# tether - by attaching units directly, the way test_bind_thy_flesh covers the chain without firing
# the trigger. The burst trigger is a separate piece with its own spec.
extends GutTest

const KIT_ID := &'mt_my_domain'
const TETHER_BUFF_ID := &'buff_my_domain_tether'
const TETHER_FXE_ID := &'fxe_my_domain_tether'
const VANILLA_GRAPPLE_FXE_ID := &'fxe_outgoing_grapple'

## Far enough apart that nothing about this grapple could be explained by ordinary adjacency.
const KRAKEN_TILE := Vector2i(0, 0)
const PREY_TILE := Vector2i(4, 0)

var game:Gamemaster
var kraken:Unit
var prey:Unit
var gear:GearCore

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	kraken = SpecFactory.create_unit(game.map, KRAKEN_TILE)
	gear = kraken.core.equip_system(KIT_ID)
	prey = SpecFactory.create_unit(game.map, PREY_TILE)

## Grapple through My Domain's own gear, which is what the burst trigger does.
func _grapple() -> void:
	Katamari.attach_units(SpecFactory.dummy_event(), kraken, prey, gear.persistent_id)

## Apply and bind the tether, as the trigger does alongside the grapple.
func _tether() -> BuffCore:
	var core := UnitCondition.apply_buff_id(SpecFactory.dummy_event(), prey, TETHER_BUFF_ID)
	ContentLibrary.get_buff(TETHER_BUFF_ID).bind(core, kraken)
	return core

# ============================== the reaching grapple ==============================

func test_the_trait_declares_a_grapple_that_reaches():
	# Both flags matter and they are easy to set independently by mistake: is_grapple alone gives a
	# grapple that snaps the moment the target is not adjacent, which is every case here.
	assert_true(GearCore.is_valid(gear), '%s equipped.' % KIT_ID)
	if not GearCore.is_valid(gear): return

	var attachments := gear.get_passives_of_type(PassiveAttachment)
	assert_false(attachments.is_empty(), 'My Domain carries an attachment passive.')
	for passive:PassiveAttachment in attachments:
		assert_true(passive.is_grapple, 'It is a grapple.')
		assert_true(passive.ignores_adjacency_requirement, 'And it holds at a distance.')

func test_a_grapple_made_at_range_survives_validation():
	# Katamari.attach_units calls validate_attachments immediately, which is where an ordinary
	# grapple on a non-adjacent target would be dropped again.
	assert_gt(UnitRelation.distance_between(kraken, prey), 1, 'They start well apart.')
	_grapple()

	var held:Array[StringName] = []
	for grapple:SpecificAction in UnitCondition.get_outgoing_grapples(kraken):
		held.append(grapple.unit.core.persistent_id)
	assert_true(held.has(prey.core.persistent_id), 'The Kraken is still holding it.')

# ============================== adjacency ==============================

func test_a_character_out_of_reach_is_not_adjacent_to_begin_with():
	# Guards against a vacuous pass below: if these two counted as adjacent anyway, every adjacency
	# assertion in this file would be green for the wrong reason.
	assert_false(UnitRelation.is_adjacent(kraken, prey), 'Four spaces apart is not adjacent.')

func test_a_grappled_character_counts_as_adjacent():
	_grapple()
	assert_true(UnitRelation.is_adjacent(kraken, prey), 'The Kraken counts it as adjacent.')

func test_adjacency_is_symmetric():
	# is_adjacent is defined as adjacent_characters(a).has(b), so the two directions are separate
	# lookups. A grappled character must be able to swing back at what is holding it.
	_grapple()
	assert_true(UnitRelation.is_adjacent(prey, kraken), 'And it counts the Kraken as adjacent.')

func test_adjacency_ends_with_the_grapple():
	_grapple()
	assert_true(UnitRelation.is_adjacent(kraken, prey), 'Adjacent while held.')
	Katamari.dettach_units(SpecFactory.dummy_event(), kraken, prey, gear.persistent_id)
	assert_false(UnitRelation.is_adjacent(kraken, prey), 'And not once released.')

func test_it_does_not_make_bystanders_adjacent():
	# The extension keys on the grapple, not on a radius - unlike the House Guard talent it is
	# modelled on. A third party standing right where the prey is must be unaffected.
	var bystander:Unit = SpecFactory.create_unit(game.map, Vector2i(4, 1))
	_grapple()
	assert_false(UnitRelation.is_adjacent(kraken, bystander), 'A bystander is still just far away.')

# ============================== the tether ==============================

func test_the_tether_is_drawn_from_the_grappled_character():
	# Deliberately from this end. unit_token.gd tickets every outgoing grapple with the same fx id
	# at Vector2i.ZERO, and the attached-fx map keys on (tile, id), so tethers drawn from the Kraken
	# would be competing for one key - and My Domain grapples a whole burst at once.
	_grapple()
	var tickets := ContentLibrary.get_buff(TETHER_BUFF_ID).get_attached_fx(_tether(), prey)
	assert_eq(tickets.size(), 1, 'The grappled character draws exactly one tether.')
	if tickets.is_empty(): return

	assert_eq(tickets.front().context.unit, prey, 'It starts at the grappled character.')
	assert_eq(tickets.front().context.target_unit, kraken, 'And ends at the Kraken.')

func test_every_grappled_character_draws_its_own_tether():
	# The failure this exists for: one shackle holding two prisoners drawing a single chain, which
	# read in play as only one of them being tethered.
	var second_prey:Unit = SpecFactory.create_unit(game.map, Vector2i(0, 4))
	_grapple()
	Katamari.attach_units(SpecFactory.dummy_event(), kraken, second_prey, gear.persistent_id)

	var buff:Buff = ContentLibrary.get_buff(TETHER_BUFF_ID)
	var first_core := _tether()
	var second_core := UnitCondition.apply_buff_id(SpecFactory.dummy_event(), second_prey, TETHER_BUFF_ID)
	buff.bind(second_core, kraken)

	assert_eq(buff.get_attached_fx(first_core, prey).size(), 1, 'The first is tethered.')
	assert_eq(buff.get_attached_fx(second_core, second_prey).size(), 1, 'And so is the second.')

func test_the_tether_uses_our_own_fx_not_vanillas():
	# Recolouring fxe_outgoing_grapple would have turned every grapple in the game blue, including
	# other frames'. This pins that we shipped a separate scene instead.
	var buff:Buff = ContentLibrary.get_buff(TETHER_BUFF_ID)
	assert_true(is_instance_valid(buff), '%s is in the buffs index.' % TETHER_BUFF_ID)
	if not is_instance_valid(buff): return

	assert_eq(buff.get_fxe_id(), TETHER_FXE_ID, 'The tether has its own fx scene.')
	assert_ne(buff.get_fxe_id(), VANILLA_GRAPPLE_FXE_ID, 'And it is not vanillas.')

func test_the_tether_stops_drawing_once_the_grapple_is_gone():
	# The buff and the attachment are applied together but can end apart - release, a death, a
	# forced move. A line hanging off a character nothing is holding reads as a bug.
	_grapple()
	var core := _tether()
	assert_eq(ContentLibrary.get_buff(TETHER_BUFF_ID).get_attached_fx(core, prey).size(), 1, 'Drawn while held.')

	Katamari.dettach_units(SpecFactory.dummy_event(), kraken, prey, gear.persistent_id)
	assert_eq(ContentLibrary.get_buff(TETHER_BUFF_ID).get_attached_fx(core, prey).size(), 0, 'Gone once released.')

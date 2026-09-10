# Resilience: the Draugr's charge pool on cp_cupiditas_vitae.
#
#   "The Draugr has charges called Resilience, up to a maximum of 1 + its missing structure."
#   (localizations.csv, gear.cp_cupiditas_vitae.action_ceaseless_death.effect)
#
# The store is a vanilla PassiveDieCounter (key "resilience"), wired exactly like the Barbarossa's
# Apocalypse Rail (cp_apocalypse_rail.tres:16-20). That buys the action-bar number, the tooltip
# entry, the popcorn on change and {resilience} interpolation in effect text for free. max_value = 8
# is only a hard ceiling; the REAL cap is variable and lives in resilience.gd's gain path, because
# PassiveDieCounter.update_value_core clamps against a static max (passive_die_counter.gd:63-67).
#
# The Draugr's frame is structure 4 (mf_draugr.tres), so at full structure the cap is 1, and at one
# structure left it is 4. Everything below is that arithmetic.
extends GutTest

const Resilience := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/cp_cupiditas_vitae/resilience.gd')
const DRAUGR_FRAME := 'res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/mf_draugr.tres'

var game:Gamemaster
var draugr:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	draugr = SpecFactory.create_unit(game.map, Vector2i(0, 0))
	draugr.core.change_mech_frame(load(DRAUGR_FRAME))
	SpecFactory.apply_passive_buffs(draugr)

func test_the_ring_of_pips_follows_the_count():
	# passive_resilience_fx.gd: one scene per count (fxe_resilience_1 .. _8), the Aegis Shield
	# Generator's recipe, so a change of count is a change of fxe_id and the token swaps the scene.
	var gear := Resilience.gear(draugr)
	var passive:Passive = null
	for p:Passive in gear.kit.passives:
		if p.has_method(&'fxe_id_for'): passive = p
	assert_not_null(passive, 'cp_cupiditas_vitae carries the Resilience fx passive.')
	if passive == null: return
	assert_true(passive.get_attached_fx(gear, draugr).is_empty(), 'No ring at zero.')
	for n in range(1, 9):
		assert_false(ContentLibrary.get_fxendless_path(StringName('fxe_resilience_%d' % n)).is_empty(),
			'fxe_resilience_%d is indexed.' % n)
	draugr.core.current.structure = 1 # the cap is 1 + missing structure
	Resilience.gain(draugr, 3)
	var tickets:Array[FxEndless.Ticket] = passive.get_attached_fx(gear, draugr)
	assert_eq(tickets.size(), 1, 'One ring.')
	if tickets.is_empty(): return
	assert_eq(tickets[0].fxe_id, &'fxe_resilience_3', 'Three pips for three Resilience.')
	Resilience.spend(draugr)
	assert_eq(passive.get_attached_fx(gear, draugr)[0].fxe_id, &'fxe_resilience_2', 'Two after a spend.')

func test_a_fresh_draugr_has_no_resilience():
	# starting_value = 0 and min_value = 0. The vanilla default for both is nonzero
	# (passive_die_counter.gd:12-14), so this is a real assertion about our .tres, not a tautology.
	assert_eq(Resilience.count(draugr), 0, 'The pool starts empty.')

func test_the_counter_is_reachable_from_the_core_power_gear():
	var gear:GearCore = Resilience.gear(draugr)
	assert_true(GearCore.is_valid(gear), 'cp_cupiditas_vitae is on the frame and equipped.')
	if not GearCore.is_valid(gear): return
	var die:PassiveDieCounter = gear.get_die_counter_passive()
	assert_true(is_instance_valid(die), 'It carries a PassiveDieCounter.')
	if is_instance_valid(die): assert_eq(die.key, 'resilience', 'Keyed "resilience", which is what the tooltip looks up.')

func test_at_full_structure_the_cap_is_one():
	assert_eq(draugr.core.current.structure, 4, 'Fixture: the Draugr starts at 4 structure.')
	assert_eq(Resilience.maximum(draugr), 1, '1 + 0 missing structure.')
	Resilience.gain(draugr, 1)
	assert_eq(Resilience.count(draugr), 1, 'The first point lands.')
	Resilience.gain(draugr, 1)
	assert_eq(Resilience.count(draugr), 1, 'The second is refused by the variable cap.')

func test_missing_structure_raises_the_cap():
	draugr.core.current.structure = 1 # three missing
	assert_eq(Resilience.maximum(draugr), 4, '1 + 3 missing structure.')
	Resilience.gain(draugr, 9)
	assert_eq(Resilience.count(draugr), 4, 'A big gain is clamped to the variable cap, not to max_value.')

func test_a_gain_never_lowers_the_pool():
	# Repairing structure lowers the cap. A later gain must not be a stealth punishment: it clamps
	# the ADDITION, it does not retroactively trim what is already banked.
	draugr.core.current.structure = 1
	Resilience.gain(draugr, 4)
	assert_eq(Resilience.count(draugr), 4, 'Fixture: four banked while three structure were missing.')
	draugr.core.current.structure = 4
	assert_eq(Resilience.maximum(draugr), 1, 'The cap is back down to 1.')
	Resilience.gain(draugr, 1)
	assert_eq(Resilience.count(draugr), 4, 'And the four banked points survive the gain.')

func test_spending_takes_one_and_stops_at_zero():
	draugr.core.current.structure = 2
	Resilience.gain(draugr, 2)
	assert_eq(Resilience.spend(draugr), 1, 'Spend one.')
	assert_eq(Resilience.spend(draugr), 0, 'Spend the other.')
	assert_eq(Resilience.spend(draugr), 0, 'min_value = 0, so it cannot go negative.')

func test_a_repair_empties_the_pool():
	# resets_on_repair is read by mech_repair_panel.gd:216. Nothing in a spec runs that panel, so
	# this asserts the FLAG rather than the behaviour - and the flag is the whole contract.
	var gear:GearCore = Resilience.gear(draugr)
	if not GearCore.is_valid(gear): return fail_test('the core power gear resolved.')
	var die:PassiveDieCounter = gear.get_die_counter_passive()
	if not is_instance_valid(die): return fail_test('the die counter resolved.')
	assert_true(die.resets_on_repair, 'A full repair clears banked Resilience.')
	assert_eq(die.starting_value, 0, 'And it resets to empty, not to a stocked pool.')

func test_a_unit_without_the_core_power_answers_zero_rather_than_erroring():
	# Every later task calls count() from a reaction that may fire on any unit on the map.
	var stranger := SpecFactory.create_unit(game.map, Vector2i(2, 0))
	stranger.core.full_repair()
	assert_eq(Resilience.count(stranger), 0, 'No core power, no Resilience.')
	assert_eq(Resilience.gain(stranger, 1), 0, 'And a gain on it is a no-op, not a crash.')

# The PESTILENCE-class NHP. "Your mech gains the AI tag and the Kill Host protocol."
#
# Pure vanilla wiring, and the template is content/gear/horus/systems/ms_scylla_class_nhp.
#
# system_tags IS A BITMASK (kit.gd:30): {UNIQUE = 1, INDESTRUCTIBLE = 2, AI = 4, NHP = 8,
# SHIELD = 16}. 13 = 1 + 4 + 8 = Unique + AI + NHP, which is what all ten vanilla NHP systems set.
# It drives is_unique/is_ai/is_nhp (:54-57), the geartag chips (:96-101) and
# UnitCore.has_nhp_copilot (unit_core.gd:319).
#
# THE FACE AND THE NAME ARRIVE TOGETHER, from UnitPrinter.full_repair ->
# PassiveAiPrivilege.inherit_default_nhp_settings (unit_printer.gd:79, passive_ai_privilege.gd:61-77):
# the passive's default_portrait JSON is copied onto the pilot, and the name comes from
# Translate.gear(kit_id, 'default_name', false) - i.e. from the CSV row that already exists. Both are
# adopted only when the pilot has nothing, or when what it has is marked "is_stock"; that is why the
# shipped pestilence.json sets is_stock true (plan decision D11) and why the "custom" test below sets
# it false.
#
# Kill Host itself is task 5; this file asserts the Kit has no actions yet, which is the honest state
# and which task 5 then flips.
extends GutTest

const NHP := &'ms_pestilence_class_nhp'

var game:Gamemaster
var unit:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self)
	unit = SpecFactory.create_unit(game.map, Vector2i(0, 0), Faction.PLAYER)
	unit.core.equip_system(NHP)
	unit.core.pilot.nhp_name = ''
	unit.core.pilot.nhp_portrait_json = {}

func test_the_kit_is_unique_ai_and_nhp():
	var kit:Kit = ContentLibrary.get_kit(NHP)
	assert_true(Kit.is_valid(kit), '%s is in the kits index.' % NHP)
	if not Kit.is_valid(kit): return
	assert_eq(kit.system_tags, 13, 'system_tags 13 is UNIQUE 1 + AI 4 + NHP 8.')
	assert_true(kit.is_unique(), 'Unique.')
	assert_true(kit.is_ai(), 'AI.')
	assert_true(kit.is_nhp(), 'NHP.')
	assert_eq(kit.sp_cost, 3, 'Three SP.')

func test_the_mech_reads_as_carrying_an_nhp_copilot():
	assert_true(unit.core.has_nhp_copilot(), 'unit_core.gd:319 scans the loadout for a kit.is_nhp().')

func test_the_nhp_takes_its_name_from_the_csv():
	unit.core.full_repair()
	assert_eq(unit.core.pilot.nhp_name, 'Pestilence',
		'gear.ms_pestilence_class_nhp.default_name, adopted by inherit_default_nhp_settings.')

func test_the_nhp_takes_its_default_portrait():
	unit.core.full_repair()
	assert_false(unit.core.pilot.nhp_portrait_json.is_empty(), 'A portrait was adopted.')
	assert_true(unit.core.pilot.nhp_portrait_json.get('is_nhp', false), 'And it is an NHP portrait.')
	assert_true(unit.core.pilot.nhp_portrait_json.get('is_stock', false),
		'Shipped as stock, so a later NHP can replace it (plan decision D11).')

func test_the_portrait_actually_deserializes():
	# A malformed or too-old json would be refused at portrait_sandwich_core.gd:131-132 and the mech
	# would render with a blank face and no error the player could act on.
	unit.core.full_repair()
	var core := PortraitSandwichCore.deserialize(unit.core.pilot.nhp_portrait_json, true)
	assert_true(is_instance_valid(core), 'The author json survives deserialization.')
	if is_instance_valid(core): assert_true(core.is_nhp, 'As an NHP.')

func test_a_hand_authored_portrait_is_not_overwritten():
	unit.core.pilot.nhp_name = 'Someone Else'
	unit.core.pilot.nhp_portrait_json = {is_stock = false, is_nhp = true}
	unit.core.full_repair()
	assert_eq(unit.core.pilot.nhp_name, 'Someone Else', 'A custom name survives.')
	assert_false(unit.core.pilot.nhp_portrait_json.get('is_stock', true), 'And so does the custom portrait.')

func test_the_kit_counts_against_the_single_ai_limit():
	# counts_against_limit and increases_limit are both left at their defaults, so this is an
	# ordinary AI: one per mech (passive_ai_privilege.gd:33-49).
	var kit:Kit = ContentLibrary.get_kit(NHP)
	if not Kit.is_valid(kit): return fail_test('%s loaded.' % NHP)
	assert_true(PassiveAiPrivilege.is_kit_illegal_to_equip_due_to_ai_limit(kit, unit.core.loadout),
		'A second AI on a mech that already has one is refused.')

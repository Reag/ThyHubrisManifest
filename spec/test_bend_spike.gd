# THROWAWAY SPIKE - deleted in Task 10. See Task 1 of the To Bend Reality plan.
extends GutTest

const SpikeBend := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_banshee/mt_to_bend_reality/spike_bend.gd')

var game:Gamemaster
var shooter:Unit
var target:Unit

func before_each():
	game = SpecFactory.setup_gamemaster(self, true, SpecFactory.create_combat(Landscape.create_default(Vector2i(20,20))))
	game.campaign_core = CampaignCore.create(SpecFactory.create_campaign_base())
	game.map.campaign_core = game.campaign_core
	shooter = SpecFactory.create_unit(game.map, Vector2i(1,1))
	shooter.core.equip_system(&'mw_assault_rifle')
	shooter.core.full_repair()
	SpecFactory.apply_passive_buffs(shooter)
	target = SpecFactory.create_unit(game.map, Vector2i(14,1), Faction.AI_ENEMY)

## A: does a variant offered by a buff appear on a weapon that buff does not own?
func test_variant_entry_reaches_an_arbitrary_kinetic_weapon():
	SpecFactory.apply_buff(shooter, &'buff_spike_bend')
	var gear:GearCore = shooter.get_gear(&'mw_assault_rifle')
	var specific := SpecificAction.create(shooter, gear, gear.get_solo_action())
	var groups := specific.action.get_alternate_actions(specific)
	var keys:Array = []
	for group:VariantActionGroup in groups: keys.append(group.key)
	assert_true(keys.has(&'spike_bend'),
		'A VARIANT_ACTIONS buff reaches a weapon it does not own. Got groups: %s' % [keys])

## B: does relaying to a proxy actually move range?
func test_a_relay_proxy_moves_range():
	var gear:GearCore = shooter.get_gear(&'mw_assault_rifle')
	var specific := SpecificAction.create(shooter, gear, gear.get_solo_action())
	var weapon_range:int = specific.action.get_target_range(specific)
	assert_false(UnitTargeting.get_tiles_in_range(specific).has(Vector2i(14,1)),
		'Target starts OUT of range from the shooter (range %s).' % weapon_range)

	var proxy := TargetActionUtil.create_targeting_proxy(Vector2i(12,1), shooter, 1)
	var relayed := SpecificAction.create(proxy, gear, gear.get_solo_action())
	assert_true(UnitTargeting.get_tiles_in_range(relayed).has(Vector2i(14,1)),
		'Measured from the proxy, the same target IS in range.')
	proxy.remove_from_game()

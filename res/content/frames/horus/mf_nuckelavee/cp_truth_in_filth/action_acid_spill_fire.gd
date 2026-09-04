# Acid Spill, part 3 of 4: offer the attack, make it, and foul the ground.
#
#   "This weapon may only be used as a free action after you BOOST, and deals damage equal to half
#    the distance moved. If you BOOST your full speed in a straight line, the attack area becomes
#    difficult terrain which lasts until you create terrain this way again"
#
# ORDERING NOTE, and it is the one real difference from action_poisoned_soil_lay.gd: that file
# disarms FIRST, before prompting, because nothing downstream needs the flag. This one must not.
# action_acid_spill.gd's availability gate requires the arm, so disarming early would make the
# weapon unavailable to the very call that fires it. The disarm therefore sits in an unconditional
# tail after both branches - do NOT add an early return above it.
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-04-acid-spill-design.md
extends ActionReaction

## Bookkeeping, not an ability the pilot uses - the WEAPON is what shows in the tooltip.
func show_in_tooltip(_kit:Kit) -> bool: return false


const AcidSpill := preload('./passive_acid_spill.gd')

## Poisoned Soil prompts first, by the designer's call. Lower is sooner; action_poisoned_soil_lay
## leaves get_priority at the default 0, so anything above 0 orders us after it.
func get_priority() -> int: return 1

func get_required_triggering_context() -> Array[Context.PROP]:
	return [Context.PROP.unit]

func triggers_on_event(unit:Unit, gear:GearCore, triggering_event:EventCore) -> bool:
	if not AcidSpill.is_armed(gear, triggering_event.context.map.game_core.round_count): return false
	if triggering_event.context.unit != unit: return false
	# A knockback or pull must not fire the frame's weapon mid-enemy-turn.
	if not AcidSpill.is_voluntary_movement(triggering_event): return false
	# Nothing to offer if it cannot deal damage. The weapon's own gate says the same thing; this
	# keeps the prompt from appearing at all.
	return AcidSpill.damage_for(gear) >= 1

func activate(context:Context, activation:EventCore) -> void:
	var gear:GearCore = context.gear
	var unit:Unit = context.unit
	var weapon:ActionAttackWeapon = gear.kit.get_action(&'action_acid_spill')

	# Read both of these BEFORE anything is spent - the burst is taken from the weapon's own
	# range_pattern so the fouled ground is definitionally the attack area, not a second definition
	# of it that could drift.
	var qualifies:bool = AcidSpill.is_straight_full_speed(gear, context.map.shape)
	var burst_tiles:Array[Vector2i] = weapon.range_pattern.get_tiles(
		context.map.shape, unit.get_size(), unit.occupied_tiles()
	)

	# Free action, so the player gets to decline. CommonActionUtil.choose_and_use auto-picks when
	# there is exactly one option and would give no chance to say no, so the confirm is explicit.
	if await CommonActionUtil.confirm_use(context, [], burst_tiles):
		await CommonActionUtil.choose_and_use(
			activation,
			SpecificAction.from_context(context),
			[SpecificAction.create(unit, gear, weapon)] as Array[SpecificAction],
			CommonActionUtil.choose_and_use_no_spend, # a free action spends no action economy
			[unit.tile()], # a BURST centres on the attacker; this only satisfies the target count
		)
		if qualifies:
			AcidSpill.write_trail(gear, burst_tiles)
			# set_state does not refresh the map - only set_aura_active does - so the new terrain
			# would not exist until something unrelated triggered a sweep. Ask for one.
			UnitTile.update_tracking_and_statuses(context.map, activation)

	# UNCONDITIONAL TAIL. Whichever way the player answered, this boost is spent. See the header.
	AcidSpill.set_armed(gear, false)
	AcidSpill.write_pending(gear, [] as Array[Vector2i])

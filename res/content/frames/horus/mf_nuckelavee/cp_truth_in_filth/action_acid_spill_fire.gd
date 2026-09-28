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
	if triggering_event.context.unit != unit: return false
	# A knockback or pull must not fire the frame's weapon mid-enemy-turn.
	if not AcidSpill.is_voluntary_movement(triggering_event): return false
	# Delegate to the weapon's own gate (armed + can deal damage) rather than re-deriving it here -
	# one definition of "armed and able to deal damage" instead of two that could drift apart.
	# NOT a status-blocking guarantee: Action.is_available_to_activate (action.gd:175-176) returns
	# true unconditionally today, and neither ActionAttack nor ActionAttackWeapon overrides it, so the
	# super call action_acid_spill.gd makes into it currently guards nothing. JAMMED specifically does
	# not apply here either way - action_acid_spill_fire.tres sets consumes_rxn = false, so
	# ActionReaction.is_jammable() (action_reaction.gd:66) is false and a jammed Nuckelavee can still
	# fire Acid Spill. The super call stays in action_acid_spill.gd regardless, as correct defensive
	# practice for composability, but this delegation should not be read as buying a block it doesn't.
	var weapon:ActionAttackWeapon = gear.kit.get_action(&'action_acid_spill')
	return weapon.is_available_to_activate(unit, gear)

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

	# NO confirm_use here, deliberately. The weapon's own activation raises its own confirm/targeting
	# step, so an outer prompt made the player press OK twice to fire once. Declining happens at the
	# weapon's step instead, and choose_and_use auto-picks when there is exactly one option, so it
	# goes straight there.
	#
	# But choose_and_use returns SpecificAction.is_valid(chosen) (common_action_util.gd:736), NOT
	# whether the attack resolved - it swallows choose_to_use_event.aborted. So a cancel at the
	# weapon's own step is indistinguishable from a hit as far as the return value goes, and fouling
	# the ground off it would hand the player free terrain for an attack they never made. That
	# mattered less when the outer confirm existed; now that it is gone, this IS the decline path.
	#
	# The engine's own usage counter is the honest signal: UnitAction.spend calls
	# gear.increment_action_usage_for_action unconditionally (unit_action.gd:279) - freebies included,
	# they only skip the per-TURN half - so it moves if and only if the weapon really spent.
	var usage_group:StringName = gear.get_usage_group_for_action(weapon)
	var uses_before:int = gear.get_uses_this_round_alt(usage_group)

	await CommonActionUtil.choose_and_use(
		activation,
		SpecificAction.from_context(context),
		[SpecificAction.create(unit, gear, weapon)] as Array[SpecificAction],
		CommonActionUtil.choose_and_use_no_spend, # a free action spends no action economy
		[unit.tile()], # a BURST centres on the attacker; this only satisfies the target count
	)

	if qualifies and gear.get_uses_this_round_alt(usage_group) > uses_before:
		AcidSpill.write_trail(gear, burst_tiles)
		# set_state does not refresh the map - only set_aura_active does - so the new terrain
		# would not exist until something unrelated triggered a sweep. Ask for one.
		UnitTile.update_tracking_and_statuses(context.map, activation)

	# UNCONDITIONAL TAIL. Whichever way the player answered, this boost is spent. See the header.
	# The arm is the only thing that gates re-firing - pending is not read by anything once armed
	# is false (action_acid_spill.gd's gate and this file's own triggers_on_event both check
	# is_armed first), so there is nothing left to clear here. The next boost reseeds pending from
	# scratch via action_acid_spill_arm.gd; do not "helpfully" restore a clear of it.
	AcidSpill.set_armed(gear, false)

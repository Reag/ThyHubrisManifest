# The visible Resilience counter: a ring of green pips over the Draugr, one per point.
#
# The Aegis Shield Generator's recipe (passive_aegis_shield_generator_charges_fx.gd): FxEndless
# tickets are keyed by (tile, fxe_id) on the token (unit_token.update_attached_fx), so a count CHANGE
# has to be a DIFFERENT id for the controller to swap the scene - hence fxe_resilience_1 .. _8, one
# scene per count (generated; res/content/fx_endless/character/resilience/). A single scene reading
# the count off its ticket would not be rebuilt when only the context changed.
#
# PassiveDieCounter.update_value already calls unit.update_attached_fx() on every change
# (passive_die_counter.gd:44), so nothing here has to listen for anything: Resilience.gain/spend go
# through that counter and the ring follows.
extends Passive

const Resilience := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/cp_cupiditas_vitae/resilience.gd')

const FXE_PREFIX := 'fxe_resilience_'
const MAX_PIPS := 8

static func fxe_id_for(count:int) -> StringName:
	if count <= 0: return &''
	return StringName(FXE_PREFIX + str(mini(count, MAX_PIPS)))

func get_attached_fx(gear:GearCore, unit:Unit) -> Array[FxEndless.Ticket]:
	if not Unit.is_valid(unit) or not GearCore.is_valid(gear) or gear.is_destroyed: return []
	var fxe_id := fxe_id_for(Resilience.count(unit))
	if fxe_id == &'': return []
	return [FxEndless.Ticket.create(fxe_id, Vector2i.ZERO, {unit = unit})]

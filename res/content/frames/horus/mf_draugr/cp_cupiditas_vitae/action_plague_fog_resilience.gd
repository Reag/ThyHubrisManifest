# "Gain 1 Resilience when a hostile character begins their turn inside the fog" - while the Draugr
# is inside it too.
#
# An ActionReactionOnComingWithin on the FOG's kit, not the Draugr's: the cloud is what has to be
# adjacent to the victim, and the base class's distance test (:73-75) then measures from the cloud
# for free. A MARKER deployable can carry a reaction - dep_apocalypse_burn does exactly this - and
# consumes_rxn = false is what makes it possible, since statblock_zero gives the cloud no reactions
# to spend.
#
# The .tres does almost all the filtering declaratively: when_start_turn_within, triggers_on_allies
# = false, triggers_only_on_characters (default true), triggers_on_coming_within_range = 2. It is
# triggers_on_allies = false that keeps a Draugr standing in its own gas from paying itself at the
# start of its own turn - the fog inherits its deployer's faction, so the Draugr reads as an ally to
# its own cloud. All this override adds is the "while YOU are inside the fog" gate, which nothing
# declarative can express.
#
# can_trigger_any_number_of_times_per_round = true with can_only_affect_a_unit_once_per_round = true
# is the caustic-earth pairing: several hostiles may each start a turn in the cloud in one round and
# each should pay - and a hostile granted a second activation in the round pays twice, matching
# vanilla's action_apocalypse_burn (action_reaction_on_coming_within.gd:29). The per-unit stamp is
# the base class's own buff_track_affection bookkeeping (:96-107); buff_track_affection.tres clears
# it at START_OF_TURN, i.e. the victim's own next turn start reopens it.
#
# The point goes to the fog's OWNER, not to the fog - the cloud has no core power and
# Resilience.gain on it would be a silent no-op.
extends ActionReactionOnComingWithin

const PlagueFog := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/cp_cupiditas_vitae/plague_fog.gd')
const Resilience := preload('res://unpacked/Reag-ThyHubris/res/content/frames/horus/mf_draugr/cp_cupiditas_vitae/resilience.gd')

## Bookkeeping, not an ability with its own tooltip entry: the fog's kit carries no localization
## rows at all, and Action.show_in_tooltip would otherwise advertise this as a nameless action.
## Same move as action_caustic_earth.gd and vanilla's action_system_clear_buff.gd:21.
func show_in_tooltip(_kit:Kit) -> bool: return false

func triggers_on_event(unit:Unit, gear:GearCore, triggering_event:EventCore) -> bool:
	if not super.triggers_on_event(unit, gear, triggering_event): return false
	if not PlagueFog.owner_is_inside(unit): return false # "While you are inside the fog"
	# A Faction.NONE unit is neither ally nor enemy, so triggers_on_allies = false (which only
	# excludes actual allies) lets it pay for free. The fog inherits its deployer's faction, so
	# checking hostility against the fog itself reads the same as checking against its owner.
	if not UnitRelation.are_enemies(unit, triggering_event.context.unit): return false
	return true

func activate(context:Context, activation:EventCore) -> void:
	var fog:Unit = context.unit
	var victim:Unit = activation.context.event.context.unit
	# Stamps the victim and bails if something else already paid for it this round. Checked here as
	# well as in triggers_on_event because reactions are queued as a block and resolved later.
	if record_unit_affected_and_abort_if_already_affected(activation, victim): return
	if not Unit.is_valid(fog): return
	Resilience.gain(fog.get_owner_unit(), 1)

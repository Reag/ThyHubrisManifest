# Face Thy Judgement - the basic half of DHIYED Observation. STUB.
#
# A 1/round reaction. consumes_rxn is left at its default of true, which is what makes it cost the
# unit's reaction and therefore limits it to once per round on its own
# (ActionReaction.get_per_round_hard_limit).
#
# TODO: the trigger and the effect. triggers_on is deliberately empty in the .tres so this cannot
# fire while it is a stub - an armed reaction that does nothing would be worse than an absent one.
extends ActionReaction

func activate(context:Context, activation:EventCore) -> void:
	pass # TODO: implement Face Thy Judgement

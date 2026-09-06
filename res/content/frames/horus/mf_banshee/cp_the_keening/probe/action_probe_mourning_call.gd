# PROBE -- throwaway, deleted after the real Mourning Call build.
# PROBE 1: can an OnHitEffect activate a QUICK action mid-resolution through
# CommonActionUtil.choose_and_use, and have the action's own cost machinery
# actually pay for it (unit.state.actions AND unit.core.has_core_power)?
# See "The gauntlet" in
# D:\DEV\lancer-tactics-claude\specs\2026-09-06-banshee-mourning-call-design.md
extends ActionSystem

const ACTIVATED_META_KEY := &'probe_mourning_call_activated'

func activate(context:Context, activation:EventCore) -> void:
	# mirrors action_castigate.gd / action_unstable_system.gd: call spend_actions()
	# ourselves so the deferred_spend chain from choose_and_use actually runs.
	spend_actions(activation)
	Engine.set_meta(ACTIVATED_META_KEY, true)

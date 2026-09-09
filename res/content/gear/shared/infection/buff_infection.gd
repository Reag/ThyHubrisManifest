# The Infection buff. Its state holds the count (COUNT_KEY); infection.gd is the only writer.
# Behaviour arrives in two more tasks: the end-of-turn Systems check, and clearing whenever Burn
# is cleared. Read the design doc (2026-09-09-draugr-design.md, section 1) before adding to it.
extends Buff

const Infection := preload('res://unpacked/Reag-ThyHubris/res/content/gear/shared/infection/infection.gd')

func name_text(core:BuffCore) -> String:
	return Translate.buff(core, 'name.count').format({count = core.get_state(Infection.COUNT_KEY, 0)})

# The Injector Drill's attack. A heavy melee weapon whose four charges are a fuel tank for the tech
# strike it delivers on a hit, not ammunition for the swing.
#
#   "You may attack with this weapon without expending or requiring charges, and it can be destroyed
#    even with no charges remaining."
#
# ONE OVERRIDE COVERS THE WHOLE FIRST SENTENCE. Action.consumes_charges (action.gd:108) defaults to
# true and is read in exactly two places: unit_action.gd:153 refuses the action with REASON.NO_CHARGES
# when the gear is empty ("without requiring"), and unit_action.gd:274 spends one on every use
# ("without expending"). Vanilla's precedents are one line each - action_turret_attack.gd:11,
# action_recall.gd:43, action_redeploy.gd:42.
#
# THE SECOND SENTENCE IS A KNOWN, RECORDED GAP. UnitPrinter.get_destructable_gear
# (unit_printer.gd:311-320) requires gear.has_charges_left(), so an empty drill is not offered as a
# destruction target, and no mod-side seam on unit_printer.gd has been proven live
# (memory lancer-tactics-dead-extension-seams). Design 2026-09-09-draugr-design.md section 5 accepts
# it for now; spec/test_injector_drill.gd asserts the current behaviour so the gap cannot be forgotten.
#
# The charges are spent by hand in on_hit (task 2).
extends ActionAttackWeapon

func consumes_charges(specific:SpecificAction) -> bool: return false

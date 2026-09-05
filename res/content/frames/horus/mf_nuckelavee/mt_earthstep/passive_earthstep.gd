# Earthstep's marker. Carries no behaviour and no exports - its only job is to be findable.
#
# The rule lives in res/engine/character/unit/service/unit_relation.gd_ext.gd, which overrides
# get_weapons_that_can_overwatch. That is engine-level code running for every unit in every overwatch
# check on the map, so it must not know the id 'mt_earthstep': hardcoding one mod's content id inside
# an engine extension is the coupling that bites later. It asks for THIS TYPE instead, so any future
# gear - ours or another mod's - can grant Earthstep by carrying one of these.
#
# Same reasoning as Caustic Earth's get_caustic_tiles, which names no specific trait either.
#
# Kit.is_passive_of_type (kit.gd:161-165) matches on the script identity exactly, or one base level
# deep. This extends Passive directly and is queried as itself, so the exact match is what fires.
#
# Design notes: D:\DEV\lancer-tactics-claude\specs\2026-09-04-earthstep-design.md
extends Passive

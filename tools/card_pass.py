#!/usr/bin/env python3
"""The Dynamic Turn Rework card pass (Notion: Dynamic Turn Rework, Phase 5).
Claude's drafts of reworked and added cards on existing parts, batch by batch,
for Logan to review in Refit Bay. Reactors stay passive-only (Logan,
2026-10-13); their passives can still be rewritten here.

Each entry replaces a part's whole card list (cards matched by position keep
their Refit Bay ids). Parts in tools/claude_parts.py take their cards from
here too, so `claude_parts.py sync` doesn't undo the pass.

Usage: python3 tools/card_pass.py refit <refit_bay.json> <out.json>  (the doc with the cards replaced)
       python3 tools/card_pass.py components   (patch data/components.json and data/component_rules.json)
"""
import json
import random
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def snake(name):
    s = re.sub(r"['’!]", "", name.lower())
    s = re.sub(r"[^a-z0-9]+", "_", s)
    return s.strip("_")


def card(name, heat, hits, dmg, statuses=(), effect="", rule=None):
    return {"name": name, "heat": heat, "hits": hits, "dmg": dmg, "statuses": list(statuses), "effect": effect, "rule": rule or {}}


def passive(name, effect, rule, statuses=()):
    return {"name": name, "heat": 0, "hits": 0, "dmg": "", "statuses": list(statuses), "effect": effect, "passive": rule}


S = lambda status, stacks, target="enemy": (status, stacks, target)
SELF = {"play_mode": "self"}

# Batch 1: Surplus hardpoints (Logan, 2026-10-13: Harpoon 4 Heat / 5-7;
# Lockout Round's Disabled stays, Cipher and Relay Sentinel are boss / elite).
# Numbers are Refit Bay's (the game adds heat_add and damage_mult).
BATCH1 = {
    "Autocannon": [
        card("Suppressing Fire", 1, 1, "3-4", [S("jam", 1)]),
        card("Rapid Fire", 4, 5, "5-7", [S("jam", 2, "self")], "Reduces chance to fire by 20% each hit after the second.",
             {"hit_chance": [1.0, 0.9, 0.7, 0.4, 0.2]}),
        card("Tracer Burst", 2, 2, "4-6", effect="Vs a part attacking this turn: Shock 1.",
             rule={"vs_attacking": {"status": "shock", "stacks": 1}}),
    ],
    "HV Rifle": [
        card("Shock Round", 2, 1, "6-8", [S("shock", 1)]),
        card("EMP Round", 3, 1, "4-6", effect="Deals triple damage if the targeted hard point is already shocked.",
             rule={"mult_if_target_status": {"status": "shock", "mult": 3, "hardpoint_only": True}}),
        card("Lockout Round", 3, 1, "4-6", effect="Vs a Shocked part: Disabled 1.",
             rule={"status_if_target_status": {"if": "shock", "status": "disabled", "stacks": 1}}),
    ],
    "Ion Blade": [
        card("Swipe", 1, 1, "5-8", effect="Double damage vs a part attacking this turn.", rule={"vs_attacking": {"mult": 2}}),
        card("Thrust Through", 6, 1, "12-16", effect="Deals double damage to hard points at half or lower.",
             rule={"mult_if_target_below": {"fraction": 0.5, "mult": 2, "hardpoint_only": True}}),
        card("Foresight", 3, 0, "", effect="Until your next turn: the next hit on your mech is canceled, and its attacker takes 8.",
             rule={**SELF, "guard": {"type": "parry", "damage": 8}}),
    ],
    "Laser Drive": [
        card("Helix Drum", 2, 2, "4-6", effect="Double damage vs a part at half HP or less.",
             rule={"mult_if_target_below": {"fraction": 0.5, "mult": 2}}),
        card("Optical Pinpoint", 5, 1, "22-28", effect="Disables the target hardpoint for one round.",
             rule={"on_hit_status": {"status": "disabled", "stacks": 1, "hardpoint_only": True}}),
        card("Rainbow Rain", 6, 6, "4-7", effect="Hits random parts.", rule={"random_part_hits": True}),
    ],
    "Thermal Lance": [
        card("Piercing Rush", 3, 1, "10-13", [S("burn", 2)]),
        card("Precision Throw", 1, 1, "16-22", [S("offline", "", "self"), S("burn", 3)]),
        card("Heat Jab", 1, 1, "6-8", [S("burn", 1, "self")]),
    ],
    "Voltage Spike": [
        card("Spike 'Em", 2, 1, "6-10", [S("shock", 2)]),
        card("Spike Setup", 2, 0, "0", [S("absorb", 5, "ownMech")]),
        card("Static Field", 2, 0, "", effect="Until your next turn: every enemy part that hits you gets Shock 1.",
             rule={**SELF, "guard": {"type": "static_field", "status": "shock", "stacks": 1}}),
    ],
    "Arc Whip": [
        card("Whiplash", 2, 1, "7-11", [S("shock", 2)]),
        card("Wrap Up", 4, 1, "8-13", [S("shock", 4), S("disabled", 2, "self")]),
        card("Snap", 2, 1, "6-9", effect="Double damage vs a Shocked part.", rule={"mult_if_target_status": {"status": "shock", "mult": 2}}),
    ],
    "Fang Blade": [
        card("Embed", 2, 1, "7-14", [S("disabled", 1), S("disabled", 1, "self")]),
        card("Jab Jab Jab!", 4, 4, "4-6", effect="Double damage vs a Disabled part.",
             rule={"mult_if_target_status": {"status": "disabled", "mult": 2}}),
        card("Twist", 1, 1, "4-6", effect="Vs a Disabled part: Disabled 1 more.",
             rule={"status_if_target_status": {"if": "disabled", "status": "disabled", "stacks": 1}}),
    ],
    "Flare Array": [
        card("Eject Flares", 3, 0, "0", [S("absorb", 10, "ownMech")]),
        card("Heat Eject", -3, 0, "0", [S("smoke", 1, "ownMech")]),
        card("Decoy Flares", 2, 0, "", effect="Until your next turn: the next attack aimed at one of your hardpoints hits this part instead.",
             rule={**SELF, "guard": {"type": "decoy"}}),
    ],
    "Needle Carbine": [
        card("Prick", 1, 1, "3-4", [S("acid", 1)]),
        card("Needle Storm", 3, 5, "4-6", effect="Hits random parts.", rule={"random_part_hits": True}),
        card("Tranq Dart", 2, 1, "3-4", effect="Vs a part attacking this turn: Shock 2.",
             rule={"vs_attacking": {"status": "shock", "stacks": 2}}),
    ],
    "Flash Pistol": [
        card("Flashbang", 2, 1, "5-7", [S("smoke", 2)]),
        card("Quick Draw", 0, 1, "4-6", effect="First card this turn: double damage.", rule={"double_if_first": True}),
        card("Blind Shot", 2, 1, "6-8", effect="Double damage vs a Smoked mech.", rule={"mult_if_target_status": {"status": "smoke", "mult": 2}}),
    ],
    "Heat Lance": [
        card("Searing Line", 3, 1, "12-16", effect="+1 damage per 2 Heat you have.", rule={"bonus_per_heat": {"per": 2, "bonus": 1}}),
        card("Redline Burst", 5, 1, "22-28", effect="+50% damage while over max Heat.", rule={"mult_if_over_max": 1.5}),
        card("Heat Dump", -3, 0, "", [S("disabled", 1, "self")], "Vent 3.", {"vents": True}),
    ],
    "Coil Whip": [
        card("Crackle", 2, 2, "4-6", [S("shock", 1)]),
        card("Discharge", 3, 1, "8-11", effect="Consume the target's Shock: +5 damage per stack.",
             rule={"consume_status": {"status": "shock", "per_stack": 5}}),
        card("Arc Lash", 3, 0, "", effect="Shock 1 on every enemy part attacking this turn.",
             rule={**SELF, "status_on_attackers": {"status": "shock", "stacks": 1}}),
    ],
    "Vent Cannon": [
        card("Blow-Off", -2, 1, "7-10", effect="Vent 2.", rule={"vents": True}),
        card("Steam Slug", 3, 1, "14-18", effect="Enemy gains 2 Heat.", rule={"heat_to_target": 2}),
        card("Purge", 2, 0, "", effect="Remove all Burn and Smoke from your mech.", rule={**SELF, "cleanse": ["burn", "smoke"]}),
    ],
    "Buzzsaw Arm": [
        card("Grind", 2, 3, "3-5", effect="+3 damage per hit vs a part with Acid.", rule={"bonus_if_target_status": {"status": "acid", "flat": 3}}),
        card("Shred", 3, 2, "7-10", [S("acid", 2)]),
        card("Rip Plating", 2, 1, "5-7", effect="First removes all Deflect and Absorb from the target mech.", rule={"strip_shields": True}),
    ],
    "Mortar Pod": [
        card("Lob", 3, 2, "8-11", effect="Hits random parts.", rule={"random_part_hits": True, "volley": True}),
        card("Smoke Shell", 1, 0, "", [S("smoke", 3)]),
        card("Smoke Screen", 1, 0, "", [S("smoke", 2, "ownMech")], "Until your next turn: enemy attacks hit random parts of yours.",
             {"guard": {"type": "scatter"}}),
    ],
    "Hook Lance": [
        card("Harpoon", 4, 1, "5-7", [S("disabled", 1)]),
        card("Reel In", 2, 1, "6-9", effect="Double damage vs Disabled.", rule={"mult_if_target_status": {"status": "disabled", "mult": 2}}),
        card("Yank Aim", 4, 1, "4-6", effect="Vs a part attacking this turn: its attacks this turn hit its own mech.",
             rule={"vs_attacking": {"turn": True}}),
    ],
    "Pile Driver": [
        card("Drive", 4, 1, "22-28", effect="Last card this turn.", rule={"last_card": True}),
        card("Aftershock", 6, 1, "28-36", [S("disabled", 1), S("disabled", 1, "self")]),
        card("Breaker", 3, 1, "10-14", effect="Double damage vs a mech with Deflect or Absorb.",
             rule={"mult_if_target_status": {"status": ["deflect", "absorb"], "mult": 2}}),
    ],
    "Flak Wall": [
        card("Flak", 3, 5, "3-5", effect="Can't target hardpoints.", rule={"volley": True, "no_hardpoints": True}),
        card("Brace", 2, 0, "", [S("deflect", 5, "ownMech")]),
        card("Hunker", 3, 0, "", [S("deflect", 3, "ownMech")], "Deflect 8 instead if a heavy attack is coming.",
             {"if_heavy_incoming": {"status": "deflect", "stacks": 5}}),
    ],
    "Grinder Maw": [
        card("Chew", 3, 2, "6-8", effect="Reclaim 50%.", rule={"heal_on_hit": 0.5}),
        card("Maul", 5, 1, "24-30", [S("disabled", 2, "self")]),
        card("Devour", 4, 1, "8-10", effect="If this destroys a part, Vent 4.", rule={"vent_on_kill": 4}),
    ],
    "Rivet Gun": [
        card("Rivet", 1, 1, "4-6", effect="+4 damage vs a Jammed part.", rule={"bonus_if_target_status": {"status": "jam", "flat": 4}}),
        card("Weld Shut", 3, 1, "11-14", [S("jam", 2)]),
        card("Patch Job", 2, 0, "", effect="Heal your most damaged part 8.", rule={**SELF, "heal_lowest": 8}),
    ],
}

# Batches 3-4: the original cards of the Salvaged and Prototype hardpoints
# (their added cards are in ADDED). Every pure-damage card takes a tradeoff
# from the Phase 2 menu or moves to another role (Logan, 2026-10-13: "continue
# to the next batch").
BATCH34 = {
    # ---- Salvaged ----
    "Neon Axe": [
        card("Wide Swing", 4, 3, "6-10", effect="Hits random parts.", rule={"random_part_hits": True}),
        card("Cross Chop", 6, 2, "14-20", effect="Last card this turn.", rule={"last_card": True}),
        card("Extension", 3, 0, "0", [S("deflect", 5, "ownMech")], "Deflect 9 instead if a heavy attack is coming.",
             {"if_heavy_incoming": {"status": "deflect", "stacks": 4}}),
    ],
    "Caustic Schism": [
        card("Spillage", 4, 1, "6-8", [S("acid", 1)], "Repeat this effect the next two turns.", {"repeat_turns": 2}),
        card("Self Splash", -3, 1, "24-32", effect="Vents heat at the cost of taking damage.", rule={"play_mode": "self", "self_damage": True}),
        card("Acid Rain", 3, 3, "4-7", effect="+3 damage per hit vs a part with Acid.", rule={"bonus_if_target_status": {"status": "acid", "flat": 3}}),
    ],
    "Railspike": [
        card("33% Power Rail", 3, 1, "6-10", effect="Vs a part attacking this turn: Disabled 1.",
             rule={"vs_attacking": {"status": "disabled", "stacks": 1}}),
        card("66% Power Rail", 4, 1, "20-32", [S("offline", "", "self")], "50% chance to apply.", {"status_chance": 0.5}),
        card("100% Power Rail", 6, 1, "40-54", [S("offline", "", "self")]),
    ],
    "Cluster Rockets": [
        card("Salvo Fire", 3, 6, "3-6", effect="Hits random parts.", rule={"volley": True, "random_part_hits": True}),
        card("All 0ut Salvo", 5, 10, "3-6", [S("disabled", 2, "self")], rule={"volley": True}),
    ],
    "FireStorm": [
        card("Set Ablaze", 3, 3, "3-5", [S("burn", 3)]),
        card("Lay Waste", 5, 2, "8-12", [S("burn", 1, "allEnemies")], "Hits all enemies.", {"hits_all_enemies": True}),
    ],
    "Hell Dropper": [
        card("Targeted Napalm", 4, 3, "4-6", [S("burn", 2)], rule={"volley": True}),
        card("Napalm Rain", 4, 2, "7-10", [S("burn", 1, "allEnemies")], "Hits all enemies; 50% chance per hit.",
             {"hits_all_enemies": True, "hit_chance": [0.5], "volley": True}),
    ],
    "Impact Hammer": [
        card("Hammer Down", 3, 1, "14-22", effect="The target mech gains Deflect 3.", rule={"gift_status": {"status": "deflect", "stacks": 3}}),
        card("Leap Slam", 5, 1, "22-30", [S("disabled", 1)]),
    ],
    "Scatter Shot": [
        card("Blast 'Em", 2, 4, "2-6", effect="+50% damage vs a part at half HP or less.",
             rule={"volley": True, "mult_if_target_below": {"fraction": 0.5, "mult": 1.5}}),
        card("Empty Clip", 3, 6, "2-6", [S("jam", 2, "self")], rule={"volley": True}),
    ],
    "Arc Thrower": [
        card("Arc", 3, 1, "8-11", effect="Also hits an adjacent part. Double damage vs a Shocked part.",
             rule={"arc_adjacent": True, "mult_if_target_status": {"status": "shock", "mult": 2}}),
        card("Overload", 4, 2, "5-7", [S("shock", 2)]),
    ],
    "Siege Mortar": [
        card("Barrage", 5, 3, "10-13", effect="Hits random parts.", rule={"random_part_hits": True, "volley": True}),
        card("Zero In", 4, 1, "16-20", [S("disabled", 2, "self")]),
    ],
    "Twin-Linked Autocannon": [
        card("Twin Burst", 3, 4, "5-8", effect="Later hits may miss.", rule={"hit_chance": [1, 1, 0.7, 0.4]}),
        card("Suppress", 2, 2, "4-6", [S("smoke", 2)]),
    ],
    "Grav Anchor": [
        card("Pin", 3, 1, "10-13", [S("freeze", 1)]),
        card("Crush", 4, 1, "24-30", effect="Double damage vs Frozen.", rule={"mult_if_target_status": {"status": "freeze", "mult": 2}}),
    ],
    "Thermal Spike Rifle": [
        card("Overheat Round", 4, 1, "14-18", effect="Enemy gains 3 Heat.", rule={"heat_to_target": 3}),
        card("Cool Shot", -3, 1, "5-7", effect="Vent 3.", rule={"vents": True}),
    ],
    "Flechette Launcher": [
        card("Flechettes", 3, 6, "2-3", [S("acid", 2)], rule={"volley": True}),
        card("Pin Down", 2, 1, "6-8", [S("jam", 2)]),
    ],
    "Demolition Hammer": [
        card("Wreck", 5, 1, "34-42", [S("disabled", 2, "self")], "Pierce.", {"pierce": True}),
        card("Topple", 5, 1, "12-16", [S("disabled", 2)]),
    ],
    "Lockdown Cannon": [
        card("Lockdown", 4, 1, "10-14", [S("freeze", 2)]),
        card("Heavy Round", 3, 1, "21-27", effect="The target mech gains Deflect 3.", rule={"gift_status": {"status": "deflect", "stacks": 3}}),
    ],
    # ---- Prototype ----
    "Ricochet Pistols": [
        card("Ricochet", 2, 3, "6-8", effect="Hits random parts.", rule={"random_part_hits": True}),
        card("Trick Shot", 3, 3, "7-10", effect="+1 hit per different status on the target.", rule={"hits_per_target_status": True}),
    ],
    "Tesla Coil Tower": [
        card("Chain Lightning", 3, 1, "8-11", [S("shock", 2)], "Also hits an adjacent part.", {"arc_adjacent": True}),
        card("Ground Out", 0, 0, "", effect="Remove Shock and Acid from your parts.", rule={"cleanse": ["shock", "acid"], "play_mode": "self"}),
    ],
    "Parasite Leech": [
        card("Latch", 2, 1, "9-12", effect="Repeats on the same part your next 3 turns. Reclaim 50%. Can't target hardpoints.",
             rule={"repeat_turns": 3, "heal_on_hit": 0.5, "no_hardpoints": True}),
    ],
    "Plasma Rapier": [
        card("Flurry", 3, 5, "6-8", [S("burn", 2, "self")]),
        card("Lunge", 3, 1, "14-18", effect="+2 damage per Heat you have.", rule={"bonus_per_heat": {"per": 1, "bonus": 2}}),
    ],
    "Nova Cannon": [
        card("Nova", 7, 1, "48-60", effect="Hits all enemies. This part takes 12.", rule={"hits_all_enemies": True, "recoil": 12}),
    ],
    "Swarm Hive": [
        card("Release Swarm", 3, 3, "5-7", effect="Hits random parts. Repeats your next 2 turns.",
             rule={"random_part_hits": True, "repeat_turns": 2, "volley": True}),
        card("Sting", 1, 3, "3-5", [S("acid", 1)]),
    ],
    "Resonance Blade": [
        card("Resonate", 1, 1, "10-13", [S("jam", 1, "self")], "+4 damage per Resonate played this fight.", {"stacking_damage": 4}),
    ],
    "Colossus Fist": [
        card("Titan Punch", 5, 1, "50-62", [S("disabled", 2, "self")]),
        card("Earthshaker", 6, 1, "20-26", [S("disabled", 1, "allEnemies")], "Hits all enemies.", {"hits_all_enemies": True}),
    ],
    "Cataclysm Mortar": [
        card("Cataclysm", 8, 4, "14-18", effect="Hits all enemies, random parts.",
             rule={"hits_all_enemies": True, "random_part_hits": True, "volley": True}),
        card("Ranging Shot", 2, 1, "6-8", [S("acid", 2)]),
    ],
}

# Every hardpoint has 3 cards (Logan, 2026-10-13: "i want those to have 3
# before we move on"). Added to the Salvaged and Prototype hardpoints, kept
# after their existing cards; reworking those waits for batches 3-4.
ADDED = {
    # Salvaged: up to two clauses.
    "Cluster Rockets": [card("Smoke Rockets", 3, 4, "2-4", [S("smoke", 2)], rule={"volley": True})],
    "FireStorm": [card("Fan the Flames", 3, 2, "6-8", effect="+5 damage per hit vs a Burning part.",
                       rule={"bonus_if_target_status": {"status": "burn", "flat": 5}})],
    "Hell Dropper": [card("Drop Zone", 4, 1, "14-18", effect="Double damage vs a Burning part.",
                          rule={"mult_if_target_status": {"status": "burn", "mult": 2}})],
    "Impact Hammer": [card("Wind Up", 2, 0, "", effect="Your next attack: +50% damage.",
                           rule={"protocol": "lock_on", "mult": [1.5, 1.5]})],
    "Scatter Shot": [card("Pick Off", 1, 1, "5-8", effect="Double damage vs a part at half HP or less.",
                          rule={"mult_if_target_below": {"fraction": 0.5, "mult": 2}})],
    "Arc Thrower": [card("Ground Arc", 2, 1, "6-9", effect="Also hits an adjacent part. Vs a part attacking this turn: Shock 2.",
                         rule={"arc_adjacent": True, "vs_attacking": {"status": "shock", "stacks": 2}})],
    "Siege Mortar": [card("Creeping Fire", 4, 2, "8-10", effect="Hits random parts. Repeats your next turn.",
                          rule={"random_part_hits": True, "repeat_turns": 1, "volley": True})],
    "Twin-Linked Autocannon": [card("Pin Fire", 2, 3, "3-5", effect="Vs a part attacking this turn: Jam 2.",
                                    rule={"vs_attacking": {"status": "jam", "stacks": 2}})],
    "Grav Anchor": [card("Drag Down", 3, 1, "10-13", effect="Vs a Frozen part: Disabled 2.",
                         rule={"status_if_target_status": {"if": "freeze", "status": "disabled", "stacks": 2}})],
    "Thermal Spike Rifle": [card("Cold Snap", 3, 1, "8-11", [S("freeze", 1)])],
    "Flechette Launcher": [card("Flay", 3, 2, "5-7", effect="+4 damage per hit vs a part with Acid.",
                                rule={"bonus_if_target_status": {"status": "acid", "flat": 4}})],
    "Demolition Hammer": [card("Collapse", 4, 1, "14-18", [S("disabled", 1, "self")], "Also hits an adjacent part.",
                               {"arc_adjacent": True})],
    "Lockdown Cannon": [card("Containment", 3, 1, "8-10", effect="Vs a part attacking this turn: Freeze 1.",
                             rule={"vs_attacking": {"status": "freeze", "stacks": 1}})],
    # Prototype: combos and intent-reading with a twist.
    "Ricochet Pistols": [card("Bank Shot", 3, 2, "6-8", effect="Also hits an adjacent part. Vs a part attacking this turn: Shock 1.",
                              rule={"arc_adjacent": True, "vs_attacking": {"status": "shock", "stacks": 1}})],
    "Tesla Coil Tower": [card("Overcharge Field", 3, 0, "", effect="Until your next turn: every enemy part that hits you gets Shock 2.",
                              rule={**SELF, "guard": {"type": "static_field", "status": "shock", "stacks": 2}})],
    "Plasma Rapier": [card("Riposte", 2, 0, "", effect="Until your next turn: the next hit on your mech is canceled, and its attacker takes 14.",
                           rule={**SELF, "guard": {"type": "parry", "damage": 14}})],
    "Swarm Hive": [card("Infest", 2, 1, "4-6", effect="Vs a part with Acid: Disabled 1.",
                        rule={"status_if_target_status": {"if": "acid", "status": "disabled", "stacks": 1}})],
    "Colossus Fist": [card("Guard Break", 4, 1, "18-24",
                           effect="First removes all Deflect and Absorb from the target mech. Double damage vs a part attacking this turn.",
                           rule={"strip_shields": True, "vs_attacking": {"mult": 2}})],
    "Cataclysm Mortar": [card("Spotting Round", 1, 1, "4-6", effect="Vs a part attacking this turn: Acid 2.",
                              rule={"vs_attacking": {"status": "acid", "stacks": 2}})],
    "Parasite Leech": [card("Feed", 1, 1, "5-7", effect="Reclaim 100%.", rule={"heal_on_hit": 1.0}),
                       card("Burrow", 3, 1, "8-10", [S("acid", 2)], "Repeats on the same part your next turn.", {"repeat_turns": 1})],
    "Nova Cannon": [card("Focused Nova", 5, 1, "30-38", effect="This part takes 6.", rule={"recoil": 6}),
                    card("Core Purge", -4, 0, "", [S("disabled", 1, "self")], "Vent 4.", {"vents": True})],
    "Resonance Blade": [card("Shatter Note", 3, 1, "6-9", effect="Vs a part attacking this turn: Disabled 1.",
                             rule={"vs_attacking": {"status": "disabled", "stacks": 1}}),
                        card("Resonant Ward", 2, 0, "", [S("deflect", 3, "ownMech")], "Deflect 7 instead if a heavy attack is coming.",
                             {"if_heavy_incoming": {"status": "deflect", "stacks": 4}})],
}

def proto(name, effect, rule, statuses=()):
    return card(name, "", 0, "", statuses, effect, rule)


def grant(rule, on="attack"):
    """A protocol that gives the next card these rule keys for one play."""
    return {"protocol": "grant", "on": on, "grant": rule}


# Batch 2: every protocol, Surplus, Salvaged and Prototype (Logan,
# 2026-10-13). Protocols change how the next card plays (Phase 2, Decided):
# the damage-only ones are reworked, each gets a second card. Protocol cards
# stay free; the few non-protocol cards cost Heat.
BATCH2 = {
    # ---- Surplus ----
    "Echo Buffer": [
        proto("Replay", "Play the last card you used this turn again, for +2 Heat.", {"protocol": "replay", "extra_heat": 2}),
        proto("Echo", "Take the protocol an enemy has waiting: it's primed for you instead.", {"protocol": "steal"}),
    ],
    "Targeting Computer": [
        proto("Lock On", "Your next attack: double damage vs a part attacking this turn.", grant({"vs_attacking": {"mult": 2}})),
        proto("Zero Lock", "Your next attack can't be covered, redirected, dodged or parried, and every hit lands.", grant({"sure_hit": True})),
    ],
    "Munitions Splitter": [
        proto("Split Feed", "Your next card gets double the hits at half the damage per hit.", {"protocol": "split_feed"}),
        proto("Ricochet Feed", "Your next attack also hits an adjacent part.", grant({"arc_adjacent": True})),
    ],
    "Catalyst Injector": [
        proto("Catalyze", "Your next card applies +2 stacks of every status it already applies.", {"protocol": "catalyze", "stacks": 2}),
        proto("Purify", "Your next card that targets your own mech also removes Shock, Acid and Burn from your parts.",
              grant({"cleanse": ["shock", "acid", "burn"]}, on="self")),
    ],
    "Payload Converter": [
        proto("Reroute", "Swap the status on your next card for a different one (e.g. Burn into Shock).", {"protocol": "reroute"}),
        proto("Detonate", "Your next attack consumes the target's Burn: +4 damage per stack.",
              grant({"consume_status": {"status": "burn", "per_stack": 4}})),
    ],
    "Queue Processor": [
        proto("Standby", "Set a card aside; it plays automatically at the start of your next turn for 0 Heat.", {"protocol": "standby"}),
        proto("Batch", "Your next card costs 0 Heat now; you pay its Heat at the start of your next turn.", {"protocol": "defer_heat"}),
    ],
    "Overdrive Chip": [
        proto("Overdrive", "Your next attack also hits every other hardpoint of the target mech, then the part that played it is Disabled.",
              {"protocol": "overdrive"}),
        proto("Overclock", "Your next card costs 2 less Heat. Burn 1 on this part.", {"protocol": "discount", "amount": 2},
              [S("burn", 1, "self")]),
    ],
    "Fire Control Relay": [
        proto("Salvo", "Every hardpoint this protocol reaches fires its cheapest card at once.", {"protocol": "salvo", "play_mode": "attack"}),
        proto("Target Call", "Your next attack: vs a part attacking this turn, Disabled 1.",
              grant({"vs_attacking": {"status": "disabled", "stacks": 1}})),
    ],
    "Thermal Transfer Bus": [
        proto("Bleed Off", "Pay your next card's Heat cost with HP from the linked component instead.", {"protocol": "bleed_off"}),
        proto("Heat Transfer", "Your next attack moves 3 of your Heat onto the target mech.", grant({"heat_to_target": 3, "transfer": True})),
    ],
    "Signal Interceptor": [
        proto("Intercept", "Copy the enemy's telegraphed attack as a one-use card, damage range included.",
              {"protocol": "intercept", "play_mode": "attack"}),
        proto("Scramble Signal", "Clear every protocol the enemies have waiting.", {"protocol": "clear_enemy"}),
    ],
    "Quickload Chip": [
        proto("Quickload", "Next card costs 3 less Heat. Smoke 1 on your mech.", {"protocol": "discount", "amount": 3},
              [S("smoke", 1, "ownMech")]),
        card("Borrow Time", -2, 0, "", effect="Vent 2. Your next card costs 1 more Heat.", rule={"protocol": "discount", "amount": -1}),
    ],
    "Scatter Link": [
        proto("Fan Out", "Next attack also hits every other enemy.", {"protocol": "fan_out"}),
        card("Ghost Signal", 2, 0, "", effect="Until your next turn: enemy attacks hit random parts of yours.",
             rule={**SELF, "guard": {"type": "scatter"}}),
    ],
    "Siphon Driver": [
        proto("Siphon", "Next attack: Reclaim 50%.", {"protocol": "siphon", "fraction": 0.5}),
        proto("Leech Field", "Your next attack takes the target mech's Deflect and Absorb for your mech.", grant({"steal_shields": True})),
    ],
    "Breach Charge": [
        proto("Breach", "Next attack: Pierce.", {"protocol": "pierce"}),
        proto("Crack Open", "Your next attack also applies Acid 2.", grant({"on_hit_status": {"status": "acid", "stacks": 2}})),
    ],
    "Chain Relay": [
        proto("Chain", "Your next card's statuses also land on every part adjacent to its target.", grant({"spread_status": True}, on="status")),
        card("Backlash Link", 2, 0, "", effect="Until your next turn: every enemy part that hits you gets Jam 1.",
             rule={**SELF, "guard": {"type": "static_field", "status": "jam", "stacks": 1}}),
    ],
    "Hydraulic Ram": [
        proto("Ram", "Next attack also applies Disabled 1; the part that plays it is Disabled 1.",
              grant({"on_hit_status": {"status": "disabled", "stacks": 1}, "self_disable": True})),
        proto("Push Back", "Your next attack: vs a part attacking this turn, its attacks this turn hit its own mech.",
              grant({"vs_attacking": {"turn": True}})),
    ],
    "Ballast Tank": [
        proto("Ballast", "Next card costs 4 less Heat. Smoke 2 on your mech.", {"protocol": "discount", "amount": 4},
              [S("smoke", 2, "ownMech")]),
        card("Ballast Brace", 2, 0, "", [S("deflect", 6, "ownMech"), S("smoke", 1, "ownMech")]),
    ],
    # ---- Salvaged ----
    "Tactical Uplink": [
        proto("Double Tap", "Your next attack also hits the enemy part with the biggest attack shown this turn.",
              grant({"hits_top_attacker": True})),
        proto("Overlay", "Your next attack can't be covered, dodged or parried. Vs a part attacking this turn: Shock 2.",
              grant({"sure_hit": True, "vs_attacking": {"status": "shock", "stacks": 2}})),
    ],
    "Kill Switch": [
        proto("Execute", "Next attack: triple damage vs a part at or below half HP.", {"protocol": "execute", "fraction": 0.5, "mult": 3}),
        proto("Kill Order", "Your next attack: if it destroys a part, Vent 5.", grant({"vent_on_kill": 5})),
    ],
    "Coordinated Strike Suite": [
        proto("Coordinated Strike", "Linked hardpoints fire their cheapest card.", {"protocol": "salvo"}),
        card("Hold the Line", 3, 0, "", effect="Until your next turn: no hit deals more than 12 to one of your parts.",
             rule={**SELF, "guard": {"type": "cap", "cap": 12}}),
    ],
    "Rampart Protocol": [
        proto("Fortify", "Next card: gain Deflect 4 per Heat it costs.", {"protocol": "fortify", "per_heat": 4}),
        proto("Rampart", "Your next shield card also bites back: until your next turn, every enemy part that hits you takes 4.",
              grant({"guard": {"type": "thorns", "damage": 4}}, on="shield")),
    ],
    # ---- Prototype ----
    "Probability Engine": [
        proto("Loaded Dice", "Next attack never misses and rolls max damage; the attack after it rolls min damage.", {"protocol": "max_roll"}),
        proto("Long Odds", "Your next attack: x4 damage vs a part at a quarter HP or less.",
              grant({"mult_if_target_below": {"fraction": 0.25, "mult": 4}})),
    ],
    "Salvage Recursor": [
        proto("Recall", "Next card plays again next turn for 0 Heat.", {"protocol": "recall"}),
        proto("Scavenge", "Your next attack: if it destroys a part, heal your most damaged part 15.", grant({"heal_on_kill": 15})),
    ],
    "Feedback Loop": [
        proto("Feedback", "Next attack: Vent 2 per hit.", {"protocol": "vent_on_hit", "amount": 2}),
        card("Feedback Field", 2, 0, "", effect="Until your next turn: every enemy attack that hits you gives its mech 2 Heat.",
             rule={**SELF, "guard": {"type": "heat_back", "amount": 2}}),
    ],
    "Polarity Inverter": [
        proto("Invert", "Next attack: swap Heat with the target mech.", {"protocol": "invert"}),
        proto("Reverse Polarity", "Your next attack swaps the statuses of the part that fires it and its target.", grant({"swap_statuses": True})),
    ],
    "Last Stand Protocol": [
        proto("Last Stand", "Your next card costs 0 Heat while your mech is at half HP or less.",
              {"protocol": "discount", "amount": 99, "if_below": 0.5}),
        card("Final Order", 4, 0, "", effect="Until your next turn: your parts can't drop below 1 HP.",
             rule={**SELF, "guard": {"type": "floor"}}),
    ],
}

# Reactor passives rewritten (Logan, 2026-10-13). Redirect Spike: covers its
# own mech or an ally. Coolant Loop and Overpressure Valve: their heat decay
# did nothing under heat.full_reset.
PASSIVES = {
    "Redirect Spike": passive("Redirect Spike",
        "Whenever another component on this mech would take damage, redirect that damage to this component instead. "
        "In a squad, it covers whichever mech on its side is most hurt: itself or an ally.",
        {"type": "redirect"}),
    "Coolant Loop": passive("Coolant Loop", "Turn start: Coolant 1 on a random hardpoint of yours.",
        {"type": "turn_start_coolant", "stacks": 1}),
    "Overpressure Valve": passive("Overpressure Valve", "+2 Max Heat while installed. Overheat backlash +25%.",
        {"type": "heat_mods", "max_heat": 2, "backlash_mult": 1.25}),
}

ALL = {**BATCH1, **BATCH2, **BATCH34, **PASSIVES}
ALL = {k: (v if isinstance(v, list) else [v]) for k, v in ALL.items()}


def note_for(name):
    return ("Card pass batch 1" if name in BATCH1 else "Card pass batch 2" if name in BATCH2
            else "Card pass batch 3-4" if name in BATCH34 or name in ADDED else "")


def uid():
    return "".join(random.choice("abcdefghijklmnopqrstuvwxyz0123456789") for _ in range(10))


def plain(name):
    return name[4:] if name.startswith("(C) ") else name


def refit_card(c, old=None):
    old = old or {}
    out = {"id": old.get("id", uid()), "name": c["name"], "heatCost": str(c["heat"]), "hits": str(c["hits"]), "damage": c["dmg"],
           "statuses": [], "effects": []}
    for i, s in enumerate(c["statuses"]):
        prev = old.get("statuses", [])
        out["statuses"].append({"id": prev[i]["id"] if i < len(prev) else uid(), "status": s[0], "stacks": str(s[1]), "target": s[2]})
    if c["effect"]:
        prev = old.get("effects", [])
        out["effects"].append({"id": prev[0]["id"] if prev else uid(), "text": c["effect"]})
    return out


def patch_refit(doc):
    seen = set()
    for it in doc["items"]:
        cards = ALL.get(plain(it["name"]))
        if cards is None:
            continue
        seen.add(plain(it["name"]))
        old = it["cards"]
        cards = cards + ADDED.get(plain(it["name"]), [])
        it["cards"] = [refit_card(c, old[i] if i < len(old) else None) for i, c in enumerate(cards)]
        tag = note_for(plain(it["name"]))
        if tag and tag not in it.get("notes", ""):
            it["notes"] = (it.get("notes", "") + " " + tag + " (Claude's draft, 2026-10-13).").strip()
    for it in doc["items"]:
        for c in ADDED.get(plain(it["name"]), []):
            seen.add(plain(it["name"]))
            if c["name"] not in [k["name"] for k in it["cards"]]:
                it["cards"].append(refit_card(c))
    missing = (set(ALL) | set(ADDED)) - seen
    assert not missing, missing
    return doc


def game_card(c):
    return {"id": snake(c["name"]), "name": c["name"], "heat_cost": str(c["heat"]), "hits": str(c["hits"]), "damage": c["dmg"],
            "statuses": [{"status": s[0], "stacks": str(s[1]), "target": s[2]} for s in c["statuses"]], "effect_text": c["effect"]}


def patch_components():
    path = ROOT / "data" / "components.json"
    data = json.loads(path.read_text())
    removed = []
    for comp in data["components"]:
        cards = ALL.get(comp["name"])
        if cards is None:
            continue
        new = [game_card(c) for c in cards + ADDED.get(comp["name"], [])]
        removed += [k["id"] for k in comp["cards"] if k["id"] not in {n["id"] for n in new}]
        comp["cards"] = new
        tag = note_for(comp["name"])
        if tag and tag not in comp["notes"]:
            comp["notes"] = (comp["notes"] + " " + tag + " (Claude's draft, 2026-10-13).").strip()
    for comp in data["components"]:
        for c in ADDED.get(comp["name"], []):
            if snake(c["name"]) not in [k["id"] for k in comp["cards"]]:
                comp["cards"].append(game_card(c))
    path.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n")
    return removed


def patch_rules(removed=()):
    path = ROOT / "data" / "component_rules.json"
    rules = json.loads(path.read_text())
    for cid in removed:
        rules["cards"].pop(cid, None)
    for name, cards in list(ALL.items()) + list(ADDED.items()):
        for c in cards:
            if "passive" in c:
                rules["passives"][snake(name)] = c["passive"]
            elif c["rule"]:
                rules["cards"][snake(c["name"])] = c["rule"]
            else:
                rules["cards"].pop(snake(c["name"]), None)
    path.write_text(json.dumps(rules, indent=1, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    random.seed(20261013)
    if sys.argv[1] == "refit":
        doc = patch_refit(json.loads(Path(sys.argv[2]).read_text()))
        Path(sys.argv[3]).write_text(json.dumps(doc, indent=1, ensure_ascii=False))
        print("refit doc patched")
    elif sys.argv[1] == "components":
        removed = patch_components()
        patch_rules(removed)
        print("components and rules patched; removed cards:", removed)

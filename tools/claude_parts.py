#!/usr/bin/env python3
"""Claude's 70 drafted components (Logan, 2026-09-28: "10 more surplus for
each type (light medium heavy), 5 salvaged for each type including general,
and 5 prototype for each type including general ... don't be afraid to get
wacky"). Every name starts with "(C) " in Refit Bay so they're easy to tell
apart; the game shows the name without it.

This file is the design source for two things:
  - the Refit Bay items (pushed into the Refit Bay document), and
  - their mechanics in data/component_rules.json (merge_rules()).
Once they're in Refit Bay, Refit Bay is the source of truth for names and
numbers like every other part; this file keeps the rules side in step.

Usage: python3 tools/claude_parts.py items <out.json>   (Refit Bay items, fresh ids)
       python3 tools/claude_parts.py sync <refit_bay.json> <out.json>
                                    (the doc with the "(C) " items updated in place, ids kept)
       python3 tools/claude_parts.py rules              (merge into component_rules.json)
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


def shape(s):
    """'##/.#' -> [[0,0],[0,1],[1,1]]"""
    return [[r, c] for r, row in enumerate(s.split("/")) for c, ch in enumerate(row) if ch == "#"]


def card(name, heat, hits, dmg, statuses=(), effect="", rule=None):
    return {"name": name, "heat": heat, "hits": hits, "dmg": dmg, "statuses": list(statuses), "effect": effect, "rule": rule or {}}


def passive(name, effect, rule, statuses=()):
    return {"name": name, "heat": 0, "hits": 0, "dmg": "", "statuses": list(statuses), "effect": effect, "passive": rule}


def protocol(name, effect, rule):
    return {"name": name, "heat": "", "hits": 0, "dmg": "", "statuses": [], "effect": effect, "rule": rule}


def part(name, cat, cls, rar, hp, cells, cards, link=None, notes=""):
    return {"name": name, "category": cat, "class": cls, "rarity": rar, "hp": hp, "cells": shape(cells),
            "cards": cards, "link": link or {"dir": "none", "dirs": [], "reach": "adjacent"}, "notes": notes}


def link(*dirs, reach="adjacent"):
    dirs = list(dirs)
    return {"dir": dirs[0] if len(dirs) == 1 else "multi", "dirs": dirs, "reach": reach}


S = lambda status, stacks, target="enemy": (status, stacks, target)
HP, RE, PR = "hardpoint", "reactor", "protocol"

PARTS = [
    # Strength targets (Logan, 2026-09-29): Surplus on par with Refit Bay's own
    # Surplus (~6 damage per Heat plus ~2, ~12.5 HP per cell). Salvaged 25-35%
    # stronger than Surplus (~1.3x: ~8 per Heat, ~16 HP per cell); Prototype
    # 50-65% stronger than Surplus (~1.575x: ~9.5 per Heat, ~19.5 HP per cell).
    # The player should usually want to trade up a rarity unless what they
    # have already synergizes.
    #
    # Text (Logan, 2026-09-29): short, Slay-the-Spire-like, icon-ready. The
    # target is implied ("Burn 1", not "Burns the enemy mech"); keywords
    # (Vent, Pierce, Lifesteal) are explained by the hover glossary.

    # ---------------- Surplus · Light ----------------
    part("Needle Carbine", HP, "light", "surplus", 38, "###", [
        card("Prick", 1, 1, "5-7"),
        card("Needle Storm", 3, 5, "4-6", effect="Hits after the 2nd may miss.", rule={"hit_chance": [1, 1, 0.8, 0.6, 0.5]})]),
    part("Flash Pistol", HP, "light", "surplus", 36, ".#/##", [
        card("Flashbang", 2, 1, "8-11", [S("smoke", 2)]),
        card("Quick Draw", 0, 1, "4-6", effect="First card this turn: double damage.", rule={"double_if_first": True})]),
    part("Heat Lance", HP, "light", "surplus", 50, "#/#/#/#", [
        card("Searing Line", 3, 1, "12-16", effect="+1 damage per 2 Heat you have.", rule={"bonus_per_heat": {"per": 2, "bonus": 1}}),
        card("Redline Burst", 5, 1, "22-28", effect="+50% damage while over max Heat.", rule={"mult_if_over_max": 1.5})],
        notes="Built for Redline's end-of-turn check: go over max, fire, vent before the turn ends."),
    part("Coil Whip", HP, "light", "surplus", 48, "#./##/.#", [
        card("Crackle", 2, 2, "4-6", [S("shock", 1)]),
        card("Discharge", 3, 1, "8-11", effect="Consume the target's Shock: +5 damage per stack.", rule={"consume_status": {"status": "shock", "per_stack": 5}})]),
    part("Vent Cannon", HP, "light", "surplus", 38, "#/#/#", [
        card("Blow-Off", -2, 1, "7-10", effect="Vent 2.", rule={"vents": True}),
        card("Steam Slug", 3, 1, "14-18", effect="Enemy gains 2 Heat.", rule={"heat_to_target": 2})]),
    part("Afterburner", RE, "light", "surplus", 26, "##", [
        passive("Afterburner", "First attack each turn: +50% damage.", {"type": "first_attack_bonus", "mult": 1.5})]),
    part("Blowout Vent", RE, "light", "surplus", 24, "#/#", [
        passive("Blowout Vent", "Destroy a part: Vent 4.", {"type": "kill_vent", "amount": 4})]),
    part("Static Collector", RE, "light", "surplus", 32, ".#/##", [
        passive("Static Collector", "Attacks have a 50% chance to Shock 1.", {"type": "status_on_attack", "status": "shock", "stacks": 1, "chance": 0.5})]),
    part("Quickload Chip", PR, "light", "surplus", 24, "##", [
        protocol("Quickload", "Next card costs 3 less Heat.", {"protocol": "discount", "amount": 3})]),
    part("Scatter Link", PR, "light", "surplus", 24, "#/#", [
        protocol("Fan Out", "Next attack also hits every other enemy.", {"protocol": "fan_out"})]),

    # ---------------- Surplus · Medium ----------------
    part("Arc Thrower", HP, "medium", "surplus", 50, "##/##", [
        card("Arc", 3, 1, "11-15", effect="Also hits an adjacent part.", rule={"arc_adjacent": True}),
        card("Overload", 4, 2, "8-11", [S("shock", 2)])]),
    part("Buzzsaw Arm", HP, "medium", "surplus", 52, "###/.#.", [
        card("Grind", 2, 3, "4-5"),
        card("Shred", 3, 2, "7-10", [S("acid", 2)])]),
    part("Mortar Pod", HP, "medium", "surplus", 40, "#./##", [
        card("Lob", 3, 2, "8-11", effect="Hits random parts.", rule={"random_part_hits": True}),
        card("Smoke Shell", 1, 0, "", [S("smoke", 3)])]),
    part("Hook Lance", HP, "medium", "surplus", 50, "#../###", [
        card("Harpoon", 3, 1, "12-16", [S("disabled", 1)]),
        card("Reel In", 2, 1, "6-9", effect="Double damage vs Disabled.", rule={"mult_if_target_status": {"status": "disabled", "mult": 2}})]),
    part("Relay Booster", RE, "medium", "surplus", 26, "##", [
        passive("Relay Booster", "Linked hardpoints: +3 damage per hit.", {"type": "linked_damage_bonus", "amount": 3})],
        link=link("right")),
    part("Spiked Plating", RE, "medium", "surplus", 38, "###", [
        passive("Spiked Plating", "When this part is hit: deal 6 to the attacker.", {"type": "thorns", "damage": 6, "scope": "self"})]),
    part("Field Medic Unit", RE, "medium", "surplus", 26, "#/#", [
        passive("Field Medic Unit", "Turn start: heal linked parts 6.", {"type": "turn_start_heal_linked", "amount": 6})],
        link=link("up")),
    part("Siphon Driver", PR, "medium", "surplus", 30, "##/#.", [
        protocol("Siphon", "Next attack: Lifesteal 50%.", {"protocol": "siphon", "fraction": 0.5})]),
    part("Breach Charge", PR, "medium", "surplus", 26, "##", [
        protocol("Breach", "Next attack: Pierce, +25% damage.", {"protocol": "pierce", "mult": 1.25})]),
    part("Chain Relay", PR, "medium", "surplus", 30, ".#/#./.#", [
        protocol("Chain", "Next attack also hits an adjacent part.", {"protocol": "chain"})]),

    # ---------------- Surplus · Heavy ----------------
    part("Pile Driver", HP, "heavy", "surplus", 56, "#/#/#/#", [
        card("Drive", 4, 1, "22-28"),
        card("Aftershock", 6, 1, "28-36", [S("disabled", 1), S("disabled", 1, "self")])]),
    part("Flak Wall", HP, "heavy", "surplus", 54, "####", [
        card("Flak", 3, 5, "3-5"),
        card("Brace", 2, 0, "", [S("deflect", 5, "ownMech")])]),
    part("Siege Mortar", HP, "heavy", "surplus", 56, "##/##", [
        card("Barrage", 5, 3, "10-13", effect="Hits random parts.", rule={"random_part_hits": True}),
        card("Zero In", 3, 1, "16-20")]),
    part("Grinder Maw", HP, "heavy", "surplus", 60, ".#./###", [
        card("Chew", 3, 2, "8-11", effect="Lifesteal 30%.", rule={"heal_on_hit": 0.3}),
        card("Maul", 5, 1, "24-30")]),
    part("Rivet Gun", HP, "heavy", "surplus", 42, "###", [
        card("Rivet", 1, 1, "6-8"),
        card("Weld Shut", 3, 1, "11-14", [S("jam", 2)])]),
    part("Bulwark Frame", RE, "heavy", "surplus", 48, "##/##", [
        passive("Bulwark Frame", "Linked parts take at most 10 per hit.", {"type": "damage_cap_linked", "cap": 10})],
        link=link("up")),
    part("Heat Sink Array", RE, "heavy", "surplus", 36, "###", [
        passive("Heat Sink Array", "When an attack damages you: Vent 3.", {"type": "on_damaged_vent", "amount": 3})]),
    part("Overheat Fuse", RE, "heavy", "surplus", 24, "##", [
        passive("Overheat Fuse", "Prevents your first overheat (Heat drops to max), then burns out.", {"type": "overheat_fuse"})],
        notes="Made for Bastion's live heat check."),
    part("Hydraulic Ram", PR, "heavy", "surplus", 32, "###", [
        protocol("Ram", "Next attack also applies Disabled 1.", {"protocol": "knockback"})]),
    part("Ballast Tank", PR, "heavy", "surplus", 30, "#./##", [
        protocol("Ballast", "Next card costs 4 less Heat.", {"protocol": "discount", "amount": 4})]),

    # ---------------- Salvaged · General ----------------
    part("Twin-Linked Autocannon", HP, "general", "salvaged", 68, "##/##", [
        card("Twin Burst", 3, 4, "5-8"),
        card("Suppress", 2, 2, "6-8", [S("smoke", 2)])]),
    part("Scrap Magnet", RE, "general", "salvaged", 48, "#.#/.#.", [
        passive("Scrap Magnet", "Destroy a part: +6 Scraps.", {"type": "scrap_on_kill", "amount": 6})]),
    part("Mirror Plating", RE, "general", "salvaged", 48, "###", [
        passive("Mirror Plating", "When your mech is hit: deal 5 to the attacker.", {"type": "thorns", "damage": 5, "scope": "mech"})]),
    part("Tactical Uplink", PR, "general", "salvaged", 30, "##", [
        protocol("Double Tap", "Next attack: double the hits.", {"protocol": "double_hits"})]),
    part("Grav Anchor", HP, "general", "salvaged", 68, ".#./###", [
        card("Pin", 3, 1, "17-21", [S("freeze", 1)]),
        card("Crush", 4, 1, "24-30", effect="Double damage vs Frozen.", rule={"mult_if_target_status": {"status": "freeze", "mult": 2}})]),

    # ---------------- Salvaged · Light ----------------
    part("Afterimage Emitter", RE, "light", "salvaged", 32, "#/#", [
        passive("Afterimage Emitter", "Turn start:", {"type": "turn_start_status"}, [S("deflect", 7, "ownMech")])]),
    part("Thermal Spike Rifle", HP, "light", "salvaged", 48, "###", [
        card("Overheat Round", 4, 1, "28-34", effect="Enemy gains 3 Heat.", rule={"heat_to_target": 3}),
        card("Cool Shot", -3, 1, "10-13", effect="Vent 3.", rule={"vents": True})]),
    part("Ricochet Pistols", HP, "light", "salvaged", 48, "#.#/.#.", [
        card("Ricochet", 2, 3, "6-8", effect="Hits random parts.", rule={"random_part_hits": True}),
        card("Trick Shot", 3, 3, "7-10", effect="+1 hit per different status on the target.", rule={"hits_per_target_status": True})]),
    part("Pressure Regulator", RE, "light", "salvaged", 46, ".#/##", [
        passive("Pressure Regulator", "+5 Max Heat. Overheating hurts 25% more.", {"type": "heat_mods", "max_heat": 5, "backlash_mult": 1.25})]),
    part("Kill Switch", PR, "light", "salvaged", 30, "##", [
        protocol("Execute", "Next attack: triple damage vs a part at or below half HP.", {"protocol": "execute", "fraction": 0.5, "mult": 3})]),

    # ---------------- Salvaged · Medium ----------------
    part("Tesla Coil Tower", HP, "medium", "salvaged", 66, "#./#./##", [
        card("Chain Lightning", 3, 1, "15-19", [S("shock", 2)], effect="Also hits an adjacent part.", rule={"arc_adjacent": True}),
        card("Ground Out", 0, 0, "", effect="Remove Shock and Acid from your parts.", rule={"cleanse": ["shock", "acid"], "play_mode": "self"})]),
    part("Repair Drone Bay", RE, "medium", "salvaged", 48, "##/#.", [
        passive("Repair Drone Bay", "Turn start: heal your most damaged part 12.", {"type": "turn_start_heal_lowest", "amount": 12})]),
    part("Harmonic Amplifier", RE, "medium", "salvaged", 32, "##", [
        passive("Harmonic Amplifier", "Linked hardpoints: +4 damage per hit.", {"type": "linked_damage_bonus", "amount": 4})],
        link=link("left", "right")),
    part("Coordinated Strike Suite", PR, "medium", "salvaged", 42, ".#/##", [
        protocol("Coordinated Strike", "Linked hardpoints fire their cheapest card.", {"protocol": "salvo"})],
        link=link("up", "right", "down", "left")),
    part("Flechette Launcher", HP, "medium", "salvaged", 50, "#/##", [
        card("Flechettes", 3, 6, "3-5", [S("acid", 2)]),
        card("Pin Down", 2, 1, "11-14", [S("jam", 2)])]),

    # ---------------- Salvaged · Heavy ----------------
    part("Aegis Projector", RE, "heavy", "salvaged", 64, "##/##", [
        passive("Aegis Projector", "Turn start:", {"type": "turn_start_status"}, [S("deflect", 10, "ownMech")])]),
    part("Demolition Hammer", HP, "heavy", "salvaged", 92, "###/.#./.#.", [
        card("Wreck", 5, 1, "34-42", effect="Pierce.", rule={"pierce": True}),
        card("Topple", 4, 1, "22-28", [S("disabled", 2)])]),
    part("Lockdown Cannon", HP, "heavy", "salvaged", 74, "####", [
        card("Lockdown", 4, 1, "22-28", [S("freeze", 2)]),
        card("Heavy Round", 3, 1, "21-27")]),
    part("Reinforced Bulkhead", RE, "heavy", "salvaged", 48, "#/#/#", [
        passive("Reinforced Bulkhead", "Twice per fight, a part that would be destroyed is left at 1 HP.", {"type": "save_once_per_fight", "charges": 2})]),
    part("Rampart Protocol", PR, "heavy", "salvaged", 42, "###", [
        protocol("Fortify", "Next card: gain Deflect 4 per Heat it costs.", {"protocol": "fortify", "per_heat": 4})]),

    # ---------------- Prototype · General ----------------
    part("Singularity Core", RE, "general", "prototype", 76, "##/##", [
        passive("Singularity Core", "+8 Max Heat. −1 Heat decay.", {"type": "heat_mods", "max_heat": 8, "decay": -1})]),
    part("Probability Engine", PR, "general", "prototype", 36, "#/#", [
        protocol("Loaded Dice", "Next attack: never misses, max damage, +50% damage.", {"protocol": "max_roll", "mult": 1.5})]),
    part("Parasite Leech", HP, "general", "prototype", 62, "#./##", [
        card("Latch", 2, 1, "9-12", effect="Repeats on the same part your next 3 turns. Lifesteal 50%.", rule={"repeat_turns": 3, "heal_on_hit": 0.5})]),
    part("Salvage Recursor", PR, "general", "prototype", 52, ".#./##.", [
        protocol("Recall", "Next card plays again next turn for 0 Heat.", {"protocol": "recall"})]),
    part("Chaos Reactor", RE, "general", "prototype", 58, "#.#/.#.", [
        passive("Chaos Reactor", "Turn start: Burn 5 a random enemy part, Coolant 2 a random part of yours.", {"type": "turn_start_chaos", "burn": 5, "coolant": 2})]),

    # ---------------- Prototype · Light ----------------
    part("Blink Drive", RE, "light", "prototype", 38, "##", [
        passive("Blink Drive", "Dodge the first 2 hits each turn.", {"type": "dodge_first", "hits": 2})]),
    part("Plasma Rapier", HP, "light", "prototype", 58, "#/#/#", [
        card("Flurry", 3, 5, "6-8"),
        card("Lunge", 3, 1, "14-18", effect="+2 damage per Heat you have.", rule={"bonus_per_heat": {"per": 1, "bonus": 2}})]),
    part("Overclock Heart", RE, "light", "prototype", 56, "#/##", [
        passive("Overclock Heart", "Attacks: +1 damage per hit per 2 Heat you have.", {"type": "heat_damage_bonus", "per": 2})]),
    part("Feedback Loop", PR, "light", "prototype", 36, "##", [
        protocol("Feedback", "Next attack: Vent 2 per hit.", {"protocol": "vent_on_hit", "amount": 2})]),
    part("Nova Cannon", HP, "light", "prototype", 78, "##/##", [
        card("Nova", 7, 1, "48-60", effect="Hits all enemies. This part takes 6.", rule={"hits_all_enemies": True, "recoil": 6})]),

    # ---------------- Prototype · Medium ----------------
    part("Swarm Hive", HP, "medium", "prototype", 80, "#.#/#.#", [
        card("Release Swarm", 3, 3, "5-7", effect="Hits random parts. Repeats your next 2 turns.", rule={"random_part_hits": True, "repeat_turns": 2}),
        card("Sting", 1, 3, "3-5", [S("acid", 1)])]),
    part("Polarity Inverter", PR, "medium", "prototype", 52, "###", [
        protocol("Invert", "Next attack: swap Heat with the target mech.", {"protocol": "invert"})]),
    part("Phase Array", RE, "medium", "prototype", 58, ".#/##", [
        passive("Phase Array", "Linked parts' cards cost 1 less Heat.", {"type": "linked_cost_down", "amount": 1})],
        link=link("up", "right", "down", "left")),
    part("Resonance Blade", HP, "medium", "prototype", 80, "#/#/#/#", [
        card("Resonate", 1, 1, "10-13", effect="+4 damage per Resonate played this fight.", rule={"stacking_damage": 4})]),
    part("Neural Link", RE, "medium", "prototype", 38, "#/#", [
        passive("Neural Link", "Destroy a part: your next card this turn is free.", {"type": "on_kill_refund"})]),

    # ---------------- Prototype · Heavy ----------------
    part("Colossus Fist", HP, "heavy", "prototype", 112, "##/##/.#", [
        card("Titan Punch", 5, 1, "50-62"),
        card("Earthshaker", 6, 1, "20-26", [S("disabled", 1, "allEnemies")], effect="Hits all enemies.", rule={"hits_all_enemies": True})]),
    part("Fortress Core", RE, "heavy", "prototype", 78, "##/##", [
        passive("Fortress Core", "Turn start: gain Deflect 5 per living reactor.", {"type": "fortress", "per": 5})]),
    part("Juggernaut Treads", RE, "heavy", "prototype", 60, "###", [
        passive("Juggernaut Treads", "Each attack in a turn: +3 damage per hit over the last.", {"type": "momentum", "amount": 3})]),
    part("Last Stand Protocol", PR, "heavy", "prototype", 52, "###", [
        protocol("Last Stand", "Next attack: +20% damage per 10% HP lost.", {"protocol": "last_stand", "per_tenth": 0.2})]),
    part("Cataclysm Mortar", HP, "heavy", "prototype", 88, "##/##", [
        card("Cataclysm", 8, 4, "14-18", effect="Hits all enemies, random parts.", rule={"hits_all_enemies": True, "random_part_hits": True}),
        card("Ranging Shot", 2, 1, "14-18", [S("acid", 2)])]),
]


def uid():
    return "id_" + "".join(random.choice("abcdefghijklmnopqrstuvwxyz0123456789") for _ in range(14))


def refit_items():
    out = []
    for p in PARTS:
        cards = []
        for c in p["cards"]:
            cards.append({
                "id": uid(), "name": c["name"], "heatCost": str(c["heat"]), "hits": str(c["hits"]),
                "damage": c["dmg"],
                "statuses": [{"id": uid(), "status": s[0], "stacks": str(s[1]), "target": s[2]} for s in c["statuses"]],
                "effects": [{"id": uid(), "text": c["effect"]}] if c["effect"] else [],
            })
        out.append({"id": uid(), "name": "(C) " + p["name"], "category": p["category"], "weightClass": p["class"],
                    "rarity": p["rarity"], "hp": str(p["hp"]), "cells": p["cells"], "link": p["link"],
                    "notes": ("Claude's draft (2026-09-28). " + p["notes"]).strip(), "cards": cards})
    return out


def sync_items(doc):
    """The Refit Bay document with every "(C) " item rewritten from PARTS,
    keeping the ids of the item, its cards, statuses and effects (by
    position) so the edit reads as an update, not a replacement."""
    fresh = {it["name"]: it for it in refit_items()}
    for i, it in enumerate(doc["items"]):
        new = fresh.pop(it["name"], None)
        if new is None:
            continue
        new["id"] = it["id"]
        for nc, oc in zip(new["cards"], it["cards"]):
            nc["id"] = oc["id"]
            for key in ("statuses", "effects"):
                for n, o in zip(nc[key], oc[key]):
                    n["id"] = o["id"]
        doc["items"][i] = new
    doc["items"].extend(fresh.values())
    return doc


def merge_rules():
    path = ROOT / "data" / "component_rules.json"
    rules = json.loads(path.read_text())
    for p in PARTS:
        pid = snake(p["name"])
        for c in p["cards"]:
            if "passive" in c:
                rules["passives"][pid] = c["passive"]
            elif c.get("rule"):
                rules["cards"][snake(c["name"])] = c["rule"]
            else:
                rules["cards"].pop(snake(c["name"]), None) # a card that lost its rule
    path.write_text(json.dumps(rules, indent=1, ensure_ascii=False) + "\n")


def check():
    comps = json.loads((ROOT / "data" / "components.json").read_text())["components"]
    existing_parts = {c["id"] for c in comps if not c.get("claude_draft")}
    existing_cards = {k["id"] for c in comps if not c.get("claude_draft") for k in c["cards"]}
    seen_parts, seen_cards = set(), set()
    counts = {}
    for p in PARTS:
        pid = snake(p["name"])
        assert pid not in existing_parts and pid not in seen_parts, pid
        seen_parts.add(pid)
        counts[(p["rarity"], p["class"])] = counts.get((p["rarity"], p["class"]), 0) + 1
        for c in p["cards"]:
            cid = snake(c["name"])
            if "passive" in c:
                continue
            assert cid not in existing_cards and cid not in seen_cards, cid
            seen_cards.add(cid)
    return counts


if __name__ == "__main__":
    random.seed(20260928)
    if sys.argv[1] == "items":
        Path(sys.argv[2]).write_text(json.dumps(refit_items(), indent=1, ensure_ascii=False))
        print(len(PARTS), "items")
    elif sys.argv[1] == "sync":
        doc = sync_items(json.loads(Path(sys.argv[2]).read_text()))
        Path(sys.argv[3]).write_text(json.dumps(doc, indent=1, ensure_ascii=False))
        print(len(doc["items"]), "items")
    elif sys.argv[1] == "rules":
        merge_rules()
        print("rules merged")
    elif sys.argv[1] == "check":
        print(check())

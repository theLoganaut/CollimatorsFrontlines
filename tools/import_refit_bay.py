#!/usr/bin/env python3
"""Turns a Refit Bay export (the `refit_bay` document) into data/components.json,
data/chassis.json and one data/mechs/<id>.json per enemy (the Enemies tab).

Everything is copied verbatim from Refit Bay: names, categories, rarities, HP,
shapes, links, notes, and every card's heat / hits / damage / statuses /
effect text. Nothing here decides how an effect plays; that lives in the
hand-written data/component_rules.json, keyed by the same ids.

Usage: python3 tools/import_refit_bay.py <refit_bay.json>
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def snake(name: str) -> str:
    s = re.sub(r"['’!]", "", name.lower())
    s = re.sub(r"[^a-z0-9]+", "_", s)
    return s.strip("_")


def card(c: dict) -> dict:
    return {
        "id": snake(c["name"]),
        "name": c["name"],
        "heat_cost": c["heatCost"],
        "hits": c["hits"],
        "damage": c["damage"],
        "statuses": [{"status": s["status"], "stacks": s["stacks"], "target": s["target"]} for s in c["statuses"]],
        "effect_text": " ".join(e["text"] for e in c["effects"]),
    }


def main() -> None:
    src = json.loads(Path(sys.argv[1]).read_text())
    components = []
    for it in src["items"]:
        # Claude's drafts carry "(C) " in Refit Bay; the game shows the plain name.
        draft = it["name"].startswith("(C) ")
        name = it["name"][4:] if draft else it["name"]
        components.append({
            "id": snake(name),
            "name": name,
            "claude_draft": draft,
            "category": it["category"],
            "rarity": it["rarity"],
            "weight_class": it.get("weightClass", "general"),
            "hp": int(it["hp"]),
            "cells": it["cells"],
            "link": it["link"],
            "notes": it.get("notes", ""),
            "cards": [card(c) for c in it["cards"]],
        })
    ids = [c["id"] for c in components]
    assert len(ids) == len(set(ids)), "duplicate component ids"
    (ROOT / "data" / "components.json").write_text(json.dumps(
        {"_source": "Refit Bay export, verbatim (tools/import_refit_bay.py). Mechanics: data/component_rules.json.",
         "components": components}, indent=1, ensure_ascii=False) + "\n")

    chassis = [{
        "id": snake(m["name"]), "name": m["name"], "weight_class": m["weightClass"],
        "max_heat": int(m["maxHeat"]), "cells": m["cells"],
    } for m in src["mechs"]]
    (ROOT / "data" / "chassis.json").write_text(json.dumps(
        {"_source": "Refit Bay export, verbatim (tools/import_refit_bay.py).", "chassis": chassis},
        indent=1, ensure_ascii=False) + "\n")
    names = {it["id"]: snake(it["name"][4:] if it["name"].startswith("(C) ") else it["name"]) for it in src["items"]}
    enemies = src.get("enemies", [])
    for e in enemies:
        write_enemy(e, names)
    print(f"{len(components)} components, {len(chassis)} chassis, {len(enemies)} enemies")


def pct(v, fallback):
    try:
        return round(float(v) / 100.0, 3)
    except (TypeError, ValueError):
        return fallback


def write_enemy(e: dict, names: dict) -> None:
    """One enemy from the Enemies tab as a game mech file. Placements carry
    absolute cells; the offset is their top-left corner (GridUtils places a
    rotated, normalized shape at its offset). Repeated parts get _2, _3 ids."""
    ai_in = e.get("ai", {})
    ai = {"heat": ai_in.get("heat", "careful"), "cards": ai_in.get("cards", "random"),
          "targets": ai_in.get("targets", "random"), "slip": pct(ai_in.get("slip"), 0.3),
          "protocols": pct(ai_in.get("protocols"), 0.7), "guard": pct(ai_in.get("guard"), 0.5)}
    p2 = e.get("phase2", {})
    if p2.get("enabled"):
        ov = {}
        for k in ("cards", "targets"):
            if p2.get(k):
                ov[k] = p2[k]
        for k in ("slip", "guard"):
            if str(p2.get(k, "")).strip() != "":
                ov[k] = pct(p2[k], 0.0)
        ai["phase2"] = ov
    if e.get("notes"):
        ai["_why"] = e["notes"]
    comps, seen = [], {}
    for p in e.get("placements", []):
        part = names.get(p["itemId"])
        if part is None:
            continue
        seen[part] = seen.get(part, 0) + 1
        entry = {"id": part if seen[part] == 1 else f"{part}_{seen[part]}",
                 "offset": [min(c[0] for c in p["cells"]), min(c[1] for c in p["cells"])],
                 "rotation": int(p.get("rotation", 0))}
        if seen[part] > 1:
            entry["part"] = part
        comps.append(entry)
    mech = {"id": snake(e["name"]), "name": e["name"], "tier": e.get("tier", "regular"), "weight_class": "general",
            "max_heat": int(float(e.get("maxHeat") or 6)), "defeat_hp_fraction": pct(e.get("defeatPct"), 0.4),
            "heat_check_timing": e.get("heatCheck", "end_of_turn"), "ai": ai,
            "_note": "From Refit Bay's Enemies tab, verbatim (tools/import_refit_bay.py).",
            "cells": sorted([list(c) for c in e.get("cells", [])]), "components": comps}
    if e.get("title"):
        mech["title"] = e["title"]
    lines = {k: v for k, v in e.get("lines", {}).items() if v}
    if lines:
        mech["lines"] = lines
    (ROOT / "data" / "mechs" / f"{mech['id']}.json").write_text(json.dumps(mech, indent=2, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()

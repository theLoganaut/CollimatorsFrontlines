#!/usr/bin/env python3
"""Dev helper: lists where Refit Bay parts fit on an enemy frame.

Usage: python3 tools/fit_parts.py <mech id> <part id> [<part id> ...]
Prints, for each part, every (rotation, offset) that fits the mech's free
cells. Rotation matches Refit Bay / GridUtils: (row, col) -> (col, -row),
then normalized.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def norm(cells):
    mr = min(c[0] for c in cells)
    mc = min(c[1] for c in cells)
    return sorted([(r - mr, c - mc) for r, c in cells])


def rot(cells, steps):
    out = norm(cells)
    for _ in range(steps % 4):
        out = norm([(c, -r) for r, c in out])
    return out


def comps():
    return {c["id"]: c for c in json.loads((ROOT / "data/components.json").read_text())["components"]}


def placed(comp, steps, off):
    return [(r + off[0], c + off[1]) for r, c in rot(comp["cells"], steps)]


def free_cells(mech, lib):
    frame = {tuple(c) for c in mech["cells"]}
    for p in mech["components"]:
        for cell in placed(lib[p["id"]], p.get("rotation", 0), p["offset"]):
            frame.discard(cell)
    return frame


def fits(comp, free):
    out = []
    for steps in range(4):
        for r in range(-1, 10):
            for c in range(-1, 10):
                cells = placed(comp, steps, (r, c))
                if all(x in free for x in cells):
                    out.append((steps, (r, c)))
    return out


def main():
    lib = comps()
    mech = json.loads((ROOT / "data/mechs" / f"{sys.argv[1]}.json").read_text())
    free = free_cells(mech, lib)
    print("free cells:", sorted(free))
    for pid in sys.argv[2:]:
        print(pid, fits(lib[pid], free)[:12])


if __name__ == "__main__":
    main()

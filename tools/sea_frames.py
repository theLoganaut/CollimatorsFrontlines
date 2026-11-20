#!/usr/bin/env python3
"""Builds animated backgrounds' frame strips (PlayField plays backgrounds.json
`frames` / `frames_phase2`) from PixelLab-animated 256x256 crops of them.

The crops live in art_src/sea/<background id>/<set>_<i>.png (frame 0 = the
crop as it is, then the generated frames, the last pinned back to the first
so it loops; frames 0..FRAMES-1 are used). Each output frame is the whole
background with only some of its pixels taken from that frame's crops:
  "sea":  the pixels the background's water mask marks (the pier never moves)
  "diff": the pixels that change anywhere in the crop's animation (the rest,
          and so the crop's edges, stay exactly as drawn)
A strip can also run `heat` over a circle: its bright pixels pushed toward
red-hot, the rest of it darkened and reddened (a part glowing in phase 2).

Shipyard pier (Logan, 2026-11-20): phase 1 = PixelLab animate_image (the foam
churns, the waves stay put), phase 2 = PixMiniMax (waves crash over the pier,
draw back and break again).
Mining Grounds tunnel: the borer's cutterhead turns (PixMiniMax), and in phase
2 the same turn runs red-hot (and faster: fps_phase2 in backgrounds.json).

Usage: python3 tools/sea_frames.py
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
FRAMES = 8  # 0..7: the generated 8th is the pinned copy of frame 0

# background id -> its image, how pixels are picked, and the strips to build:
# each strip is a list of layers (crop set, where it sits) and maybe `heat`
BACKGROUNDS = {
    "shipyard_boss_alt": {
        "image": "assets/backgrounds/shipyard_boss_alt.png",
        "pick": "sea",
        "mask": "assets/backgrounds/shipyard_boss_alt_sea.png",
        "strips": {
            "assets/backgrounds/shipyard_boss_alt_frames.png": {"layers": [("pl_left", (0, 134)), ("pl_right", (368, 134))]},
            "assets/backgrounds/shipyard_boss_alt_frames_p2.png": {"layers": [("mm_left", (0, 134)), ("mm_right", (368, 134))]},
        },
    },
    "mining_grounds_boss": {
        "image": "assets/backgrounds/mining_grounds_boss.png",
        "pick": "diff",
        "strips": {
            "assets/backgrounds/mining_grounds_boss_frames.png": {"layers": [("mm_tbm", (182, 0))]},
            "assets/backgrounds/mining_grounds_boss_frames_p2.png": {"layers": [("mm_tbm", (182, 0))],
                                                                     "heat": {"center": (313, 106), "radius": 72}},
        },
    },
}

DIFF_THRESHOLD = 40  # summed RGB difference that counts as "moved"


def lum(px):
    return (0.3 * px[0] + 0.59 * px[1] + 0.11 * px[2]) / 255


def diff_mask(frames):
    """White where any frame differs from frame 0 (grown by a pixel)."""
    w, h = frames[0].size
    m = Image.new("L", (w, h), 0)
    first = frames[0].load()
    mp = m.load()
    for f in frames[1:]:
        fp = f.load()
        for y in range(h):
            for x in range(w):
                a, b = first[x, y], fp[x, y]
                if abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2]) > DIFF_THRESHOLD:
                    mp[x, y] = 255
    grown = m.copy()
    gp = grown.load()
    for y in range(h):
        for x in range(w):
            if mp[x, y]:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    if 0 <= x + dx < w and 0 <= y + dy < h:
                        gp[x + dx, y + dy] = 255
    return grown


def heat(frame, center, radius):
    """Red-hot: bright pixels in the circle go toward glowing red-orange."""
    px = frame.load()
    cx, cy = center
    for y in range(max(0, cy - radius), min(frame.height, cy + radius + 1)):
        for x in range(max(0, cx - radius), min(frame.width, cx + radius + 1)):
            if (x - cx) ** 2 + (y - cy) ** 2 > radius * radius:
                continue
            r, g, b, a = px[x, y]
            if lum((r, g, b)) > 0.42:
                k = 0.65
                px[x, y] = (int(r + (255 - r) * k), int(g + (85 - g) * k), int(b + (30 - b) * k), a)
            else:
                px[x, y] = (min(255, int(r * 0.9 + 22)), int(g * 0.75), int(b * 0.7), a)


def build(bg_id, spec):
    base = Image.open(ROOT / spec["image"]).convert("RGBA")
    src = ROOT / "art_src" / "sea" / bg_id
    full_mask = Image.open(ROOT / spec["mask"]).convert("L") if spec["pick"] == "sea" else None
    for out_path, strip_spec in spec["strips"].items():
        crops = {name: [Image.open(src / f"{name}_{i}.png").convert("RGBA") for i in range(FRAMES)]
                 for name, _ in strip_spec["layers"]}
        masks = {}
        for name, (ox, oy) in strip_spec["layers"]:
            w, h = crops[name][0].size
            masks[name] = full_mask.crop((ox, oy, ox + w, oy + h)) if full_mask is not None else diff_mask(crops[name])
        strip = Image.new("RGBA", (base.width * FRAMES, base.height))
        for i in range(FRAMES):
            frame = base.copy()
            for name, (ox, oy) in strip_spec["layers"]:
                frame.paste(crops[name][i], (ox, oy), masks[name])
            if "heat" in strip_spec:
                heat(frame, strip_spec["heat"]["center"], strip_spec["heat"]["radius"])
            strip.paste(frame, (i * base.width, 0))
        strip.save(ROOT / out_path)
        print(f"{out_path}: {FRAMES} frames")


if __name__ == "__main__":
    for bg_id, spec in BACKGROUNDS.items():
        build(bg_id, spec)

#!/usr/bin/env python3
"""Builds the bosses' phase-2 idle animations from their still sprites
(assets/enemies/<id>_p2.png) into assets/enemies/<id>_p2_anim.png: a strip
of square frames side by side (MechArt plays it at 8 fps; Reduce motion holds frame 0).

Each effect works on the sprite's own pixels, picked by colour inside a
rectangle, so nothing is redrawn (Logan, 2026-11-20):
  anchor:  the chest core and the burning gun flicker like a fire inside them
  bedrock: the drill spins (its stripes turn down the cone, its outline stays
           put), rocks fall off it and sparks fly; the purple chest core pulses
  cipher:  the energy tails whip like an annoyed cat's (a wave running out to
           the tips, with sudden flicks); the purple shoulder panels glow

Usage: python3 tools/boss_p2_anim.py [build|masks <out folder>]
  build  writes the strips (default)
  masks  writes each boss's masks over its sprite, x4, to check the regions
"""
import colorsys
import math
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ENEMIES = ROOT / "assets" / "enemies"
FRAMES = 12  # 1.5 s at MechArt.ANIM_FPS (8)


def hsv(px):
    r, g, b, a = px
    h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    return h * 360, s, v, a


def mask(img, rect, test):
    """Pixels inside rect (x0, y0, x1, y1, inclusive) whose colour passes test."""
    x0, y0, x1, y1 = rect
    out = set()
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            px = img.getpixel((x, y))
            if px[3] > 0 and test(*hsv(px)):
                out.add((x, y))
    return out


def hash01(*k):
    return (math.sin(sum((i + 1) * 12.9898 * v for i, v in enumerate(k)) + 78.233) * 43758.5453) % 1.0


def clamp(v):
    return max(0, min(255, int(round(v))))


def fire(px, level):
    """A fire pixel at `level` (about 0.6 dim .. 1.5 roaring): brighter goes
    yellow-white, dimmer goes deep red, keeping the pixel's own shading."""
    r, g, b, a = px
    lum = (0.3 * r + 0.59 * g + 0.11 * b) / 255
    heat = max(0.0, min(1.0, lum * level))
    # dark red -> red -> orange -> yellow -> near white
    stops = [(0.0, (60, 8, 4)), (0.35, (190, 30, 10)), (0.6, (245, 105, 20)), (0.8, (255, 190, 60)), (1.0, (255, 245, 200))]
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if heat <= t1:
            k = (heat - t0) / (t1 - t0)
            target = [c0[i] + (c1[i] - c0[i]) * k for i in range(3)]
            break
    mix = 0.75
    return (clamp(r + (target[0] - r) * mix), clamp(g + (target[1] - g) * mix), clamp(b + (target[2] - b) * mix), a)


def glow(px, level, tint):
    """Brightens a pixel toward `tint` by `level` (0 = as drawn)."""
    r, g, b, a = px
    return (clamp(r + (tint[0] - r) * level), clamp(g + (tint[1] - g) * level), clamp(b + (tint[2] - b) * level), a)


# ---------- the bosses ----------

def is_fire(h, s, v, a):
    return (h <= 50 or h >= 345) and s > 0.45 and v > 0.45


def is_purple(h, s, v, a):
    return 255 <= h <= 320 and s > 0.3 and v > 0.25


def is_tail(h, s, v, a):
    return 195 <= h <= 250 and s > 0.35 and v > 0.2


ANCHOR = {"core": (48, 26, 74, 54), "gun": (0, 52, 32, 118)}
BEDROCK = {"core": (48, 28, 78, 52),
           # the drill's cone (inside it, the stripes turn) and where loose rocks and sparks fly
           "cone": [(7, 65), (31, 65), (28, 77), (23, 88), (17, 98), (13, 107), (11, 107), (9, 96), (8, 84), (6, 72)],
           "loose": (0, 56, 39, 127)}
CIPHER = {"shoulders": [(22, 24, 46, 50), (64, 24, 90, 50)], "tails": [(0, 56, 38, 104), (80, 38, 127, 104)],
          "roots": [(38, 80), (84, 76)]}  # where each tail leaves the body


def anchor_masks(img):
    return {"core": mask(img, ANCHOR["core"], is_fire), "gun": mask(img, ANCHOR["gun"], is_fire)}


def anchor_frames(img):
    m = anchor_masks(img)
    out = []
    for f in range(FRAMES):
        fr = img.copy()
        t = f / FRAMES
        # the core breathes slowly; the gun burns faster and rougher
        core = 1.0 + 0.35 * math.sin(t * math.tau) + 0.08 * math.sin(t * math.tau * 3)
        for (x, y) in m["core"]:
            fr.putpixel((x, y), fire(img.getpixel((x, y)), core + 0.15 * (hash01(x, y, f) - 0.5)))
        for (x, y) in m["gun"]:
            lick = 1.0 + 0.3 * math.sin(t * math.tau * 2 + y * 0.35) + 0.35 * (hash01(x, y, f // 2) - 0.5)
            fr.putpixel((x, y), fire(img.getpixel((x, y)), lick))
        out.append(fr)
    return out


def bedrock_masks(img):
    """The cone's inside (its outline stays put, so it keeps a clean edge on
    the mech), the loose rocks and the sparks around it."""
    from PIL import ImageDraw
    poly = Image.new("L", img.size, 0)
    ImageDraw.Draw(poly).polygon(BEDROCK["cone"], fill=255)
    pp = poly.load()
    px = img.load()

    def solid(x, y):
        return 0 <= x < img.width and 0 <= y < img.height and pp[x, y] and px[x, y][3] > 0

    cone = {(x, y) for y in range(img.height) for x in range(img.width)
            if solid(x, y) and lum(px[x, y]) > 0.13 and all(solid(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))}
    loose = specks(img, BEDROCK["loose"])
    rocks = [c for c in loose if lum(avg(img, c)) < 0.3]
    sparks = [c for c in loose if lum(avg(img, c)) >= 0.3]
    return {"core": mask(img, BEDROCK["core"], is_purple), "cone": cone, "rocks": rocks, "sparks": sparks}


def lum(px):
    return (0.3 * px[0] + 0.59 * px[1] + 0.11 * px[2]) / 255


def avg(img, pts):
    return tuple(sum(img.getpixel(p)[i] for p in pts) // len(pts) for i in range(3))


def specks(img, rect, biggest=60):
    """Small separate clusters of pixels in rect (not the body: the biggest one)."""
    x0, y0, x1, y1 = rect
    px = img.load()
    seen, out = set(), []
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if px[x, y][3] == 0 or (x, y) in seen:
                continue
            stack, comp = [(x, y)], []
            seen.add((x, y))
            while stack:
                p = stack.pop()
                comp.append(p)
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        q = (p[0] + dx, p[1] + dy)
                        if x0 <= q[0] <= x1 and y0 <= q[1] <= y1 and q not in seen and px[q][3] > 0:
                            seen.add(q)
                            stack.append(q)
            if len(comp) <= biggest:
                out.append(comp)
    return out


DRILL_PERIOD = 6  # px between the drill's stripes at the top of the cone
DRILL_TURNS = 2  # stripes the drill turns through in one loop (whole, so it loops)
DRILL_SLANT = -1.1  # how far a stripe drops across the cone, in stripes (the art's are steep)

# The drill's spiral, from the art's own colours: a hot edge, the orange
# band, its shadow, then bare steel between the bands. (start of band, colour)
DRILL_BANDS = [(0.0, (252, 205, 110)), (0.12, (238, 128, 48)), (0.38, (168, 74, 34)),
               (0.52, (96, 84, 78)), (0.78, (66, 58, 56))]


def drill_colour(band, light, alpha):
    colour = DRILL_BANDS[0][1]
    for start, c in DRILL_BANDS:
        if band >= start:
            colour = c
    k = max(0.55, min(1.2, light))
    return (clamp(colour[0] * k), clamp(colour[1] * k), clamp(colour[2] * k), alpha)


def bedrock_frames(img):
    """The drill spins: each pixel inside the cone takes its colour from the
    same place across the cone, a fraction of a stripe further up. Measured
    in stripes, not pixels, since they crowd together toward the tip. Loose
    rocks fall off it and sparks fly; the chest core pulses."""
    m = bedrock_masks(img)
    cone = m["cone"]
    rows = {}
    for (x, y) in cone:
        rows.setdefault(y, []).append(x)
    ys = sorted(rows)
    span = {y: (min(rows[y]), max(rows[y])) for y in ys}
    width = {y: span[y][1] - span[y][0] + 1 for y in ys}
    top_w = max(width.values())
    # u: stripes from the top of the cone (each stripe narrower nearer the tip)
    u, acc = {}, 0.0
    for y in ys:
        u[y] = acc
        acc += 1.0 / max(2.5, DRILL_PERIOD * width[y] / top_w)
    total = acc

    def row_at(target):
        return min(ys, key=lambda y: abs(u[y] - target))

    out = []
    base = img.copy()
    for comp in m["rocks"] + m["sparks"]:
        for p in comp:
            base.putpixel(p, (0, 0, 0, 0))
    for f in range(FRAMES):
        fr = base.copy()
        t = f / FRAMES
        phase = DRILL_TURNS * t
        for (x, y) in cone:
            a = (x - span[y][0]) / max(1, width[y] - 1)  # 0..1 across the cone
            # where this pixel sits on the spiral (stripes slant across the cone)
            band = (u[y] + DRILL_SLANT * a - phase) % 1.0
            # rounded: lit a little left of centre, dark at both edges
            light = 1.0 - 1.6 * (a - 0.4) ** 2
            fr.putpixel((x, y), drill_colour(band, light, img.getpixel((x, y))[3]))
        # rocks break off and fall, each on its own beat (a new one replaces it at the top)
        for k, comp in enumerate(m["rocks"]):
            ph = (t + k * 0.37) % 1.0
            dy = round(-6 + ph * ph * 22)
            dx = round(-ph * 3)
            for (x, y) in comp:
                nx, ny = x + dx, y + dy
                if 0 <= nx < img.width and 0 <= ny < img.height and fr.getpixel((nx, ny))[3] == 0:
                    fr.putpixel((nx, ny), img.getpixel((x, y)))
        # sparks fly off the cone and burn out
        cx = sum(x for x, _ in cone) / len(cone)
        cy = sum(y for _, y in cone) / len(cone)
        for k, comp in enumerate(m["sparks"]):
            ph = (t * 2 + k * 0.29) % 1.0
            if ph > 0.75:
                continue
            sx = sum(x for x, _ in comp) / len(comp) - cx
            sy = sum(y for _, y in comp) / len(comp) - cy
            n = max(1.0, math.hypot(sx, sy))
            dx, dy = round((ph - 0.3) * 10 * sx / n), round((ph - 0.3) * 10 * sy / n + ph * ph * 4)
            for (x, y) in comp:
                nx, ny = x + dx, y + dy
                if 0 <= nx < img.width and 0 <= ny < img.height and fr.getpixel((nx, ny))[3] == 0:
                    fr.putpixel((nx, ny), img.getpixel((x, y)))
        pulse = 0.5 + 0.5 * math.sin(t * math.tau)
        for (x, y) in m["core"]:
            fr.putpixel((x, y), glow(img.getpixel((x, y)), 0.45 * pulse, (245, 190, 255)))
        out.append(fr)
    return out


def cipher_masks(img):
    shoulders = set()
    for r in CIPHER["shoulders"]:
        shoulders |= mask(img, r, is_purple)
    tails = []
    for r in CIPHER["tails"]:
        tails.append(mask(img, r, is_tail))
    return {"shoulders": shoulders, "tails": tails}


def whip(t):
    """An annoyed cat's tail: a steady sway with a sharp flick now and then."""
    sway = math.sin(t * math.tau)
    flick = math.exp(-((t - 0.62) % 1.0) * 9.0) * math.sin(((t - 0.62) % 1.0) * math.tau * 3.0)
    return sway * 0.6 + flick * 1.1


def cipher_frames(img):
    m = cipher_masks(img)
    out = []
    for f in range(FRAMES):
        fr = img.copy()
        t = f / FRAMES
        every_tail = set().union(*m["tails"])
        for (x, y) in every_tail:
            fr.putpixel((x, y), (0, 0, 0, 0))
        for side, (tail, root) in enumerate(zip(m["tails"], CIPHER["roots"])):
            if not tail:
                continue
            reach = max(math.dist(p, root) for p in tail)
            pad = 6
            x0 = max(0, min(p[0] for p in tail) - pad)
            x1 = min(img.width - 1, max(p[0] for p in tail) + pad)
            y0 = max(0, min(p[1] for p in tail) - pad)
            y1 = min(img.height - 1, max(p[1] for p in tail) + pad)
            # Backwards: each pixel near the tail takes the tail pixel that
            # moves onto it, so the bent tail has no holes.
            for y in range(y0, y1 + 1):
                for x in range(x0, x1 + 1):
                    d = min(1.0, math.dist((x, y), root) / reach)  # 0 at the body, 1 at the tip
                    # the wave runs out along the tail, growing toward the tip
                    wave = whip(t - d * 0.35 + side * 0.5)
                    dy = round(wave * 6.0 * d * d)
                    dx = round(wave * 2.5 * d * d * (1 if side == 0 else -1))
                    src = (x - dx, y - dy)
                    if src in tail:
                        under = fr.getpixel((x, y))
                        if under[3] == 0 or (x, y) in every_tail:
                            fr.putpixel((x, y), img.getpixel(src))
        glow_level = 0.25 + 0.25 * math.sin(t * math.tau)
        for (x, y) in m["shoulders"]:
            fr.putpixel((x, y), glow(img.getpixel((x, y)), glow_level, (225, 170, 255)))
        out.append(fr)
    return out


BOSSES = {"anchor": (anchor_masks, anchor_frames), "bedrock": (bedrock_masks, bedrock_frames), "cipher": (cipher_masks, cipher_frames)}


def build():
    for boss, (_, frames_of) in BOSSES.items():
        img = Image.open(ENEMIES / f"{boss}_p2.png").convert("RGBA")
        frames = frames_of(img)  # frame 0 is computed too, so the loop never pops back to the still
        strip = Image.new("RGBA", (img.width * len(frames), img.height))
        for i, fr in enumerate(frames):
            strip.paste(fr, (i * img.width, 0))
        strip.save(ENEMIES / f"{boss}_p2_anim.png")
        print(f"{boss}_p2_anim.png: {len(frames)} frames")


def masks(out_dir):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    colors = [(255, 0, 255, 255), (0, 255, 0, 255), (0, 200, 255, 255), (255, 255, 0, 255)]
    for boss, (masks_of, _) in BOSSES.items():
        img = Image.open(ENEMIES / f"{boss}_p2.png").convert("RGBA")
        view = img.copy()
        groups = masks_of(img)
        sets = []
        for v in groups.values():
            sets.extend(v if isinstance(v, list) else [v])
        for i, s in enumerate(sets):
            for p in s:
                view.putpixel(p, colors[i % len(colors)])
        view.resize((img.width * 4, img.height * 4), Image.NEAREST).save(out / f"{boss}_masks.png")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "masks":
        masks(sys.argv[2])
    else:
        build()

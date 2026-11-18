"""Review sheets for enemy drafts: one of sprite candidates, one of grids and weapons.

    python tools/enemy_sheets.py <drafts dir> <out dir> [--candidates=<dir>] [--existing=id,id] [--title=Shipyard]

<drafts dir> holds enemy files in data/mechs format (e.g. art_src/enemy_drafts/shipyard/).
--candidates: PNGs named <id>_<n>.png (PixelLab picks); each draft gets a row of them.
--existing: enemies already in data/mechs to show alongside (their current sprite and grid).
Writes <out>/<title>_sprites.png and <out>/<title>_grids.png. Needs Pillow.
Card numbers are Refit Bay's (components.json), before balance.json's combat scaling.
"""
import glob, json, os, sys, textwrap
from PIL import Image, ImageDraw, ImageFont

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COMP = {c["id"]: c for c in json.load(open(os.path.join(REPO, "data/components.json"), encoding="utf-8"))["components"]}
RULES = json.load(open(os.path.join(REPO, "data/component_rules.json"), encoding="utf-8"))["passives"]

BG = (22, 25, 30); PANEL = (34, 38, 46); INK = (232, 234, 238); DIM = (150, 156, 168); ARROW = (250, 210, 60)
CAT = {"hardpoint": (232, 145, 58), "reactor": (58, 192, 176), "protocol": (160, 112, 224)}
TIER = {"regular": (150, 156, 168), "elite": (232, 190, 70), "boss": (190, 110, 240)}
DIRS = {"up": (-1, 0), "right": (0, 1), "down": (1, 0), "left": (0, -1)}
ORDER = ["up", "right", "down", "left"]


def font(size, bold=False):
    for name in (["segoeuib.ttf", "arialbd.ttf", "DejaVuSans-Bold.ttf"] if bold else ["segoeui.ttf", "arial.ttf", "DejaVuSans.ttf"]):
        for d in ("C:/Windows/Fonts", "/System/Library/Fonts/Supplemental", "/usr/share/fonts/truetype/dejavu"):
            p = os.path.join(d, name)
            if os.path.exists(p):
                return ImageFont.truetype(p, size)
    return ImageFont.load_default()


F_TITLE, F_H, F_B, F_S, F_SB = font(34, True), font(22, True), font(16), font(14), font(14, True)


def rot_cells(cells, steps):
    out = [tuple(c) for c in cells]
    for _ in range(steps % 4):
        out = [(c, -r) for r, c in out]
        mr = min(r for r, _ in out); mc = min(c for _, c in out)
        out = [(r - mr, c - mc) for r, c in out]
    return out


def facing(pid, steps):
    """Arrows a part shows: (direction, kind) after `steps` clockwise turns."""
    c = COMP[pid]; out = []
    rule = RULES.get(pid, {})
    if "facing" in rule:
        out.append(rule["facing"])
    link = c.get("link", {})
    out += [d for d in link.get("dirs", []) if d not in out]
    return [ORDER[(ORDER.index(d) + steps) % 4] for d in out if d in ORDER]


def placed(mech):
    parts = []
    for p in mech["components"]:
        r0, c0 = p["offset"]; steps = p.get("rotation", 0)
        parts.append((p["id"], steps, [(r + r0, c + c0) for r, c in rot_cells(COMP[p["id"]]["cells"], steps)], (r0, c0)))
    return parts


def draw_grid(mech, cell):
    cells = [tuple(c) for c in mech["cells"]]
    rows = max(r for r, _ in cells) + 1; cols = max(c for _, c in cells) + 1
    img = Image.new("RGBA", (cols * cell + 1, rows * cell + 1), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for r, c in cells:
        d.rectangle([c * cell, r * cell, (c + 1) * cell, (r + 1) * cell], fill=(44, 49, 58), outline=(80, 86, 98))
    for pid, steps, pcells, (r0, c0) in placed(mech):
        col = CAT.get(COMP[pid]["category"], INK)
        path = os.path.join(REPO, "assets/components", pid + ".png")
        if os.path.exists(path):
            art = Image.open(path).convert("RGBA").rotate(-90 * steps, expand=True)
            art = art.resize((art.width * cell // 32, art.height * cell // 32), Image.NEAREST)
            for r, c in pcells:
                lr, lc = r - r0, c - c0
                tile = art.crop((lc * cell, lr * cell, (lc + 1) * cell, (lr + 1) * cell))
                img.alpha_composite(tile, (c * cell, r * cell))
        else:
            for r, c in pcells:
                d.rectangle([c * cell, r * cell, (c + 1) * cell, (r + 1) * cell], fill=col + (90,))
        own = set(pcells)
        for r, c in pcells:  # outline only the part's outer edges
            x0, y0, x1, y1 = c * cell, r * cell, (c + 1) * cell, (r + 1) * cell
            for (dr, dc), seg in (((-1, 0), (x0, y0, x1, y0)), ((1, 0), (x0, y1, x1, y1)),
                                  ((0, -1), (x0, y0, x0, y1)), ((0, 1), (x1, y0, x1, y1))):
                if (r + dr, c + dc) not in own:
                    d.line(seg, fill=col, width=3)
        for dname in facing(pid, steps):
            dr, dc = DIRS[dname]
            for r, c in pcells:
                if (r + dr, c + dc) in own:
                    continue
                cx, cy = c * cell + cell / 2 + dc * cell * 0.38, r * cell + cell / 2 + dr * cell * 0.38
                s = cell * 0.13; px, py = -dr, dc  # perpendicular
                d.polygon([(cx + dc * s, cy + dr * s), (cx + px * s - dc * s * 0.4, cy + py * s - dr * s * 0.4),
                           (cx - px * s - dc * s * 0.4, cy - py * s - dr * s * 0.4)], fill=ARROW, outline=(0, 0, 0))
    return img


def card_line(cd, category):
    bits = []
    if category != "reactor" or cd.get("heat_cost") not in (None, "", "0"):
        if cd.get("heat_cost") not in (None, ""):
            bits.append(f"{cd['heat_cost']} Heat")
    if cd.get("damage"):
        hits = cd.get("hits") or "1"
        bits.append(f"{hits}x{cd['damage']}" if hits != "1" else f"{cd['damage']} dmg")
    for s in cd.get("statuses", []):
        who = "self" if s.get("target") == "self" else ""
        bits.append(f"{s['status'].replace('_', ' ').title()} {s.get('stacks', '')}{' (self)' if who else ''}".strip())
    text = ", ".join(bits)
    if cd.get("effect_text"):
        text += (". " if text else "") + cd["effect_text"]
    return cd["name"], text


def wrap(draw, text, fnt, width):
    words, lines, cur = text.split(), [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if draw.textlength(t, font=fnt) <= width:
            cur = t
        else:
            lines.append(cur); cur = w
    if cur:
        lines.append(cur)
    return lines


def ai_line(m):
    ai = m.get("ai", {})
    parts = [ai.get(k) for k in ("heat", "cards", "targets") if ai.get(k)]
    if ai.get("rhythm"):
        parts.append("rhythm: " + ai["rhythm"])
    if ai.get("role"):
        parts.append("role: " + ai["role"])
    return " · ".join(parts)


def grid_panel(m, draft, width=620):
    cell = 56 if m["tier"] == "regular" else 50
    g = draw_grid(m, cell)
    scratch = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    text_w = width - 40
    # measure the parts list
    blocks = []
    for p in m["components"]:
        c = COMP[p["id"]]
        lines = [(f"{c['name']}  ·  {c['category']} · {c['weight_class']} · {c['rarity']} · {c['hp']} HP", F_SB, CAT.get(c["category"], INK))]
        for cd in c.get("cards", []):
            name, txt = card_line(cd, c["category"])
            if c["category"] == "reactor" and name == c["name"]:
                for i, l in enumerate(wrap(scratch, txt, F_S, text_w - 14)):
                    lines.append(("  " + l, F_S, INK))
            else:
                for i, l in enumerate(wrap(scratch, f"{name}: {txt}", F_S, text_w - 14)):
                    lines.append((("  " if i == 0 else "      ") + l, F_S, INK))
        blocks.append(lines)
    hp = sum(COMP[p["id"]]["hp"] for p in m["components"])
    why = wrap(scratch, m.get("ai", {}).get("_why", ""), F_S, text_w)
    head_h = 34 + 24 + 22 + 20 * len(why) + 10
    list_h = sum(len(b) * 19 + 8 for b in blocks)
    h = head_h + g.height + 20 + list_h + 16
    img = Image.new("RGB", (width, h), PANEL)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, width - 1, h - 1], outline=TIER.get(m["tier"], DIM), width=2)
    y = 12
    d.text((20, y), m["name"], font=F_H, fill=INK)
    tag = ("NEW DRAFT" if draft else "EXISTING")
    d.text((width - 20 - d.textlength(tag, font=F_SB), y + 6), tag, font=F_SB, fill=ARROW if draft else DIM)
    y += 34
    d.text((20, y), f"{m['tier'].title()} · {m['weight_class'].title()} · {len(m['cells'])} cells · parts {hp} HP · "
           f"max Heat {m['max_heat']} · defeat at {int(m['defeat_hp_fraction'] * 100)}%",
           font=F_S, fill=TIER.get(m["tier"], DIM))
    y += 24
    d.text((20, y), "AI: " + ai_line(m), font=F_S, fill=DIM); y += 22
    for l in why:
        d.text((20, y), l, font=F_S, fill=DIM); y += 20
    y += 10
    img.paste(g, ((width - g.width) // 2, y), g); y += g.height + 20
    for b in blocks:
        for txt, f, col in b:
            d.text((20, y), txt, font=f, fill=col); y += 19
        y += 8
    return img


def sprite_row(m, cands, draft, scale=2):
    tile = 128 * scale; pad = 16
    n = max(1, len(cands))
    img = Image.new("RGB", (220 + n * (tile + pad), tile + 2 * pad + 22), PANEL)
    d = ImageDraw.Draw(img)
    d.text((pad, pad), m["name"], font=F_H, fill=INK)
    d.text((pad, pad + 32), m["tier"].title() + " · " + m["weight_class"].title(), font=F_S, fill=TIER.get(m["tier"], DIM))
    d.text((pad, pad + 54), "new: pick one" if draft else "existing sprite", font=F_S, fill=ARROW if draft else DIM)
    for i, path in enumerate(cands):
        x = 220 + i * (tile + pad)
        d.rectangle([x - 1, pad - 1, x + tile, pad + tile], fill=(52, 58, 68))
        sp = Image.open(path).convert("RGBA").resize((tile, tile), Image.NEAREST)
        img.paste(sp, (x, pad), sp)
        if draft:
            label = f"#{i + 1}"
            d.text((x + tile // 2 - d.textlength(label, font=F_SB) / 2, pad + tile + 3), label, font=F_SB, fill=INK)
    return img


def stack(images, cols, title, footer, gap=18):
    if not images:
        return None
    rows = [images[i:i + cols] for i in range(0, len(images), cols)]
    col_w = max(i.width for i in images)
    width = cols * col_w + (cols + 1) * gap
    heights = [max(i.height for i in r) for r in rows]
    H = 70 + sum(heights) + gap * (len(rows) + 1) + 30
    sheet = Image.new("RGB", (width, H), BG)
    d = ImageDraw.Draw(sheet)
    d.text((gap, 18), title, font=F_TITLE, fill=INK)
    y = 70 + gap
    for r, h in zip(rows, heights):
        for i, im in enumerate(r):
            sheet.paste(im, (gap + i * (col_w + gap), y))
        y += h + gap
    d.text((gap, H - 28), footer, font=F_S, fill=DIM)
    return sheet


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--"))
    drafts_dir, out = args[0], args[1]
    title = opts.get("title", "Enemies")
    drafts = [json.load(open(p, encoding="utf-8")) for p in sorted(glob.glob(os.path.join(drafts_dir, "*.json")))]
    existing = [json.load(open(os.path.join(REPO, "data/mechs", i + ".json"), encoding="utf-8"))
                for i in opts.get("existing", "").split(",") if i]
    order = {"regular": 0, "elite": 1, "boss": 2}
    allm = sorted([(m, True) for m in drafts] + [(m, False) for m in existing],
                  key=lambda t: (order.get(t[0]["tier"], 3), not t[1], t[0]["name"]))
    os.makedirs(out, exist_ok=True)
    cand_dir = opts.get("candidates")
    rows = []
    for m, draft in allm:
        if draft and cand_dir:
            cands = sorted(glob.glob(os.path.join(cand_dir, m["id"] + "_*.png")))
        else:
            p = os.path.join(REPO, "assets/enemies", m["id"] + ".png")
            cands = [p] if os.path.exists(p) else []
        rows.append(sprite_row(m, cands, draft))
    w = max(r.width for r in rows)
    rows = [r if r.width == w else _pad(r, w) for r in rows]
    s = stack(rows, 1, f"{title} enemies: sprites", "PixelLab Pro (style from the existing sprites), 128×128 shown at 2×. Pick one per new enemy.")
    s.save(os.path.join(out, f"{title.lower()}_sprites.png"))
    panels = [grid_panel(m, draft) for m, draft in allm]
    g = stack(panels, 3, f"{title} enemies: grids and weapons",
              "Part art from assets/components. Orange hardpoint, teal reactor, violet protocol; yellow arrows = facing/links. "
              "Card numbers are Refit Bay's, before combat scaling.")
    g.save(os.path.join(out, f"{title.lower()}_grids.png"))
    print("wrote", os.path.join(out, f"{title.lower()}_sprites.png"), "and", os.path.join(out, f"{title.lower()}_grids.png"))


def _pad(img, w):
    out = Image.new("RGB", (w, img.height), PANEL)
    out.paste(img, (0, 0))
    return out


if __name__ == "__main__":
    main()

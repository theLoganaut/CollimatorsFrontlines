# The War Room's side walls, seen straight on (PixelLab Pro, 2026-11-11; room.png as the style
# and layout reference): left_v1.png (R&D bay, Info Bay terminal) and right_v1.png (Livery Bay,
# Pilot Log). The left one drew the War Table's floor pad again, so that floor is patched from
# the right wall's (left_v2.png). Each station is cut from its wall by hand-placed rectangles
# (PixelLab's background removal tore them up: nobg_*.png) into a room-sized layer, which the
# War Room draws over the wall as its Hotspot. Run from this folder.
from PIL import Image

A = '../../assets/warroom/'
L = Image.open('left_v1.png').convert('RGBA')
R = Image.open('right_v1.png').convert('RGBA')
pad = (195, 262, 435, 345)
L.paste(R.crop(pad), pad[:2])
L.save('left_v2.png')

# COMING SOON (Logan, 2026-11-11: the middle panels looked empty): strips of black-and-yellow
# caution tape pinned pillar to pillar, crossing every which way like a sealed door at a crime
# scene, and a COMING SOON! sign hung over the middle on two chains. Each strip is sheared a
# column at a time (not rotated) so its stripes stay crisp pixels.
EDGE, FILL, LIT, INK = (44, 36, 28, 255), (212, 174, 70, 255), (232, 200, 98, 255), (30, 25, 22, 255)
TAPE_H = 8
RECESS = (221, 401) # the middle panel's sunken face, between the pillars (x, both walls)

def tape_strip(width, start):
    """A tape's pixels: dark edges, a lit top row, black bars slanting across the yellow."""
    strip = Image.new('RGBA', (width, TAPE_H))
    for x in range(width):
        strip.putpixel((x, 0), EDGE); strip.putpixel((x, TAPE_H - 1), EDGE)
        for y in range(1, TAPE_H - 1):
            black = (x + start + y) % 10 < 5
            strip.putpixel((x, y), INK if black else (LIT if y == 1 else FILL))
    return strip

def tape(wall, x0, y0, x1, y1, start):
    """Pins a strip from (x0, y0) to (x1, y1). It's stuck flat on the pillars, so no shadow there,
    but it spans the sunken middle panel (RECESS) held off it, and casts a shadow down-right on it."""
    slope = (y1 - y0) / (x1 - x0)
    strip = tape_strip(x1 - x0, start)
    px = wall.load()
    for x in range(x1 - x0):
        top = y0 + round(slope * x)
        sx = x0 + x + 1
        if not RECESS[0] <= sx <= RECESS[1]:
            continue
        for y in range(TAPE_H):
            sy = top + y + 2
            r, g, b, a = px[sx, sy]
            px[sx, sy] = (int(r * 0.55), int(g * 0.55), int(b * 0.6), a)
    for x in range(x1 - x0):
        top = y0 + round(slope * x)
        for y in range(TAPE_H):
            px[x0 + x, top + y] = strip.getpixel((x, y))

# The sign's lettering: the Discord sign's 5x7 face (art_src/discord_sign/stamp.py), plus M and G.
G7 = {
    'C': ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
    'O': ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    'M': ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    'I': ["111", "010", "010", "010", "010", "010", "111"],
    'N': ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    'G': ["01111", "10000", "10000", "10011", "10001", "10001", "01111"],
    'S': ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    '!': ["1", "1", "1", "1", "1", "0", "1"],
}
OUTLINE, STEEL, STEEL_LIT, STEEL_DARK, RIVET = (16, 17, 24, 255), (92, 102, 118, 255), (142, 152, 168, 255), (56, 61, 74, 255), (176, 184, 196, 255)

def word_width(word):
    return sum(len(G7[ch][0]) for ch in word) + len(word) - 1

def stamp(img, word, cx, y, ink, shadow):
    x = cx - word_width(word) // 2
    for ch in word:
        g = G7[ch]
        for r, row in enumerate(g):
            for c, bit in enumerate(row):
                if bit == '1':
                    img.putpixel((x + c, y + r + 1), shadow)
        for r, row in enumerate(g):
            for c, bit in enumerate(row):
                if bit == '1':
                    img.putpixel((x + c, y + r), ink)
        x += len(g[0]) + 1

def sign(wall, cx, top, chain_top):
    """A steel-framed yellow plate, COMING / SOON! on two lines, hung on two chains."""
    w, h = 54, 34
    x0, y0 = cx - w // 2, top
    px = wall.load()
    for side in (x0 + 9, x0 + w - 10):                          # chains, link by link
        for y in range(chain_top, y0 + 1):
            link = (y - chain_top) % 4
            if link in (0, 3):
                px[side, y] = STEEL_LIT if link == 0 else STEEL_DARK
            else:
                px[side - 1, y] = OUTLINE; px[side + 1, y] = OUTLINE
                px[side, y] = STEEL_DARK
        px[side, chain_top - 1] = OUTLINE                       # its hook
    for y in range(y0 + 2, y0 + h + 2):                         # the plate's shadow on the wall
        for x in range(x0 + 2, x0 + w + 2):
            r, g, b, a = px[x, y]
            px[x, y] = (int(r * 0.55), int(g * 0.55), int(b * 0.6), a)
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            edge = x in (x0, x0 + w - 1) or y in (y0, y0 + h - 1)
            frame = x < x0 + 3 or x > x0 + w - 4 or y < y0 + 3 or y > y0 + h - 4
            if edge:
                c = OUTLINE
            elif frame:
                c = STEEL_LIT if y == y0 + 1 or x == x0 + 1 else (STEEL_DARK if y == y0 + h - 2 or x == x0 + w - 2 else STEEL)
            elif x == x0 + 3 or y == y0 + 3:
                c = (150, 118, 44, 255)                         # the face's inset shade
            else:
                c = FILL
            px[x, y] = c
    for rx, ry in ((x0 + 1, y0 + 1), (x0 + w - 2, y0 + 1), (x0 + 1, y0 + h - 2), (x0 + w - 2, y0 + h - 2)):
        px[rx, ry] = RIVET
    stamp(wall, "COMING", cx, y0 + 7, INK, (176, 140, 52, 255))
    stamp(wall, "SOON!", cx, y0 + 19, INK, (176, 140, 52, 255))

TAPES = [  # (x0, y0, x1, y1, where the stripes start)
    (204, 96, 416, 146, 0), (204, 214, 416, 112, 3), (204, 150, 416, 170, 6),
    (204, 118, 416, 216, 1), (204, 196, 416, 92, 7),
]
for i, t in enumerate(TAPES):
    tape(L, *t)
    a, b, c, d, e = TAPES[(i + 2) % len(TAPES)]
    tape(R, a, b + 3, c, d - 2, e + 4)                        # the right wall's, shuffled
sign(L, 310, 132, 96)
sign(R, 310, 132, 74)
# The floor's corner trenches (grates, cables) that PixelLab copied from room.png get the same plating
# the center lays over its own (floor_left.png / floor_right.png), so all three views share one floor.
for wall in (L, R):
    for f in ('floor_left.png', 'floor_right.png'):
        wall.alpha_composite(Image.open(A + f).convert('RGBA'))
L.save(A + 'wall_left.png')
R.save(A + 'wall_right.png')

# station -> (wall, rectangles in wall pixels)
STATIONS = {
    'research_bay': (L, [(45, 98, 192, 266), (0, 232, 46, 268)]),         # the shelf, the crates beside it
    'info_bay': (L, [(464, 155, 562, 199), (457, 196, 570, 266)]),        # the monitors, the desk
    'livery_bay': (R, [(69, 110, 183, 252)]),
    'pilot_log': (R, [(442, 129, 568, 250)]),
}
for name, (wall, rects) in STATIONS.items():
    out = Image.new('RGBA', wall.size, (0, 0, 0, 0))
    for r in rects:
        out.paste(wall.crop(r), r[:2])
    out.save(A + name + '.png')
    print(name, out.getbbox())

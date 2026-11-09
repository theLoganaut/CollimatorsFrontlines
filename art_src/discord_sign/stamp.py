# The War Room's "Join the Discord!" sign: a blank PixelLab plate with the
# Discord logo and pixel lettering stamped on its face (art pixels, no scaling).
#   /usr/bin/python3 art_src/discord_sign/stamp.py <plate.png> <face x0,y0,x1,y1> <out.png> [preview.png]
import sys, numpy as np
from PIL import Image
G = {
 'J':["00111","00010","00010","00010","00010","10010","01100"],
 'O':["01110","10001","10001","10001","10001","10001","01110"],
 'I':["111","010","010","010","010","010","111"],
 'N':["10001","11001","10101","10011","10001","10001","10001"],
 'T':["11111","00100","00100","00100","00100","00100","00100"],
 'H':["10001","10001","10001","11111","10001","10001","10001"],
 'E':["11111","10000","10000","11110","10000","10000","11111"],
 'D':["11110","10001","10001","10001","10001","10001","11110"],
 'S':["01111","10000","10000","01110","00001","00001","11110"],
 'C':["01111","10000","10000","10000","10000","10000","01111"],
 'R':["11110","10001","10001","11110","10100","10010","10001"],
 '!':["1","1","1","1","1","0","1"],
 ' ':["00","00","00","00","00","00","00"],
}
# Clyde, the Discord mark (white on a blurple tile), 16x12
CLYDE = [
 "...XXX....XXX...",
 "..XXXXXXXXXXXX..",
 ".XXXXXXXXXXXXXX.",
 ".XXXXXXXXXXXXXX.",
 "XXXX..XXXX..XXXX",
 "XXX....XX....XXX",
 "XXX....XX....XXX",
 "XXXX..XXXX..XXXX",
 "XXXXXXXXXXXXXXXX",
 ".XXXXXXXXXXXXXX.",
 ".XXXX......XXXX.",
 "..XX........XX..",
]
BLURPLE = (88, 101, 242, 255)
WHITE = (240, 244, 255, 255)
TEXT = (226, 232, 255, 255)
SHADOW = (12, 14, 30, 255)

def text_mask(s):
    cols = []
    for i, ch in enumerate(s):
        g = G[ch]
        for x in range(len(g[0])):
            cols.append([g[y][x] == '1' for y in range(7)])
        if i < len(s) - 1:
            cols.append([False] * 7)
    return np.array(cols, dtype=bool).T

def stamp(a, mask, x, y, col, shadow=True):
    h, w = mask.shape
    if shadow:
        for yy in range(h):
            for xx in range(w):
                if mask[yy, xx]:
                    a[y + yy + 1, x + xx + 1] = SHADOW
    for yy in range(h):
        for xx in range(w):
            if mask[yy, xx]:
                a[y + yy, x + xx] = col

def main():
    plate, face, out = sys.argv[1], [int(v) for v in sys.argv[2].split(',')], sys.argv[3]
    im = Image.open(plate).convert("RGBA")
    a = np.array(im)
    x0, y0, x1, y1 = face
    l1, l2 = text_mask("JOIN THE"), text_mask("DISCORD!")
    tile_w, tile_h = 20, 16
    tw = max(l1.shape[1], l2.shape[1])
    total = tile_w + 4 + tw
    lx = x0 + (x1 - x0 - total) // 2
    th = 7 + 3 + 7
    cy = (y0 + y1) // 2
    # the logo tile: blurple, rounded corners, Clyde in white
    ty = cy - tile_h // 2
    for yy in range(tile_h):
        for xx in range(tile_w):
            corner = (xx in (0, tile_w - 1)) and (yy in (0, tile_h - 1))
            if not corner:
                a[ty + yy, lx + xx] = BLURPLE
    m = np.array([[c == 'X' for c in r] for r in CLYDE])
    stamp(a, m, lx + 2, ty + 2, WHITE, shadow=False)
    tx = lx + tile_w + 4
    top = cy - th // 2
    stamp(a, l1, tx + (tw - l1.shape[1]) // 2, top, TEXT)
    stamp(a, l2, tx + (tw - l2.shape[1]) // 2, top + 10, TEXT)
    Image.fromarray(a).save(out)
    if len(sys.argv) > 4:
        Image.fromarray(a).resize((a.shape[1] * 8, a.shape[0] * 8), Image.NEAREST).save(sys.argv[4])

main()

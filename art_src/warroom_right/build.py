# The War Room's right side (PixelLab, 2026-11-11), placed into the room's layers.
# Livery Bay starts from the left side's Research Bay, mirrored onto the
# right wall (in_livery.png), then repainted by PixelLab edit_image (e_livery2.png),
# so it stands against the side wall facing the war table like the left side's.
# Directives is a PixelLab Pro piece (scr_0.png). try1/, try2/ and cands/ hold
# earlier attempts.
from PIL import Image
A = '../../assets/warroom/'
F3 = {'D':["110","101","101","101","110"], 'I':["111","010","010","010","111"], 'R':["110","101","110","101","101"],
      'E':["111","100","110","100","111"], 'C':["011","100","100","100","011"], 'T':["111","010","010","010","010"],
      'V':["101","101","101","101","010"], 'S':["011","100","010","001","110"]}
def stencil(img, text, cx, y, ink, shadow):
    w = len(text) * 4 - 1; x0 = cx - w // 2
    for i, ch in enumerate(text):
        for r, row in enumerate(F3[ch]):
            for c, bit in enumerate(row):
                if bit == '1':
                    img.putpixel((x0 + i * 4 + c, y + r + 1), shadow)
        for r, row in enumerate(F3[ch]):
            for c, bit in enumerate(row):
                if bit == '1':
                    img.putpixel((x0 + i * 4 + c, y + r), ink)
# Directives: a wall screen (PixelLab Pro, scr_0.png), stretched to the bay's height by repeating a band
# of its glass, the glass darkened so the dailies read, then the header stenciled. Drawn at Rect2(437, 124, 120, 116).
import numpy as np
src = np.asarray(Image.open('scr_0.png').convert('RGBA'))[2:105]          # its 103 rows
tall = np.concatenate([src[:62], src[49:62], src[62:]])                    # + 13 glass rows = 116
r, g, b = (tall[..., i].astype(int) for i in range(3))
glass = np.zeros(r.shape, bool); glass[21:101, 18:102] = True
dim = glass & (g - r > 40) & (b - r > 40) & (g < 170)                     # the glass, not its lit edge strips
tall = tall.copy(); tall[dim, :3] = (tall[dim, :3] * 0.42).astype(np.uint8)
board = Image.new('RGBA', (120, 116)); board.alpha_composite(Image.fromarray(tall), (1, 0))
stencil(board, "DIRECTIVES", 60, 25, (120, 235, 255, 255), (8, 40, 48, 255)) # the screen's title, lit
board.save(A + 'directives.png')
def layer(piece, x, y, out):
    canvas = Image.new('RGBA', (624, 390), (0, 0, 0, 0))
    canvas.alpha_composite(Image.open(piece).convert('RGBA'), (x, y))
    canvas.save(A + out)
layer('e_livery2.png', 560, 122, 'livery_bay.png')
# The two wall terminals start from the R&D shelf's lower part (in_lterm.png; mirrored for the right wall,
# in_rterm.png), so they keep its angle, skew and edge crop; PixelLab edit_image turned them into terminals
# (e_lterm2.png, e_rterm3.png; the cut-off shelf top fixed in a second edit, a stray fleck dropped).
canvas = Image.new('RGBA', (624, 390)); t = Image.open('e_rterm3.png').convert('RGBA')
canvas.paste(t, (624 - t.width, 340 - t.height), t); canvas.save(A + 'pilot_log.png')
canvas = Image.new('RGBA', (624, 390)); t = Image.open('e_lterm2.png').convert('RGBA'); t = t.crop((0, 0, 64, 86))
canvas.paste(t, (0, 338 - t.height), t); canvas.save(A + 'info_bay.png')
# R&D shelf: the original (old_research_bay.png) with its floating hologram removed by PixelLab (e_rnd.png).
canvas = Image.new('RGBA', (624, 390)); t = Image.open('e_rnd.png').convert('RGBA')
canvas.paste(t, (0, 122), t); canvas.save(A + 'research_bay.png')

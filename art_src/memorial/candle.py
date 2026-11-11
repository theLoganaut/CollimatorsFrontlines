# The Memorial Wall's first trophy, the candle (assets/warroom/memorial/slot_00.png), cleaned up
# (Logan, 2026-11-11: pixel clipping around it): the old slot (old_slot_00.png) carried a flat,
# hard-edged brown glow, a panel seam drawn over it, and bits of the neighbouring trophies' dog-tag
# chains. This keeps only the candle and its holder and gives it a soft glow in see-through bands,
# so the wall shows through. Run from this folder.
from PIL import Image
old = Image.open('old_slot_00.png').convert('RGBA')
GLOW = {(100, 65, 52), (87, 63, 55), (72, 53, 51), (68, 60, 64)}
out = Image.new('RGBA', old.size, (0, 0, 0, 0))
cx, cy = 126.5, 105.0                       # the flame
for r, a in ((30, 34), (24, 48), (18, 64), (12, 82)):       # glow bands, faint outside to warm inside
    for y in range(old.height):
        for x in range(old.width):
            if ((x - cx) ** 2 + ((y - cy) * 1.15) ** 2) ** 0.5 <= r:
                out.putpixel((x, y), (255, 150, 70, a))
glow = out.copy()
out = Image.new('RGBA', old.size, (0, 0, 0, 0))
for y in range(old.height):
    for x in range(old.width):
        p = old.getpixel((x, y))
        if out.getpixel((x, y))[3] == 0:
            out.putpixel((x, y), glow.getpixel((x, y)))
        if not (117 <= x <= 137 and 97 <= y <= 137) or p[3] == 0 or p[:3] in GLOW:
            continue
        if y in (119, 120) and not (120 <= x <= 133):          # the seam, not the candle's outline
            continue
        out.putpixel((x, y), p)
out.save('../../assets/warroom/memorial/slot_00.png')

# collage2.py <scratch dir> <out.png> <angle from vertical> <shiftL> <shiftM> <shiftR>
import sys, math
from PIL import Image, ImageDraw
S, out, ang = sys.argv[1], sys.argv[2], float(sys.argv[3])
sh = [int(v) for v in sys.argv[4:7]]
ims = [Image.open(f"{S}/{n}.png").convert("RGB") for n in ("warroom_left", "warroom_mid", "warroom_right")]
W, H = ims[0].size
TOP = 74
mid_y = (TOP + H) / 2
lean = math.tan(math.radians(ang)) * (H - TOP) / 2
lines = [(c + lean, c - lean) for c in (640, 1280)]  # x at TOP, x at H
def shifted(im, dx):  # room moved right by dx; edges filled from the room itself
    c = Image.new("RGB", (W, H)); c.paste(im, (dx, 0))
    if dx > 0: c.paste(im.crop((0, 0, dx, H)).transpose(Image.FLIP_LEFT_RIGHT), (0, 0))
    if dx < 0: c.paste(im.crop((W + dx, 0, W, H)).transpose(Image.FLIP_LEFT_RIGHT), (W + dx, 0))
    return c
rooms = [shifted(im, d) for im, d in zip(ims, sh)]
img = rooms[0].copy()
big = 4000
m1 = Image.new("L", (W, H), 0); ImageDraw.Draw(m1).polygon([(lines[0][0], TOP), (big, TOP), (big, H), (lines[0][1], H)], fill=255)
m2 = Image.new("L", (W, H), 0); ImageDraw.Draw(m2).polygon([(lines[1][0], TOP), (big, TOP), (big, H), (lines[1][1], H)], fill=255)
img.paste(rooms[1], (0, 0), m1); img.paste(rooms[2], (0, 0), m2)
img.paste(ims[0].crop((0, 0, W, TOP)), (0, 0))  # one top bar
d = ImageDraw.Draw(img)
for a, b in lines:
    d.line([(a, TOP), (b, H)], fill=(8, 14, 20), width=14)
    d.line([(a, TOP), (b, H)], fill=(70, 220, 210), width=6)
img.save(out); print("saved", out, "lean", round(lean))

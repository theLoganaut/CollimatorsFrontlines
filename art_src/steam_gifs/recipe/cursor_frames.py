# cursor_frames.py <frames dir> <mouse log> <out dir> <scale>: copies the film's frames with a cursor drawn on
import sys, os
from PIL import Image, ImageDraw
d, log, out, k = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])
lines = open(log).read().splitlines()
a, b = map(int, lines[0].split()[1:])
mouse = {int(l.split()[0]): list(map(int, l.split()[1:])) for l in lines[1:]}
ARROW = [(0,0),(0,26),(7,20),(12,31),(17,29),(12,18),(21,18)]
os.makedirs(out, exist_ok=True)
for n, f in enumerate(range(a, b + 1)):
    im = Image.open(f"{d}/frame{f-1:08d}.png").convert("RGB")
    x, y, dn = mouse[f]; x *= k; y *= k
    s = 1.15 if dn else 1.3
    pts = [(x + px*s, y + py*s) for px, py in ARROW]
    ImageDraw.Draw(im).polygon(pts, fill=(170, 235, 228) if dn else (240, 244, 244), outline=(8, 12, 16), width=3)
    im.save(f"{out}/frame{n:08d}.png")
print(b - a + 1, "frames")

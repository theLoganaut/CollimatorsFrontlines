# The salvage crates (RewardScreen, SalvageCrate; Logan, 2026-11-11): PixelLab Pro, one per category
# (cand_<category>_<n>.png; picked: hardpoint 1, reactor 0, protocol 1), and their open state made by
# PixelLab Pro Flash edit from each (e_<category>_open.png). Copies them into assets/run/crates/ and
# prints where each lid ends (the lowest row the open art changed), for SalvageCrate.LID_ROWS.
import os, shutil
import numpy as np
from PIL import Image
OUT = '../../assets/run/crates/'
os.makedirs(OUT, exist_ok=True)
for cat in ('hardpoint', 'reactor', 'protocol'):
    shutil.copy(cat + '.png', OUT + cat + '.png')
    shutil.copy('e_%s_open.png' % cat, OUT + cat + '_open.png')
    a = np.asarray(Image.open(cat + '.png').convert('RGBA')).astype(int)
    b = np.asarray(Image.open('e_%s_open.png' % cat).convert('RGBA')).astype(int)
    diff = (np.abs(a - b).sum(axis=2) > 60).sum(axis=1)
    rows = [y for y in range(len(diff)) if diff[y] > 6]
    print(cat, 'lid rows', max(rows) + 1 if rows else 0)

# Emits frontlines_trailer.sketch for `piro sketch`: a ~48 s future-military mech track
# whose sections line up with the trailer pitch (cold open, build, shoot, heat, front, boss, end).
# 150 bpm, 4/4, grid 16: a slot is a 16th = 0.1 s, a bar 1.6 s.
import sys

OUT = sys.argv[1]
BAR = 16
NOTE = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]

def midi(name):  # "D3" -> midi number
    p, o = name[:-1], int(name[-1])
    p = {"Db": "C#", "D#": "Eb", "Gb": "F#", "G#": "Ab", "A#": "Bb"}.get(p, p)
    return NOTE.index(p) + 12 * (o + 1)

def name(m):
    return f"{NOTE[m % 12]}{m // 12 - 1}"

def up(n, semis):
    return name(midi(n) + semis)

# ---------- drums: one char per slot ----------
KIT = {
    "K": ("C4", "vol 15 fade"),   # kick: low letter thuds
    "S": ("E4", "vol 12 fade"),   # snare
    "s": ("E4", "vol 5 fade"),    # ghost snare (march)
    "h": ("B4", "vol 4"),         # closed hat
    "H": ("B4", "vol 8 fade"),    # open hat
    "C": ("B4", "vol 13 fade"),   # crash
    "M": ("E4", "vol 8 fade"),    # march snare, lighter
    "m": ("E4", "vol 3 fade"),    # march ghost
}

def drums(steps):
    """'K.h.S.h.' -> notes; '.' extends the previous hit, '-' at the start is a rest."""
    notes = []
    for ch in steps:
        if ch == ".":
            if notes:
                notes[-1][1] += 1
            else:
                notes.append(["-", 1, ""])
        elif ch == "-":
            if notes and notes[-1][0] == "-":
                notes[-1][1] += 1
            else:
                notes.append(["-", 1, ""])
        else:
            p, fx = KIT[ch]
            notes.append([p, 1, fx])
    for n in notes:  # a fade needs 2+ frames; x1 is 6 frames, fine
        pass
    return notes

def roll(length, v0, v1):
    return [["E4", 1, f"vol {round(v0 + (v1 - v0) * i / (length - 1))}"] for i in range(length)]

# ---------- bass ----------
def gallop(root):
    """The engine: staccato eighths with octave kicks (triangle has no volume, so gaps articulate)."""
    r, o, s = root, up(root, 12), up(root, 10)
    return [[r, 1, ""], ["-", 1, ""], [r, 1, ""], ["-", 1, ""], [o, 2, ""],
            [r, 1, ""], ["-", 1, ""], [r, 1, ""], ["-", 1, ""], [s, 2, ""],
            [r, 1, ""], ["-", 1, ""], [o, 2, ""]]

def march_bass(root):
    return [[root, 2, ""], ["-", 2, ""]] * 2 + [[up(root, 7), 2, ""], ["-", 2, ""], [root, 2, ""], ["-", 2, ""]]

# ---------- chords on pulse2 ----------
MINOR, MAJOR = "arp 0,3,7", "arp 0,4,7"

def stabs(chord, arp, vol=8):
    """Offbeat stabs that decay like a struck chord."""
    out = []
    for _ in range(4):
        out += [["-", 2, ""], [chord, 2, f"{arp} vol {vol} fade"]]
    return out

def eighth_stabs(chord, arp, vol=9):
    out = []
    for _ in range(8):
        out += [[chord, 1, f"{arp} vol {vol} fade"], ["-", 1, ""]]
    return out

# ---------- the hook (pulse1), one bar per chord: Dm Bb C A ----------
HOOK = [
    [["D5", 4, ""], ["A4", 2, ""], ["D5", 2, ""], ["F5", 4, ""], ["E5", 2, ""], ["D5", 2, ""]],
    [["F5", 6, ""], ["D5", 2, ""], ["Bb4", 4, ""], ["C5", 2, ""], ["D5", 2, ""]],
    [["E5", 4, ""], ["C5", 2, ""], ["E5", 2, ""], ["G5", 4, ""], ["F5", 2, ""], ["E5", 2, ""]],
    [["A4", 2, ""], ["C#5", 2, ""], ["E5", 4, ""], ["A5", 6, "vib 35ct 6.667hz 200ms"], ["-", 2, ""]],
]

def echo(notes, delay=2, extra="vol 4 duty 12.5"):
    """The same line `delay` slots late, quieter and thinner, cut to fit the pattern."""
    total = sum(n[1] for n in notes)
    out = [["-", delay, ""]]
    for p, l, fx in notes:
        fx2 = extra if p != "-" else ""
        if p != "-" and "vib" in fx:
            fx2 = extra  # keep the echo plain
        out.append([p, l, fx2])
    # trim the tail back to the pattern length
    over = delay
    while over > 0:
        p, l, fx = out[-1]
        if l <= over:
            out.pop(); over -= l
        else:
            out[-1][1] = l - over; over = 0
            if "fade" in out[-1][2] and out[-1][1] < 2:
                out[-1][2] = out[-1][2].replace("fade", "").strip()
    return out

def flat(bars):
    return [n for b in bars for n in b]

# ---------- patterns ----------
P = {}

# cold open: one impact, then a snare roll and a climbing bass into the build (2 bars)
P["cold"] = {
    "pulse1 duty 25 vol 11": [["D5", 8, f"{MINOR} vol 13 fade"], ["-", 24, ""]],
    "pulse2 duty 50 vol 10": [["D4", 8, "vol 12 fade"], ["-", 8, ""], ["A3", 16, "from D3 vol 7"]],
    "triangle": [["D3", 8, ""], ["-", 8, ""], ["A2", 4, ""], ["Bb2", 4, ""], ["B2", 4, ""], ["C#3", 4, ""]],
    "noise vol 10": [["B4", 8, "vol 14 fade"], ["-", 8, ""]] + roll(16, 3, 15),
}

# build: the engine starts, the mech is assembled (2 bars, played twice)
P["build"] = {
    "pulse1 duty 50 vol 6": [["D4", 16, "vol 7 fade"], ["F4", 16, "vol 7 fade"]],
    "pulse2 duty 25 vol 7": stabs("D4", MINOR, 6) + stabs("D4", MINOR, 7),
    "triangle": gallop("D3") + gallop("D3"),
    "noise vol 6": drums("K.h.h.h.K.h.h.h.") + drums("K.h.h.h.K.h.h.hh"),
}

# build_b: Bb -> A, a rising line pulls into the hook (2 bars)
P["build_b"] = {
    "pulse1 duty 25 vol 7": [["D5", 4, ""], ["F5", 4, ""], ["A5", 4, ""], ["Bb5", 4, ""],
                             ["A5", 8, "vib 35ct 6.667hz 150ms"], ["C#5", 4, "vol 8"], ["E5", 4, "vol 10"]],
    "pulse2 duty 25 vol 7": stabs("Bb3", MAJOR, 6) + stabs("A3", MAJOR, 7),
    "triangle": gallop("Bb2") + gallop("A2"),
    "noise vol 8": drums("K.h.S.h.K.h.S.h.") + drums("K.h.S.h.K.K.") + roll(4, 6, 14),
}

CHORDS = [("D4", MINOR, "D3"), ("Bb3", MAJOR, "Bb2"), ("C4", MAJOR, "C3"), ("A3", MAJOR, "A2")]
SHOOT_DRUMS = ["K.h.S.h.K.K.S.h.", "K.h.S.h.K.K.S.h.", "K.h.S.h.K.K.S.h.", "K.h.S.h.K.KSSSS"]

# shoot: the hook, chords stabbing under it (4 bars)
P["shoot"] = {
    "pulse1 duty 25 vol 8": flat(HOOK),
    "pulse2 duty 25 vol 5": flat(stabs(c, a, 5) for c, a, _ in CHORDS),
    "triangle": flat(gallop(b) for _, _, b in CHORDS),
    "noise vol 7": flat(drums(d.replace("S", "M")) for d in SHOOT_DRUMS[:3]) + drums("K.h.S.h.K.K.") + roll(4, 7, 15),
}

# shoot_b: the same hook, now with the echo trailing it (4 bars)
P["shoot_b"] = {
    "pulse1 duty 25 vol 10": flat(HOOK),
    "pulse2 duty 12.5 vol 4": echo(flat(HOOK)),
    "triangle": flat(gallop(b) for _, _, b in CHORDS),
    "noise vol 9": drums("C.h.S.h.K.K.S.h.") + flat(drums(d) for d in SHOOT_DRUMS[1:3]) + drums("K.h.S.h.K.K.S.S."),
}

# heat: long notes climbing over half-time drums, then the floor drops out (4 bars)
P["heat"] = {
    "pulse1 duty 50 vol 10": [["F5", 16, "vib 35ct 6.667hz 300ms"], ["G5", 16, "vib 35ct 6.667hz 300ms"],
                              ["A5", 16, "vib 40ct 6.667hz 200ms"], ["Bb5", 8, "vol 13 fade"], ["-", 8, ""]],
    "pulse2 duty 25 vol 6": eighth_stabs("Bb3", MAJOR, 6) + eighth_stabs("C4", MAJOR, 7)
                            + eighth_stabs("D4", MINOR, 9) + [["-", 16, ""]],
    "triangle": [["Bb2", 8, ""], ["-", 8, ""], ["C3", 8, ""], ["-", 8, ""], ["D3", 8, ""], ["-", 8, ""],
                 ["D3", 4, ""], ["-", 12, ""]],
    "noise vol 8": drums("K.hhhhhhS.hhhhhh") + drums("K.hhhhhhS.hhhhhh") + drums("K.hhS.hhK.hhS.hh")
                   + roll(8, 4, 15) + [["-", 8, ""]],
}

# front: a march for the locations montage (4 bars)
MARCH_LEAD = [
    [["A4", 3, "vol 10"], ["A4", 1, "vol 6"], ["D5", 4, ""], ["-", 2, ""], ["D5", 2, ""], ["F5", 2, ""], ["A5", 2, ""]],
    [["Bb5", 8, ""], ["A5", 4, ""], ["F5", 4, ""]],
    [["G5", 3, "vol 10"], ["G5", 1, "vol 6"], ["E5", 4, ""], ["C5", 4, ""], ["E5", 4, ""]],
    [["A5", 12, "vib 35ct 6.667hz 200ms"], ["-", 4, ""]],
]
P["front"] = {
    "pulse1 duty 12.5 vol 9": flat(MARCH_LEAD),
    "pulse2 duty 25 vol 6": flat(stabs(c, a, 4) for c, a, _ in [("D4", MINOR, 0), ("Bb3", MAJOR, 0), ("C4", MAJOR, 0), ("A3", MAJOR, 0)]),
    "triangle": flat(march_bass(b) for b in ["D3", "Bb2", "C3", "A2"]),
    "noise vol 9": drums("M.mmm.M.M.mmm.M.") + drums("M.mmm.M.M.mmm.M.") + drums("M.mmm.M.M.mmm.M.")
                   + roll(8, 3, 11) + drums("K.K.") + drums("M.M."),
}

# boss: Phrygian Eb, heavy eighth stabs, a wail on top (4 bars)
BOSS_CHORDS = [("D4", MINOR, "D3"), ("Eb4", MAJOR, "Eb3"), ("D4", MINOR, "D3"), ("A3", MAJOR, "A2")]
P["boss"] = {
    "pulse1 duty 25 vol 11": [["D6", 8, "vib 40ct 6.667hz 150ms"], ["C6", 4, ""], ["Bb5", 4, ""],
                              ["Bb5", 16, "vib 40ct 6.667hz 200ms vol 12"],
                              ["D6", 4, ""], ["F6", 4, ""], ["E6", 4, ""], ["D6", 4, ""],
                              ["C#6", 8, ""], ["E6", 8, "vib 40ct 6.667hz 150ms"]],
    "pulse2 duty 50 vol 9": flat(eighth_stabs(c, a, 10) for c, a, _ in BOSS_CHORDS),
    "triangle": flat(gallop(b) for _, _, b in BOSS_CHORDS),
    "noise vol 10": drums("C.S.K.S.K.KSK.S.") + drums("K.S.K.S.K.KSK.S.") + drums("K.S.K.S.K.KSK.S.")
                    + drums("K.S.K.S.") + roll(8, 8, 15),
}

# end: the hook's head once more, then the final chord fades (2 bars)
P["end"] = {
    "pulse1 duty 25 vol 11": [["D5", 2, ""], ["F5", 2, ""], ["A5", 2, ""], ["D6", 2, ""], ["C#6", 4, ""], ["E6", 4, ""],
                              ["D6", 16, f"{MINOR} vol 13 fade"]],
    "pulse2 duty 50 vol 9": [["A4", 8, ""], ["A4", 8, "vol 6"], ["D5", 16, "vol 11 fade"]],
    "triangle": gallop("A2") + [["D3", 4, ""], ["-", 12, ""]],
    "noise vol 10": drums("K.h.S.h.K.K.S.S.") + [["B4", 16, "vol 14 fade"]],
}

PLAY = ["cold", "build", "build", "build_b", "shoot", "shoot_b", "heat", "front", "boss", "end"]
BARS = {"cold": 2, "build": 2, "build_b": 2, "shoot": 4, "shoot_b": 4, "heat": 4, "front": 4, "boss": 4, "end": 2}

lines = ['song "frontlines" tempo 150 profile nes', "", "play"] + [f"  {p}" for p in PLAY] + [""]
for pname, lanes in P.items():
    lines.append(f"pattern {pname} bars {BARS[pname]} grid 16")
    for lane, notes in lanes.items():
        total = sum(n[1] for n in notes)
        if total != BARS[pname] * BAR:
            print(f"WARN {pname} {lane}: {total} slots, want {BARS[pname] * BAR}")
        lines.append("")
        lines.append(f"lane {lane}")
        for p, l, fx in notes:
            lines.append(f"  {p} x{l} {fx}".rstrip())
    lines.append("")
open(OUT, "w").write("\n".join(lines) + "\n")
print("wrote", OUT)

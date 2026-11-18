# Emits a sketch for `piro sketch`: the trailer track as a military orchestra on the NES chip.
# Same timeline as compose_dark.py plus a 3-bar select section (33 bars, sections on the trailer's cuts), written in D minor.
#   pulse1   = brass: fanfares and horn calls, bright duty 25, no wavering vibrato
#   pulse2   = strings: a driving low ostinato (the "da-da-DUM" of a war march)
#   triangle = timpani: short hits on the beat, rolls into the big moments
#   noise    = snare and bass drum: a marching cadence with rolls
# Held notes end with a quick fade (a release) instead of a hard stop.
# Usage: python compose_war.py <out.sketch> [tempo 120] [transpose -3] [hold 0.72] [release slots 3] [--no-select] [--no-hush]
# With the select section (3 bars after the cold open) and the hush bar (after the drop) it runs 68 s;
# --no-hush gives the 66 s cut, and both flags the original 60 s one.
import re, sys

OUT = sys.argv[1]
TEMPO = int(sys.argv[2]) if len(sys.argv) > 2 else 120
SHIFT = int(sys.argv[3]) if len(sys.argv) > 3 else -3
HOLD = float(sys.argv[4]) if len(sys.argv) > 4 else 0.72
TAIL = int(sys.argv[5]) if len(sys.argv) > 5 else 3
BAR = 16

KIT = {
    "K": ("C4", "vol 15 fade"),   # bass drum
    "S": ("E4", "vol 12 fade"),   # snare
    "s": ("E4", "vol 5 fade"),    # ghost / drag
    "a": ("E4", "vol 9 fade"),    # accent between
    "C": ("B4", "vol 13 fade"),   # crash
    "h": ("B4", "vol 3"),         # light cymbal tick
}

def drums(steps):
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
    return notes

def roll(length, v0, v1):
    return [["E4", 1, f"vol {round(v0 + (v1 - v0) * i / (length - 1))}"] for i in range(length)]

def flat(bars):
    return [n for b in bars for n in b]

NOTES = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
def up(n, semis):
    p, o = n[:-1], int(n[-1])
    m = NOTES.index(p) + 12 * o + semis
    return f"{NOTES[m % 12]}{m // 12}"

# ---------- strings: the ostinato ----------
def ostinato(root, vol=7):
    """Da-da-DUM, four times a bar: two short notes and a longer one, the root with a fifth kick."""
    fifth = up(root, 7)
    out = []
    for i in range(4):
        top = fifth if i == 3 else root
        out += [[root, 1, f"vol {vol}"], [root, 1, f"vol {vol - 2}"], [top, 2, f"vol {vol + 1} fade"]]
    return out

def tremolo(root, vol):
    """Sixteenth notes alternating root and octave: strings sawing away."""
    return [[root if i % 2 == 0 else up(root, 12), 1, f"vol {vol}"] for i in range(16)]

# ---------- timpani ----------
def timp(root, kind="beat"):
    fifth = up(root, -5)  # the fifth below
    if kind == "beat":     # hits on 1 and 3, a pickup into 3
        return [[root, 2, ""], ["-", 4, ""], [root, 1, ""], ["-", 1, ""], [root, 2, ""], ["-", 6, ""]]
    if kind == "drive":    # every beat, root and fifth
        return [[root, 2, ""], ["-", 2, ""], [fifth, 2, ""], ["-", 2, ""], [root, 2, ""], ["-", 2, ""], [fifth, 1, ""], ["-", 1, ""], [root, 1, ""], ["-", 1, ""]]
    if kind == "roll":     # a timpani roll: root and fifth alternating fast
        return [[root if i % 2 == 0 else fifth, 1, ""] for i in range(16)]
    if kind == "one":
        return [[root, 2, ""], ["-", 14, ""]]

MARCH = "K.sSs.S.K.sSs.S."
MARCH_B = "K.sSs.S.K.sSsSSS"

P, BARS = {}, {}

# cold open (0:00): one orchestral hit, then a snare roll and a timpani roll lift into the march
BARS["cold"] = 2
P["cold"] = {
    "pulse1 duty 25 vol 11": [["D4", 10, "arp 0,3,7 vol 12"], ["-", 22, ""]],
    "pulse2 duty 50 vol 8": [["D3", 8, "vol 10"], ["-", 8, ""]] + tremolo("D3", 4)[:8] + tremolo("D3", 6)[:8],
    "triangle": [["D2", 2, ""], ["-", 14, ""]] + timp("D2", "roll"),
    "noise vol 10": [["C4", 1, "vol 15 fade"], ["B4", 12, "vol 13 fade"], ["-", 3, ""]] + roll(16, 3, 14),
}

# select (0:04): the Hangar, one bar per mech. Same band as build but a different texture, so build
# lands as a change: no ostinato and no march. The strings play broken chords in eighths over Bb -> C -> A
# (away from D minor, ending on its dominant), the brass hits one stab per mech swap, the timpani hit
# once a bar, and a light cymbal ticks like a selection screen. The A chord and a short timpani and
# snare pickup resolve into build's D minor ostinato at 0:10.
def broken(r, third, fifth, vol):
    oct_ = up(r, 12)
    return [[n, 2, f"vol {vol}"] for n in [r, third, fifth, oct_, fifth, third, r, third]]

BARS["select"] = 3
P["select"] = {
    "pulse1 duty 25 vol 8": [["D4", 3, "vol 9 fade"], ["-", 13, ""],
                             ["E4", 3, "vol 9 fade"], ["-", 13, ""],
                             ["C#4", 3, "vol 10 fade"], ["-", 9, ""], ["E4", 2, "vol 7 fade"], ["A3", 2, "vol 8 fade"]],
    "pulse2 duty 50 vol 6": broken("Bb2", "D3", "F3", 5) + broken("C3", "E3", "G3", 5) + broken("A2", "C#3", "E3", 6),
    "triangle": timp("Bb1", "one") + timp("C2", "one") + [["A1", 2, ""], ["-", 6, ""]] + timp("A1", "roll")[:8],
    "noise vol 6": drums("K.h.h.h.h.h.h.h.") + drums("K.h.h.h.h.h.h.h.") + drums("K.h.h.h.s.s.SsSS"),
}

# build (0:10 with select, 0:04 without): the strings start the ostinato, timpani mark the beat, the snare marches quietly
BARS["build"] = 2
P["build"] = {
    "pulse2 duty 50 vol 7": ostinato("D3", 6) + ostinato("D3", 7),
    "triangle": timp("D2") + timp("D2"),
    "noise vol 7": drums("K.......K...s.s.") + drums("K.......K.s.s.ss"),
}

# build2 (0:08): a horn call answers over it
BARS["build2"] = 2
P["build2"] = {
    "pulse1 duty 25 vol 9": [["A3", 3, ""], ["A3", 1, "vol 6"], ["D4", 8, ""], ["F4", 4, ""],
                             ["E4", 3, ""], ["D4", 1, ""], ["A3", 12, ""]],
    "pulse2 duty 50 vol 7": ostinato("D3", 7) + ostinato("D3", 8),
    "triangle": timp("D2") + timp("D2", "drive"),
    "noise vol 8": drums(MARCH) + drums(MARCH_B),
}

# rise (0:12): the harmony climbs Bb -> C -> A, snare and timpani roll into the theme
BARS["rise"] = 2
P["rise"] = {
    "pulse1 duty 25 vol 10": [["Bb3", 8, ""], ["C4", 8, ""], ["C#4", 12, "vol 12"], ["E4", 4, ""]],
    "pulse2 duty 50 vol 8": ostinato("Bb2", 8)[:6] + ostinato("C3", 8)[6:] + tremolo("A2", 6),
    "triangle": [["Bb1", 2, ""], ["-", 2, ""], ["F1", 2, ""], ["-", 2, ""], ["C2", 2, ""], ["-", 2, ""], ["G1", 1, ""], ["-", 1, ""], ["C2", 1, ""], ["-", 1, ""]]
                + timp("A1", "roll"),
    "noise vol 9": drums(MARCH) + roll(16, 3, 12),
}

# the theme (0:16): a brass fanfare over Dm, Bb, C, A
THEME = [
    [["D4", 3, ""], ["D4", 1, "vol 7"], ["A4", 4, ""], ["G4", 2, ""], ["F4", 2, ""], ["E4", 2, ""], ["F4", 2, ""]],
    [["D4", 12, ""], ["C4", 2, ""], ["D4", 2, ""]],
    [["E4", 3, ""], ["E4", 1, "vol 7"], ["G4", 4, ""], ["F4", 2, ""], ["E4", 2, ""], ["C4", 2, ""], ["E4", 2, ""]],
    [["C#4", 8, ""], ["E4", 4, ""], ["A4", 4, ""]],
]
ROOTS = [("D3", "D2"), ("Bb2", "Bb1"), ("C3", "C2"), ("A2", "A1")]

BARS["shoot"] = 4
P["shoot"] = {
    "pulse1 duty 25 vol 10": flat(THEME),
    "pulse2 duty 50 vol 7": flat(ostinato(s, 7) for s, _ in ROOTS),
    "triangle": flat(timp(t) for _, t in ROOTS[:3]) + timp("A1", "drive"),
    "noise vol 9": drums("C.sSs.S.K.sSs.S.") + drums(MARCH) + drums(MARCH) + drums(MARCH_B),
}

# the theme again (0:24), an octave up and louder, timpani driving every beat
THEME_UP = [[[p[:-1] + str(int(p[-1]) + 1), l, fx] for p, l, fx in bar] for bar in THEME]
BARS["shoot2"] = 4
P["shoot2"] = {
    "pulse1 duty 25 vol 11": flat(THEME_UP),
    "pulse2 duty 50 vol 8": flat(ostinato(s, 8) for s, _ in ROOTS),
    "triangle": flat(timp(t, "drive") for _, t in ROOTS),
    "noise vol 10": drums("C.sSs.S.K.sSs.S.") + drums("K.sSs.S.K.sSs.S.") + drums(MARCH) + drums("K.sSs.S.") + roll(8, 6, 15),
}

# heat (0:32): strings saw in sixteenths, brass climbs, everything stops at 0:38
BARS["heat"] = 4
P["heat"] = {
    "pulse1 duty 25 vol 10": [["F4", 16, ""], ["G4", 16, ""], ["A4", 12, "vol 10"], ["Bb4", 4, "vol 11"],
                              ["A4", 4, "vol 13 fade"], ["-", 12, ""]],
    "pulse2 duty 50 vol 7": tremolo("Bb2", 6) + tremolo("C3", 7) + tremolo("C#3", 6) + [["D3", 2, "vol 10 fade"], ["-", 14, ""]],
    "triangle": timp("Bb1", "drive") + timp("C2", "drive") + timp("C#2", "roll") + timp("D2", "one"),
    "noise vol 9": drums(MARCH) + drums(MARCH) + roll(16, 2, 11) + [["C4", 1, "vol 15 fade"], ["B4", 6, "vol 12 fade"], ["-", 9, ""]],
}

# hush (0:44 with select): a bar of quiet after the drop while the Operator talks; only a soft
# snare roll on the last beat leads into the march
BARS["hush"] = 1
P["hush"] = {
    "noise vol 6": [["-", 12, ""]] + roll(4, 2, 7),
}

# front (0:40): the march proper, a horn call over a full snare cadence
BARS["front"] = 4
CALL = [
    [["A3", 3, ""], ["A3", 1, "vol 6"], ["D4", 4, ""], ["D4", 3, "vol 8"], ["D4", 1, "vol 6"], ["F4", 4, ""]],
    [["E4", 8, ""], ["D4", 4, ""], ["C4", 4, ""]],
    [["Bb3", 3, ""], ["Bb3", 1, "vol 6"], ["D4", 4, ""], ["G4", 4, ""], ["F4", 4, ""]],
    [["E4", 12, ""], ["A3", 4, ""]],
]
BARS_FRONT = [("D3", "D2"), ("C3", "C2"), ("G2", "G1"), ("A2", "A1")]
P["front"] = {
    "pulse1 duty 25 vol 10": flat(CALL),
    "pulse2 duty 50 vol 6": flat(ostinato(s, 6) for s, _ in BARS_FRONT),
    "triangle": flat(timp(t) for _, t in BARS_FRONT),
    "noise vol 9": drums("K.sSs.S.s.sSs.S.") + drums("K.sSs.S.s.sSs.S.") + drums("K.sSs.S.s.sSs.S.") + drums("K.sSs.S.") + roll(8, 5, 13),
}

# boss (0:48): heaviest, Dm and Eb grinding, brass low and hard, timpani on every beat
BARS["boss"] = 4
BOSS = [("D3", "D2"), ("Eb3", "Eb2"), ("D3", "D2"), ("A2", "A1")]
P["boss"] = {
    "pulse1 duty 25 vol 12": [["D4", 3, ""], ["D4", 1, "vol 8"], ["Eb4", 4, ""], ["D4", 8, ""],
                              ["Eb4", 3, ""], ["Eb4", 1, "vol 8"], ["G4", 4, ""], ["F4", 4, ""], ["Eb4", 4, ""],
                              ["D4", 3, ""], ["D4", 1, "vol 8"], ["F4", 4, ""], ["A4", 8, ""],
                              ["C#4", 8, ""], ["E4", 4, ""], ["A3", 4, ""]],
    "pulse2 duty 50 vol 9": flat(ostinato(s, 9) for s, _ in BOSS),
    "triangle": flat(timp(t, "drive") for _, t in BOSS),
    "noise vol 10": drums("C.KSs.S.K.KSs.S.") + drums("K.KSs.S.K.KSs.S.") + drums("K.KSs.S.K.KSs.S.") + drums("K.KSs.S.") + roll(8, 7, 15),
}

# end (0:56): three tutti hits, then the last chord, timpani and crash, and it rings out
BARS["end"] = 2
P["end"] = {
    "pulse1 duty 25 vol 12": [["D4", 2, "vol 12 fade"], ["-", 2, ""], ["D4", 2, "vol 12 fade"], ["-", 2, ""], ["A3", 2, "vol 12 fade"], ["-", 2, ""],
                              ["C#4", 2, "vol 12 fade"], ["-", 2, ""], ["D4", 14, "arp 0,3,7 vol 13 fade"], ["-", 2, ""]],
    "pulse2 duty 50 vol 9": [["D3", 2, "vol 11 fade"], ["-", 2, ""], ["D3", 2, "vol 11 fade"], ["-", 2, ""], ["A2", 2, "vol 11 fade"], ["-", 2, ""],
                             ["A2", 2, "vol 11 fade"], ["-", 2, ""], ["D3", 14, "vol 12 fade"], ["-", 2, ""]],
    "triangle": [["D2", 2, ""], ["-", 2, ""], ["D2", 2, ""], ["-", 2, ""], ["A1", 2, ""], ["-", 2, ""],
                 ["A1", 1, ""], ["-", 1, ""], ["A1", 1, ""], ["-", 1, ""], ["D2", 2, ""], ["-", 14, ""]],
    "noise vol 10": drums("K...K...K...SSSS") + [["C4", 1, "vol 15 fade"], ["B4", 14, "vol 13 fade"], ["-", 1, ""]],
}

PLAY = ["cold", "select", "build", "build2", "rise", "shoot", "shoot2", "heat", "hush", "front", "boss", "end"]

if "--no-select" in sys.argv:  # without the Hangar section
    PLAY.remove("select")
if "--no-hush" in sys.argv:  # without the quiet bar after the drop
    PLAY.remove("hush")

def lane_vol(lane):
    m = re.search(r"vol (\d+)", lane)
    return int(m.group(1)) if m else 10

def release(lane, notes):
    """Held notes (6+ slots) on the pulses ring HOLD of their length and fade out over their
    last TAIL slots; the rest is silence. Starts never move. The triangle can't fade, so its
    hits are written short already."""
    if not lane.startswith("pulse"):
        return notes
    out = []
    for p, l, fx in notes:
        if p == "-" or l < 6 or "fade" in fx:
            out.append([p, l, fx]); continue
        keep = max(TAIL + 2, round(l * HOLD))
        m = re.search(r"vol (\d+)", fx)
        v = int(m.group(1)) if m else lane_vol(lane)
        arp = re.search(r"arp [\d,]+", fx)
        tail_fx = (arp.group(0) + " " if arp else "") + f"vol {v} fade"
        out += [[p, keep - TAIL, fx], [p, TAIL, tail_fx]]
        if l - keep:
            out.append(["-", l - keep, ""])
    return out

shift = f" {SHIFT:+d}" if SHIFT else ""
lines = [f'song "frontlines (war)" tempo {TEMPO} profile nes', "", "play"] + [f"  {p}{shift}" for p in PLAY] + [""]
for name, lanes in P.items():
    lines.append(f"pattern {name} bars {BARS[name]} grid 16")
    for lane, notes in lanes.items():
        notes = release(lane, notes)
        total = sum(n[1] for n in notes)
        if total != BARS[name] * BAR:
            print(f"WARN {name} {lane}: {total} slots, want {BARS[name] * BAR}")
        lines += ["", f"lane {lane}"] + [f"  {p} x{l} {fx}".rstrip() for p, l, fx in notes]
    lines.append("")
open(OUT, "w").write("\n".join(lines) + "\n")
print("wrote", OUT)

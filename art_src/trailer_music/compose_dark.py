# Emits frontlines_dark.sketch for `piro sketch`: the darker take on the trailer track.
# Same timeline as compose.py (150 bpm, 30 bars, 48 s, sections on the trailer's cuts), but
# half-time drums, long low notes, minor and Phrygian harmony, and a ticking clock under it all.
# Usage: python compose_dark.py <out.sketch> [tempo, default 150] [transpose in semitones, default 0]
#          [hold, default 1.0: held notes (6+ slots, pitched lanes) ring this share of their length]
import sys

OUT = sys.argv[1]
TEMPO = int(sys.argv[2]) if len(sys.argv) > 2 else 150
SHIFT = int(sys.argv[3]) if len(sys.argv) > 3 else 0
HOLD = float(sys.argv[4]) if len(sys.argv) > 4 else 1.0

def release(lane, notes):
    """Cut held notes to HOLD of their length; the rest of the slot is silence, so starts never move."""
    if HOLD >= 1.0 or lane.startswith("noise"):
        return notes
    out = []
    for p, l, fx in notes:
        if p != "-" and l >= 6:
            keep = max(4, round(l * HOLD))
            out += [[p, keep, fx], ["-", l - keep, ""]]
        else:
            out.append([p, l, fx])
    return out
BAR = 16

KIT = {
    "K": ("C4", "vol 15 fade"),   # kick
    "k": ("C4", "vol 9 fade"),    # soft kick (heartbeat)
    "S": ("E4", "vol 11 fade"),   # snare
    "s": ("E4", "vol 3 fade"),    # ghost snare
    "h": ("B4", "vol 3"),         # hat
    "C": ("B4", "vol 12 fade"),   # crash
    "T": ("D4", "vol 12 fade"),   # low tom
}

def drums(steps):
    """One char per slot: a hit, '.' to let it ring on, '-' for silence."""
    notes = []
    for ch in steps:
        if ch == ".":
            if notes and notes[-1][0] != "-":
                notes[-1][1] += 1
            elif notes:
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

def clock(pitches, every=2, vol=4, bars=1):
    """The tick under everything: short, thin notes walking a figure, `every` slots apart."""
    out = []
    n = BAR * bars // every
    for i in range(n):
        out += [[pitches[i % len(pitches)], 1, f"vol {vol} fade" if every > 1 else f"vol {vol}"]]
        if every > 1:
            out += [["-", every - 1, ""]]
    return out

def flat(bars):
    return [n for b in bars for n in b]

def held(*notes):  # [("D2", 16), ...] for the triangle drones
    return [[p, l, ""] for p, l in notes]

P, BARS = {}, {}

# cold open (0:00): one deep impact that hangs, then the clock starts in the dark (2 bars)
BARS["cold"] = 2
P["cold"] = {
    "pulse1 duty 50 vol 10": [["D3", 24, "vol 12 fade"], ["-", 8, ""]],
    "pulse2 duty 12.5 vol 4": [["-", 16, ""]] + clock(["A3", "D4"], 2, 3),
    "triangle": held(("D2", 24)) + [["-", 8, ""]],
    "noise vol 10": [["C4", 2, "vol 15 fade"], ["B4", 22, "vol 11 fade"], ["-", 8, ""]],
}

# build (0:03): heartbeat kick, the clock, a drone grinding D against Eb (2 bars, twice)
BARS["build"] = 2
P["build"] = {
    "pulse2 duty 12.5 vol 4": clock(["D4", "A3", "F3", "A3"], 2, 4, 2),
    "triangle": held(("D2", 16), ("Eb2", 16)),
    "noise vol 8": drums("k..k............") + drums("k..k............"),
}
BARS["build2"] = 2
P["build2"] = {
    "pulse1 duty 50 vol 7": [["A3", 16, "vib 35ct 5hz 400ms"], ["Bb3", 16, "vib 35ct 5hz 400ms"]],
    "pulse2 duty 12.5 vol 4": clock(["D4", "A3", "F3", "A3"], 2, 5, 2),
    "triangle": held(("D2", 16), ("Eb2", 16)),
    "noise vol 8": drums("k..k........s...") + drums("k..k........s.s."),
}

# riser (0:10): the drone climbs a semitone at a time, a roll swells under it (2 bars)
BARS["rise"] = 2
P["rise"] = {
    "pulse1 duty 50 vol 8": [["C4", 16, "vib 35ct 5hz 300ms"], ["C#4", 16, "vib 40ct 6.667hz 200ms vol 10"]],
    "pulse2 duty 12.5 vol 5": clock(["D4", "A3"], 2, 5) + clock(["E4", "A3"], 1, 5),
    "triangle": held(("Eb2", 8), ("E2", 8), ("F2", 8), ("A1", 8)),
    "noise vol 8": drums("k..k....k..k....") + roll(16, 2, 14),
}

# the hook, slow and low (0:13): Dm, Eb, Gm, A. Whole bars, nothing hurries.
HOOK = [
    [["D4", 10, ""], ["F4", 2, ""], ["E4", 4, ""]],
    [["Eb4", 12, "vib 35ct 5hz 300ms"], ["D4", 4, ""]],
    [["G3", 4, ""], ["Bb3", 4, ""], ["D4", 8, "vib 35ct 5hz 200ms"]],
    [["C#4", 12, "vib 40ct 5hz 300ms"], ["-", 4, ""]],
]
ROOTS = ["D2", "Eb2", "G1", "A1"]
TICKS = [["D4", "A3"], ["Eb4", "G3"], ["D4", "Bb3"], ["E4", "C#4"]]
HALF = "K.......S.......", "K.....K.S......."

BARS["shoot"] = 4
P["shoot"] = {
    "pulse1 duty 50 vol 8": flat(HOOK),
    "pulse2 duty 12.5 vol 3": flat(clock(t, 2, 3) for t in TICKS),
    "triangle": held(*[(r, 16) for r in ROOTS]),
    "noise vol 9": drums(HALF[0]) + drums(HALF[1]) + drums(HALF[0]) + drums("K.....K.S...TTTT"),
}

def echo(notes, delay=2, extra="vol 4 duty 12.5"):
    out = [["-", delay, ""]] + [[p, l, extra if p != "-" else ""] for p, l, fx in notes]
    over = delay
    while over > 0:
        if out[-1][1] <= over:
            over -= out.pop()[1]
        else:
            out[-1][1] -= over; over = 0
    return out

# the hook again (0:19), an octave up with a dark echo a beat behind, ghost snares stirring
BARS["shoot2"] = 4
HOOK_UP = [[[p[:-1] + str(int(p[-1]) + 1) if p != "-" else p, l, fx] for p, l, fx in bar] for bar in HOOK]
P["shoot2"] = {
    "pulse1 duty 50 vol 10": flat(HOOK_UP),
    "pulse2 duty 12.5 vol 4": echo(flat(HOOK)),
    "triangle": held(*[(r, 16) for r in ROOTS]),
    "noise vol 9": drums("C.....s.S..s....") + drums("K..s..K.S..s..s.") + drums("K..s....S..s....")
                   + drums("K..s..K.S.") + roll(6, 6, 15),
}

# heat (0:26): the clock doubles, long notes climb, then everything stops at 0:30 (4 bars)
BARS["heat"] = 4
P["heat"] = {
    "pulse1 duty 50 vol 9": [["F4", 16, "vib 35ct 5hz 300ms"], ["G4", 16, "vib 40ct 6.667hz 200ms"],
                             ["A4", 16, "vib 40ct 6.667hz 100ms vol 10"], ["Bb4", 4, "vol 13 fade"], ["-", 12, ""]],
    "pulse2 duty 12.5 vol 5": clock(["D4", "A3"], 1, 4) + clock(["Eb4", "A3"], 1, 5) + clock(["E4", "A3"], 1, 6)
                              + [["-", 16, ""]],
    "triangle": held(("Bb1", 16), ("C2", 16), ("C#2", 16), ("D2", 4)) + [["-", 12, ""]],
    "noise vol 9": drums("K.......S.......") + drums("K...K...S...S...") + roll(16, 3, 12)
                   + [["C4", 2, "vol 15 fade"], ["-", 14, ""]],
}

# front (0:32): a slow funeral march, low brass-like lead (4 bars)
BARS["front"] = 4
MARCH = [
    [["D4", 6, ""], ["D4", 2, "vol 6"], ["F4", 8, ""]],
    [["Eb4", 6, ""], ["D4", 2, ""], ["C4", 8, ""]],
    [["Bb3", 6, ""], ["A3", 2, ""], ["G3", 8, "vib 35ct 5hz 200ms"]],
    [["A3", 12, "vib 40ct 5hz 300ms"], ["-", 4, ""]],
]
P["front"] = {
    "pulse1 duty 50 vol 8": flat(MARCH),
    "pulse2 duty 12.5 vol 4": flat(clock(t, 2, 3) for t in [["D4", "A3"], ["Eb4", "G3"], ["D4", "G3"], ["E4", "A3"]]),
    "triangle": held(("D2", 16), ("C2", 16), ("G1", 16), ("A1", 16)),
    "noise vol 8": drums("S..ss.S.T.......") * 1 + drums("S..ss.S.T.......") + drums("S..ss.S.T.......")
                   + roll(8, 3, 12) + drums("T.T."[:4]) + drums("T..."),
}

# boss (0:38): the heaviest, the D/Eb grind right in the lead, stabs pounding (4 bars)
BARS["boss"] = 4
def stab8(root, arp, vol):
    return flat([[[root, 1, f"arp {arp} vol {vol} fade"], ["-", 1, ""]] for _ in range(8)])
P["boss"] = {
    "pulse1 duty 50 vol 11": [["D4", 8, ""], ["Eb4", 8, "vib 40ct 5hz 200ms"], ["D4", 16, "vib 40ct 6.667hz 300ms"],
                              ["F4", 8, ""], ["Eb4", 8, ""], ["C#4", 16, "vib 40ct 6.667hz 200ms vol 12"]],
    "pulse2 duty 25 vol 8": stab8("D3", "0,3,7", 9) + stab8("Eb3", "0,4,7", 9) + stab8("D3", "0,3,7", 10)
                            + stab8("A2", "0,4,7", 10),
    "triangle": held(("D2", 16), ("Eb2", 16), ("D2", 16), ("A1", 16)),
    "noise vol 10": drums("C.K.S...K.K.S...") + drums("K.K.S...K.K.S...") + drums("K.K.S...K.K.S.s.")
                    + drums("K.K.S...") + roll(8, 7, 15),
}

# end (0:45): one low minor chord fades, the drone lets go, and the clock ticks once more (2 bars)
BARS["end"] = 2
P["end"] = {
    "pulse1 duty 50 vol 11": [["D3", 24, "arp 0,3,7 vol 12 fade"], ["-", 8, ""]],
    "pulse2 duty 12.5 vol 6": [["Eb4", 8, "vol 7 fade"], ["-", 20, ""], ["A3", 1, "vol 4 fade"], ["-", 3, ""]],
    "triangle": held(("D2", 16)) + [["-", 16, ""]],
    "noise vol 10": [["C4", 2, "vol 15 fade"], ["B4", 14, "vol 10 fade"], ["-", 16, ""]],
}

PLAY = ["cold", "build", "build2", "rise", "shoot", "shoot2", "heat", "front", "boss", "end"]

shift = f" {SHIFT:+d}" if SHIFT else ""
lines = [f'song "frontlines (dark)" tempo {TEMPO} profile nes', "", "play"] + [f"  {p}{shift}" for p in PLAY] + [""]
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

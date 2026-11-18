# Trailer

The Steam trailer, made entirely from the game so it can be remade after a patch. The plan,
shot by shot, is the vault note *Frontlines Trailer Edit Plan*. The music is
`art_src/trailer_music/frontlines_war.wav`.

## Needs

- Godot 4.7 at `~/Desktop/Projects/Godot_v4.7-stable_win64_console.exe` (or `$GODOT`)
- ffmpeg on the PATH (`winget install Gyan.FFmpeg`)
- Python 3.10+ with numpy and Pillow (`python -m pip install numpy pillow`)

## Steps

1. **Record** everything (an hour or more; leave the computer alone while it runs):
   `art_src/trailer/record_all.sh`
   It first plays the fights that aren't in `build/trailer/fights/` yet, then records every clip
   to `build/trailer/footage/<name>.mkv` (lossless) with `<name>.events.json` beside it. Redo some
   with `only=heat,refit`.
   **Faster:** `art_src/trailer/record_fast.sh` does the same recording four at a time (Movie Maker
   spends most of its time compressing PNGs on one core), with the mouse-driven refit and heat
   shots alone at the end; it took about 25 minutes instead of 3 hours. It skips the full fight
   replays: record those with `record.sh` (add `--seconds=N` when the trailer only needs the start).
   `EVENTS_ONLY=1 art_src/trailer/record.sh <name> ...` replays a fight without saving frames to
   rewrite just its events; that replay runs about 5 frames behind the recorded video, so shift its
   frames back by 5 (the four logs rebuilt this way carry `"shifted": -5`).
2. **Check** the shot list against the footage: `python art_src/trailer/trailer_edit.py art_src/trailer/shotlist.json --check`
3. **Look** at moments: `... --stills 0.1,16.2,38.0` writes PNGs to `build/trailer/`.
4. **Preview**: `... --preview` (half size, 30 fps, fast), or one stretch with `--from 16 --to 24`.
5. **Render**: `... ` with no flags writes `build/trailer/trailer.mp4` (1080p60, H.264, AAC: Steam's spec).

## The parts

| File | What it does |
|---|---|
| `trailer_rec.gd` | Drives the game for one shot while Movie Maker records (Godot `-s`, so the game's own code is untouched). Hides the Feedback, speed, settings, map and log buttons and the build label. Logs every hit, destroyed part, card, Heat change, turn, click and pan with its frame and screen position. Modes: `replay`, `screen`, `refit`, `heat`, `walls`, `table`. |
| `record.sh` | Records one shot: sets the resolution for that run (a temporary `override.cfg`), runs `trailer_rec.gd` under Movie Maker, encodes the frames to lossless H.264 and deletes them. |
| `record_all.sh` | Every recording `shotlist.json` uses, in order. |
| `record_fast.sh` | The non-fight recordings, four at a time, plus `--events-only=a,b` to rewrite fights' events. |
| `trailer_edit.py` | The editor. It reads `shotlist.json` and builds the video: in-points by event ("the first part destroyed, minus 0.2 s"), speed ramps and freezes, an eased virtual camera (zoom and pan keys, or following the logged hits and clicks), punches and shakes, transitions (cut, flash, fade, dip, pixelize, whip, crt), text cards in the game's font and glass-panel style, and logo overlays. Its docstring documents the format. |
| `shotlist.json` | The trailer itself, as data. Event in-points are first guesses until the footage exists. |

## Resolution

Footage is recorded at 1920x1080, the trailer's own size; the editor's zooms (up to 2×) are
scaled smoothly from that. Sharper zooms need 4K footage (`record_all.sh --res=3840x2160`),
and that only works when Windows itself runs at 4K, e.g. with NVIDIA DSR on a 1080p monitor.
Otherwise the game lays some screens out for the smaller window and the frames come out wrong.

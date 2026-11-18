#!/bin/bash
# Records one trailer shot: runs art_src/trailer/trailer_rec.gd under Godot's Movie Maker,
# then encodes the frames to a lossless video and writes the shot's events beside it.
#   build/trailer/footage/<name>.mkv          lossless RGB H.264 (the editor reads this)
#   build/trailer/footage/<name>.events.json  what happened on which frame (hits, cards, clicks...)
# Usage: art_src/trailer/record.sh <name> --mode=<mode> [--res=1920x1080] [--fps=60] [--seconds=N]
#            [--beat=0.5] [--keep-png] [other --flags for trailer_rec.gd] [positional args]
# Examples (record_all.sh has them all):
#   art_src/trailer/record.sh anchor --mode=replay build/trailer/fights/anchor.json --clean
#   art_src/trailer/record.sh map --mode=screen --seconds=6 map x 99 --store
#   art_src/trailer/record.sh refit --mode=refit refit x 99 --store
# --res above the monitor's own size only works with a desktop that big (NVIDIA DSR / AMD VSR):
# otherwise the game lays some screens out for the smaller window.
# Environment:
#   EVENTS_ONLY=1     play the shot at the same fixed frame rate without saving frames, to rewrite
#                     just <name>.events.json for footage that already exists (same frames, fast)
#   TRAILER_SHARED=1  several record.sh runs at once (record_fast.sh) share one override.cfg,
#                     which the caller removes when they're all done
set -e
cd "$(dirname "$0")/../.."
if [ -z "$GODOT" ]; then
	GODOT=/Applications/Godot.app/Contents/MacOS/Godot
	[ -f "$HOME/Desktop/Projects/Godot_v4.7-stable_win64_console.exe" ] && GODOT="$HOME/Desktop/Projects/Godot_v4.7-stable_win64_console.exe"
fi
command -v ffmpeg > /dev/null || export PATH="$PATH:$LOCALAPPDATA/Microsoft/WinGet/Links"
command -v ffmpeg > /dev/null || { echo "record.sh: needs ffmpeg (winget install Gyan.FFmpeg)"; exit 1; }

NAME="$1"; shift || true
[ -z "$NAME" ] && { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
RES=1920x1080; FPS=60; KEEP=0; PASS=()
for a in "$@"; do
	case "$a" in
		--res=*) RES="${a#--res=}";;
		--fps=*) FPS="${a#--fps=}";;
		--keep-png) KEEP=1;;
		*) PASS+=("$a");;
	esac
done
OUT=build/trailer/footage
TMP="$OUT/.frames_$NAME"
mkdir -p "$OUT"
# an events-only run must never touch the frames folder: a recording of the same shot may be using it
[ "$EVENTS_ONLY" = 1 ] || { rm -rf "$TMP"; mkdir -p "$TMP"; }
EVENTS="$(cd "$OUT" && pwd -W 2>/dev/null || pwd)/$NAME.events.json"

# the resolution, for this run only (the game reads override.cfg at start)
W="${RES%x*}"; H="${RES#*x}"
write_override() {
	printf '[display]\n\nwindow/size/mode=0\nwindow/size/window_width_override=%s\nwindow/size/window_height_override=%s\n' "$W" "$H" > override.cfg
}
if [ "$TRAILER_SHARED" = 1 ]; then
	write_override
else
	if [ -f override.cfg ]; then echo "record.sh: override.cfg already exists; not touching it"; exit 1; fi
	write_override
	trap 'rm -f override.cfg' EXIT
fi

MOVIE=(--write-movie "$TMP/frame.png")
[ "$EVENTS_ONLY" = 1 ] && MOVIE=(--disable-vsync)
echo "record.sh: $NAME at $RES, $FPS fps${EVENTS_ONLY:+ (events only)}..."
START=$(date +%s)
"$GODOT" --path . --fixed-fps "$FPS" "${MOVIE[@]}" \
	-s "$(pwd -W 2>/dev/null || pwd)/art_src/trailer/trailer_rec.gd" -- "--fps=$FPS" "--events=$EVENTS" "${PASS[@]}" 2>&1 \
	| grep -E "trailer_rec|SCRIPT ERROR|^ERROR" | grep -v "BUG: Unreferenced" || true
[ "$TRAILER_SHARED" = 1 ] || rm -f override.cfg
if [ "$EVENTS_ONLY" = 1 ]; then
	[ -f "$OUT/$NAME.events.json" ] || { echo "record.sh: $NAME wrote no events"; exit 1; }
	echo "record.sh: $NAME events ($(( $(date +%s) - START )) s): $OUT/$NAME.events.json"
	exit 0
fi

N=$(ls "$TMP" | grep -c '^frame.*\.png$' || true)
[ "$N" -gt 0 ] || { echo "record.sh: no frames recorded"; exit 1; }
# lossless RGB, so the editor's zooms start from the exact pixels
ffmpeg -y -loglevel error -framerate "$FPS" -i "$TMP/frame%08d.png" \
	-c:v libx264rgb -preset veryfast -crf 0 "$OUT/$NAME.mkv"
[ $KEEP = 1 ] || rm -rf "$TMP"
echo "record.sh: $OUT/$NAME.mkv ($N frames, $(( $(date +%s) - START )) s), events: $OUT/$NAME.events.json"

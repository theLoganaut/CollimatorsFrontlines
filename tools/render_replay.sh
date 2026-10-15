#!/bin/bash
# Renders a recorded fight to video for trailers and clips: the combat
# screen's replay mode under Godot's Movie Maker (frame-perfect at any
# resolution, whatever the machine's speed), then ffmpeg to an H.264 mp4.
# Every run fight is recorded, so any fight a tester played (a playtest
# report, or fight_replay.json from a feedback zip) can be rendered.
# Usage: tools/render_replay.sh <file|latest> [--fight=N] [--res=1920x1080] [--fps=60]
#          [--speed=1.0] [--clean] [--hold=3] [--lossless] [--out=build/clips/<name>.mp4]
#   <file>    a fight record (user://replays/*.json), a playtest report or
#             fight_replay.json (--fight=N: its Nth fight, default the last);
#             "latest" = the newest fight in user://replays
#   --clean   hides the REPLAY strip
#   --lossless renders PNG frames instead of MJPEG (sharpest pixels; a lot
#             of disk while it runs, ~1.5 MB a frame at 1080p)
# Needs a window (not --headless). Don't worry about the mouse: the render
# ignores it.
cd "$(dirname "$0")/.."
if [ -z "$GODOT" ]; then
	GODOT=/Applications/Godot.app/Contents/MacOS/Godot
	[ -f "$HOME/Desktop/Projects/Godot_v4.7-stable_win64_console.exe" ] && GODOT="$HOME/Desktop/Projects/Godot_v4.7-stable_win64_console.exe"
fi
case "$(uname -s)" in
	Darwin) USERDIR="$HOME/Library/Application Support/Godot/app_userdata/Collimators- Frontlines";;
	MINGW*|MSYS*) USERDIR="$APPDATA/Godot/app_userdata/Collimators- Frontlines";;
	*) USERDIR="$HOME/.local/share/godot/app_userdata/Collimators- Frontlines";;
esac

FILE=""; RES=1920x1080; FPS=60; OUT=""; LOSSLESS=0; PASS=()
for a in "$@"; do
	case "$a" in
		--res=*) RES="${a#--res=}";;
		--fps=*) FPS="${a#--fps=}";;
		--out=*) OUT="${a#--out=}";;
		--lossless) LOSSLESS=1;;
		--*) PASS+=("$a");;
		*) FILE="$a";;
	esac
done
if [ -z "$FILE" ]; then sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 2; fi
if [ "$FILE" = latest ]; then
	FILE="$USERDIR/replays/$(ls "$USERDIR/replays" | grep '\.json$' | sort | tail -1)"
fi
[ -f "$FILE" ] || { echo "no file: $FILE"; exit 1; }
FILE="$(cd "$(dirname "$FILE")" && pwd)/$(basename "$FILE")"
NAME="$(basename "$FILE" .json)"
[ -z "$OUT" ] && OUT="build/clips/$NAME.mp4"
mkdir -p "$(dirname "$OUT")"
TMP="build/clips/.render_$NAME"
rm -rf "$TMP"; mkdir -p "$TMP"
if [ $LOSSLESS = 1 ]; then MOVIE="$TMP/frame.png"; else MOVIE="$TMP/render.avi"; fi

# Movie Maker records at the window size override, not --resolution: set it
# for this render only (override.cfg, removed again however the render ends)
W="${RES%x*}"; H="${RES#*x}"
printf '[display]\n\nwindow/size/mode=0\nwindow/size/window_width_override=%s\nwindow/size/window_height_override=%s\n' "$W" "$H" > override.cfg
trap 'rm -f override.cfg' EXIT
echo "rendering $NAME at $RES, $FPS fps..."
"$GODOT" --path . --fixed-fps "$FPS" --write-movie "$MOVIE" \
	res://tools/RenderReplay.tscn -- "$FILE" "${PASS[@]}" 2>&1 | grep -E "render_replay|ERROR|SCRIPT"

if ! command -v ffmpeg > /dev/null; then
	echo "no ffmpeg: the raw render is in $TMP"; exit 0
fi
# x264 at a low CRF keeps pixel-art edges crisp; yuv420p so every player and site takes it
if [ $LOSSLESS = 1 ]; then
	ffmpeg -y -loglevel error -framerate "$FPS" -i "$TMP/frame%08d.png" -i "$TMP/frame.wav" \
		-c:v libx264 -preset slow -crf 14 -pix_fmt yuv420p -c:a aac -b:a 192k -shortest "$OUT"
else
	ffmpeg -y -loglevel error -i "$MOVIE" -c:v libx264 -preset slow -crf 14 -pix_fmt yuv420p -c:a aac -b:a 192k "$OUT"
fi && rm -rf "$TMP" && echo "wrote $OUT"

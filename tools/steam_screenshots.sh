#!/bin/bash
# The Steam page's screenshots, made again from tools/Screenshot.tscn with --store
# (no Feedback buttons or build label). Order = the order on the store page: the
# first is a fight in progress with a card aimed at a part.
# Usage: tools/steam_screenshots.sh [out folder, default art_src/steam_screenshots] [only=NN_name]
# Needs a window (not --headless); shots are the screen's size (1920x1080 on a 1080p
# display, which is what Steam wants).
cd "$(dirname "$0")/.."
if [ -z "$GODOT" ]; then
	GODOT=/Applications/Godot.app/Contents/MacOS/Godot
	[ -f "$HOME/Desktop/Projects/Godot_v4.7-stable_win64_console.exe" ] && GODOT="$HOME/Desktop/Projects/Godot_v4.7-stable_win64_console.exe"
fi
OUT="${1:-art_src/steam_screenshots}"
ONLY="${2#only=}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd -W 2>/dev/null || pwd)"

shot() { # name, then Screenshot.tscn's arguments after the out path
	local name="$1" what="$2"; shift 2
	[ -n "$ONLY" ] && [ "$ONLY" != "$name" ] && return
	"$GODOT" --path . res://tools/Screenshot.tscn -- "$what" "$OUT/$name.png" "$@" --store 2>&1 | grep -E "^saved|ERROR" || echo "$name: no output"
}

shot 01_combat_aim     combat_preview 9 --location=shipyard --enemies=scrap_warden,rivet_brute
shot 02_boss_anchor    combat 9 --location=shipyard --enemies=anchor
shot 03_combat_mining  combat 9 --location=mining_grounds
shot 04_refit          refit 3
shot 05_location_map   map 3
shot 06_war_table      popup 3
shot 07_autonomous_bay shop 3
shot 08_hangar         hub_hangar 3
shot 09_event          event 3
shot 10_war_room       warroom 3

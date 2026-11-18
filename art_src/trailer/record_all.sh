#!/bin/bash
# Records every piece of footage the trailer's shot list uses (art_src/trailer/shotlist.json),
# in two passes. Plays the fights that don't exist yet, then records each shot with record.sh.
# It's long (an hour or more at 1080p60): run it and leave the computer alone, since Movie Maker
# takes over the game window and parks the mouse.
# Usage: art_src/trailer/record_all.sh [--res=1920x1080] [only=<name>[,<name>...]] [--refights]
#   only=     record just these (e.g. only=heat,refit after a change)
#   --refights  play the fights again even if build/trailer/fights/<name>.json exists
cd "$(dirname "$0")/../.."
if [ -z "$GODOT" ]; then
	GODOT=/Applications/Godot.app/Contents/MacOS/Godot
	[ -f "$HOME/Desktop/Projects/Godot_v4.7-stable_win64_console.exe" ] && GODOT="$HOME/Desktop/Projects/Godot_v4.7-stable_win64_console.exe"
fi
RES=""; ONLY=""; REFIGHT=0
for a in "$@"; do
	case "$a" in
		--res=*) RES="$a";;
		only=*) ONLY=",${a#only=},";;
		--refights) REFIGHT=1;;
	esac
done
want() { [ -z "$ONLY" ] || [[ "$ONLY" == *",$1,"* ]]; }
FIGHTS=build/trailer/fights
mkdir -p "$FIGHTS"
FDIR="$(cd "$FIGHTS" && pwd -W 2>/dev/null || pwd)"

# ---------- pass 1: the fights (played by the screenshot tool's bot, at 3x, recorded as commands) ----------
fight() { # name, location, enemies, [player mech]
	local name="$1" loc="$2" enemies="$3" mech="${4:-bastion}"
	want "$name" || return 0
	if [ -f "$FIGHTS/$name.json" ] && [ $REFIGHT = 0 ]; then echo "fight $name: have it"; return 0; fi
	"$GODOT" --path . res://tools/Screenshot.tscn -- combat_record "$FDIR/$name.png" 15 \
		"--location=$loc" "--enemies=$enemies" "--mech=$mech" --store 2>&1 | grep -E "^combat_record" || echo "fight $name: no record"
	[ -f "$FIGHTS/$name.png.json" ] && mv "$FIGHTS/$name.png.json" "$FIGHTS/$name.json"
	rm -f "$FIGHTS/$name.png"
}
fight anchor        shipyard        anchor
fight shipyard_pair shipyard        scrap_warden,rivet_brute
fight mining        mining_grounds  ember_hound,rivet_brute
fight archives      data_archives   arc_sentry,arc_sentry
fight triple        shipyard        scrap_warden,needle_drone,needle_drone
fight cipher        data_archives   cipher
fight bedrock       mining_grounds  bedrock
fight redline       shipyard        scrap_warden,rivet_brute  redline
fight jackal        data_archives   arc_sentry,arc_sentry     jackal

# ---------- pass 2: the footage ----------
rec() { # name, then record.sh's arguments
	local name="$1"; shift
	want "$name" || return 0
	art_src/trailer/record.sh "$name" $RES "$@"
}
# fights, replayed from their records (the whole fight; the editor picks the moments by event)
for f in anchor shipyard_pair mining archives triple cipher bedrock redline; do
	rec "$f" --mode=replay "$FDIR/$f.json" --clean
done
# scripted scenes
rec jackal --mode=replay --seconds=40 "$FDIR/jackal.json" --clean
rec refit  --mode=refit refit x 99 --store
rec hangar_swap --mode=hangar hub_hangar x 99 --store
rec operator --mode=operator --hold=1.5 "--line=You think you can quit now? That's not your decision to make, people are counting on you."
rec heat   --mode=heat  combat x 99 --store --location=shipyard --enemies=scrap_warden,rivet_brute
rec aim    --mode=screen --seconds=6 combat_preview x 99 --store --location=shipyard --enemies=scrap_warden,rivet_brute
rec opening --mode=screen --seconds=8 combat_reveal x 99 --store --location=shipyard --enemies=scrap_warden,rivet_brute
# the War Room and the run's screens
rec walls  --mode=walls
rec table  --mode=table
rec map    --mode=screen --seconds=6 map x 99 --store
rec event  --mode=screen --seconds=5 event x 99 --store
rec shop   --mode=screen --seconds=5 shop x 99 --store
rec hangar --mode=screen --seconds=6 hub_hangar x 99 --store
echo "record_all: done. Footage in build/trailer/footage/"

#!/bin/bash
# record_all.sh's pass 2, several shots at once. Movie Maker spends most of its time compressing
# each frame to PNG on one CPU core, so four games recording side by side finish about four
# times sooner, with identical frames. Shots that drive the mouse (refit, heat) still run alone
# at the end. Fights must already be played (record_all.sh's pass 1).
# Usage: art_src/trailer/record_fast.sh [--jobs=4] [--res=1920x1080] [only=a,b] [--events-only=a,b]
#   --events-only  re-plays those fights without saving frames, just to rewrite their events
set -e
cd "$(dirname "$0")/../.."
REC="${REC:-art_src/trailer/record.sh}"
JOBS=4; RES=--res=1920x1080; ONLY=""; EVONLY=""
for a in "$@"; do
	case "$a" in
		--jobs=*) JOBS="${a#--jobs=}";;
		--res=*) RES="$a";;
		only=*) ONLY=",${a#only=},";;
		--events-only=*) EVONLY="${a#--events-only=}";;
	esac
done
want() { [ -z "$ONLY" ] || [[ "$ONLY" == *",$1,"* ]]; }
FDIR="$(pwd -W 2>/dev/null || pwd)/build/trailer/fights"
if [ -f override.cfg ] && ! ps -ef | grep -q "[r]ecord.sh"; then
	echo "record_fast: override.cfg already exists; not touching it"; exit 1
fi
export TRAILER_SHARED=1
trap 'rm -f override.cfg' EXIT
FAIL=0

job() { # name, then record.sh's arguments; runs in the background, at most $JOBS at once
	want "$1" || return 0
	while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n || FAIL=1; done
	"$REC" "$@" $RES &
	sleep 3 # let each game open its window before the next starts
}
solo() {
	want "$1" || return 0
	wait || FAIL=1
	# and no other game at all (one started elsewhere would park the mouse every frame)
	while tasklist 2>/dev/null | grep -qi "^Godot"; do sleep 5; done
	"$REC" "$@" $RES || FAIL=1
}

for f in ${EVONLY//,/ }; do
	EVENTS_ONLY=1 job "$f" --mode=replay "$FDIR/$f.json" --clean
done
# the bosses only appear in the trailer for their opening second
job cipher  --mode=replay --seconds=5 "$FDIR/cipher.json" --clean
job bedrock --mode=replay --seconds=5 "$FDIR/bedrock.json" --clean
job aim     --mode=screen --seconds=6 combat_preview x 99 --store --location=shipyard --enemies=scrap_warden,rivet_brute
job opening --mode=screen --seconds=8 combat_reveal x 99 --store --location=shipyard --enemies=scrap_warden,rivet_brute
job walls   --mode=walls
job table   --mode=table
job map     --mode=screen --seconds=6 map x 99 --store
job event   --mode=screen --seconds=5 event x 99 --store
job shop    --mode=screen --seconds=5 shop x 99 --store
job hangar  --mode=screen --seconds=6 hub_hangar x 99 --store
# these move the mouse themselves, so nothing else runs beside them
solo refit --mode=refit refit x 99 --store
solo heat  --mode=heat  combat x 99 --store --location=shipyard --enemies=scrap_warden,rivet_brute
wait || FAIL=1
echo "record_fast: done$([ $FAIL = 1 ] && echo ', with failures (see above)'). Footage in build/trailer/footage/"

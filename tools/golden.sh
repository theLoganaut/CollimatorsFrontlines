#!/bin/bash
# Golden master for refactors: plays a fixed set of seeded runs (every
# mission × bot) with the balance sim's --trace, and records or checks the
# trace (every combat signal, each mech's state after every turn, the run's
# state after every step). A behaviour-preserving change must leave it
# identical. Rerecord after any intended change to rules, data or the bots.
# Usage: tools/golden.sh record|check [runs per mission per bot, default 6]
cd "$(dirname "$0")/.."
GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
N=${2:-6}
GOLDEN=tests/golden/trace_$N.txt
OUT=$(mktemp -t golden.XXXXXX)
command -v cygpath > /dev/null && OUT=$(cygpath -m "$OUT") # Git Bash: a path Godot can open
mkdir -p tests/golden
"$GODOT" --headless --path . -s tools/balance_sim.gd -- "$N" --orders=none --events=first --variants=none --trace="$OUT" > /dev/null 2>&1
case "$1" in
	record)
		cp "$OUT" "$GOLDEN"
		echo "recorded $GOLDEN ($(wc -l < "$GOLDEN" | tr -d ' ') lines)";;
	check)
		if [ ! -f "$GOLDEN" ]; then echo "no $GOLDEN: run tools/golden.sh record $N first"; exit 1; fi
		if cmp -s "$OUT" "$GOLDEN"; then
			echo "golden: identical ($(wc -l < "$GOLDEN" | tr -d ' ') lines)"
		else
			echo "golden: DIFFERENT; first differences:"
			diff "$GOLDEN" "$OUT" | head -20
			exit 1
		fi;;
	*) echo "usage: tools/golden.sh record|check [runs]"; exit 2;;
esac

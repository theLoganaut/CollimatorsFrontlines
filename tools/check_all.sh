#!/bin/bash
# Everything that should pass before a commit: the headless tests, the data
# validator, and a quick balance sim smoke run (a handful of runs per bot,
# only checked for crashes, not for numbers).
# Usage: tools/check_all.sh [sim runs, default 5]
cd "$(dirname "$0")/.."
GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
fail=0
echo "== tests"
"$GODOT" --headless --path . -s tests/run_tests.gd 2>&1 | grep -v "^Godot Engine" | grep -v "^$" | tail -20 || true
"$GODOT" --headless --path . -s tests/run_tests.gd > /dev/null 2>&1 || fail=1
echo "== data"
"$GODOT" --headless --path . -s tools/validate_data.gd 2>&1 | grep -v "^Godot Engine" | grep -v "^$" || true
"$GODOT" --headless --path . -s tools/validate_data.gd > /dev/null 2>&1 || fail=1
echo "== sim smoke"
out=$("$GODOT" --headless --path . -s tools/balance_sim.gd -- "${1:-5}" 2>&1)
if echo "$out" | grep -q "SCRIPT ERROR\|Parse Error"; then
	echo "$out" | grep -A3 "SCRIPT ERROR\|Parse Error" | head -20
	fail=1
else
	echo "ok ($(echo "$out" | grep -c "clear") mission × bot lines)"
fi
[ $fail -eq 0 ] && echo "== ALL GREEN" || echo "== FAILED"
exit $fail

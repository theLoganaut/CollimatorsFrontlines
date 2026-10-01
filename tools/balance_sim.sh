#!/bin/bash
# Balance sim: whole runs of every mission with four bots.
# Usage: tools/balance_sim.sh [runs per mission per bot, default 150] [--report] [--set=section.key=value] [--mech=id.key=value]
#        [--pilot=id] [--orders=random|none|id] [--events=random|first] [--seed-start=n] [--sweeps=k] (options: tools/balance_sim.gd)
cd "$(dirname "$0")/.."
GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
"$GODOT" --headless --path . -s tools/balance_sim.gd -- "${1:-150}" "${@:2}" 2>&1 | grep -v "^Godot Engine" | grep -v "^$"

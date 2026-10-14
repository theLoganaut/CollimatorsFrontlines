#!/usr/bin/env bash
# Ships what's on main: pushes it to GitHub (which runs the build check),
# then builds it and uploads it to Steam from this Mac (tools/steam_release.sh,
# with SteamCMD's saved login here).
#
#   tools/ship.sh                  push main (and tags), export, upload
#   tools/ship.sh --desc "text"    any tools/steam_release.sh option passes through
#
# Stops before pushing if you're not on main, have uncommitted changes, or
# main has commits on GitHub you don't have yet. Afterwards, set the build
# live on Steamworks' Builds page (the link is printed).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

branch="$(git rev-parse --abbrev-ref HEAD)"
[[ "$branch" == "main" ]] || { echo "You're on '$branch'. Switch to main first (git checkout main)." >&2; exit 1; }
if [[ -n "$(git status --porcelain)" ]]; then
	echo "Uncommitted changes. Commit them first (the build should match what's on GitHub):" >&2
	git status --short >&2
	exit 1
fi

echo "== Pushing main to GitHub"
git fetch -q origin main
if ! git merge-base --is-ancestor origin/main HEAD; then
	echo "GitHub's main has commits you don't have. Pull first (git pull --rebase), then ship again." >&2
	exit 1
fi
git push --follow-tags origin main

echo "== Building and uploading $(git rev-parse --short HEAD) to Steam"
exec "$ROOT/tools/steam_release.sh" "$@"

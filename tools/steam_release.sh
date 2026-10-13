#!/usr/bin/env bash
# Builds the game and uploads it to Steam (live on $BRANCH if set; see tools/steam/config.sh).
#
#   tools/steam_release.sh                 export, upload (and set live on $BRANCH if set)
#   tools/steam_release.sh --desc "text"   build description shown in Steamworks
#   tools/steam_release.sh --branch NAME   set live on another branch ("" = upload only)
#   tools/steam_release.sh --preview       export and dry-run the upload (nothing sent)
#   tools/steam_release.sh --no-upload     export only (build/steam/)
#   tools/steam_release.sh --login         one-time SteamCMD login (password + Steam Guard;
#                                          run it yourself in a terminal, it's cached after)
#
# Settings: tools/steam/config.sh. Output and logs: build/steam/.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tools/steam/config.sh"

DESC=""
PREVIEW=0
UPLOAD=1
LOGIN=0
while [[ $# -gt 0 ]]; do
	case "$1" in
		--desc) DESC="$2"; shift 2 ;;
		--branch) BRANCH="$2"; shift 2 ;;
		--preview) PREVIEW=1; shift ;;
		--no-upload) UPLOAD=0; shift ;;
		--login) LOGIN=1; shift ;;
		*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
done

if [[ $LOGIN == 1 || $UPLOAD == 1 ]]; then
	[[ -n "$STEAM_USER" ]] || { echo "Set STEAM_USER in tools/steam/config.sh first." >&2; exit 1; }
	# Unzipping the SDK drops the executable bit; put it back.
	[[ -f "$STEAMCMD" && ! -x "$STEAMCMD" ]] && chmod u+x "$STEAMCMD" "$(dirname "$STEAMCMD")/steamcmd"
	[[ -x "$STEAMCMD" ]] || { echo "SteamCMD not found at $STEAMCMD (tools/steam/config.sh)." >&2; exit 1; }
fi
if [[ $LOGIN == 1 ]]; then
	"$STEAMCMD" +login "$STEAM_USER" +quit
	exit $?
fi

OUT="$ROOT/build/steam"
COMMIT="$(git -C "$ROOT" rev-parse --short HEAD)"
DIRTY="$(git -C "$ROOT" status --porcelain | head -1)"
STAMP="$(date '+%Y-%m-%d %H:%M')"
[[ -n "$DIRTY" ]] && COMMIT="$COMMIT+local changes"
[[ -n "$DESC" ]] || DESC="$STAMP ($COMMIT)"

echo "== Exporting ($DESC)"
rm -rf "$OUT/windows" "$OUT/macos"
mkdir -p "$OUT/windows" "$OUT/logs"
"$GODOT" --headless --path "$ROOT" --export-release "Windows" "$OUT/windows/CollimatorsFrontlines.exe" > "$OUT/logs/export_windows.log" 2>&1 \
	|| { echo "Windows export failed, see $OUT/logs/export_windows.log" >&2; exit 1; }
[[ -f "$OUT/windows/CollimatorsFrontlines.exe" ]] || { echo "Windows export made no .exe, see $OUT/logs/export_windows.log" >&2; exit 1; }
[[ -f "$OUT/windows/steam_api64.dll" ]] || { echo "steam_api64.dll is missing from the Windows build" >&2; exit 1; }
if [[ -n "$DEPOT_MACOS" ]]; then
	mkdir -p "$OUT/macos"
	"$GODOT" --headless --path "$ROOT" --export-release "macOS" "$OUT/macos/Collimators Frontlines.app" > "$OUT/logs/export_macos.log" 2>&1 \
		|| { echo "macOS export failed, see $OUT/logs/export_macos.log" >&2; exit 1; }
fi
ls -la "$OUT/windows"

[[ $UPLOAD == 1 ]] || { echo "== Exported to $OUT (no upload)"; exit 0; }

# The app build script, written fresh each time (SetLive, description).
VDF="$OUT/app_build.vdf"
{
	echo '"AppBuild"'
	echo '{'
	echo "	\"AppID\" \"$APP_ID\""
	echo "	\"Desc\" \"${DESC//\"/\'}\""
	echo "	\"Preview\" \"$PREVIEW\""
	echo "	\"SetLive\" \"$BRANCH\""
	echo "	\"ContentRoot\" \"$OUT\""
	echo "	\"BuildOutput\" \"$OUT/output\""
	echo '	"Depots"'
	echo '	{'
	echo "		\"$DEPOT_WINDOWS\" { \"FileMapping\" { \"LocalPath\" \"windows/*\" \"DepotPath\" \".\" \"Recursive\" \"1\" } }"
	[[ -n "$DEPOT_MACOS" ]] && echo "		\"$DEPOT_MACOS\" { \"FileMapping\" { \"LocalPath\" \"macos/*\" \"DepotPath\" \".\" \"Recursive\" \"1\" } }"
	echo '	}'
	echo '}'
} > "$VDF"

echo "== Uploading to Steam (app $APP_ID, branch '${BRANCH:-none}'$([[ $PREVIEW == 1 ]] && echo ", preview only"))"
LOG="$OUT/logs/upload.log"
set +e
"$STEAMCMD" +login "$STEAM_USER" +run_app_build "$VDF" +quit 2>&1 | tee "$LOG"
set -e
if grep -q "Successfully finished AppID $APP_ID build" "$LOG"; then
	BUILD_ID="$(grep -oE 'BuildID [0-9]+' "$LOG" | tail -1)"
	if [[ -n "$BRANCH" ]]; then
		echo "== Done: $BUILD_ID, live on '$BRANCH'. Testers on that branch get it next time Steam updates."
	else
		echo "== Done: $BUILD_ID uploaded. Set it live: https://partner.steamgames.com/apps/builds/$APP_ID"
		echo "   (find $BUILD_ID, 'Set build live on branch' -> default -> Preview Change -> Set Build Live Now)"
	fi
else
	if grep -qiE "Two-factor|Steam Guard|password|Login Failure|Cached credentials not found" "$LOG"; then
		echo "== Upload failed: SteamCMD needs you to log in. Run: tools/steam_release.sh --login" >&2
	else
		echo "== Upload failed, see $LOG" >&2
	fi
	exit 1
fi

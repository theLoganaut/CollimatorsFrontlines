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
# Stamped into the build for the game to show (BuildInfo); only there while exporting.
printf '{"stamp": "%s", "commit": "%s", "feedback_webhook": "%s"}\n' "$STAMP" "$COMMIT" "${FEEDBACK_WEBHOOK:-}" > "$ROOT/build_info.json"
trap 'rm -f "$ROOT/build_info.json"' EXIT
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

# The app build script for one app, written fresh each time (SetLive, description).
write_vdf() { # app_id windows_depot mac_depot vdf_path
	{
		echo '"AppBuild"'
		echo '{'
		echo "	\"AppID\" \"$1\""
		echo "	\"Desc\" \"${DESC//\"/\'}\""
		echo "	\"Preview\" \"$PREVIEW\""
		echo "	\"SetLive\" \"$BRANCH\""
		echo "	\"ContentRoot\" \"$OUT\""
		echo "	\"BuildOutput\" \"$OUT/output\""
		echo '	"Depots"'
		echo '	{'
		echo "		\"$2\" { \"FileMapping\" { \"LocalPath\" \"windows/*\" \"DepotPath\" \".\" \"Recursive\" \"1\" } }"
		[[ -n "$3" ]] && echo "		\"$3\" { \"FileMapping\" { \"LocalPath\" \"macos/*\" \"DepotPath\" \".\" \"Recursive\" \"1\" } }"
		echo '	}'
		echo '}'
	} > "$4"
}

ARGS=(+login "$STEAM_USER")
write_vdf "$APP_ID" "$DEPOT_WINDOWS" "$DEPOT_MACOS" "$OUT/app_build.vdf"
ARGS+=(+run_app_build "$OUT/app_build.vdf")
APPS=("$APP_ID")
if [[ -n "$PLAYTEST_APP_ID" && -n "$PLAYTEST_DEPOT" ]]; then
	write_vdf "$PLAYTEST_APP_ID" "$PLAYTEST_DEPOT" "" "$OUT/app_build_playtest.vdf"
	ARGS+=(+run_app_build "$OUT/app_build_playtest.vdf")
	APPS+=("$PLAYTEST_APP_ID")
fi
ARGS+=(+quit)

echo "== Uploading to Steam (apps ${APPS[*]}, branch '${BRANCH:-none}'$([[ $PREVIEW == 1 ]] && echo ", preview only"))"
LOG="$OUT/logs/upload.log"
set +e
"$STEAMCMD" "${ARGS[@]}" 2>&1 | tee "$LOG"
set -e
FAILED=0
for app in "${APPS[@]}"; do
	if line="$(grep -E "Successfully finished AppID $app build" "$LOG" | tail -1)"; then
		BUILD_ID="$(echo "$line" | grep -oE 'BuildID [0-9]+' || true)"
		if [[ $PREVIEW == 1 ]]; then
			echo "== App $app: preview OK (nothing uploaded)."
		elif [[ -n "$BRANCH" ]]; then
			echo "== App $app: $BUILD_ID, live on '$BRANCH'."
		else
			echo "== App $app: $BUILD_ID uploaded. Set it live: https://partner.steamgames.com/apps/builds/$app"
			echo "   (find $BUILD_ID, 'Set build live on branch' -> default -> Preview Change -> Set Build Live Now)"
		fi
	else
		FAILED=1
		echo "== App $app: upload failed." >&2
	fi
done
if [[ $FAILED == 1 ]]; then
	if grep -qiE "Two-factor|Steam Guard|password|Login Failure|Cached credentials not found" "$LOG"; then
		echo "== SteamCMD needs you to log in. Run: tools/steam_release.sh --login" >&2
	else
		echo "== See $LOG" >&2
	fi
	exit 1
fi

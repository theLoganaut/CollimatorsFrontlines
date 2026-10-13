# Steam upload settings for tools/steam_release.sh. No passwords here: SteamCMD
# keeps its own login after the one-time `tools/steam_release.sh --login`.

# The Steam account that uploads builds (a Steamworks account with build rights for the app).
STEAM_USER="lyle20222"

APP_ID=5441720
# Depot IDs from Steamworks (App Admin -> SteamPipe -> Depots). A new app's first
# depot is usually the App ID + 1; check it there. Leave the macOS one empty to skip it.
DEPOT_WINDOWS=5441721
DEPOT_MACOS=""

# The branch a new build goes live on. "" = upload only: one branch (default), and you set
# each build live in Steamworks (SteamPipe -> Builds), since SteamCMD can't set the default
# branch live; Valve only allows that on the website. A beta branch name here (e.g.
# "testers") makes uploads go live by themselves, but testers must opt into it once.
BRANCH=""

# Tools: SteamCMD from the Steamworks SDK, and the Godot editor.
STEAMCMD="$HOME/Downloads/sdk/tools/ContentBuilder/builder_osx/steamcmd.sh"
GODOT="/Applications/Godot.app/Contents/MacOS/Godot"

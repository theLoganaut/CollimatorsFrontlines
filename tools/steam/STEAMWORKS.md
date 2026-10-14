# Steamworks setup (partner.steamgames.com, app 5441720)

The game side of each of these is built; these are the settings on Steam's
side. Publish the changes (Publish tab) after editing.

## Steam Cloud (App Admin → Steam Cloud)

Saves live in Godot's user folder. Godot turns the colon in the project name
into a dash, so the folder is `Collimators- Frontlines`.

- Byte quota per user: 50 MB · Number of files allowed per user: 100
- Auto-Cloud root paths:

| Root | Subdirectory | Pattern | OS |
|---|---|---|---|
| WinAppDataRoaming | `Godot/app_userdata/Collimators- Frontlines` | `profile.json*` | Windows |
| WinAppDataRoaming | `Godot/app_userdata/Collimators- Frontlines` | `run_save.json*` | Windows |

- Root overrides (so a Mac build shares the same saves):
  WinAppDataRoaming → MacAppSupport (macOS), same subdirectory.

The `*` takes each file's `.bak` (SafeFile's backup) too. Left out on purpose:
`settings.cfg` (per machine), `replays/`, `playtests/`, `session/`, `logs/`.

## Achievements (App Admin → Stats & Achievements → Achievements)

API name = the id in `data/achievements.json`. The game sets them when a run
earns them (`Profile._earn_achievements`) and re-sends every earned one on
launch, so testers who earned some before this get them too. Each needs a
256×256 achieved and unachieved icon (JPG).

| API name | Name | Description |
|---|---|---|
| first_win | First Blood | Win a fight |
| elite | Elite Hunter | Beat an elite |
| boss | Kingslayer | Defeat a boss |
| clear | Sector Secured | Clear a location |
| daily | Daily Operator | Finish a Daily Operation |
| untouched | Untouched | Win a fight without taking damage |
| close_call | Close Call | Win a fight with a tenth of your HP or less left |
| blitz | Blitz | Win a fight in 3 turns or fewer |
| big_hit | Heavy Hitter | Land a single hit of 30 or more |
| big_turn | Alpha Strike | Deal 100 damage in one turn |
| cool_head | Cool Head | Clear a location without overheating |
| parts_100 | Scrapper | Destroy 100 enemy parts |
| damage_10k | Ten Thousand | Deal 10,000 damage |
| runs_10 | Veteran | Finish 10 missions |
| all_mechs | Full Hangar | Clear a location with every mech |
| streak_3 | Routine | Finish every daily directive 3 days running |
| all_bosses | Hit List | Defeat every boss |

## Rich Presence (Community → Rich Presence Localization)

Upload `tools/steam/rich_presence.vdf`. The game sets `steam_display` to
`#Base` (War Room, Hangar, Debrief), `#Mission` (any run screen) or `#Fight`
(a fight), with `%location%`, `%mission%` and `%fight%` filled in
(`SteamService.update_presence`).

## Shipping a build

`tools/ship.sh` does both steps from the Mac: pushes `main` to GitHub, then
exports and uploads with `tools/steam_release.sh` (options pass through, e.g.
`--desc "..."`). It stops first if you're not on `main`, have uncommitted
changes, or GitHub's `main` has commits you haven't pulled. Then set the
build live on the Builds page as before.

Every push to `main` also runs `.github/workflows/build_check.yml` on GitHub:
the data check, a few simulated runs to catch script errors, and the Windows
export (the combat rule tests don't gate it). It doesn't upload: Steam Guard
ties SteamCMD's saved login to the machine that made it, so a GitHub runner
can't reuse the Mac's login (tried 2026-10-14 on Linux and macOS runners).
Optional secret: `FEEDBACK_WEBHOOK`, stamped into the checked build.

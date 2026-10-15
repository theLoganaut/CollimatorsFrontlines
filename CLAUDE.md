# Collimators: Frontlines

Turn-based, Slay-the-Spire-style mech combat game in **Godot 4.7 / GDScript**. You pack shaped
components into a chassis grid. Each component grants cards, and you spend **Heat** to play them against
individual enemy components. A mech is destroyed once all of its hardpoints are, or (enemies) once its HP falls to its threshold.

**Scene flow:** War Room (main scene) → War Table → sector map (3 locations, each with a rolled mission type) →
pop-up (optional seed) → Launch → `LocationMap` (Slay-the-Spire-style stops: fights, elites, events, repair bays,
autonomous bays, boss) → the stop's screen (`CombatScene`, `RewardScreen`, `RefitScreen`, `RepairBayScreen`,
`ShopScreen`, `EventScreen`) → back to the map; a run ends in `DebriefScreen` → War Room. The War Room's Hangar
(`HangarScreen`) picks the mech and its Surplus starting loadout. Autoloads: `RunState` (the run, `scripts/run/RunData.gd`,
saved by `SaveGame`), `Profile` (what persists between runs), `SceneRouter` (fades), `Sfx`, `Tutorial`, `Gamepad`. `scenes/Main.tscn` is a standalone
fight with no run, used by dev tools.

**Data:** `data/components.json`, `data/chassis.json` and every enemy in `data/mechs/` are Refit Bay imported verbatim
(`tools/import_refit_bay.py <export.json>`; enemies come from Refit Bay's **Enemies** tab, with their AI profile and boss
lines). `data/component_rules.json` says how each effect plays. Player mechs (`bastion/redline/jackal.json`) name parts by id.
Parts named "(C) …" in Refit Bay are Claude's drafts (shown without the prefix in game; `claude_draft` in components.json);
their mechanics are written in `tools/claude_parts.py` (`rules` merges them into component_rules.json). The card rework
(Notion: Dynamic Turn Rework, Phase 5) keeps its reworked/added cards and rewritten passives in `tools/card_pass.py`
(`refit` patches a Refit Bay doc, `components` patches components.json + rules; claude_parts.py takes those parts' cards from it). Reactors are passive-only. Weight classes are
enforced: Light/Medium/Heavy parts only fit that class, General fits all. Missions, sectors (with encounter pools), events,
directives, liveries and Operator lines are JSON in `data/`. **Every tuning number is in `data/balance.json`**; rerun
`tools/balance_sim.sh [runs] [--report] [--set=section.key=value]` after changing numbers (bots: smart, focused, casual, and
builder, which also takes parts, refits and shops; they take deployment orders and random event choices; options like
`--mech=<enemy>.swap=a:b`, `--orders=`, `--variants=`, `--sweeps=` are listed atop `tools/balance_sim.gd`). `tools/card_value.gd` measures every attack card's damage per Heat (outliers by rarity) and what each protocol adds on the hardest-hitting cards. `tools/check_all.sh` runs the tests, `tools/validate_data.gd` (every
data reference resolves) and a sim smoke run; run it before calling work done. `tools/golden.sh check [25]` is the golden
master for refactors (seeded sim traces must stay identical); rerecord (`record`) after intended rule or data changes. `tools/Screenshot.tscn` opens a run screen
(shop, refit, combat, map, event) in a set state and saves a PNG (needs a window, not `--headless`). New `class_name` scripts need
`Godot --headless --editor --quit` once to register, and tests (`--script`) can't see autoloads.

**Code shape:** `CombatManager` holds a fight's state; its rules are static helpers taking it (`CombatAttack`, `CombatProtocols`,
`CombatEnemyTurn`, `CombatHeat`). Player decisions go through `CombatManager.apply(cmd)` (id-based commands, logged in
`command_log`, replayable). `RunData` likewise delegates to `RunEvents`, `RunShop`, `RunParts`, `RunSave`. Enemy turns (Phase 6): `data/enemy_ai.json` gives each enemy two-turn rhythms of themes (assault/guard/charge/afflict/recover/combo),
openers, squad roles, on_lost and phase 2; `EnemyAI.plan_all` plays every affordable card in theme order, `EnemyAI.repair` updates
the shown plan after each player command, and a Charge fires free at `enemy_ai.charge_mult` next enemy turn unless its part is stopped. Location rules and
mission variants are `Conditions` (`data/conditions.json`); the seeded daily run is `Daily`.
**Combat scaling:** `balance.json` "combat" (`damage_mult`, `heat_add`, `hp_mult`, `heat_mult`) is applied to every Refit Bay
part as it loads (`ComponentLibrary.make`), player and enemy alike, so the game shows the scaled numbers while Refit Bay and
components.json keep the originals (target: about 6 turns a fight). Tests run with it off (`tests/run_tests.gd`), so rule tests
use Refit Bay's numbers; rule tests that need a kit use `tests/fixtures/*_classic.json`, not the live starting kits (all
Surplus, about 50 damage a turn; the Hangar and saved loadouts are Surplus only).
**Combat rules to know:** each card plays once per turn and is back next turn (`CombatManager.spent`; Logan: nothing
more, nothing less). The Vent action (player before any card; enemies with nothing to play) vents a flat
`heat.vent_action_share` at the next dispersal. An enemy that started with cards and can never play one again (all its card parts destroyed or Offline) retreats as its turn starts; that counts as a kill, bosses included. One protocol waits at a time (no stacking): priming another replaces it, for the player and enemies alike. Pointing parts (Coolant Flush) give their status only at the start of
combat. Event buttons are built from their outcome (`EventOutcome`: the label, then one short sentence per effect, gains first: "+70 Scraps. Hardpoints Jam 1 next fight."); every gain needs a cost. A run's frame grows at most
one ring past the chassis' original bounds (`RunData.base_bounds`). Run saves go through `SafeFile` (atomic, with a backup),
are versioned (`RunData.SAVE_VERSION`, `SaveMigration`; `SaveMigration.problems` refuses a save that names parts/enemies/events
that no longer exist, and `tests/fixtures/saves/` holds saves from released builds that must keep loading) and carry their mission, so retuning missions.json doesn't change a
run in progress.

**Meta:** Scraps = in-run money; Chips = meta currency (`scripts/run/Meta.gd`, state in `Profile`). The War Room stations
(Directives, Pilot Log, Memorial Wall, Info Bay, Livery Bay) are `scripts/hub/*Screen.gd` on `HubScreen`, each over its own dimmed room art (`assets/warroom/screens/<station>.png`, `backdrop_name()`). The training run
is the `training` mission, coached by the `Tutorial` autoload (screens call `Tutorial.reached(point, targets)` /
`Tutorial.event(name)`). Sound effects are synthesized by the `Sfx` autoload; call `Audio.play(key)`; music and ambience
loops (`SoundLoops`, rendered on a worker thread) via `Audio.music(key)` / `Audio.ambience(key)`. Settings (`GameSettings`,
per machine in `user://settings.cfg`): per-bus volume, colorblind-safe statuses (`Palette.status_color`), reduce motion,
the combat log's open state (closed by default; Log button / L), whether the description box (shown only while
something is hovered) also needs Shift held, and key bindings (`GameSettings.KEY_ACTIONS`, `key()` / `is_key()`; never
compare a letter keycode directly). `KitMath.best_turn` is the "damage a turn" yardstick (starting kits, salvage compare).
**Recordings and playtests:** every run fight is recorded (`FightRecord`: mechs at the start, seed, fight-start
statuses, commands; saved by `Replays` in `user://replays/`, named in the run's `fight_log`). The Pilot Log's Watch
buttons play one back in `CombatScene`'s replay mode (`CombatScene.replay_record`). Every finished run also writes a
playtest report (`PlaytestReport`, `user://playtests/`; Settings → "Save playtest report" mid-run);
`tools/playtest_report.gd [file|folder] [--turns]` prints each fight and checks it still replays the same.
**Crash reports** (`CrashLog`, autoload `CrashWatch`, first): a session file touched every 2 s and a trail of what the player did
(screens, hovered parts/cards/intents, cards played, turns; `CrashLog.crumb`) plus every engine/script error with its backtrace,
flushed line by line to `user://session/`. A launch that finds the last session never quit writes `<stamp>_crash.txt` (verdict,
last action, system/GPU, trail, the end of that session's Godot log) to `user://playtests/`; a run continued after it lists it in
`RunData.resumes`, and the run's playtest report carries the text.
**Feedback** (`Feedback`, `FeedbackDialog`): the Feedback button right of the location name on every screen (combat: right of the
turn plate, which names the location), Settings → Send feedback, or F8 posts the pilot's note, where they are (`Feedback.context`), and
a zip (screenshot, the fight in progress as `fight_replay.json` (a one-fight playtest report), run so far,
last week's crash report, session trail, Godot log, profile, settings) to a Discord webhook; the address is `FEEDBACK_WEBHOOK` in
`tools/steam/config.local.sh` (git-ignored, read by `config.sh`), stamped into the build by the release script (`BuildInfo`), or `user://feedback_webhook.txt` for a dev test.
**Steam** (App ID 5441720, project setting `steam/initialization/app_data/app_id`): the GodotSteam GDExtension in
`addons/godotsteam` (Steamworks SDK 1.65; the steam_api libraries are copied from Valve's SDK). The `SteamService` autoload
starts it and `SteamService.available` / `api()` say whether Steam is up; without the extension or a running client the game plays on.
**Releases to testers** ("build it" / "push a build"): `tools/steam_release.sh [--desc "..."]` exports Windows (macOS too if
`DEPOT_MACOS` is set) and uploads it with SteamCMD (one branch, default: Logan sets each build live on the Steamworks Builds page; settings: `tools/steam/config.sh`; logs:
`build/steam/logs/`). It runs on the Mac or on Logan's Windows PC (Git Bash; config.sh picks each one's SteamCMD and Godot). If it says SteamCMD needs a login, Logan runs `tools/steam_release.sh --login` himself on that machine (password + Steam Guard).
`tools/ship.sh` = push `main`, then `steam_release.sh` (Logan's one command). Every push to `main` runs a build check on GitHub (`.github/workflows/build_check.yml`: validate_data, a short sim for script errors, the Windows export; not the combat rule tests). It can't upload: Steam Guard binds SteamCMD's login to Logan's own machines.
**Versions** (`project.godot` config/version, `export_presets.cfg`, `current` in `data/changelog.json`; validate_data checks they match): a release bumps them and adds its notes to `releases`. The What's Next?! roadmap (`next.updates`) has no version numbers, only minor/major and when, so bug-fix releases and moving items between updates never renumber it.
**Achievements** (`data/achievements.json`, `Achievements`, earned in `Profile.record_run`, Pilot Log tab).
**Gamepad** (`Gamepad` autoload): the stick drives the mouse cursor and A clicks, so screens need nothing of their own;
buttons press the bound keys; a screen can take buttons first (`Gamepad.handler.pad_button`, combat does). Code that
polls the left mouse button uses `Gamepad.left_held()`. Card text in part cards uses `UIKit.rich_label`
(`StatusGlossary.annotate`: statuses and keywords tinted, with their rule as a hover hint).
Mech sprites (PixelLab, 128×128, straight-on) are `assets/enemies/<id>.png` and `assets/mechs/<id>_front.png` /
`_back.png`, loaded through `MechArt`; a mech without one keeps the placeholder.
Component art is `assets/components/<library id>.png` (32 px per cell of the unrotated shape), drawn tile by tile over
the part's cells, turned with the part, by `PartArt`. Grid squares have no fill: `PartArt.draw_part_cell` /
`draw_empty_cell` draw every grid's squares as see-through edges in the category color (a part without art keeps a faint tint).
The War Room is pixel art in `assets/warroom/` (624×390, drawn ×1152/624): `room.png`, then each station's piece as a
`Hotspot` (hover and clicks only on its opaque pixels, yellow outline of its shape) with a `HoloLabel` projected from a
fixed emitter on it; live holograms, dailies, sector beacons and Memorial Wall trophies (`Profile.memorial_points`) are drawn on top.
The War Table's sector map is a generated theater (`WarMap`, seeded by `Profile.sector_seed`: coast, mountain flank, river,
front line, units; each location placed by its `map_zone` in sectors.json) shown by `SectorMapView` as a 3D hologram
(`HoloTerrain`: heightmap mesh in a SubViewport, composited additively) with a 2D overlay of markers; `LocationPopup` is glass, beamed from the marker.
In a run the same look carries on: `LocationMapScreen` is a `HoloTerrain` of the location (`WarMap.location_terrain`, by its `map_zone`)
with the stops on pins; `RefitScreen`, `ShopScreen` and `RepairBayScreen` extend `WorkshopScreen` (pixel-art bay in `assets/run/`, the mech as a hologram,
glass panels, Cargo plus a 6×6 workbench `RunData.bench`; parts left on the bench are scrapped for scraps, `Economy.scrap_value`);
combat's `CardUI`, `DescriptionBox`, `CombatLog`, `HeatBox`, name plates, End Turn and `PartCardUI` are glass with the part's art (`PartArt.draw_shape`).
`RewardScreen` sits over the fight's own background (`RunScreen.backdrop()`), `DebriefScreen` over the dimmed War Room. `EventScreen` shows the event's own scene, dimmed (`assets/events/<event id>.png`, PixelLab Pixen 640×400).
The Operator speaks from glass comm panels with his portrait (`OperatorPortrait`, `assets/operator/operator.png`, a handler in shadow): the War Room's line and the training coach (`Tutorial`), both typed in.
The Hangar is the bay behind that door (`assets/warroom/hangar_bay.png`): the mech as a hologram (`MechArt.hologram_material`)
on the pad, and `GlassPanel` holo screens: chassis + a 6×6 workbench (`Profile.hangar_bench`, never launched), `PartPreview`
and `ArmoryBrowser` (search, category chips, sort).
Combat backgrounds are `assets/backgrounds/`, listed per location and tier in `data/backgrounds.json` with where
enemies' feet stand (`PlayField` draws them, with `Rain` for rainy ones; `CombatScene` stands the enemies on those spots).

## Source of truth: Notion

**Hub:** https://app.notion.com/p/Collimators-Frontlines-3e783c3998468084af6bd3f5f89f96ab

The hub is an index. Open only the subpage you need (fetch by ID with the Notion tools):

| Page | ID | Contents |
|---|---|---|
| Game Overview | `3e783c39984681a496e1ed34c22fdb11` | Pitch, pillars, core concepts, glossary |
| Chassis | `3e783c39984681d988eced9ed68578f4` | Redline / Jackal / Bastion cell maps, max heat, heat-check timing, starting loadouts, frame ring |
| Components & Cards | `3e783c39984681e29907e0ae0b18b830` | Categories, rarity targets, card anatomy, passives, protocols, per-part rulings; catalog subpages below |
| ↳ Hardpoints Catalog | `3e783c39984681c68ebcc3a04977d51b` | Generated from components.json |
| ↳ Reactors Catalog | `3e783c39984681df8adef3a155b9dcd4` | Generated from components.json |
| ↳ Protocols Catalog | `3e783c39984681aa80f7eec5090050cc` | Generated from components.json |
| Statuses & Links | `3e783c39984681bba51add32eac87f8e` | Status/state rules, keywords, link and facing-arrow system |
| Combat Rules | `3e783c39984681869ee2df147f4abb1a` | Round structure, venting, Vent action, overheat, once-per-turn cards, damage, win/lose |
| Enemies | `3e783c399846819fb6c2c7b37026549d` | Principles (intents, enemy heat), AI profiles, bosses, roster, location pools, win rates |
| Runs & Progression | `3e783c399846811c9983e2a03e8089bc` | Missions, map, encounters, salvage, Cargo/workbench, refits, repairs, shops, events, deployment orders |
| Hub & Meta-Progression | `3e783c399846811fa8d1cff263925ace` | War Room stations, Hangar, Operator, Chips, directives, liveries, co-op |
| Balance Targets | `3e783c39984681cf9a83e34ef26268bd` | Feel targets, HP calibration, current sim results, watch list |
| UI & Screens | `3e783c39984681e893f9f69f833474f8` | **Chosen combat layout = Logan's sketch** (image on page), card face, intents, settings, screen flow, art |
| Tech & Tools | `3e783c399846811abcebdaa3f51e0749` | Project setup, data files, tools, Refit Bay, conventions |
| Change Log | `3fa83c39984681219dfecc7645c982f7` | One subpage per version (0.X.X) with what changed, the version in progress, and the roadmap (the one posted on Discord). **Add every change to the in-progress version's page as it's made** |
| Scratchpad & Backlog | `3e783c39984681f88fbef6abf2ecefaf` | Logan's in-progress thoughts (not decided); its **Backlog (non-art)** subpage (`3ea83c39984681418305d1e79f381380`) is the open work |

## Other sources

- **Refit Bay** (authoritative component/card/chassis numbers): https://claude.ai/artifact/Hw6ggBMRNmmcSzutZ8ta3k
  Read it with the Artifact tool: `read_db` → `get`, collection `data/users/me`, doc `refit_bay`.
- **Combat Screen Layout Options** (early mockups A/B/C, exploration only, **not** the chosen UI): https://claude.ai/artifact/2eZL6ybson1eCNNNfQ8oes

## Working rules

- **Mechs use only Refit Bay parts**, player and enemy alike: components, HP, shapes, cards and effect text copied verbatim. Never make up a part or effect unless Logan explicitly asks.
- Settled decisions go into the matching Notion topic page, not only into chat or code.
- Treat Scratchpad → "Thoughts in progress" as undecided. Pages tag items **Decided / Proposed / Open / Shelved / Cut**; only Decided is settled.
- Godot CLI for headless runs/tests: `/Applications/Godot.app/Contents/MacOS/Godot` on the Mac; on Windows,
  `~/Desktop/Projects/Godot_v4.7-stable_win64_console.exe`.

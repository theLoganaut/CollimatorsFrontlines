# Art sources

Working files behind shipped art, kept in git so they're on every machine.
`.gdignore` keeps Godot from importing or exporting anything here.

- `discord_sign/` — the War Room's "Join the Discord!" sign: PixelLab plate, `stamp.py`
  (stamps the logo and lettering), candidates. The shipped art is `assets/warroom/discord_sign.png`.
- `steam_capsules/` — Steam store art: `header_capsule_920x430.png`, `main_capsule_1232x706.png`,
  `small_capsule_462x174.png`, `vertical_capsule_748x896.png`, `library_capsule_600x900.png`,
  `library_hero_3840x1240.png` (no title; Steam lays the logo over it), `library_logo.png` (transparent title),
  `old/` (earlier A/B), `src/` (PixelLab scenes `scene_*.png` at half size, guides, scripts). Capsules are a
  half-size PixelLab Pro scene (main scene `sceneA2.png` as reference), cropped, titled by `holo3.py`'s
  `compose(..., panel=False)`, then ×2 nearest; the hero is ×5; `logo.py` draws the logo.
- `steam_screenshots/` — the Steam page's screenshots at 1920×1080, made by `tools/steam_screenshots.sh`
  (`tools/Screenshot.tscn --store`).
- `warroom_right/` — the War Room's side-wall stations (Directives screen, Livery Bay, Pilot Log and Info Bay
  terminals, the R&D shelf without its hologram): PixelLab sources, candidates and `build.py`, which writes them
  into `assets/warroom/`. `old_*.png` are the pieces they replaced.
- `warroom_walls/` — the War Room's left and right walls seen straight on (PixelLab Pro `left_v1.png` /
  `right_v1.png`, room.png as reference) and `build.py`, which patches the left floor and cuts the four
  side stations (Research Bay, Info Bay, Livery Bay, Pilot Log) out of them by rectangles into
  `assets/warroom/`, and seals the empty middle panels with hazard tape and a hung COMING SOON! sign. These replace `warroom_right/`'s corner pieces.
- `memorial/` — the Memorial Wall's candle trophy cleaned up by `candle.py` (`old_slot_00.png` is the one it replaced).
- `crates/` — the salvage crates (RewardScreen, SalvageCrate): PixelLab Pro candidates per category (`cand_*`), the picked ones, their open state (`e_*_open.png`, a Pro Flash edit) and `build.py`, which copies them into `assets/run/crates/` and prints each lid's height for `SalvageCrate.LID_ROWS`. `ref_style.png` is the War Room crop used as the style.

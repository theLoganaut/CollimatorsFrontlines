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

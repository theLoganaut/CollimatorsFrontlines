# Collimators: Frontlines

Turn-based, Slay-the-Spire-style mech combat game in **Godot 4.7 / GDScript**. You pack shaped
components into a chassis grid. Each component grants cards, and you spend **Heat** to play them against
individual enemy components. A mech is beaten when all of its components are destroyed.

## Source of truth: Notion

**Hub:** https://app.notion.com/p/Collimators-Frontlines-3e783c3998468084af6bd3f5f89f96ab

The hub is an index. Open only the subpage you need (fetch by ID with the Notion tools):

| Page | ID | Contents |
|---|---|---|
| Combat Slice (current work) | `3e783c3998468176bc1cd4698d6de907` | Signed-off plan for the first playable build (Bastion vs 3 Scrap Wardens), milestones M0–M6 |
| Game Overview | `3e783c39984681a496e1ed34c22fdb11` | Pitch, core concepts, glossary |
| Chassis | `3e783c39984681d988eced9ed68578f4` | Redline / Jackal / Bastion cell maps, max heat, heat-check timing |
| Components & Cards | `3e783c39984681e29907e0ae0b18b830` | Categories, card anatomy; catalog subpages below |
| ↳ Hardpoints Catalog | `3e783c39984681c68ebcc3a04977d51b` | |
| ↳ Reactors Catalog | `3e783c39984681df8adef3a155b9dcd4` | |
| ↳ Protocols Catalog | `3e783c39984681aa80f7eec5090050cc` | |
| Statuses & Links | `3e783c39984681bba51add32eac87f8e` | Status/state rules, link system |
| Combat Rules | `3e783c39984681869ee2df147f4abb1a` | Round structure, ratio venting, overheat, damage pipeline |
| Enemies | `3e783c399846819fb6c2c7b37026549d` | Principles (telegraphs, enemy heat), bosses, roster |
| Runs & Progression | `3e783c399846811c9983e2a03e8089bc` | Starting loadouts, rewards, shops, item pools, map, eject |
| Hub & Meta-Progression | `3e783c399846811fa8d1cff263925ace` | Hub features, dailies, debrief, co-op |
| Balance Targets | `3e783c39984681cf9a83e34ef26268bd` | Feel targets, HP calibration, balance watch list |
| UI & Screens | `3e783c39984681e893f9f69f833474f8` | **Chosen combat layout = Logan's sketch** (image on page), card face, palette/fonts |
| Tech & Tools | `3e783c399846811abcebdaa3f51e0749` | Project setup, Refit Bay, design canvas, conventions |
| Scratchpad & Backlog | `3e783c39984681f88fbef6abf2ecefaf` | In-progress thoughts (not decided), checklist, open questions |

## Other sources

- **Refit Bay** (authoritative component/card/chassis numbers): https://claude.ai/artifact/Hw6ggBMRNmmcSzutZ8ta3k
  Read it with the Artifact tool: `read_db` → `get`, collection `data/users/me`, doc `refit_bay`.
- **Combat Screen Layout Options** (early mockups A/B/C, exploration only, **not** the chosen UI): https://claude.ai/artifact/2eZL6ybson1eCNNNfQ8oes

## Working rules

- Settled decisions go into the matching Notion topic page, not only into chat or code.
- Treat Scratchpad → "Thoughts in progress" as undecided. Pages tag items **Decided / Proposed / Open / Shelved / Cut**; only Decided is settled.
- Godot CLI for headless runs/tests: `/Applications/Godot.app/Contents/MacOS/Godot`

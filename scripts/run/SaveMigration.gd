class_name SaveMigration
extends RefCounted
## Upgrades an older run save's dictionary to RunData.SAVE_VERSION. Kept
## apart from SaveGame (and free of autoloads) so the tests can run it.

## Mission settings before the longer-runs change (2026-09-30), for v1 saves
## (which didn't carry their mission).
const V1_MISSIONS := {
	"assault": {"rows": 7, "refit_after_rows": [1, 3, 5], "elite_escort_from_row": 4, "weak_fights": 3, "repair_before_boss": false},
	"rescue": {"rows": 7, "refit_after_rows": [1, 3, 5], "elite_escort_from_row": 4, "weak_fights": 3, "alert_turns_per_tier": 6, "repair_before_boss": false},
	"deep_recon": {"rows": 10, "refit_after_rows": [1, 3, 5, 7], "weak_fights": 4},
}

## Brings an older save's dictionary up to RunData.SAVE_VERSION.
static func migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("v", 1))
	if v < 2: # v1: no mission snapshot; its map was built with the old row counts
		var mid := str(d.get("mission_id", ""))
		# missions.json read directly (not GameData), so tests can run this headless
		var all: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/missions.json")).get("missions", {})
		var m: Dictionary = all.get(mid, {}).duplicate(true)
		if not m.is_empty():
			m["id"] = mid
		var old: Dictionary = V1_MISSIONS.get(mid, {})
		for k in old:
			if k == "alert_turns_per_tier":
				if m.has("alert"):
					m["alert"]["turns_per_tier"] = old[k]
			else:
				m[k] = old[k]
		d["mission"] = m
	d["v"] = RunData.SAVE_VERSION
	return d

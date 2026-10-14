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

# ---------- can it still load? ----------

static var _known: Dictionary = {}

## What a (migrated) save refers to that today's game no longer has: parts
## (on the mech, in Cargo, on the bench, in the shop, in a salvage offer),
## enemies in rolled fights, the event, the location, the mech, or a save
## made by a newer build. Empty = it loads as it was. Reads the data files
## directly (no autoloads), so the tests can run it.
static func problems(d: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if int(d.get("v", 1)) > RunData.SAVE_VERSION:
		out.append("saved by a newer version (v%d)" % int(d.get("v", 1)))
		return out
	var k := _known_ids()
	var loc := str(d.get("location_id", ""))
	if not k["locations"].has(loc):
		out.append("location '%s'" % loc)
	if not FileAccess.file_exists(str(d.get("mech_path", ""))):
		out.append("mech '%s'" % d.get("mech_path", ""))
	var parts: Array = []
	for p in d.get("mech", []) + d.get("cargo", {}).get("items", []) + d.get("bench", []):
		parts.append(str(p.get("library_id", "")))
	for id in d.get("shop", {}).get("parts", []):
		if str(id) != "":
			parts.append(str(id))
	for ids in d.get("reward", {}).get("options", {}).values():
		for id in ids:
			parts.append(str(id))
	for id in parts:
		if not k["parts"].has(id):
			out.append("part '%s'" % id)
	for ids in d.get("fight_rolls", {}).values():
		for id in ids:
			if not FileAccess.file_exists("res://data/mechs/%s.json" % id):
				out.append("enemy '%s'" % id)
	var ev := str(d.get("event", {}).get("id", ""))
	if ev != "" and not k["events"].has(ev):
		out.append("event '%s'" % ev)
	return out

static func _known_ids() -> Dictionary:
	if _known.is_empty():
		var parts := {}
		var comps = JSON.parse_string(FileAccess.get_file_as_string("res://data/components.json"))
		for c in (comps["components"] if typeof(comps) == TYPE_DICTIONARY else comps):
			parts[c["id"]] = true
		var locations := {}
		for l in JSON.parse_string(FileAccess.get_file_as_string("res://data/sectors.json")).get("locations", []):
			locations[l["id"]] = true
		var events := {}
		for e in JSON.parse_string(FileAccess.get_file_as_string("res://data/events.json")).get("events", []):
			events[e["id"]] = true
		_known = {"parts": parts, "locations": locations, "events": events}
	return _known

class_name Operator
extends RefCounted
## The Operator's War Room line (data/operator.json): what came out of the
## last run, in the voice of a busy handler who's glad you're alive. A run
## left mid-mission comes first ("back from break"); then a first boss
## sighting or new Recon intel; then the plain result, an eject read by how
## far the run got (Logan, 2026-10-02: a handful of lines for each, not
## always about ejecting). The line is picked at random from its pool.

const PATH := "res://data/operator.json"

## `report`: Profile.last_report; `saved`: SaveGame.summary() of a run in
## progress ({} if none).
static func line(report: Dictionary, runs: int, saved: Dictionary = {}) -> String:
	var lines = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(lines) != TYPE_DICTIONARY:
		return ""
	var key := pool_key(report, saved)
	var pool: Array = lines.get(key, lines.get("ejected", []) if key.begins_with("ejected") else [])
	if pool.is_empty():
		return ""
	var text: String = pool[(runs + randi()) % pool.size()]
	var boss: String = (report.get("new_bosses", [""]) as Array)[0] if not (report.get("new_bosses", []) as Array).is_empty() else ""
	var fill := {"location": report.get("location", ""), "mission": report.get("mission", ""), "stops": int(report.get("stops", 0)), "boss": boss}
	if not saved.is_empty():
		fill = {"location": (saved.get("location", {}) as Dictionary).get("name", ""), "mission": (saved.get("mission", {}) as Dictionary).get("name", ""),
			"stops": int(saved.get("stops", 0)) + 1, "boss": ""}
	return text.format(fill)

## Which pool of lines fits: paused, first_time, boss_first, recon_intel,
## rescue_hot, cleared, or ejected_early / ejected / ejected_late (under 30%
## of the way, or 2 encounters or fewer; 70% or more; the rest).
static func pool_key(report: Dictionary, saved: Dictionary = {}) -> String:
	if not saved.is_empty():
		return "paused"
	if report.is_empty():
		return "first_time"
	if not (report.get("new_bosses", []) as Array).is_empty():
		return "boss_first"
	if report.get("intel", false):
		return "recon_intel"
	if int(report.get("alert", 0)) >= 3:
		return "rescue_hot"
	if report.get("result", "ejected") == "cleared":
		return "cleared"
	var stops := int(report.get("stops", 0))
	var total := int(report.get("total", 0))
	var share := float(stops) / float(total) if total > 0 else -1.0
	if stops <= 2 or (share >= 0.0 and share < 0.3):
		return "ejected_early"
	if share >= 0.7:
		return "ejected_late"
	return "ejected"

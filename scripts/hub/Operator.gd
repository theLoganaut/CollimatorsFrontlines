class_name Operator
extends RefCounted
## The Operator's War Room line (data/operator.json): what came out of the
## last run, in the voice of a busy handler who's glad you're alive. A first
## boss sighting or new Recon intel takes priority over the plain result.

const PATH := "res://data/operator.json"

static func line(report: Dictionary, runs: int) -> String:
	var lines = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(lines) != TYPE_DICTIONARY:
		return ""
	var key := "first_time"
	if not report.is_empty():
		key = report.get("result", "ejected")
		if not (report.get("new_bosses", []) as Array).is_empty():
			key = "boss_first"
		elif report.get("intel", false):
			key = "recon_intel"
		elif int(report.get("alert", 0)) >= 3:
			key = "rescue_hot"
	var pool: Array = lines.get(key, [])
	if pool.is_empty():
		return ""
	var text: String = pool[runs % pool.size()]
	var boss: String = (report.get("new_bosses", [""]) as Array)[0] if not (report.get("new_bosses", []) as Array).is_empty() else ""
	return text.format({"location": report.get("location", ""), "mission": report.get("mission", ""), "stops": int(report.get("stops", 0)), "boss": boss})

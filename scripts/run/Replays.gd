class_name Replays
extends RefCounted
## Recorded fights on disk (FightRecord), one JSON file each in
## user://replays/, named by when the fight was saved. A run's fight_log
## names each fight's file ("replay"), so the Pilot Log can play it again
## and a playtest report can carry it. Only the newest KEEP are kept.

const DIR := "user://replays"
const KEEP := 120

## Saves a finished record. Returns its file name ("" if it couldn't).
static func save(rec: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "").replace("-", "")
	var name := "%s_%03d.json" % [stamp, randi() % 1000]
	while FileAccess.file_exists("%s/%s" % [DIR, name]):
		name = "%s_%03d.json" % [stamp, randi() % 1000]
	if not SafeFile.write_json("%s/%s" % [DIR, name], rec):
		return ""
	prune()
	return name

static func exists(name: String) -> bool:
	return name != "" and FileAccess.file_exists("%s/%s" % [DIR, name])

## The record saved as `name`, or {}.
static func load_record(name: String) -> Dictionary:
	if not exists(name):
		return {}
	var d = SafeFile.read_json("%s/%s" % [DIR, name])
	return d if typeof(d) == TYPE_DICTIONARY else {}

## Drops the oldest files past KEEP.
static func prune() -> void:
	var files := _files()
	while files.size() > KEEP:
		SafeFile.remove("%s/%s" % [DIR, files.pop_front()])

## Saved records, oldest first (names sort by time).
static func _files() -> Array:
	var out := []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".json"):
			out.append(f)
	out.sort()
	return out

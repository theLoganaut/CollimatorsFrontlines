class_name PlaytestReport
extends RefCounted
## Playtest reports: a run written out as one JSON file a tester can send in,
## so real play (not just the sim's bots) can be read and replayed.
## - Every finished run (not training) writes one at its end: the Pilot Log
##   entry (mech, location, mission, order, result, stats, each fight's
##   turns and HP), the final loadout, and every fight's FightRecord.
## - Settings → "Save playtest report" writes one mid-run: the run's save,
##   the fights so far, and the fight in progress up to now.
## Both carry the run's resumes (each Continue from its save) and the text
## of any crash report (CrashLog) the game wrote before one of them.
## Files go to user://playtests/ (the Pilot Log opens the folder), newest
## KEEP kept; CrashLog's <stamp>_crash.txt reports go there too. tools/playtest_report.gd reads them: per-fight numbers, and
## each fight replayed headless to check it still plays the same.

const DIR := "user://playtests"
const KEEP := 40
const VERSION := 1
const DATA_FILES := ["res://data/balance.json", "res://data/components.json", "res://data/component_rules.json"]

## The fight in progress, as a record so far (CombatScene sets this while
## it's open), for a mid-run report. Returns {} when there's none.
static var current_fight: Callable = Callable()

## A finished run: `entry` is its Pilot Log entry (Profile.history[0]).
static func for_run(run: RunData, entry: Dictionary) -> Dictionary:
	return {
		"v": VERSION, "kind": "run", "written": Time.get_datetime_string_from_system(false, true),
		"game": game_info(), "run": entry.duplicate(true),
		"loadout": RunSave.parts_to_list(run.player_mech.components),
		"fights": _records(run.fight_log),
		"resumes": run.resumes, "crashes": _crashes(run),
	}

## A run in progress: its save and its fights so far, plus the one being
## fought now (if any).
static func snapshot(run: RunData) -> Dictionary:
	var fights := _records(run.fight_log)
	var now: Dictionary = current_fight.call() if current_fight.is_valid() else {}
	if not now.is_empty():
		fights.append(now)
	return {
		"v": VERSION, "kind": "snapshot", "written": Time.get_datetime_string_from_system(false, true),
		"game": game_info(), "save": RunSave.to_dict(run), "fights": fights,
		"resumes": run.resumes, "crashes": _crashes(run),
	}

## What the report was played on: the combat scaling, and a fingerprint of
## the data files (if it differs from today's, old fights may not replay).
static func game_info() -> Dictionary:
	var text := ""
	for path in DATA_FILES:
		text += FileAccess.get_file_as_string(path)
	return {"build": BuildInfo.label(), "combat": _combat_section(), "data_hash": str(hash(text))}

static func _combat_section() -> Dictionary:
	var out := {}
	for k in ["damage_mult", "heat_add", "hp_mult", "heat_mult"]:
		out[k] = Balance.get_num("combat", k, 0.0)
	return out

## The crash reports the run was continued after: {file name: its text}.
static func _crashes(run: RunData) -> Dictionary:
	var out := {}
	for r in run.resumes:
		var name := str(r.get("crash", ""))
		if name != "":
			out[name] = CrashLog.report_text(name)
	return out

## The saved FightRecords a fight log names, in order (missing ones skipped).
static func _records(fight_log: Array) -> Array:
	var out := []
	for f in fight_log:
		var rec := Replays.load_record(str(f.get("replay", "")))
		if not rec.is_empty():
			out.append(rec)
	return out

## Writes a report. Returns its file path on disk ("" if it couldn't).
static func write(report: Dictionary, label: String = "") -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "").replace("-", "")
	var name := "%s_%s%s.json" % [stamp, report.get("kind", "run"), "_" + _slug(label) if label != "" else ""]
	var path := "%s/%s" % [DIR, name]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(report, " "))
	f.close()
	_prune()
	return ProjectSettings.globalize_path(path)

## The reports folder on disk (made if it isn't there yet).
static func folder() -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	return ProjectSettings.globalize_path(DIR)

static func _slug(s: String) -> String:
	var out := ""
	for ch in s.to_lower():
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	return out.left(40)

static func _prune() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	var files := Array(dir.get_files()).filter(func(f): return f.ends_with(".json"))
	files.sort()
	while files.size() > KEEP:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s" % [DIR, files.pop_front()]))

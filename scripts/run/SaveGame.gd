class_name SaveGame
extends RefCounted
## The run in progress on disk (Logan, 2026-09-27: save / continue run is
## needed, even though it "breaks the game a little"). Written every time
## the run changes screen; a fight in progress isn't saved, so continuing
## mid-fight restarts that fight from its start.
##
## Saves are versioned (RunData.SAVE_VERSION) and written through SafeFile
## (atomic, with a backup to fall back on). A save carries the mission
## settings its run started with, so retuning missions.json doesn't change
## a run in progress; SaveMigration brings older saves up to date.

const PATH := "user://run_save.json"
## A save that can't load any more (SaveMigration.problems) is moved here,
## kept for bug reports, and the run is closed.
const SET_ASIDE := "user://run_save_incompatible.json"

static func has_save() -> bool:
	return FileAccess.file_exists(PATH) or FileAccess.file_exists(PATH + ".bak")

static func save(run: RunData) -> void:
	SafeFile.write_json(PATH, run.to_dict())

static func load_run() -> RunData:
	var d = SafeFile.read_json(PATH)
	if d == null:
		return null
	d = SaveMigration.migrate(d)
	if not SaveMigration.problems(d).is_empty():
		return null
	var location := GameData.sector(d.get("location_id", ""))
	if location.is_empty():
		return null
	var mission: Dictionary = d.get("mission", GameData.mission(d.get("mission_id", "")))
	return RunData.from_dict(d, location, mission)

## A short summary for the Continue prompt, without loading the whole run.
static func summary() -> Dictionary:
	var d = SafeFile.read_json(PATH)
	if d == null:
		return {}
	var hp := 0
	var max_hp := 0
	for p in d.get("mech", []):
		hp += int(p.get("hp", 0))
		max_hp += int(p.get("max_hp", ComponentLibrary.definition(p.get("library_id", "")).get("hp", 0)))
	return {"location": GameData.sector(d.get("location_id", "")), "mission": GameData.mission(d.get("mission_id", "")), "stops": (d.get("path", []) as Array).size(),
		"hp": hp, "max_hp": max_hp, "scraps": int(d.get("scraps", 0)), "seed": int(d.get("seed", 0)),
		"mech": str(d.get("mech_path", "bastion")).get_file().get_basename()}

## Why the saved run can't be continued after an update ([] = it can).
static func problems() -> Array[String]:
	var d = SafeFile.read_json(PATH)
	if d == null:
		return [] as Array[String]
	return SaveMigration.problems(SaveMigration.migrate(d))

## Moves a save that can't load out of the way (kept as SET_ASIDE) and
## clears it. The profile is never touched.
static func set_aside() -> void:
	var d = SafeFile.read_json(PATH)
	if d != null:
		var f := FileAccess.open(SET_ASIDE, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(d))
			f.close()
	clear()

static func clear() -> void:
	SafeFile.remove(PATH)

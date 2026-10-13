class_name Achievements
extends RefCounted
## Achievements (data/achievements.json): one-time milestones that pay
## Chips once, checked when a run ends (Profile.record_run). Pure rules:
## `career` is what Profile knows across runs, passed in so this stays
## testable without the autoload:
##   {"runs": n, "stats": {lifetime sums}, "mech_clears": {mech id: n},
##    "mechs": [every player mech id], "streak": days,
##    "bosses_beaten": [ids], "bosses": [every boss id]}

const PATH := "res://data/achievements.json"

static var _defs: Array = []

static func defs() -> Array:
	if _defs.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_defs = parsed.get("achievements", []) if typeof(parsed) == TYPE_DICTIONARY else []
	return _defs

static func def(id: String) -> Dictionary:
	for d in defs():
		if d["id"] == id:
			return d
	return {}

## The achievements this finished run earns that `have` (ids) doesn't hold yet.
static func newly_earned(run: RunData, career: Dictionary, have: Array) -> Array:
	var out := []
	for d in defs():
		if not have.has(d["id"]) and earned(d, run, career):
			out.append(d)
	return out

static func earned(d: Dictionary, run: RunData, career: Dictionary) -> bool:
	var cleared := run.result == RunData.Result.CLEARED
	var n: float = float(d.get("n", 0))
	match str(d.get("check", "")):
		"run":
			var v := (1 if cleared else 0) if d["stat"] == "clears" else run.stats.get_stat(d["stat"])
			return v >= n
		"fight":
			for f in run.fight_log:
				if f.get("won", false) and fight_value(f, d["stat"]) <= n:
					return true
			return false
		"career":
			var v := int(career.get("runs", 0)) if d["stat"] == "runs" else int(career.get("stats", {}).get(d["stat"], 0))
			return v >= n
		"special":
			match str(d.get("special", "")):
				"daily":
					return run.mission.has("daily")
				"clear_no_overheat":
					return cleared and run.stats.get_stat("overheats") == 0
				"all_mechs":
					var clears: Dictionary = career.get("mech_clears", {})
					var mechs: Array = career.get("mechs", [])
					return not mechs.is_empty() and mechs.all(func(id): return int(clears.get(id, 0)) > 0)
				"streak":
					return int(career.get("streak", 0)) >= n
				"all_bosses":
					var beaten: Array = career.get("bosses_beaten", [])
					var all: Array = career.get("bosses", [])
					return not all.is_empty() and all.all(func(id): return beaten.has(id))
	return false

## A won fight's number for a "fight" check (hp_share: HP left / max).
static func fight_value(f: Dictionary, stat: String) -> float:
	if stat == "hp_share":
		return float(f.get("hp_left", 0)) / maxf(1.0, float(f.get("hp_max", 0))) if f.has("hp_max") else 1.0
	return float(f.get(stat, 999999)) # missing (an older log): never counts

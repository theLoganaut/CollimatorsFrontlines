class_name Balance
extends RefCounted
## Reads data/balance.json, where every tuning number lives (economy, map
## odds, encounters, enemy AI, meta currency). Loaded once and cached.
## `get_num("economy", "scraps_base", 10)` falls back to the default given
## when a key is missing.

const PATH := "res://data/balance.json"

static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = parsed if typeof(parsed) == TYPE_DICTIONARY else {"_empty": true}
	return _data

static func section(name: String) -> Dictionary:
	return data().get(name, {})

static func get_num(sec: String, key: String, fallback: float) -> float:
	return float(section(sec).get(key, fallback))

static func get_int(sec: String, key: String, fallback: int) -> int:
	return int(section(sec).get(key, fallback))

static func get_dict(sec: String, key: String) -> Dictionary:
	return section(sec).get(key, {})

static func get_str(sec: String, key: String, fallback: String) -> String:
	return str(section(sec).get(key, fallback))

## Overrides one value in memory (tools and tests: the sim's --set sec.key=value).
static func set_value(sec: String, key: String, value) -> void:
	var d := data()
	if not d.has(sec):
		d[sec] = {}
	d[sec][key] = value

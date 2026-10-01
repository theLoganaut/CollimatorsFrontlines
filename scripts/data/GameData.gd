extends Node
## Autoload (see project.godot [autoload]). Loads mech definitions from disk
## on demand and hands out fresh, independent MechData instances — combat
## mutates HP/heat/statuses heavily, so every fight (and every test) gets
## its own clone rather than sharing state.

const BASTION_PATH := "res://data/mechs/bastion.json"
const SCRAP_WARDEN_PATH := "res://data/mechs/scrap_warden.json"

func fresh_mech(path: String) -> MechData:
	return DataLoader.load_mech_from_file(path)

func fresh_bastion() -> MechData:
	return fresh_mech(BASTION_PATH)

func fresh_scrap_warden() -> MechData:
	return fresh_mech(SCRAP_WARDEN_PATH)

const PLAYER_MECHS := ["redline", "bastion", "jackal"]

## A player mech with a starting loadout: the Hangar's saved one
## ([{"id", "offset", "rotation"}]) or, if none, the mech file's default.
func player_mech(mech_id: String, loadout: Array = []) -> MechData:
	var m := fresh_mech("res://data/mechs/%s.json" % mech_id)
	if m == null:
		return fresh_bastion()
	if not loadout.is_empty():
		# A saved loadout can go stale when Refit Bay is re-imported: a part
		# that's gone, no longer fits the class, or no longer fits the chassis
		# is left out, and without a working hardpoint the default is used.
		var chassis := GridUtils.cells_to_set(m.cells)
		var taken := {}
		var parts: Array[ComponentData] = []
		var used := {}
		for p in loadout:
			if not ComponentLibrary.has(p["id"]) or not ComponentLibrary.fits_class(p["id"], m.weight_class):
				continue
			if ComponentLibrary.definition(p["id"]).get("rarity", "") != "surplus":
				continue # the Hangar is Surplus only (Logan, 2026-09-30)
			var comp := DataLoader.load_component({"id": p["id"], "offset": p["offset"], "rotation": int(p["rotation"])})
			if not comp.placed_cells.all(func(c): return chassis.has(c) and not taken.has(c)):
				continue
			for c in comp.placed_cells:
				taken[c] = true
			var id: String = p["id"]
			var n := 2
			while used.has(id):
				id = "%s_%d" % [p["id"], n]
				n += 1
			used[id] = true
			comp.set_instance_id(id)
			parts.append(comp)
		if parts.any(func(c): return c.category == ComponentData.CATEGORY_HARDPOINT):
			m.components = parts
	return m

# ---------- sector map locations (data/sectors.json) ----------

const SECTORS_PATH := "res://data/sectors.json"
var _sectors: Array = []

func sectors() -> Array:
	if _sectors.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(SECTORS_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			_sectors = parsed.get("locations", [])
		else:
			push_error("GameData: failed to parse %s" % SECTORS_PATH)
	return _sectors

func sector(id: String) -> Dictionary:
	for s in sectors():
		if s.get("id", "") == id:
			return s
	return {}

# ---------- combat backgrounds (data/backgrounds.json) ----------

const BACKGROUNDS_PATH := "res://data/backgrounds.json"
var _backgrounds: Array = []

func backgrounds() -> Array:
	if _backgrounds.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(BACKGROUNDS_PATH))
		_backgrounds = parsed.get("backgrounds", []) if typeof(parsed) == TYPE_DICTIONARY else []
	return _backgrounds

## A location's backgrounds for fights of this tier ("regular" / "elite" / "boss").
func backgrounds_for(location_id: String, tier: String) -> Array:
	return backgrounds().filter(func(b): return b.get("location", "") == location_id and b.get("tier", "") == tier)

# ---------- mission types and events ----------

const MISSIONS_PATH := "res://data/missions.json"
const EVENTS_PATH := "res://data/events.json"
var _missions: Dictionary = {}
var _events: Array = []

func missions() -> Dictionary:
	if _missions.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(MISSIONS_PATH))
		_missions = parsed.get("missions", {}) if typeof(parsed) == TYPE_DICTIONARY else {}
	return _missions

func mission(id: String) -> Dictionary:
	var m: Dictionary = missions().get(id, {}).duplicate(true)
	if not m.is_empty():
		m["id"] = id
	return m

func events() -> Array:
	if _events.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(EVENTS_PATH))
		_events = parsed.get("events", []) if typeof(parsed) == TYPE_DICTIONARY else []
	return _events

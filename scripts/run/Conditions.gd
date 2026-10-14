class_name Conditions
extends RefCounted
## Location modifiers and mission variants (data/conditions.json, Claude's
## drafts 2026-09-30; numbers in balance.json "conditions"): rules on top
## of a run, built only from existing statuses and run effects.
## - A location's `modifiers` (sectors.json) are always on there, and hit
##   every mech alike (the place, not the enemy): Rain (venting at max heat
##   drops), Jamming (hardpoints start fights Jammed), Dust (mechs start
##   fights with Smoke).
## - Each location's mission also rolls a variant with the sector
##   (Profile.sector_variants): Standard, Hardened, Supply Line, Low
##   Visibility, Blackout. The run's mission keeps it (mission "variant"),
##   so a saved run never changes.

const PATH := "res://data/conditions.json"

static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = parsed if typeof(parsed) == TYPE_DICTIONARY else {"modifiers": {}, "variants": []}
	return _data

static func num(id: String, key: String, fallback: float) -> float:
	return float(Balance.section("conditions").get(id, {}).get(key, fallback))

static func _fill(id: String, text: String) -> String:
	var vals := {}
	var nums: Dictionary = Balance.section("conditions").get(id, {})
	for k in nums:
		var v = nums[k]
		vals[k] = str(int(v)) if typeof(v) == TYPE_FLOAT and v == floorf(v) else str(v)
	return text.format(vals)

# ---------- variants ----------

static func variant_def(id: String) -> Dictionary:
	for v in data().get("variants", []):
		if v["id"] == id:
			var out: Dictionary = v.duplicate(true)
			out["summary"] = _fill(id, str(v.get("summary", "")))
			return out
	return {}

## A variant by the weights in balance.json conditions.variant_weights.
static func roll_variant(rng: RandomNumberGenerator) -> String:
	var weights: Dictionary = Balance.section("conditions").get("variant_weights", {"standard": 1})
	var ids: Array = weights.keys()
	ids.sort()
	var total := 0.0
	for id in ids:
		total += float(weights[id])
	var r := rng.randf() * total
	for id in ids:
		r -= float(weights[id])
		if r < 0.0:
			return id
	return ids[-1]

## The mission with its variant attached (what a run keeps).
static func with_variant(mission: Dictionary, variant_id: String) -> Dictionary:
	var m := mission.duplicate(true)
	if variant_id != "" and variant_id != "standard" and not m.get("training", false):
		m["variant"] = variant_def(variant_id)
	return m

static func variant(run_mission: Dictionary) -> Dictionary:
	return run_mission.get("variant", {})

# ---------- what they do ----------

## Whether location rules and sector-rolled variants are on (balance.json
## conditions.enabled). Off (Logan, 2026-10-13) until locations rotate and
## a pilot always has another place to go; the Daily still rolls a variant.
static func enabled() -> bool:
	return bool(Balance.section("conditions").get("enabled", true))

## Every modifier on a run: its location's (while enabled), then its variant's.
static func modifiers(location: Dictionary, mission: Dictionary) -> Array:
	var out: Array = location.get("modifiers", []).duplicate() if enabled() else []
	for m in variant(mission).get("modifiers", []):
		if not out.has(m):
			out.append(m)
	return out

## Statuses that go on at the start of every fight ({side, status, stacks,
## parts}, as events' next_fight entries).
static func fight_start(location: Dictionary, mission: Dictionary) -> Array:
	var out := []
	for id in modifiers(location, mission):
		match id:
			"jamming":
				for side in ["player", "enemy"]:
					out.append({"side": side, "status": "jam", "stacks": int(num(id, "stacks", 1)), "parts": "hardpoints"})
			"dust":
				for side in ["player", "enemy"]:
					out.append({"side": side, "status": "smoke", "stacks": int(num(id, "stacks", 2)), "parts": "mech"})
			"braced":
				out.append({"side": "enemy", "status": "deflect", "stacks": int(num(id, "stacks", 3)), "parts": "mech"})
			"blackout":
				for side in ["player", "enemy"]:
					out.append({"side": side, "status": "smoke", "stacks": int(num(id, "stacks", 2)), "parts": "mech"})
	return out

## How much less of its heat every mech vents at max (Rain), 0 = none.
static func vent_drop(location: Dictionary, mission: Dictionary) -> float:
	return num("rain", "vent_drop", 0.1) if modifiers(location, mission).has("rain") else 0.0

static func scraps_mult(mission: Dictionary) -> float:
	return num("supply_line", "scraps_mult", 1.25) if variant(mission).get("id", "") == "supply_line" else 1.0

static func elite_chance_mult(mission: Dictionary) -> float:
	return num("supply_line", "elite_chance_mult", 1.5) if variant(mission).get("id", "") == "supply_line" else 1.0

## Rows seen ahead on the map (Low Visibility), 0 = all.
static func sight_rows(mission: Dictionary) -> int:
	return int(num("low_visibility", "sight_rows", 3)) if variant(mission).get("id", "") == "low_visibility" else 0

# ---------- words ----------

static func modifier_name(id: String) -> String:
	return str(data().get("modifiers", {}).get(id, {}).get("name", id.capitalize()))

static func modifier_text(id: String) -> String:
	return _fill(id, str(data().get("modifiers", {}).get(id, {}).get("text", "")))

## Lines for the War Table pop-up and the location map: the variant (if
## not Standard), then each modifier.
static func describe(location: Dictionary, mission: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var v := variant(mission)
	if not v.is_empty():
		out.append("%s: %s" % [v.get("name", ""), v.get("summary", "")])
	for id in modifiers(location, mission):
		out.append(modifier_text(id))
	return out

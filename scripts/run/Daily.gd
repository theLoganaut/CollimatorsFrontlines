class_name Daily
extends RefCounted
## The Daily Operation (Claude's draft, 2026-09-30): one run a day that's
## the same for every pilot, picked from the date: its seed, location,
## mission, a mission variant (never Standard) and the mech, which drops
## with its default loadout. One scored attempt a day: launching it counts.
## The score (points in balance.json "daily") is kept in the profile, with
## the pilot's best.

## The day's operation: {date, seed, location_id, mission (with its
## variant and "daily": date), mech}.
static func setup(date: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("daily:" + date)
	var sectors: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/sectors.json"))["locations"]
	var missions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/missions.json"))["missions"]
	var mission_ids: Array = missions.keys().filter(func(id): return not missions[id].get("training", false))
	mission_ids.sort()
	var loc: Dictionary = sectors[rng.randi() % sectors.size()]
	var mid: String = mission_ids[rng.randi() % mission_ids.size()]
	var variant := "standard"
	for i in range(20): # a variant that isn't Standard
		variant = Conditions.roll_variant(rng)
		if variant != "standard":
			break
	var mission: Dictionary = missions[mid].duplicate(true)
	mission["id"] = mid
	mission = Conditions.with_variant(mission, variant)
	mission["daily"] = date
	var mechs := ["bastion", "jackal", "redline"]
	return {
		"date": date, "seed": rng.randi() % 1000000000, "location_id": loc["id"], "location": loc,
		"mission": mission, "mech": mechs[rng.randi() % mechs.size()],
	}

static func is_daily(run: RunData) -> bool:
	return run.mission.has("daily")

static func points(key: String, fallback: int) -> int:
	return Balance.get_int("daily", key, fallback)

## A finished daily's score: points per stop, elite and boss, a clear
## bonus, and a little for damage dealt.
static func score(run: RunData) -> int:
	var s := run.stats
	var total := run.path.size() * points("per_stop", 10) \
		+ s.get_stat("elites_beaten") * points("per_elite", 30) \
		+ s.get_stat("bosses_beaten") * points("per_boss", 100) \
		+ s.get_stat("damage_dealt") / maxi(1, points("damage_per_point", 50))
	if run.result == RunData.Result.CLEARED:
		total += points("clear_bonus", 200)
	return total

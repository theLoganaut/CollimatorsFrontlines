class_name TestMeta
extends RefCounted
## Meta-progression helpers (2026-09-30): ISO weeks for the weekly
## directives, day arithmetic for streaks, weekly rolls, and directive
## filters.

static func run_all(t: TestContext) -> void:
	_achievements(t)
	t.group("Operator: which lines he picks")
	var rep := {"result": "ejected", "stops": 5, "total": 10}
	t.assert_eq(Operator.pool_key({}, {}), "first_time", "no runs yet: first-time lines")
	t.assert_eq(Operator.pool_key(rep, {"stops": 3}), "paused", "a run left mid-mission comes first")
	t.assert_eq(Operator.pool_key(rep), "ejected", "ejected halfway: the middle pool")
	t.assert_eq(Operator.pool_key({"result": "ejected", "stops": 2, "total": 14}), "ejected_early", "2 encounters in: early")
	t.assert_eq(Operator.pool_key({"result": "ejected", "stops": 11, "total": 14}), "ejected_late", "past 70%: late")
	t.assert_eq(Operator.pool_key({"result": "cleared", "stops": 14, "total": 14}), "cleared", "cleared")
	var ops = JSON.parse_string(FileAccess.get_file_as_string(Operator.PATH))
	t.assert_true(["first_time", "paused", "cleared", "ejected_early", "ejected", "ejected_late"].all(func(k): return (ops.get(k, []) as Array).size() >= 3), "each pool has at least 3 lines")

	t.group("meta: weeks and days")
	t.assert_eq(Meta.week_of("2026-09-30"), "2026-W40", "Wednesday 30 September 2026 is in ISO week 40")
	t.assert_eq(Meta.week_of("2026-09-28"), "2026-W40", "…the week starts on Monday")
	t.assert_eq(Meta.week_of("2026-10-04"), "2026-W40", "…and ends on Sunday")
	t.assert_eq(Meta.week_of("2026-10-05"), "2026-W41", "the next Monday is a new week")
	t.assert_eq(Meta.week_of("2027-01-01"), "2026-W53", "1 January 2027 (a Friday) is in 2026's last week")
	t.assert_eq(Meta.day_before("2026-10-01"), "2026-09-30", "the day before")
	t.assert_eq(Meta.day_before("2027-01-01"), "2026-12-31", "…across a year")

	t.group("meta: weekly directives")
	var w := Meta.weeklies_for("2026-W40")
	t.assert_eq(w, Meta.weeklies_for("2026-W40"), "the same week rolls the same weeklies")
	t.assert_eq(w.size(), Balance.get_int("meta", "weekly_per_week", 2), "weekly_per_week of them")
	t.assert_true(w.all(func(id): return not Meta.directive(id).is_empty()), "each one exists")
	t.assert_eq(Meta.directive_defs().size(), 30, "30 dailies in the pool")

	t.group("meta: directive filters")
	var ship := RunData.new(GameData_sector("shipyard"), DataLoader.load_mech_from_file("res://data/mechs/bastion.json"), 3, {})
	ship.stats.add("fights_won", 4)
	var arch := RunData.new(GameData_sector("data_archives"), DataLoader.load_mech_from_file("res://data/mechs/bastion.json"), 3, {})
	arch.stats.add("fights_won", 4)
	var d := Meta.directive("shipyard")
	t.assert_eq(Meta.run_progress(d, ship), 4, "fights won at the Shipyard count for the Shipyard directive")
	t.assert_eq(Meta.run_progress(d, arch), 0, "…fights elsewhere don't")

static func GameData_sector(id: String) -> Dictionary:
	for loc in JSON.parse_string(FileAccess.get_file_as_string("res://data/sectors.json"))["locations"]:
		if loc["id"] == id:
			return loc
	return {}

static func _achievements(t: TestContext) -> void:
	t.group("meta: achievements")
	var ids := {}
	for d in Achievements.defs():
		t.assert_true(not ids.has(d["id"]), "achievement %s: id is unique" % d["id"])
		ids[d["id"]] = true
		t.assert_true(int(d.get("chips", 0)) > 0, "achievement %s pays Chips" % d["id"])
	var run := RunData.new(GameData_sector("shipyard"), DataLoader.load_mech_from_file("res://data/mechs/bastion.json"), 3, {})
	var career := {"runs": 1, "stats": {}, "mech_clears": {}, "mechs": ["bastion", "redline"], "streak": 0, "bosses_beaten": [], "bosses": ["a", "b"]}
	t.assert_true(Achievements.newly_earned(run, career, []).is_empty(), "a run with nothing done earns nothing")
	run.stats.add("fights_won")
	run.fight_log.append({"won": true, "turns": 5, "damage_taken": 0, "hp_left": 50, "hp_max": 100})
	var got := Achievements.newly_earned(run, career, []).map(func(d): return d["id"])
	t.assert_true(got.has("first_win") and got.has("untouched"), "a fight won with no damage taken: First Blood and Untouched")
	t.assert_true(not got.has("blitz") and not got.has("close_call"), "…but not Blitz (5 turns) or Close Call (half HP left)")
	t.assert_true(not Achievements.newly_earned(run, career, ["first_win"]).any(func(d): return d["id"] == "first_win"), "an achievement already held isn't earned again")
	run.fight_log.append({"won": false, "turns": 2, "damage_taken": 90, "hp_left": 5, "hp_max": 100})
	t.assert_true(not Achievements.newly_earned(run, career, []).any(func(d): return d["id"] == "blitz"), "a lost fight never counts")
	run.result = RunData.Result.CLEARED
	got = Achievements.newly_earned(run, career, []).map(func(d): return d["id"])
	t.assert_true(got.has("clear") and got.has("cool_head"), "a clear with no overheats: Sector Secured and Cool Head")
	run.stats.add("overheats")
	t.assert_true(not Achievements.newly_earned(run, career, []).any(func(d): return d["id"] == "cool_head"), "an overheat loses Cool Head")
	career["mech_clears"] = {"bastion": 2}
	t.assert_true(not Achievements.earned(Achievements.def("all_mechs"), run, career), "Full Hangar needs a clear with every mech")
	career["mech_clears"]["redline"] = 1
	t.assert_true(Achievements.earned(Achievements.def("all_mechs"), run, career), "…and has one")
	career["bosses_beaten"] = ["a", "b"]
	t.assert_true(Achievements.earned(Achievements.def("all_bosses"), run, career), "Hit List: every boss beaten")
	career["stats"] = {"damage_dealt": 10000}
	t.assert_true(Achievements.earned(Achievements.def("damage_10k"), run, career), "career totals count across runs")


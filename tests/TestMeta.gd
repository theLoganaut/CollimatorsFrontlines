class_name TestMeta
extends RefCounted
## Meta-progression helpers (2026-09-30): ISO weeks for the weekly
## directives, day arithmetic for streaks, weekly rolls, and directive
## filters.

static func run_all(t: TestContext) -> void:
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

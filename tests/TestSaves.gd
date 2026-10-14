class_name TestSaves
extends RefCounted
## Saves from released builds must keep loading (tests/fixtures/saves/,
## one or more per save version, never edited): an update that would break
## a tester's run in progress fails here first. Add a fixture whenever
## RunData.SAVE_VERSION goes up.

const DIR := "res://tests/fixtures/saves"

static func _location(id: String) -> Dictionary:
	for loc in JSON.parse_string(FileAccess.get_file_as_string("res://data/sectors.json"))["locations"]:
		if loc["id"] == id:
			return loc
	return {}

static func run_all(t: TestContext) -> void:
	t.group("Saves from earlier builds still load")
	var files := Array(DirAccess.get_files_at(DIR)).filter(func(f): return f.ends_with(".json"))
	t.assert_true(files.size() >= 3, "fixtures are there (%d)" % files.size())
	for f in files:
		var d: Dictionary = SaveMigration.migrate(JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [DIR, f])))
		var why := SaveMigration.problems(d)
		t.assert_eq(why, [] as Array[String], "%s: everything it refers to still exists" % f)
		var run := RunSave.from_dict(d, _location(str(d["location_id"])), d.get("mission", {}))
		t.assert_eq(run.player_mech.components.size(), (d["mech"] as Array).size(), "%s: every part on the mech came back" % f)
		t.assert_eq(run.cargo.items.size() + run.bench.items.size(), (d["cargo"]["items"] as Array).size() + (d["bench"] as Array).size(), "%s: Cargo and bench too" % f)
		t.assert_true(run.player_mech.components.any(func(c): return c.category == ComponentData.CATEGORY_HARDPOINT), "%s: it still has a weapon" % f)

	t.group("A save that can't load is caught, not half-loaded")
	var bad: Dictionary = SaveMigration.migrate(JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [DIR, files[0]])))
	bad["mech"][0]["library_id"] = "part_removed_in_an_update"
	t.assert_true(SaveMigration.problems(bad).has("part 'part_removed_in_an_update'"), "a removed part is named")
	var newer := bad.duplicate(true)
	newer["v"] = RunData.SAVE_VERSION + 1
	t.assert_true(SaveMigration.problems(newer)[0].begins_with("saved by a newer version"), "a save from a newer build is refused")

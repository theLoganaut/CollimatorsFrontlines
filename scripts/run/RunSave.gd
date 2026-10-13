class_name RunSave
extends RefCounted
## Saving and loading a run, for RunData: to_dict / from_dict (versioned by
## RunData.SAVE_VERSION; SaveMigration upgrades older saves first).

static func to_dict(run: RunData) -> Dictionary:
	return {
		"v": RunData.SAVE_VERSION, "location_id": run.location.get("id", ""), "seed": run.seed_value, "mission_id": run.mission.get("id", ""),
		"mission": run.mission,
		"mech_path": "res://data/mechs/%s.json" % run.player_mech.id,
		"event": run.event, "next_fight": run.next_fight, "alert_turns": run.alert_turns, "orders": run.orders, "mods": run.mods,
		"boss_intel": run.boss_intel, "boss_intel_used": run.boss_intel_used, "bosses_met": run.bosses_met,
		"fight_rolls": run.fight_rolls, "encounter_history": run.encounter_history, "events_seen": run.events_seen, "fight_log": run.fight_log,
		"resumes": run.resumes,
		"rng_state": str(run.rng.state), "phase": run.phase, "current_node_id": run.current_node_id,
		"path": run.path, "fights_won": run.fights_won, "result": run.result, "scraps": run.scraps, "end_cause": run.end_cause,
		"reward": run.reward, "shop": run.shop, "cargo_upgrades": run.cargo_upgrades, "repair_pool": run.repair_pool,
		"cells_bought": run.cells_bought, "frame": run.player_mech.cells.map(func(c): return [c.x, c.y]),
		"base_bounds": [run.base_bounds.position.x, run.base_bounds.position.y, run.base_bounds.size.x, run.base_bounds.size.y],
		"stats": run.stats.to_dict(),
		"mech": parts_to_list(run.player_mech.components),
		"cargo": {"rows": run.cargo.rows, "cols": run.cargo.cols, "items": parts_to_list(run.cargo.items)},
		"bench": parts_to_list(run.bench.items),
	}

static func from_dict(d: Dictionary, p_location: Dictionary, p_mission: Dictionary = {}) -> RunData:
	var mech := DataLoader.load_mech_from_file(d.get("mech_path", RunData.MECH_PATH))
	mech.components = parts_from_list(d.get("mech", []))
	var original: Array[Vector2i] = mech.cells.duplicate()
	if d.has("frame"): # squares bought at autonomous bays
		mech.cells.clear()
		for c in d["frame"]:
			mech.cells.append(Vector2i(int(c[0]), int(c[1])))
	var run := RunData.new(p_location, mech, int(d["seed"]), p_mission)
	if d.has("base_bounds"):
		var b: Array = d["base_bounds"]
		run.base_bounds = Rect2i(int(b[0]), int(b[1]), int(b[2]), int(b[3]))
	else: # an older save: find where the original chassis sits in the frame
		run.base_bounds = find_base_bounds(original, mech.cells)
	run.orders = d.get("orders", {})
	run.mods = d.get("mods", {})
	if run.mods.has("map_odds"):
		run.build_map()
	run.event = d.get("event", {})
	run.next_fight = d.get("next_fight", [])
	run.alert_turns = int(d.get("alert_turns", 0))
	run.boss_intel = bool(d.get("boss_intel", false))
	run.boss_intel_used = bool(d.get("boss_intel_used", false))
	run.bosses_met = d.get("bosses_met", [])
	run.encounter_history = d.get("encounter_history", [])
	run.events_seen = d.get("events_seen", [])
	run.fight_log = d.get("fight_log", [])
	run.resumes = d.get("resumes", [])
	var rolls: Dictionary = d.get("fight_rolls", {})
	for k in rolls:
		run._set_fight_enemies(int(k), rolls[k])
	run.rng.state = int(str(d.get("rng_state", "0")))
	run.phase = d.get("phase", RunData.PHASE_MAP)
	run.current_node_id = int(d.get("current_node_id", -1))
	for id in d.get("path", []):
		run.path.append(int(id))
	run.fights_won = int(d.get("fights_won", 0))
	run.result = int(d.get("result", RunData.Result.NONE)) as RunData.Result
	run.end_cause = str(d.get("end_cause", ""))
	run.scraps = int(d.get("scraps", d.get("chips", 0))) # "chips" before the rename
	run.reward = d.get("reward", {})
	run.shop = d.get("shop", {})
	run.cargo_upgrades = int(d.get("cargo_upgrades", 0))
	run.cells_bought = int(d.get("cells_bought", 0))
	run.repair_pool = int(d.get("repair_pool", 0))
	run.stats = RunStats.from_dict(d.get("stats", {}))
	var cg: Dictionary = d.get("cargo", {})
	run.cargo = CargoGrid.new(int(cg.get("rows", CargoGrid.START_SIZE)), int(cg.get("cols", CargoGrid.START_SIZE)))
	for c in parts_from_list(cg.get("items", [])):
		run.cargo.items.append(c)
	for c in parts_from_list(d.get("bench", [])):
		run.bench.items.append(c)
	run.apply_mech_mods()
	return run

## The original chassis' bounds inside a saved frame (shifted by 0 or 1
## each way when squares were added above or left of it).
static func find_base_bounds(original: Array[Vector2i], frame: Array[Vector2i]) -> Rect2i:
	var have := GridUtils.cells_to_set(frame)
	var b := GridUtils.bounds_of(original)
	for shift in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		if original.all(func(c): return have.has(c + shift)):
			return Rect2i(b.position + shift, b.size)
	return b

static func parts_to_list(parts: Array[ComponentData]) -> Array:
	var out := []
	for c in parts:
		var p := {"id": c.id, "library_id": c.library_id, "offset": [c.offset.x, c.offset.y],
			"rotation": c.rotation_steps, "hp": c.current_hp, "destroyed": c.destroyed}
		if c.max_hp != int(ComponentLibrary.definition(c.library_id).get("hp", c.max_hp)):
			p["max_hp"] = c.max_hp # changed for this run (Modular Chassis)
		out.append(p)
	return out

static func parts_from_list(list: Array) -> Array[ComponentData]:
	var out: Array[ComponentData] = []
	for p in list:
		var c := ComponentLibrary.make(p["library_id"])
		if c == null:
			continue
		c.set_instance_id(p["id"])
		c.place(int(p.get("rotation", 0)), Vector2i(int(p["offset"][0]), int(p["offset"][1])))
		c.max_hp = int(p.get("max_hp", c.max_hp))
		c.current_hp = int(p.get("hp", c.max_hp))
		c.destroyed = bool(p.get("destroyed", false))
		out.append(c)
	return out

class_name TestPhases
extends RefCounted
## Phases 6-8 (Logan, 2026-09-28): encounter pools, the enemy AI and its
## protocols, boss phases, the enemy roster from Refit Bay, and meta
## progression (Chips, directives, liveries).

static func _mission(id: String) -> Dictionary:
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/missions.json"))["missions"][id].duplicate(true)
	m["id"] = id
	return m

static func _sector(id: String) -> Dictionary:
	for loc in JSON.parse_string(FileAccess.get_file_as_string("res://data/sectors.json"))["locations"]:
		if loc["id"] == id:
			return loc
	return {}

static func _bastion() -> MechData:
	return DataLoader.load_mech_from_file("res://tests/fixtures/bastion_classic.json")

## Plays a run's map without fighting: wins every fight, leaves every stop.
static func _walk(run: RunData, on_fight: Callable) -> void:
	var guard := 0
	while not run.is_over() and guard < 60:
		guard += 1
		match run.phase:
			RunData.PHASE_MAP:
				var opts := run.available_nodes()
				if opts.is_empty():
					return
				run.choose_node(opts[0])
			RunData.PHASE_FIGHT:
				on_fight.call(run)
				run.fight_won()
			RunData.PHASE_REWARD:
				run.finish_reward()
			RunData.PHASE_REFIT:
				run.finish_refit()
			RunData.PHASE_REPAIR:
				run.finish_repair()
			RunData.PHASE_SHOP:
				run.leave_shop()
			RunData.PHASE_EVENT:
				run.resolve_event(0)
				run.finish_event()

static func run_all(t: TestContext) -> void:
	t.group("balance.json: the tuning numbers live in one file")
	t.assert_eq(Economy.price("autocannon"), int(Balance.get_dict("economy", "prices")["surplus"]), "prices come from balance.json")

	t.group("Encounters: weak pool first, then strong; three-enemy fights only from strong")
	var shipyard := _sector("shipyard")
	var weak: Array = shipyard["encounters"]["weak"].map(func(e): return ",".join(e["enemies"]))
	var strong: Array = shipyard["encounters"]["strong"].map(func(e): return ",".join(e["enemies"]))
	var acc := {"order_ok": true, "three": 0, "strong": 0, "recon_ok": true}
	var repeats := 0
	var weak_n := Balance.get_int("encounters", "weak_fights", 3)
	for seed_value in range(1, 61):
		var run := RunData.new(shipyard, _bastion(), seed_value, _mission("assault"))
		var n := [0]
		_walk(run, func(r: RunData):
			if r.current_node()["kind"] != RunMap.KIND_FIGHT:
				return
			var key := ",".join(r.current_node()["enemies"])
			if n[0] < weak_n and not weak.has(key):
				acc["order_ok"] = false
			if n[0] >= weak_n:
				acc["strong"] += 1
				if not strong.has(key):
					acc["order_ok"] = false
				if (r.current_node()["enemies"] as Array).size() == 3:
					acc["three"] += 1
			n[0] += 1)
		for i in range(1, run.encounter_history.size()):
			if run.encounter_history[i] == run.encounter_history[i - 1]:
				repeats += 1
	t.assert_true(acc["order_ok"], "the first %d regular fights come from the weak pool, the rest from the strong pool (60 runs)" % weak_n)
	t.assert_true(acc["three"] > 0 and acc["three"] < acc["strong"], "three-enemy fights happen, but not every strong fight (%d of %d)" % [acc["three"], acc["strong"]])
	t.assert_eq(repeats, 0, "the same encounter never comes twice in a row")
	for seed_value in range(1, 31):
		var rr := RunData.new(_sector("mining_grounds"), _bastion(), seed_value, _mission("deep_recon"))
		_walk(rr, func(r: RunData):
			if r.current_node()["kind"] == RunMap.KIND_FIGHT and (r.current_node()["enemies"] as Array).size() > 2:
				acc["recon_ok"] = false)
	t.assert_true(acc["recon_ok"], "Deep Recon's regular fights never have more than 2 enemies")
	var a := RunData.new(shipyard, _bastion(), 99, _mission("assault"))
	var b := RunData.new(shipyard, _bastion(), 99, _mission("assault"))
	a.choose_node(a.available_nodes()[1])
	b.choose_node(b.available_nodes()[1])
	t.assert_eq(a.current_node()["enemies"], b.current_node()["enemies"], "same seed and path, same fight")
	var back := RunData.from_dict(a.to_dict(), shipyard, _mission("assault"))
	t.assert_eq(back.current_node()["enemies"], a.current_node()["enemies"], "a rolled fight survives save and load")
	t.assert_true((a.map.nodes_in_row(3).filter(func(nd): return nd["kind"] == RunMap.KIND_FIGHT and not nd["enemies"].is_empty())).is_empty(), "fights not yet entered stay unrolled (hidden on the map)")

	t.group("Enemy roster: every enemy from Refit Bay fits its frame")
	var sizes := {"regular": [4, 10, 12], "elite": [5, 16, 16], "boss": [6, 20, 20]}
	var ids := ["scrap_warden", "rivet_brute", "needle_drone", "arc_sentry", "ember_hound", "siege_warden", "caustic_engine",
		"dock_breaker", "relay_sentinel", "bore_crawler", "anchor", "bedrock", "cipher"]
	var bad_frames: Array[String] = []
	var bad_parts: Array[String] = []
	for id in ids:
		var m := DataLoader.load_mech_from_file("res://data/mechs/%s.json" % id)
		var sz: Array = sizes[m.tier]
		var frame := GridUtils.cells_to_set(m.cells)
		if not (m.cells.all(func(c): return c.x < sz[0] and c.y < sz[0]) and m.cells.size() >= sz[1] and m.cells.size() <= sz[2]):
			bad_frames.append(id)
		var fit := m.components.any(func(c): return c.category == ComponentData.CATEGORY_HARDPOINT)
		var seen := {}
		for c in m.components:
			for cell in c.placed_cells:
				if not frame.has(cell) or seen.has(cell):
					fit = false
				seen[cell] = true
		if not fit:
			bad_parts.append(id)
	t.assert_eq(bad_frames, [] as Array[String], "every enemy's frame fits its tier (regular 4×4 of 10–12 cells, elite 5×5 of 16, boss 6×6 of 20)")
	t.assert_eq(bad_parts, [] as Array[String], "every enemy's parts sit on its frame without overlapping, with a hardpoint")
	var bedrock := DataLoader.load_mech_from_file("res://data/mechs/bedrock.json")
	var hammer := bedrock.get_component("impact_hammer")
	t.assert_true(bedrock.cover_for(hammer) != null and bedrock.cover_for(hammer).library_id == "plated_housing", "a Plated Housing guards the part it faces (Bedrock's hammer)")

	t.group("Enemy AI: targets by profile, with slips")
	var p1 := TestFixtures.make_component("gun", 60, [])
	p1.category = ComponentData.CATEGORY_HARDPOINT
	var p2 := TestFixtures.make_component("core", 20, [])
	p2.category = ComponentData.CATEGORY_REACTOR
	var p3 := TestFixtures.make_component("gun2", 30, [])
	p3.category = ComponentData.CATEGORY_HARDPOINT
	var player := TestFixtures.make_mech("p", 14, [p1, p2, p3])
	var enemy := TestFixtures.make_mech("e", 8, [])
	var counts := {"hardpoints": 0, "weakest": 0, "strongest": 0, "systems": 0}
	for style in counts.keys():
		enemy.ai = {"targets": style, "slip": 0.0}
		for s in range(40):
			var tgt := EnemyAI.choose_target(player, TestFixtures.rng(s), enemy)
			match style:
				"hardpoints": counts[style] += 1 if tgt.category == ComponentData.CATEGORY_HARDPOINT else 0
				"weakest": counts[style] += 1 if tgt == p2 else 0
				"strongest": counts[style] += 1 if tgt == p1 else 0
				"systems": counts[style] += 1 if tgt == p2 else 0
	t.assert_eq(counts, {"hardpoints": 40, "weakest": 40, "strongest": 40, "systems": 40}, "hardpoints / weakest / strongest / systems each pick their part")
	enemy.ai = {"targets": "strongest", "slip": 1.0}
	var picks := {}
	for s in range(60):
		picks[EnemyAI.choose_target(player, TestFixtures.rng(s), enemy).id] = true
	t.assert_eq(picks.size(), 3, "a slip picks at random (slip 1.0 hits every part)")
	enemy.ai = {"targets": "focus", "slip": 0.0}
	t.assert_eq(EnemyAI.choose_target(player, TestFixtures.rng(1), enemy, null, {enemy: p3}).id, "gun2", "focus keeps hitting the part it hit last")
	var emp := ComponentLibrary.make("hv_rifle").cards.filter(func(c): return c.id == "emp_round")[0] as CardData
	p3.add_status("shock", 1)
	enemy.ai = {"targets": "strongest", "slip": 0.0}
	t.assert_eq(EnemyAI.choose_target(player, TestFixtures.rng(1), enemy, emp).id, "gun2", "EMP Round goes for the shocked hardpoint, whatever the style")

	t.group("Enemy protocols: primed, then used up by the next attack")
	var drone := DataLoader.load_mech_from_file("res://data/mechs/needle_drone.json")
	drone.ai["protocols"] = 1.0
	var bast := _bastion()
	var cm := CombatManager.new(bast, [drone] as Array[MechData], 3)
	cm.start_combat()
	var plan: Array = cm.enemy_plans[drone]
	var types := plan.map(func(s): return (s["card"] as CardData).protocol())
	t.assert_true(types.has("lock_on"), "the Needle Drone plans a Lock On")
	t.assert_true(types.find("lock_on") < plan.size() - 1, "ahead of an attack")
	t.assert_true(plan.all(func(s): return (s["card"] as CardData).protocol() != "" or s.has("target")), "every attack is planned at a part of yours (shown on hover)")
	cm.auto_resolve_enemy_turn = false
	cm.end_player_turn()
	var primed_seen := false
	var mult_used := false
	while true:
		var act := cm.next_enemy_action()
		if act.is_empty():
			break
		cm.begin_enemy_attack(act)
		if (act["card"] as CardData).protocol() == "lock_on":
			primed_seen = not (cm.enemy_primed.get(drone, []) as Array).is_empty()
		elif primed_seen and not mult_used:
			mult_used = (cm.enemy_primed.get(drone, []) as Array).is_empty()
		cm.finish_attack()
	t.assert_true(primed_seen and mult_used, "Lock On primes, and the next attack uses it up")

	t.group("Enemy Standby: the next attack waits a turn, then fires for 0 heat")
	var sb_part := ComponentLibrary.make("queue_processor")
	sb_part.place(0, Vector2i(0, 0))
	var hit_part := ComponentLibrary.make("autocannon")
	hit_part.place(0, Vector2i(2, 0))
	var sb_mech := TestFixtures.make_mech("sb", 20, [sb_part, hit_part] as Array[ComponentData])
	sb_mech.ai = {"protocols": 1.0, "slip": 0.0, "cards": "damage"}
	var target_mech := _bastion()
	var cm2 := CombatManager.new(target_mech, [sb_mech] as Array[MechData], 5)
	cm2.start_combat()
	var hp0 := target_mech.current_hp()
	cm2.end_player_turn() # standby primes, the autocannon's attack is set aside
	t.assert_true(not (cm2.enemy_standby.get(sb_mech, {}) as Dictionary).is_empty(), "the attack is set aside")
	t.assert_eq(target_mech.current_hp(), hp0, "nothing hit this turn")
	cm2.end_player_turn()
	t.assert_true(target_mech.current_hp() < hp0, "it fires at the start of the enemy's next turn")

	t.group("Boss phases: at half HP a boss changes tactics, once")
	var anchor := DataLoader.load_mech_from_file("res://data/mechs/anchor.json")
	t.assert_true(not anchor.in_phase2(), "full HP: phase 1")
	t.assert_eq(EnemyAI.profile(anchor)["targets"], "focus", "Vasquez opens methodical")
	for c in anchor.components:
		c.current_hp = int(c.max_hp * 0.45)
	t.assert_true(anchor.in_phase2(), "below half: phase 2")
	t.assert_eq(EnemyAI.profile(anchor)["targets"], "hardpoints", "then goes for your weapons")
	for c in anchor.components:
		c.current_hp = c.max_hp
	t.assert_true(anchor.in_phase2(), "and stays switched")
	var anchor2 := DataLoader.load_mech_from_file("res://data/mechs/anchor.json")
	var cm3 := CombatManager.new(_bastion(), [anchor2] as Array[MechData], 1)
	var phases := [0]
	cm3.boss_phase_changed.connect(func(_m): phases[0] += 1)
	cm3.start_combat()
	var big := TestFixtures.make_card("big", "neon_axe", 0, 1, 70, 70)
	for i in range(3):
		if cm3.is_player_turn() and not anchor2.non_destroyed_components().is_empty():
			cm3.reload(big)
			cm3.play_attack_card(big, anchor2, anchor2.non_destroyed_components()[0])
	t.assert_eq(phases[0], 1, "the phase change fires once")

	t.group("Meta: Chips per run, daily directives, liveries")
	var run := RunData.new(shipyard, _bastion(), 4, _mission("assault"))
	run.stats.add("fights_won", 7)
	run.stats.add("elites_beaten", 1)
	run.stats.add("bosses_beaten", 1)
	run.result = RunData.Result.CLEARED
	var mb := func(k: String) -> int: return Balance.get_int("meta", k, 0)
	t.assert_eq(Meta.chips_for_run(run), 5 * mb.call("chips_per_fight") + mb.call("chips_per_elite") + mb.call("chips_per_boss") + mb.call("chips_for_clear"), "5 fights, an elite, a boss and the clear")
	var day := Meta.directives_for("2026-09-28")
	t.assert_eq(day.size(), 3, "three directives a day")
	t.assert_eq(day, Meta.directives_for("2026-09-28"), "the same three all day")
	t.assert_true(day != Meta.directives_for("2026-09-29"), "different ones tomorrow")
	var d_win := Meta.directive("win_fights")
	t.assert_eq(Meta.run_progress(d_win, run), 7, "sum directives count the run's stat")
	t.assert_eq(Meta.run_progress(Meta.directive("redline_fights"), run), 0, "mech directives only count that mech")
	t.assert_eq(Meta.run_progress(Meta.directive("big_hit"), run), 0, "one-run goals need the number in one run")
	run.stats.record_max("biggest_hit", 40)
	t.assert_eq(Meta.run_progress(Meta.directive("big_hit"), run), 1, "and count once when reached")
	var prof = load("res://scripts/run/Profile.gd").new()
	prof.directives = {"date": Meta.today(), "ids": ["win_fights", "elites", "spend"], "progress": {}, "done": []}
	var done: Array = prof.advance_directives(run)
	t.assert_eq(done.map(func(f): return f["id"]), ["win_fights"], "Win 6 fights finishes; the others don't")
	t.assert_eq(prof.chips, int(d_win["chips"]), "and pays its Chips")
	t.assert_eq(prof.todays_directives()["progress"]["elites"], 1, "partial progress is kept for the day")
	t.assert_eq(prof.advance_directives(run).map(func(f): return f["id"]), ["elites"], "a second run finishes the elites one")
	prof.free()
	t.assert_eq(Meta.memorial_points_for(1, 1), 1 + 2 + 5, "Memorial points: the run, its elite and its boss")
	t.assert_eq([Meta.memorial_trophies(0, 14), Meta.memorial_trophies(1, 14), Meta.memorial_trophies(6, 14), Meta.memorial_trophies(999, 14)],
		[0, 1, 2, 14], "the wall starts empty, lights its candle on the first run, grows, and stops when full")
	t.assert_eq(Meta.livery_price(Meta.livery("standard_issue")), 0, "Standard Issue is free")

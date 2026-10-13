class_name TestRun
extends RefCounted
## The run loop's data side: sector data, MapGenerator's map shape, and
## RunData's node picking, win/loss and full carry-over between fights.

const RAMP := [1, 1, 2, 2, 2, 3, 3]

static func _location() -> Dictionary:
	return {"id": "test", "name": "Test", "enemy": "scrap_warden", "enemy_ramp": RAMP}

static func run_all(t: TestContext) -> void:
	t.group("sectors.json: Shipyard, Data Archives, Mining Grounds, with enemy pools")
	var sectors = JSON.parse_string(FileAccess.get_file_as_string("res://data/sectors.json"))
	var locations: Array = sectors.get("locations", [])
	t.assert_eq(locations.map(func(l): return l["name"]), ["Shipyard", "Data Archives", "Mining Grounds"], "Logan's three locations")
	var keys_ok := true
	var enemies_ok := true
	for loc in locations:
		keys_ok = keys_ok and ["id", "name", "description", "map_zone", "regulars", "elites", "boss"].all(func(k): return loc.has(k))
		for id in loc.get("regulars", []) + loc.get("elites", []) + [loc.get("boss", "")]:
			enemies_ok = enemies_ok and FileAccess.file_exists("res://data/mechs/%s.json" % id)
	t.assert_true(keys_ok, "every location has its id, name, description, map spot and enemy pools")
	t.assert_true(enemies_ok, "every enemy they name has a mech file")

	t.group("WarMap: the War Table's theater, generated from the sector seed")
	var placed_ok := true
	for sd in [1, 77, 4242, 90210, 123456]:
		var wm := WarMap.generate(sd, locations)
		var again := WarMap.generate(sd, locations)
		placed_ok = placed_ok and wm.heights == again.heights and wm.sites == again.sites
		var ship: Vector2 = wm.sites["shipyard"]
		var mine: Vector2 = wm.sites["mining_grounds"]
		var arch: Vector2 = wm.sites["data_archives"]
		var shore_water := false
		for dx in range(1, 12):
			var probe := ship + Vector2((-0.01 if wm.sea_left else 0.01) * dx, 0)
			shore_water = shore_water or wm.is_water(probe)
		placed_ok = placed_ok and shore_water # the Shipyard is on the water
		placed_ok = placed_ok and not wm.is_water(ship) and not wm.is_water(mine) and not wm.is_water(arch)
		placed_ok = placed_ok and arch.y < ship.y and arch.y < mine.y # Data Archives deepest behind their lines
		placed_ok = placed_ok and (mine.x > 0.7 if wm.sea_left else mine.x < 0.3) # the Mining Grounds on the far flank
		for uv in [ship, mine, arch]:
			placed_ok = placed_ok and uv.y < wm.front_at(uv.x) # every location is behind the enemy's front
		placed_ok = placed_ok and wm.hq.y > wm.front_at(wm.hq.x)
	t.assert_true(placed_ok, "same seed, same map; Shipyard on the shore, Mining Grounds on the flank, Data Archives in the backlines, all behind the front")
	t.assert_true(WarMap.generate(1, locations).heights != WarMap.generate(2, locations).heights, "a new seed is a new landscape")

	t.group("Missions: Assault and Rescue end in a boss stop; Deep Recon is longer, no boss")
	var missions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/missions.json"))["missions"]
	var shipyard: Dictionary = locations[0]
	for mid in ["assault", "rescue", "deep_recon"]:
		var mdef: Dictionary = missions[mid].duplicate(true)
		mdef["id"] = mid
		var mr := RunData.new(shipyard, DataLoader.load_mech_from_file("res://tests/fixtures/bastion_classic.json"), 31, mdef)
		var top := mr.map.nodes_in_row(mr.map.row_count - 1)
		if mdef["boss"]:
			t.assert_eq(mr.map.row_count, int(mdef["rows"]) + 2, "%s: %d rows + a repair bay + the boss stop" % [mid, int(mdef["rows"])])
			var bay := mr.map.nodes_in_row(int(mdef["rows"]))
			t.assert_true(bay.size() == 1 and bay[0]["kind"] == RunMap.KIND_REPAIR and bay[0]["next"] == [top[0]["id"]], "%s: one repair bay, straight into the boss" % mid)
			t.assert_true(top.size() == 1 and top[0]["kind"] == RunMap.KIND_BOSS and top[0]["enemies"] == ["anchor"], "%s: one boss stop, Anchor" % mid)
			var all_lead := true
			for n in mr.map.nodes_in_row(int(mdef["rows"]) - 1):
				if n["next"] != [bay[0]["id"]]:
					all_lead = false
			t.assert_true(all_lead, "%s: every path leads through the bay into it" % mid)
		else:
			t.assert_eq(mr.map.row_count, int(mdef["rows"]), "Deep Recon: its rows, no boss stop")
			t.assert_true(int(mdef["rows"]) > int(missions["assault"]["rows"]), "and longer than Assault")
			t.assert_true(not mr.map.nodes.any(func(n): return n["kind"] == RunMap.KIND_BOSS), "no boss")
		var pools_ok := true
		for n in mr.map.nodes:
			for e in n["enemies"]:
				var pool: Array = shipyard["regulars"] + shipyard["elites"] + [shipyard["boss"]]
				if not pool.has(e):
					pools_ok = false
		t.assert_true(pools_ok, "%s: enemies come from the Shipyard's pools" % mid)
		t.assert_true(mr.map.nodes.any(func(n): return n["kind"] == RunMap.KIND_ELITE), "%s: at least one elite" % mid)
		t.assert_true(mr.map.nodes.any(func(n): return n["kind"] == RunMap.KIND_EVENT), "%s: at least one event" % mid)

	t.group("Rescue: Alert rises with turns fought and braces later fights")
	var rdef: Dictionary = missions["rescue"].duplicate(true)
	rdef["id"] = "rescue"
	var rs := RunData.new(shipyard, DataLoader.load_mech_from_file("res://tests/fixtures/bastion_classic.json"), 32, rdef)
	rs.choose_node(rs.available_nodes()[0])
	var fs := RunStats.new()
	var per_tier := int(rdef["alert"]["turns_per_tier"])
	fs.add("turns_taken", per_tier * 2 + 1)
	rs.fight_won(fs)
	t.assert_eq(rs.alert_tier(), 2, "%d turns fought = Alert 2 (a tier per %d turns)" % [per_tier * 2 + 1, per_tier])
	rs.finish_reward()
	var nid: int = rs.available_nodes()[0]
	rs.current_node_id = nid
	rs.map.nodes[nid]["kind"] = RunMap.KIND_FIGHT
	rs.map.nodes[nid]["enemies"] = ["scrap_warden"]
	var foes := rs.encounter_enemies()
	rs.apply_fight_start_effects(rs.player_mech, foes)
	t.assert_eq(foes[0].mech_status_stacks("deflect"), 4, "every enemy starts braced: Deflect 2 per tier")

	t.group("Deep Recon intel: the next boss's hardpoints start Disabled, once")
	var adef: Dictionary = missions["assault"].duplicate(true)
	adef["id"] = "assault"
	var br := RunData.new(shipyard, DataLoader.load_mech_from_file("res://tests/fixtures/bastion_classic.json"), 33, adef)
	br.boss_intel = true
	var boss_node := br.map.nodes_in_row(br.map.row_count - 1)[0]
	br.current_node_id = boss_node["id"]
	var boss_foes := br.encounter_enemies()
	br.apply_fight_start_effects(br.player_mech, boss_foes)
	var all_down := true
	for c in boss_foes[0].components:
		if c.category == ComponentData.CATEGORY_HARDPOINT and c.status_stacks("disabled") != 1:
			all_down = false
	t.assert_true(all_down, "every boss hardpoint is Disabled 1 (lasts its first turn)")
	t.assert_true(br.boss_intel_used, "the intel is spent")
	t.assert_true(br.bosses_met.has("anchor"), "and Anchor is recorded as met")

	t.group("Events: a choice applies its outcome, once")
	var ev := _new_run(34)
	ev.phase = RunData.PHASE_EVENT
	ev.current_node_id = ev.available_nodes()[0] if not ev.available_nodes().is_empty() else 0
	ev.event = {"id": "wrecked_convoy", "resolved": false, "result": ""}
	var text := ev.resolve_event(1)
	t.assert_eq(ev.scraps, 60, "Drain the fuel cells: +60 scraps")
	t.assert_true(text.begins_with("Sixty scraps."), "shows the choice's result")
	t.assert_eq(ev.resolve_event(0), "", "an event resolves once")
	var ev2 := _new_run(35)
	ev2.phase = RunData.PHASE_EVENT
	ev2.event = {"id": "live_relay", "resolved": false, "result": ""}
	ev2.resolve_event(0)
	t.assert_eq(ev2.next_fight.size(), 2, "Charge your shielding waits for the next fight (your Absorb, their Deflect)")
	ev2.current_node_id = 0
	ev2.apply_fight_start_effects(ev2.player_mech, [] as Array[MechData])
	t.assert_eq(ev2.player_mech.mech_status_stacks("absorb"), 40, "and gives Absorb 40 when it starts")

	t.group("MapGenerator: 7 rows of 2–4 fights, every node reachable, no crossing links")
	var shape_ok := true
	var links_ok := true
	var reach_ok := true
	var cross_ok := true
	var ramp_ok := true
	for seed_value in range(1, 201):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var map := MapGenerator.generate(rng, RAMP)
		if map.row_count != 7:
			shape_ok = false
		var incoming := {}
		for r in range(map.row_count):
			var row := map.nodes_in_row(r)
			if row.size() < (Balance.get_int("map", "start_min", 3) if r == 0 else Balance.get_int("map", "min_per_row", 2)) or row.size() > Balance.get_int("map", "max_per_row", 4):
				shape_ok = false
			for n in row:
				if n["kind"] == RunMap.KIND_FIGHT and n["enemy_count"] != RAMP[r]:
					ramp_ok = false
				if not map.is_last_row(r) and n["next"].is_empty():
					links_ok = false
				for to_id in n["next"]:
					if map.get_map_node(to_id)["row"] != r + 1:
						links_ok = false
					incoming[to_id] = true
		for n in map.nodes:
			if n["row"] > 0 and not incoming.has(n["id"]):
				reach_ok = false
		# Links between two rows cross if one starts further left but ends further right.
		for r in range(map.row_count - 1):
			var edges := []
			for n in map.nodes_in_row(r):
				for to_id in n["next"]:
					edges.append([n["x"], map.get_map_node(to_id)["x"]])
			for a in edges:
				for b in edges:
					if a[0] < b[0] and a[1] > b[1]:
						cross_ok = false
	t.assert_true(shape_ok, "7 rows; row 0 has 3–4 starting spots, the rest 2–4 nodes (200 seeds)")
	t.assert_true(links_ok, "every node below the top links only into the next row, at least once")
	t.assert_true(reach_ok, "every node above row 0 can be reached")
	t.assert_true(cross_ok, "no two links between the same rows cross")
	t.assert_true(ramp_ok, "every fight has the row's Warden count")
	var one_piece := true
	for seed_value in range(1, 301):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var map := MapGenerator.generate(rng, [1, 1, 1, 1, 1, 1, 1, 1, 1, 1])
		var pieces := {}
		for root in MapGenerator._components(map).values():
			pieces[root] = true
		if pieces.size() != 1:
			one_piece = false
	t.assert_true(one_piece, "no separate lanes: every map is one connected piece (300 seeds, 10 rows)")
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 77
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 77
	t.assert_eq(str(MapGenerator.generate(rng_a, RAMP).nodes), str(MapGenerator.generate(rng_b, RAMP).nodes), "same seed, same map")

	t.group("MapGenerator: repair bays and autonomous bays sit between the first and last rows")
	var kinds_ok := true
	var has_both := true
	for seed_value in range(1, 101):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var map := MapGenerator.generate(rng, RAMP)
		var kinds := {}
		for n in map.nodes:
			kinds[n["kind"]] = true
			if (n["row"] == 0 or map.is_last_row(n["row"])) and n["kind"] != RunMap.KIND_FIGHT:
				kinds_ok = false
			if not RunMap.is_fight(n["kind"]) and n["enemy_count"] != 0:
				kinds_ok = false
		if not (kinds.has(RunMap.KIND_REPAIR) and kinds.has(RunMap.KIND_SHOP)):
			has_both = false
	t.assert_true(kinds_ok, "first and last rows are fights; bays have no enemies")
	var no_repeat := true
	for seed_value in range(1, 101):
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = seed_value
		var m2 := MapGenerator.generate(rng2, RAMP)
		for n in m2.nodes:
			for to_id in n["next"]:
				if n["kind"] != RunMap.KIND_FIGHT and m2.nodes[to_id]["kind"] == n["kind"]:
					no_repeat = false
	t.assert_true(no_repeat, "a bay never links straight into another bay of the same kind")
	t.assert_true(has_both, "every map has at least one repair bay and one autonomous bay")

	t.group("RunData: picking a starting spot, fighting, and the reward")
	var run := _new_run(5)
	var starts := run.available_nodes()
	var row0: Array[int] = []
	for n in run.map.nodes_in_row(0):
		row0.append(n["id"])
	t.assert_eq(starts, row0, "before the first stop, the starting row is on offer")
	var top_id: int = run.map.nodes_in_row(6)[0]["id"]
	t.assert_true(not run.choose_node(top_id), "a node that isn't on offer is refused")
	t.assert_true(run.choose_node(starts[0]), "a starting spot can be chosen")
	t.assert_eq(run.phase, RunData.PHASE_FIGHT, "row 0 is a fight")
	var enemies := run.encounter_enemies()
	t.assert_eq(enemies.size(), 1, "row 0 fights one Scrap Warden")
	var first_node := run.current_node()
	var fight := RunStats.new()
	fight.add("damage_dealt", 40)
	fight.record_max("biggest_hit", 12)
	run.fight_won(fight)
	t.assert_eq(run.phase, RunData.PHASE_REWARD, "a win opens the reward")
	t.assert_eq(run.stats.get_stat("damage_dealt"), 40, "the fight's stats join the run's")
	var lo := Balance.get_int("economy", "scraps_base", 0) + Balance.get_int("economy", "scraps_per_enemy", 0)
	var hi := lo + Balance.get_int("economy", "scraps_spread", 0)
	t.assert_true(run.reward["scraps"] >= lo and run.reward["scraps"] <= hi, "1 Warden pays %d–%d scraps" % [lo, hi])
	t.assert_true(run.reward["scraps_taken"], "the fight's scraps are banked automatically")
	t.assert_eq(run.take_reward_scraps(), 0, "and only once")
	var hp_options := run.choose_reward_category("hardpoint")
	t.assert_true(hp_options.size() > 0 and hp_options.size() <= 3, "a category shows up to 3 parts")
	t.assert_eq(run.choose_reward_category("reactor"), hp_options, "the category choice is final")
	var impl_ok := true
	for id in hp_options:
		if ComponentLibrary.definition(id)["category"] != "hardpoint" or not ComponentLibrary.is_implemented(id):
			impl_ok = false
	t.assert_true(impl_ok, "options are implemented hardpoints")
	var taken := run.take_reward_part(hp_options[0])
	var fits := not CargoGrid.new().find_fit(ComponentLibrary.make(hp_options[0])).is_empty()
	t.assert_eq(taken != null, fits, "the part goes into Cargo exactly when it fits there")
	t.assert_eq(run.reward["part_taken"], fits, "and only then counts as taken")
	run.finish_reward()
	t.assert_eq(run.phase, RunData.PHASE_MAP, "row 0 isn't a refit row: back to the map")
	t.assert_eq(run.available_nodes(), (first_node["next"] as Array).map(func(x): return int(x)), "the finished node's links are on offer")

	t.group("Skipping salvage pays scraps")
	var sk := _new_run(6)
	sk.choose_node(sk.available_nodes()[0])
	sk.fight_won(RunStats.new())
	var sk_opts := sk.choose_reward_category("hardpoint")
	var cheapest := 99999
	for id in sk_opts:
		cheapest = mini(cheapest, Economy.sell_value(id))
	var expect := maxi(Balance.get_int("economy", "skip_scraps", 10), cheapest)
	t.assert_eq(sk.skip_payout(), expect, "skip pays %d: economy.skip_scraps or the cheapest offer's sell value, whichever is more" % expect)
	var sk_before := sk.scraps
	t.assert_eq(sk.skip_reward_part(), expect, "skipping pays it")
	t.assert_eq(sk.scraps, sk_before + expect, "…into Scraps")
	t.assert_eq(sk.skip_reward_part(), 0, "…once")
	t.assert_eq(sk.skip_payout(), 0, "and nothing is left to skip")

	t.group("Rarity rolls: Surplus 70% / Salvaged 25% / Prototype 5%")
	var rr := RandomNumberGenerator.new()
	rr.seed = 3
	var counts := {"surplus": 0, "salvaged": 0, "prototype": 0}
	for i in range(20000):
		counts[Economy.roll_rarity(rr)] += 1
	t.assert_true(absf(counts["surplus"] / 20000.0 - 0.70) < 0.015, "≈70%% Surplus (%d)" % counts["surplus"])
	t.assert_true(absf(counts["salvaged"] / 20000.0 - 0.25) < 0.015, "≈25%% Salvaged (%d)" % counts["salvaged"])
	t.assert_true(absf(counts["prototype"] / 20000.0 - 0.05) < 0.01, "≈5%% Prototype (%d)" % counts["prototype"])
	var fallback_ok := true
	for i in range(300):
		var id := Economy.roll_part("protocol", rr, [], 1, "medium")
		if id == "" or not ComponentLibrary.fits_class(id, "medium"):
			fallback_ok = false
	t.assert_true(fallback_ok, "rolls only ever give parts that fit the mech's class")

	t.group("Cargo: a shaped grid (3×3 to start); parts must fit by shape")
	t.assert_eq(Vector2i(CargoGrid.new().rows, CargoGrid.new().cols), Vector2i(3, 3), "Cargo starts 3×3")
	t.assert_true(CargoGrid.new().add(ComponentLibrary.make("neon_axe")), "a 5-cell Neon Axe fits an empty 3×3")
	var cg := CargoGrid.new(2, 2)
	var axe := ComponentLibrary.make("neon_axe") # 5 cells
	t.assert_true(not cg.add(axe), "a 5-cell Neon Axe doesn't fit a 2×2 Cargo")
	var spike := ComponentLibrary.make("voltage_spike") # 4 cells, not a square
	t.assert_true(not cg.add(spike), "nor does the L-shaped Voltage Spike")
	var bank := ComponentLibrary.make("capacitor_bank") # 2 cells
	var bank2 := ComponentLibrary.make("capacitor_bank")
	t.assert_true(cg.add(bank) and cg.add(bank2), "two 2-cell Capacitor Banks fill it")
	t.assert_true(not cg.add(ComponentLibrary.make("capacitor_bank")), "a third has no room")
	cg.grow_rows()
	t.assert_true(cg.add(ComponentLibrary.make("capacitor_bank")), "+1 row makes room (rotated to fit)")

	t.group("Refit: install and stow parts; scrap wrecks; keep a hardpoint")
	var rf := _new_run(21)
	rf.phase = RunData.PHASE_REFIT
	var core := rf.player_mech.get_component("insulated_core")
	var core_cells := core.placed_cells.duplicate()
	t.assert_true(rf.stow(core, 0, Vector2i(0, 0)), "Insulated Core (2×2) stows into Cargo")
	t.assert_true(rf.install(core, 0, core_cells[0]), "and goes back to the mech")
	rf.cargo.grow_rows()
	rf.cargo.grow_cols() # 3×3
	t.assert_true(rf.stow(core, 0, Vector2i(0, 0)), "and again into a bigger Cargo")
	t.assert_true(not rf.player_mech.components.has(core), "and leaves the mech")
	t.assert_true(rf.install(core, 0, core_cells[0]), "and can go back where it was")
	var tc := rf.player_mech.get_component("targeting_computer")
	t.assert_true(not rf.install(tc, 0, Vector2i(0, 0)), "a part can't overlap another")
	rf.player_mech.get_component("voltage_spike").apply_damage(999)
	t.assert_eq(rf.scrap_destroyed(), ["Voltage Spike"] as Array[String], "a refit scraps destroyed parts")
	rf.player_mech.get_component("neon_axe").apply_damage(999)
	rf.scrap_destroyed()
	t.assert_true(not rf.finish_refit(), "a refit can't end without a working hardpoint")

	t.group("Repair bay: a pool of 50% of max HP, living parts only")
	var rp := _new_run(22)
	rp.phase = RunData.PHASE_MAP
	for n in rp.map.nodes:
		if n["kind"] == RunMap.KIND_REPAIR:
			rp.path = [n["id"]] # pretend we're next to it
			break
	rp.current_node_id = -1
	var repair_id := -1
	for n in rp.map.nodes:
		if n["kind"] == RunMap.KIND_REPAIR:
			repair_id = n["id"]
	rp.phase = RunData.PHASE_REPAIR
	rp.current_node_id = repair_id
	rp.repair_pool = Economy.repair_pool(rp.player_mech.max_hp())
	t.assert_eq(rp.repair_pool, 81, "Bastion: 50% of 162 = 81")
	var nx := rp.player_mech.get_component("neon_axe")
	nx.apply_damage(30)
	t.assert_eq(rp.repair(nx, 100), 30, "heals only what's missing")
	t.assert_eq(rp.repair_pool, 51, "and draws that from the pool")
	var ic := rp.player_mech.get_component("insulated_core")
	ic.apply_damage(999)
	t.assert_eq(rp.repair(ic, 10), 0, "a destroyed part can't be repaired")
	t.assert_eq(rp.stats.get_stat("damage_healed"), 30, "repairs count as damage healed")
	var rvs := rp.player_mech.get_component("voltage_spike")
	var rtc := rp.player_mech.get_component("targeting_computer")
	rvs.apply_damage(40) # 14 / 54
	rtc.apply_damage(6) # 20 / 26
	rp.repair_pool = 20
	t.assert_eq(rp.repair_all(), 20, "Repair all spends the pool")
	t.assert_true(rtc.current_hp == rtc.max_hp and rvs.current_hp == 14 + 14, "…topping off the part missing least first (Targeting Computer whole, Spike gets the rest)")
	rvs.current_hp = 14
	nx.current_hp = 34 # 34 / 64
	rp.repair_pool = 10
	rp.repair_even()
	t.assert_eq(rvs.current_hp, 24, "Even out raises the most worn part (Spike, 26%) first")
	t.assert_eq(rp.repair_pool, 0, "…until the pool is spent")

	t.group("Autonomous bay: parts of each category, and +1 Cargo row/column")
	var sh := _new_run(23)
	sh.phase = RunData.PHASE_SHOP
	sh._stock_shop()
	var rslot := Balance.get_int("economy", "shop_offers", 2) # the first reactor slot
	t.assert_eq(sh.shop["parts"].size(), 3 * rslot, "shop_offers slots per category")
	t.assert_eq(ComponentLibrary.definition(sh.shop["parts"][0])["category"], "hardpoint", "slot 1 is a hardpoint")
	t.assert_true(sh.buy_part(rslot) == null, "no scraps, no sale")
	sh.add_scraps(200)
	var reactor := sh.buy_part(rslot)
	t.assert_true(reactor != null and sh.bench.items.has(reactor), "a reactor bought goes onto the workbench")
	t.assert_eq(sh.scraps, 200 - Economy.price(reactor.library_id), "and costs its price")
	t.assert_eq(sh.shop["parts"][rslot], "", "that slot is sold out")
	t.assert_true(not sh.move_part(reactor, RunData.MECH, 0, Vector2i.ZERO), "the chassis can't be changed at a bay")
	var spot := sh.cargo.find_fit(reactor)
	t.assert_true(sh.move_part(reactor, RunData.CARGO, spot["rotation"], spot["offset"]) and sh.cargo.items.has(reactor) and sh.bench.items.is_empty(), "the workbench part moves into Cargo")

	t.group("Workbench: 6×6, and whatever is left on it is scrapped for scraps")
	var wb := _new_run(24)
	wb.current_node_id = wb.available_nodes()[0]
	wb.phase = RunData.PHASE_SHOP
	wb._stock_shop()
	wb.add_scraps(300)
	var bought := wb.buy_part(0)
	t.assert_eq(Vector2i(wb.bench.rows, wb.bench.cols), Vector2i(6, 6), "the workbench is 6×6")
	var value := Economy.scrap_value(bought)
	t.assert_eq(value, int(round(Economy.price(bought.library_id) * 0.5)), "an undamaged part scraps for half its price")
	bought.apply_damage(bought.max_hp / 2)
	t.assert_true(Economy.scrap_value(bought) < value, "a damaged one for less")
	var before := wb.scraps
	var worth := wb.bench_value()
	wb.leave_shop()
	t.assert_true(wb.bench.items.is_empty() and wb.scraps == before + worth, "leaving scraps the workbench into scraps")
	var rb := _new_run(25)
	rb.phase = RunData.PHASE_REFIT
	var benched := rb.player_mech.components[-1]
	t.assert_true(rb.move_part(benched, RunData.BENCH, benched.rotation_steps, Vector2i.ZERO), "at a refit a chassis part can go onto the workbench")
	var loaded := RunData.from_dict(rb.to_dict(), rb.location, rb.mission)
	t.assert_eq(loaded.bench.items.size(), 1, "the workbench is saved with the run")
	t.assert_true(sh.buy_cargo_upgrade(true), "+1 row bought")
	t.assert_eq(Vector2i(sh.cargo.rows, sh.cargo.cols), Vector2i(4, 3), "Cargo is now 4×3")
	t.assert_true(not sh.buy_cargo_upgrade(false), "one upgrade per visit")

	t.group("Autonomous bay: frame squares, 25 scraps then 25 more each")
	var fr := _new_run(26)
	fr.phase = RunData.PHASE_SHOP
	fr._stock_shop()
	var n_cells := fr.player_mech.cells.size()
	var opts := fr.cell_options()
	t.assert_true(not opts.is_empty(), "there are squares to add")
	t.assert_true(opts.all(func(c): return not fr.chassis_cells().has(c)), "only empty squares are offered")
	t.assert_eq(fr.cell_price(), 25, "the first costs 25")
	t.assert_true(not fr.buy_cell(opts[0]), "no scraps, no square")
	fr.add_scraps(200)
	var inside: Vector2i = opts.filter(func(c): return c.x >= 0 and c.y >= 0)[0]
	t.assert_true(fr.buy_cell(inside), "bought one")
	t.assert_eq(fr.player_mech.cells.size(), n_cells + 1, "the frame grew by a square")
	t.assert_eq(fr.scraps, 175, "for 25")
	t.assert_eq(fr.cell_price(), 50, "the next costs 50")
	t.assert_true(not fr.buy_cell(inside), "the same square can't be bought twice")
	# A square above row 0 shifts the frame and its parts down a row.
	var top := Vector2i(-1, fr.player_mech.cells.filter(func(c): return c.x == 0)[0].y)
	var part: ComponentData = fr.player_mech.components[0]
	var before_off := part.offset
	t.assert_true(fr.buy_cell(top), "a square above the frame")
	t.assert_true(fr.player_mech.cells.all(func(c): return c.x >= 0 and c.y >= 0), "the frame still starts at row 0")
	t.assert_eq(part.offset, before_off + Vector2i(1, 0), "parts moved with it")
	t.assert_true(fr.player_mech.components.all(func(c): return c.placed_cells.all(func(x): return fr.chassis_cells().has(x))), "every part still sits on the frame")
	t.assert_eq(fr.scraps, 125, "for 50")
	t.assert_eq(fr.cell_price(), 75, "then 75")
	var fb := RunData.from_dict(JSON.parse_string(JSON.stringify(fr.to_dict())), _location())
	t.assert_eq(fb.player_mech.cells.size(), n_cells + 2, "bought squares survive a save")
	t.assert_eq(fb.cell_price(), 75, "and so does the price")
	t.assert_eq(fb.player_mech.components[0].offset, part.offset, "and the shifted parts")

	t.group("Frame ring: squares only within one ring of the chassis' original bounds")
	var rg := _new_run(27)
	var ring := rg.frame_ring()
	t.assert_eq(ring, GridUtils.bounds_of(rg.player_mech.cells).grow(1), "the ring is the original bounds grown by one")
	# Fill everything the ring allows (free squares, as orders give them).
	for _i in range(200):
		var o := rg.cell_options()
		if o.is_empty():
			break
		rg.add_frame_cell(o[0])
	var grown := GridUtils.bounds_of(rg.player_mech.cells)
	t.assert_eq(grown.size, ring.size, "the frame fills out to the ring and no further")
	t.assert_true(rg.cell_options().is_empty(), "then nothing more is offered")
	t.assert_true(not rg.add_frame_cell(Vector2i(grown.end.x, 0)), "a square past the ring is refused")
	var rg2 := RunData.from_dict(JSON.parse_string(JSON.stringify(rg.to_dict())), _location())
	t.assert_eq(rg2.base_bounds, rg.base_bounds, "the original bounds survive a save")
	var old_save: Dictionary = JSON.parse_string(JSON.stringify(fr.to_dict())) # a square was added above that frame
	old_save.erase("base_bounds")
	t.assert_eq(RunData.from_dict(old_save, _location()).base_bounds, fr.base_bounds, "and are found again in a save made before the ring rule")
	t.assert_eq(fr.base_bounds.position, Vector2i(1, 0), "(that frame shifted down a row)")

	t.group("Autonomous bay rework: more stock, sell, refine")
	var shp := _new_run(28)
	shp.phase = RunData.PHASE_SHOP
	shp._stock_shop()
	var shop_per := Balance.get_int("economy", "shop_offers", 2)
	t.assert_eq(shp.shop["parts"].size(), 3 * shop_per, "%d parts of each type" % shop_per)
	for i in range(3):
		var shop_cat_ids: Array = shp.shop["parts"].slice(i * shop_per, (i + 1) * shop_per).filter(func(id): return id != RunData.NO_STOCK)
		t.assert_true(shop_cat_ids.all(func(id): return ComponentLibrary.definition(id)["category"] == Economy.CATEGORIES[i]), "slots grouped by type (%s)" % Economy.CATEGORIES[i])
		var shop_uniq := {}
		for id in shop_cat_ids:
			shop_uniq[id] = true
		t.assert_eq(shop_uniq.size(), shop_cat_ids.size(), "no repeats within a type")
	shp.add_scraps(1000)
	var kept_shop := RunData.from_dict(JSON.parse_string(JSON.stringify(shp.to_dict())), _location())
	t.assert_eq(kept_shop.shop["parts"], shp.shop["parts"], "the stock survives a save")
	var sold_gun := shp.new_part("autocannon")
	shp.cargo.add(sold_gun)
	var sell_worth := Economy.scrap_value(sold_gun)
	var scr_before := shp.scraps
	t.assert_eq(shp.sell_part(sold_gun), sell_worth, "selling pays the scrap value")
	t.assert_true(not shp.cargo.items.has(sold_gun) and shp.scraps == scr_before + sell_worth, "and the part is gone")
	t.assert_true(not shp.can_sell(shp.player_mech.components[0]), "installed parts can't be sold here")
	var ref_a := shp.new_part("autocannon")
	shp.cargo.add(ref_a)
	var refine_cost := shp.refine_price(ref_a)
	t.assert_eq(refine_cost, int(Balance.get_dict("economy", "refine_prices")["surplus"]), "refining a Surplus part costs its price")
	scr_before = shp.scraps
	var refined := shp.refine_part(ref_a)
	t.assert_true(refined != null, "refined")
	if refined != null:
		t.assert_eq(str(ComponentLibrary.definition(refined.library_id)["rarity"]), "salvaged", "one rarity up")
		t.assert_eq(refined.category, ComponentData.CATEGORY_HARDPOINT, "same type")
		t.assert_true((shp.cargo.items.has(refined) or shp.bench.items.has(refined)) and not shp.cargo.items.has(ref_a), "the new part replaces the old")
		t.assert_eq(shp.scraps, scr_before - refine_cost, "paid")
	var ref_b := shp.new_part("autocannon")
	shp.bench.add(ref_b)
	t.assert_true(not shp.can_refine(ref_b), "once a visit")

	_saves_and_maps(t)

	t.group("Two copies of one part get distinct ids (cards stay tied to their own copy)")
	var dup := _new_run(24)
	var s2 := dup.new_part("voltage_spike")
	t.assert_eq(s2.id, "voltage_spike_2", "a second Voltage Spike is voltage_spike_2")
	t.assert_eq(s2.cards[0].owner_component_id, "voltage_spike_2", "its cards point at it")

	t.group("Save / load: a run comes back exactly")
	var sv := _new_run(25)
	sv.choose_node(sv.available_nodes()[0])
	sv.player_mech.get_component("neon_axe").apply_damage(17)
	sv.fight_won()
	sv.take_reward_scraps()
	var back := RunData.from_dict(JSON.parse_string(JSON.stringify(sv.to_dict())), _location())
	t.assert_eq(back.phase, RunData.PHASE_REWARD, "phase restored")
	t.assert_eq(back.scraps, sv.scraps, "scraps restored")
	t.assert_eq(back.player_mech.get_component("neon_axe").current_hp, 47, "damage restored")
	t.assert_eq(str(back.map.nodes), str(sv.map.nodes), "same seed, same map")
	t.assert_eq(back.reward["options"], sv.reward["options"], "the rolled reward is kept (no reroll on reload)")
	t.assert_eq(back.rng.randi(), sv.rng.randi(), "the roll stream continues where it left off")

	t.group("RunData: a whole location, and a loss ejects")
	var full := _new_run(9)
	var fight_counts := []
	var refits := 0
	while not full.is_over():
		match full.phase:
			RunData.PHASE_MAP:
				var options := full.available_nodes()
				if options.is_empty() or not full.choose_node(options[-1]):
					break
			RunData.PHASE_FIGHT:
				fight_counts.append(full.encounter_enemies().size())
				full.fight_won()
			RunData.PHASE_REWARD:
				full.finish_reward()
			RunData.PHASE_REFIT:
				refits += 1
				full.finish_refit()
			RunData.PHASE_REPAIR:
				full.finish_repair()
			RunData.PHASE_SHOP:
				full.leave_shop()
			RunData.PHASE_EVENT:
				full.resolve_event(0)
				full.finish_event()
			_:
				break
	t.assert_eq(full.result, RunData.Result.CLEARED, "finishing the top row clears the location")
	t.assert_eq(full.path.size(), 7, "7 stops")
	t.assert_eq(refits, 3, "a refit after stops 2, 4 and 6")
	var path_ramp_ok := true
	for i in range(full.path.size()):
		var n := full.map.get_map_node(full.path[i])
		if n["kind"] == RunMap.KIND_FIGHT and n["enemy_count"] != RAMP[n["row"]]:
			path_ramp_ok = false
	t.assert_true(path_ramp_ok, "every fight follows the 1,1,2,2,2,3,3 Warden ramp")
	var lost := _new_run(11)
	lost.choose_node(lost.available_nodes()[0])
	lost.fight_lost()
	t.assert_eq(lost.result, RunData.Result.EJECTED, "losing a fight ejects the pilot")
	t.assert_true(lost.is_over(), "and ends the run")

	t.group("Fight stats: CombatManager counts what happens")
	var cp := DataLoader.load_mech_from_file("res://tests/fixtures/bastion_classic.json")
	var cw: Array[MechData] = [DataLoader.load_mech_from_file("res://tests/fixtures/scrap_warden_classic.json")]
	var cm := CombatManager.new(cp, cw, 40)
	cm.start_combat()
	cm.play_attack_card(cp.get_component("neon_axe").cards[0], cw[0], cw[0].get_component("scatter_shot"))
	t.assert_eq(cm.stats.get_stat("cards_played"), 1, "a card played")
	var swing_heat: int = cp.get_component("neon_axe").cards[0].heat_cost
	t.assert_eq(cm.stats.get_stat("heat_generated"), swing_heat, "Wide Swing's heat (%d)" % swing_heat)
	t.assert_eq(cm.stats.get_stat("damage_dealt"), cw[0].max_hp() - cw[0].current_hp(), "damage dealt matches the Warden's lost HP")
	t.assert_true(cm.stats.get_stat("biggest_hit") >= 6 and cm.stats.get_stat("biggest_hit") <= 10, "biggest hit is one Wide Swing hit")
	cm.end_player_turn()
	t.assert_eq(cm.stats.get_stat("damage_taken"), cp.max_hp() - cp.current_hp(), "damage taken matches the Bastion's lost HP")

static func _new_run(seed_value: int) -> RunData:
	return RunData.new(_location(), DataLoader.load_mech_from_file("res://tests/fixtures/bastion_classic.json"), seed_value)

## Save versions, migration, SafeFile fallback, map determinism.
static func _saves_and_maps(t: TestContext) -> void:
	t.group("Saves: versioned, carry their mission, migrate v1, survive a corrupt file")
	var mdefs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/missions.json"))["missions"]
	var am: Dictionary = mdefs["assault"].duplicate(true)
	am["id"] = "assault"
	var sv := RunData.new(_location(), DataLoader.load_mech_from_file("res://tests/fixtures/bastion_classic.json"), 41, am)
	var sd: Dictionary = JSON.parse_string(JSON.stringify(sv.to_dict()))
	t.assert_eq(int(sd["v"]), RunData.SAVE_VERSION, "saves carry the current version")
	t.assert_eq(int(sd["mission"]["rows"]), int(am["rows"]), "and the mission they started with")
	var v1 := sd.duplicate(true)
	v1["v"] = 1
	v1.erase("mission")
	var mig := SaveMigration.migrate(v1)
	t.assert_eq(int(mig["mission"]["rows"]), 7, "a v1 Assault save keeps its 7 rows")
	t.assert_eq(mig["mission"]["refit_after_rows"], [1, 3, 5], "and its refit rows")
	var old_run := RunData.from_dict(mig, _location(), mig["mission"])
	t.assert_eq(old_run.map.row_count, 8, "its map rebuilds the way it was (7 rows + boss)")
	var path := "user://test_safefile.json"
	SafeFile.remove(path)
	t.assert_true(SafeFile.write_json(path, {"a": 1}), "written")
	SafeFile.write_json(path, {"a": 2})
	t.assert_eq(int(SafeFile.read_json(path)["a"]), 2, "read back")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	t.assert_eq(int(SafeFile.read_json(path)["a"]), 1, "a damaged file falls back to the backup")
	t.assert_true(FileAccess.file_exists(path + ".corrupt"), "and is kept aside as .corrupt")
	SafeFile.remove(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".corrupt"))

	t.group("Maps are fixed by the seed")
	var ma := RunData.new(_location(), DataLoader.load_mech_from_file("res://tests/fixtures/bastion_classic.json"), 77, am)
	var mb := RunData.new(_location(), DataLoader.load_mech_from_file("res://tests/fixtures/bastion_classic.json"), 77, am)
	var mc := RunData.new(_location(), DataLoader.load_mech_from_file("res://tests/fixtures/bastion_classic.json"), 78, am)
	var shape := func(r: RunData): return r.map.nodes.map(func(n): return [n["row"], n["kind"], n["next"], n["enemies"]])
	t.assert_eq(shape.call(ma), shape.call(mb), "same seed, same map")
	t.assert_true(shape.call(ma) != shape.call(mc), "another seed, another map")

	t.group("A boss win clears the run at once: no salvage, no scraps")
	var bw := RunData.new(_location(), DataLoader.load_mech_from_file("res://tests/fixtures/bastion_classic.json"), 43, am)
	var boss_node: Dictionary = bw.map.nodes_in_row(bw.map.row_count - 1)[0]
	bw.current_node_id = boss_node["id"]
	bw.phase = RunData.PHASE_FIGHT
	var scraps_before := bw.scraps
	bw.fight_won(RunStats.new())
	t.assert_eq(bw.result, RunData.Result.CLEARED, "cleared")
	t.assert_true(bw.reward.is_empty() and bw.scraps == scraps_before, "no reward, no scraps")
	t.assert_eq(bw.stats.get_stat("bosses_beaten"), 1, "the boss still counts")

	t.group("Event buttons say what a choice gains and what it costs")
	t.assert_eq(EventOutcome.summary({"scraps": 50, "next_fight": [{"side": "enemy", "status": "deflect", "stacks": 4, "parts": "mech"}]}, false),
		"+50 scraps, but enemies start the next fight with Deflect 4", "gain, but cost")
	t.assert_eq(EventOutcome.summary({"damage_random_part": 15}, false), "a random part takes 15", "a cost alone")
	t.assert_eq(EventOutcome.summary({}, false), "nothing happens", "a safe pass")
	t.assert_eq(EventOutcome.summary({"chance": 0.6, "then": {"gain_part": {"category": "protocol", "rarity": "surplus"}}, "else": {"damage_random_part": 10}}, false),
		"60%: a random Surplus protocol  ·  else: a random part takes 10", "a gamble shows both sides")
	t.assert_eq(EventOutcome.summary({"alert_turns": 12}, false), "nothing happens", "Alert only matters on Rescue")
	t.assert_eq(EventOutcome.summary({"alert_turns": 12}, true), "Alert rises", "and shows there")
	var free := []
	for e in JSON.parse_string(FileAccess.get_file_as_string("res://data/events.json"))["events"]:
		var all_choices: Array = e["choices"].duplicate()
		for step in e.get("steps", {}).values():
			all_choices.append_array(step["choices"])
		for c in all_choices:
			var o: Dictionary = c["outcome"]
			if o.has("chance"):
				continue
			# an Alert-only event or choice is read with the Alert on
			var sp := EventOutcome.split(o, e.get("requires_alert", false) or c.get("requires_alert", false))
			if not (sp["gains"] as Array).is_empty() and (sp["costs"] as Array).is_empty():
				free.append("%s / %s" % [e["id"], c["label"]])
	t.assert_eq(free, [], "no event choice gains something for free")


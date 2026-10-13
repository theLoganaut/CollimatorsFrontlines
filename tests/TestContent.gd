class_name TestContent
extends RefCounted
## Content rules from the 2026-09-30 backlog: 1–3 autonomous bays a map,
## events that sometimes lead to a bay, events limited by sector, mission
## and Alert, multi-step events, no repeats, and scrap prices.

static func run_all(t: TestContext) -> void:
	_shop_cap(t)
	_event_shops(t)
	_event_gating(t)
	_multi_step(t)
	_prices(t)
	_conditions(t)
	_daily(t)

static func _mission(id: String) -> Dictionary:
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/missions.json"))["missions"][id].duplicate(true)
	m["id"] = id
	return m

static func _sector(id: String) -> Dictionary:
	for loc in JSON.parse_string(FileAccess.get_file_as_string("res://data/sectors.json"))["locations"]:
		if loc["id"] == id:
			return loc
	return {}

static func _run(sector: String, mission: String, seed_value: int) -> RunData:
	return RunData.new(_sector(sector), DataLoader.load_mech_from_file("res://data/mechs/bastion.json"), seed_value, _mission(mission))

static func _count(run: RunData, kind: String) -> int:
	return run.map.nodes.filter(func(n): return n["kind"] == kind).size()

static func _shop_cap(t: TestContext) -> void:
	t.group("content: 1–3 autonomous bays a map")
	var ok := true
	for sd in range(1, 80):
		for m in ["assault", "deep_recon", "rescue"]:
			var run := _run("shipyard", m, sd)
			var n := _count(run, RunMap.KIND_SHOP)
			ok = ok and n >= 1 and n <= 3
	t.assert_true(ok, "every Assault, Deep Recon and Rescue map has 1 to 3 bays (79 seeds each)")
	var uncapped := _mission("assault")
	uncapped.erase("max_shops")
	var more := false
	for sd in range(1, 80):
		var run := RunData.new(_sector("shipyard"), DataLoader.load_mech_from_file("res://data/mechs/bastion.json"), sd, uncapped)
		more = more or _count(run, RunMap.KIND_SHOP) > 3
	t.assert_true(more, "a mission saved before the cap (no max_shops) keeps its old map")

static func _event_shops(t: TestContext) -> void:
	t.group("content: some events lead to a bay")
	var shops := 0
	var events := 0
	var marked := true
	for sd in range(1, 400):
		var run := _run("shipyard", "assault", sd)
		var ev := run.map.nodes.filter(func(n): return n["kind"] == RunMap.KIND_EVENT)
		if ev.is_empty():
			continue
		# stand on a node that links straight to it, then enter it
		run.path.append(0)
		run.map.nodes[0]["next"] = [ev[0]["id"]]
		run.choose_node(ev[0]["id"])
		if run.phase == RunData.PHASE_SHOP:
			shops += 1
			marked = marked and run.shop.get("from_event", false)
		elif run.phase == RunData.PHASE_EVENT:
			events += 1
	t.assert_true(marked, "a bay that came from an event says so")
	var share := float(shops) / maxf(1.0, shops + events)
	t.assert_true(share > 0.05 and share < 0.16, "about 10%% of event stops are bays (%.1f%% of %d)" % [share * 100.0, shops + events])

static func _event_gating(t: TestContext) -> void:
	t.group("content: events by sector, mission and Alert")
	var defs := RunEvents.events()
	var by_id := {}
	for e in defs:
		by_id[e["id"]] = e
	var ship := _run("shipyard", "assault", 3)
	var arch := _run("data_archives", "rescue", 3)
	var recon := _run("mining_grounds", "deep_recon", 3)
	t.assert_true(RunEvents.eligible(ship, by_id["flooded_drydock"]), "a Shipyard event comes up at the Shipyard")
	t.assert_true(not RunEvents.eligible(arch, by_id["flooded_drydock"]), "…and not at the Data Archives")
	t.assert_true(RunEvents.eligible(recon, by_id["listening_post"]) and not RunEvents.eligible(ship, by_id["listening_post"]), "a Deep Recon event only on Deep Recon")
	t.assert_true(RunEvents.eligible(arch, by_id["pinned_squad"]) and not RunEvents.eligible(ship, by_id["pinned_squad"]), "an Alert event only with the Alert (Rescue)")
	ship.event = {"id": "radio_silence", "step": "", "resolved": false, "result": ""}
	arch.event = {"id": "radio_silence", "step": "", "resolved": false, "result": ""}
	t.assert_eq(RunEvents.visible_choices(ship).size(), 2, "an Alert-only choice is hidden without the Alert")
	t.assert_eq(RunEvents.visible_choices(arch).size(), 3, "…and offered with it")
	ship.phase = RunData.PHASE_EVENT
	t.assert_eq(ship.resolve_event(2), "", "a hidden choice can't be taken")
	var seen := {}
	var run := _run("shipyard", "assault", 9)
	var eligible := defs.filter(func(e): return RunEvents.eligible(run, e)).size()
	var repeats := false
	for i in range(eligible):
		var id := RunEvents.pick(run)
		repeats = repeats or seen.has(id)
		seen[id] = true
	t.assert_true(not repeats, "no event repeats until every one the run can have has come up (%d)" % eligible)
	t.assert_true(RunEvents.pick(run) != "", "…then they can come round again")

static func _multi_step(t: TestContext) -> void:
	t.group("content: multi-step events")
	var run := _run("mining_grounds", "assault", 5)
	run.phase = RunData.PHASE_EVENT
	run.event = {"id": "blasting_charges", "step": "", "resolved": false, "result": ""}
	run.resolve_event(0) # Take them -> the "use" step
	t.assert_eq(run.event["step"], "use", "a choice with goto leads to its step")
	t.assert_true(not run.event["resolved"], "…and the event goes on")
	t.assert_eq(RunEvents.current(run)["text"], "Where do they go?", "the step's text shows")
	t.assert_eq(run.next_fight.size(), 1, "the first choice's cost still lands (Burn next fight)")
	var scraps := run.scraps
	run.resolve_event(1) # Sell them
	t.assert_true(run.event["resolved"], "a choice without goto ends it")
	t.assert_eq(run.scraps, scraps + 80, "the step's choice pays")
	t.assert_true(str(run.event["result"]).contains("You strap the crate down") and str(run.event["result"]).contains("Eighty scraps"), "what happened at each step stays on screen")
	var saved := RunSave.from_dict(RunSave.to_dict(run), run.location, run.mission)
	t.assert_eq(saved.events_seen, run.events_seen, "events seen are saved")

static func _prices(t: TestContext) -> void:
	t.group("content: scrap prices")
	var run := _run("shipyard", "assault", 7)
	run.phase = RunData.PHASE_EVENT
	run.event = {"id": "field_tech", "step": "", "resolved": false, "result": ""}
	run.scraps = 30
	t.assert_eq(run.resolve_event(1), "", "a 60-scrap module can't be bought with 30")
	t.assert_eq(run.cargo.items.size(), 0, "…so no free part")
	run.scraps = 70
	run.resolve_event(1)
	t.assert_eq(run.scraps, 10, "with 70 it costs 60")

static func _conditions(t: TestContext) -> void:
	t.group("content: location modifiers and mission variants")
	var ship := _run("shipyard", "assault", 11)
	var p := ship.player_mech
	var ws: Array[MechData] = [DataLoader.load_mech_from_file("res://tests/fixtures/scrap_warden_classic.json")]
	ship.current_node_id = ship.available_nodes()[0]
	ship.prepare_player_for_fight()
	var log := ship.apply_fight_start_effects(p, ws)
	t.assert_true(is_equal_approx(p.vent_at_max, 0.75) and is_equal_approx(ws[0].vent_at_max, 0.75), "Rain at the Shipyard: every mech vents 75% at max, not 80%")
	t.assert_true(log.any(func(l): return l.begins_with("Rain")), "…and the combat log says so")
	ship.apply_fight_start_effects(p, ws)
	t.assert_true(is_equal_approx(p.vent_at_max, 0.75), "…without stacking fight after fight")
	var arch := _run("data_archives", "assault", 11)
	arch.current_node_id = arch.available_nodes()[0]
	arch.prepare_player_for_fight()
	arch.apply_fight_start_effects(arch.player_mech, ws)
	var jammed := arch.player_mech.non_destroyed_components().filter(func(c): return c.category == ComponentData.CATEGORY_HARDPOINT).all(func(c): return c.status_stacks("jam") == 1)
	t.assert_true(jammed, "Jamming at the Data Archives: hardpoints start Jammed (every mech's)")
	var hard := RunData.new(_sector("mining_grounds"), DataLoader.load_mech_from_file("res://data/mechs/bastion.json"), 11, Conditions.with_variant(_mission("assault"), "hardened"))
	hard.current_node_id = hard.available_nodes()[0]
	hard.prepare_player_for_fight()
	var foe: Array[MechData] = [DataLoader.load_mech_from_file("res://tests/fixtures/scrap_warden_classic.json")]
	hard.apply_fight_start_effects(hard.player_mech, foe)
	t.assert_eq(foe[0].mech_status_stacks("deflect"), 3, "Hardened: enemies start braced with Deflect 3")
	t.assert_eq(hard.player_mech.mech_status_stacks("smoke"), 1, "Dust at the Mining Grounds: mechs start with Smoke 1")
	var saved := RunSave.from_dict(RunSave.to_dict(hard), hard.location, hard.mission)
	t.assert_eq(Conditions.variant(saved.mission).get("id", ""), "hardened", "the variant is saved with the run's mission")
	t.assert_eq(Conditions.sight_rows(Conditions.with_variant(_mission("assault"), "low_visibility")), 3, "Low Visibility: three rows ahead")
	t.assert_true(Conditions.with_variant(_mission("training"), "hardened").get("variant", {}).is_empty(), "training never gets a variant")
	var counts := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in range(800):
		var v := Conditions.roll_variant(rng)
		counts[v] = int(counts.get(v, 0)) + 1
	t.assert_true(int(counts.get("standard", 0)) > 300 and counts.size() == 5, "variants roll by their weights (Standard about half the time)")

static func _daily(t: TestContext) -> void:
	t.group("content: the Daily Operation")
	var a := Daily.setup("2026-10-01")
	var b := Daily.setup("2026-10-01")
	var c := Daily.setup("2026-10-02")
	t.assert_eq([a["seed"], a["location_id"], a["mission"]["id"], a["mech"]], [b["seed"], b["location_id"], b["mission"]["id"], b["mech"]], "the same date gives every pilot the same operation")
	t.assert_true(a["seed"] != c["seed"], "another day, another operation")
	t.assert_true(not Conditions.variant(a["mission"]).is_empty(), "a daily always has a mission variant")
	t.assert_eq(a["mission"]["daily"], "2026-10-01", "the run's mission knows it's a daily (saved with it)")
	var run := RunData.new(a["location"], DataLoader.load_mech_from_file("res://data/mechs/%s.json" % a["mech"]), int(a["seed"]), a["mission"])
	t.assert_true(Daily.is_daily(run), "…so the run does too")
	run.path.append_array([0, 1, 2])
	run.stats.add("elites_beaten", 1)
	run.stats.add("damage_dealt", 500)
	t.assert_eq(Daily.score(run), 3 * 10 + 30 + 10, "score: 10 a stop, 30 an elite, 1 per 50 damage")
	run.result = RunData.Result.CLEARED
	t.assert_eq(Daily.score(run), 3 * 10 + 30 + 10 + 200, "…and 200 for clearing it")

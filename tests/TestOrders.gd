class_name TestOrders
extends RefCounted
## Deployment orders (Logan, 2026-09-29): three offers after Launch (a
## boost, a tradeoff, a gamble), one taken before the first stop, and what
## each one does to the run.

static func _mission(id: String) -> Dictionary:
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/missions.json"))["missions"][id].duplicate(true)
	m["id"] = id
	return m

static func _sector(id: String) -> Dictionary:
	for loc in JSON.parse_string(FileAccess.get_file_as_string("res://data/sectors.json"))["locations"]:
		if loc["id"] == id:
			return loc
	return {}

static func _run(seed_value: int = 11) -> RunData:
	return RunData.new(_sector("shipyard"), DataLoader.load_mech_from_file("res://tests/fixtures/bastion_classic.json"), seed_value, _mission("assault"))

## A fresh run offered only `id`, and that order taken. Returns [run, note].
static func _take(id: String, seed_value: int = 11) -> Array:
	var run := _run(seed_value)
	run.orders = {"offer": [id], "chosen": "", "steps": []}
	var note := DeploymentOrders.choose(run, id)
	return [run, note]

## An order's number from balance.json.
static func _o(order: String, key: String) -> int:
	return int(Balance.get_dict("orders", order).get(key, 0))

static func _reload(run: RunData) -> RunData:
	return RunData.from_dict(JSON.parse_string(JSON.stringify(run.to_dict())), run.location, run.mission)

## Walks into the next fight and wins it (first stop offered, repeatedly
## skipping non-fights). Returns the reward.
static func _win_next_fight(run: RunData) -> Dictionary:
	for _guard in range(30):
		match run.phase:
			RunData.PHASE_MAP:
				run.choose_node(run.available_nodes()[0])
			RunData.PHASE_FIGHT:
				run.fight_won()
				var r := run.reward.duplicate(true)
				run.finish_reward()
				return r
			RunData.PHASE_REFIT: run.finish_refit()
			RunData.PHASE_REPAIR: run.finish_repair()
			RunData.PHASE_SHOP: run.leave_shop()
			RunData.PHASE_EVENT:
				run.resolve_event(1)
				run.finish_event()
			RunData.PHASE_REWARD: run.finish_reward()
	return {}

static func run_all(t: TestContext) -> void:
	t.group("orders.json: every order has its kind, its numbers and filled-in text")
	var ids: Array = DeploymentOrders.all().map(func(o): return o["id"])
	var nums := Balance.section("orders")
	t.assert_true(ids.all(func(id): return nums.has(id)), "each order has a balance.json entry")
	t.assert_true(DeploymentOrders.all().all(func(o): return o["kind"] in DeploymentOrders.KINDS), "kinds are boost / tradeoff / gamble")
	t.assert_true(ids.all(func(id): return not DeploymentOrders.text(id).contains("{")), "every placeholder is filled")
	t.assert_true(not ids.has("target_dossier"), "no Target Dossier (boss intel is Deep Recon's reward only)")
	t.assert_eq(DeploymentOrders.text("supply_drop"), "+%d scraps." % _o("supply_drop", "scraps"), "numbers come from balance.json, without decimals")

	t.group("The offer: one boost, one tradeoff, one gamble, same for the same seed")
	var kinds_ok := true
	var shuffled := false
	for s in range(1, 40):
		var r := _run(s)
		DeploymentOrders.offer(r)
		var offer: Array = r.orders["offer"]
		var kinds: Array = offer.map(func(id): return DeploymentOrders.def(id)["kind"])
		kinds_ok = kinds_ok and offer.size() == 3 and kinds.has("boost") and kinds.has("tradeoff") and kinds.has("gamble")
		shuffled = shuffled or kinds != ["boost", "tradeoff", "gamble"]
	t.assert_true(kinds_ok, "three offers, one of each kind")
	t.assert_true(shuffled, "their order is shuffled (the kind isn't given away by position)")
	var a := _run(5)
	var b := _run(5)
	DeploymentOrders.offer(a)
	DeploymentOrders.offer(b)
	t.assert_eq(a.orders["offer"], b.orders["offer"], "same seed, same offer")

	t.group("The map waits for the orders")
	var w := _run()
	DeploymentOrders.offer(w)
	t.assert_true(w.orders_pending(), "pending until one is taken")
	t.assert_true(not w.choose_node(w.available_nodes()[0]), "no stop can be chosen yet")
	t.assert_eq(DeploymentOrders.choose(w, "not_offered"), "", "only an offered order can be taken")
	t.assert_true(not _run().orders_pending(), "a run with no orders (training) isn't held up")

	t.group("Boosts")
	var sd: RunData = _take("supply_drop")[0]
	t.assert_eq(sd.scraps, _o("supply_drop", "scraps"), "Supply Drop: its scraps")
	t.assert_true(not sd.orders_pending() and sd.choose_node(sd.available_nodes()[0]), "taken: the map opens")

	var rq: RunData = _take("requisition")[0]
	t.assert_true(rq.orders_pending(), "Requisition: a pick is waiting")
	t.assert_eq([rq.cargo.rows, rq.cargo.cols], [5, 5], "Cargo is 5×5 for the opening refit")
	t.assert_eq(rq.phase, RunData.PHASE_MAP, "the refit waits until the pick is made")
	var opts := DeploymentOrders.pick_category(rq, "hardpoint")
	t.assert_eq(opts.size(), 3, "three hardpoints to choose from")
	t.assert_true(opts.all(func(id): return ComponentLibrary.definition(id)["rarity"] == "salvaged"), "all Salvaged")
	t.assert_eq(DeploymentOrders.pick_category(rq, "reactor"), opts, "the category, once chosen, is final")
	t.assert_eq(DeploymentOrders.pick_part(rq, "not_an_option"), "", "only an option can be taken")
	DeploymentOrders.pick_part(rq, opts[0])
	t.assert_true(rq.cargo.items.size() == 1 and rq.cargo.items[0].library_id == opts[0], "the part is in Cargo")
	t.assert_true(not rq.orders_pending(), "done")
	t.assert_eq(rq.phase, RunData.PHASE_REFIT, "the run opens with a refit")

	t.group("The opening refit: Cargo is 5×5 only for it")
	var every_part_fits := true
	for id in ComponentLibrary.all_ids():
		var big := CargoGrid.new(5, 5)
		every_part_fits = every_part_fits and big.add(ComponentLibrary.make(id))
	t.assert_true(every_part_fits, "every Refit Bay part fits an empty 5×5 Cargo")
	var op: RunData = _take("requisition")[0]
	DeploymentOrders.pick_category(op, "reactor")
	DeploymentOrders.pick_part(op, DeploymentOrders.current_step(op)["options"][0])
	var kept: ComponentData = op.cargo.items[0]
	var moved := false
	for r in range(4, -1, -1): # out onto the temporary squares
		for c in range(4, -1, -1):
			if not moved and op.cargo.can_place(kept, 0, Vector2i(r, c)) and GridUtils.place_cells(kept.cells, 0, Vector2i(r, c)).any(func(x): return x.x >= 3 or x.y >= 3):
				moved = op.cargo.place(kept, 0, Vector2i(r, c))
	t.assert_eq(op.cargo_overflow(), [kept] as Array[ComponentData], "a part on the temporary squares is overflow")
	t.assert_eq(op.leave_scrap_value(), Economy.scrap_value(kept), "leaving would scrap it")
	t.assert_eq(_reload(op).opening_cargo_size(), Vector2i(3, 3), "the big Cargo survives a reload")
	op.finish_refit()
	t.assert_true([op.cargo.rows, op.cargo.cols] == [3, 3] and op.cargo.items.is_empty(), "finishing shrinks Cargo back and scraps what was outside")
	t.assert_eq(op.scraps, Economy.scrap_value(kept), "for scraps")
	t.assert_eq(op.opening_cargo_size(), Vector2i.ZERO, "and later refits are normal")

	var ec: RunData = _take("extra_cell")[0]
	var cells_before := ec.player_mech.cells.size()
	t.assert_true(not DeploymentOrders.add_cell(ec, Vector2i(40, 40)), "a square must touch the frame")
	t.assert_true(DeploymentOrders.add_cell(ec, ec.cell_options()[0]), "Extra Frame Square: placed where the pilot clicks")
	t.assert_eq(ec.player_mech.cells.size(), cells_before + 1, "the frame has one more square")
	t.assert_eq(ec.scraps, 0, "for free")
	t.assert_true(not ec.orders_pending(), "done")

	var xc: RunData = _take("expanded_cargo")[0]
	t.assert_eq([xc.cargo.rows, xc.cargo.cols], [4, 3], "Expanded Cargo: +1 row")

	var fr: RunData = _take("field_repair")[0]
	_enter(fr, RunMap.KIND_REPAIR)
	t.assert_eq(fr.repair_pool, Economy.repair_pool(fr.player_mech.max_hp(), 1.2), "Field Repair Kit: repair bays hand out 20% more")

	var cs: RunData = _take("cold_start")[0]
	var coolant := []
	var cold_n := _o("cold_start", "fights")
	for i in range(cold_n + 1):
		_win_next_fight_prepare(cs)
		cs.prepare_player_for_fight()
		var enemies: Array[MechData] = []
		cs.apply_fight_start_effects(cs.player_mech, enemies)
		var hp: ComponentData = cs.player_mech.components.filter(func(c): return c.category == ComponentData.CATEGORY_HARDPOINT)[0]
		coolant.append(hp.status_stacks("coolant"))
		cs.fight_won()
		cs.finish_reward()
	var cold_want := []
	for i in range(cold_n):
		cold_want.append(_o("cold_start", "stacks"))
	t.assert_eq(coolant, cold_want + [0], "Cold Start: Coolant on the hardpoints for the first %d fights" % cold_n)

	var wp: RunData = _take("wider_picks")[0]
	var sizes := []
	var wide_n := _o("wider_picks", "fights")
	for i in range(wide_n + 1):
		sizes.append((_win_next_fight(wp)["options"]["hardpoint"] as Array).size())
	var wide_want := []
	for i in range(wide_n):
		wide_want.append(_o("wider_picks", "options"))
	t.assert_eq(sizes, wide_want + [3], "Wider Picks: more parts per pick for the first %d fights" % wide_n)

	var fm: RunData = _take("friendly_merchant")[0]
	_enter(fm, RunMap.KIND_SHOP)
	fm.shop = {"parts": ["autocannon", "autocannon", "autocannon"], "upgrade_bought": false}
	t.assert_eq(fm.part_price("autocannon"), 0, "Friendly Merchant: a part is free")
	t.assert_true(fm.buy_part(0) != null and fm.scraps == 0, "bought with no scraps")
	t.assert_eq(fm.part_price("autocannon"), Economy.price("autocannon"), "only one")
	var fm2: RunData = _take("friendly_merchant")[0]
	_enter(fm2, RunMap.KIND_SHOP)
	fm2.leave_shop()
	t.assert_eq(fm2.part_price("autocannon"), Economy.price("autocannon"), "unused, it's gone after the first autonomous bay")

	t.group("Tradeoffs")
	var st: RunData = _take("stripped_frame")[0]
	t.assert_eq(st.scraps, 200, "Stripped Frame: +200 scraps")
	var parts_before := st.player_mech.components.size()
	var reactor: ComponentData = st.player_mech.components.filter(func(c): return c.category != ComponentData.CATEGORY_HARDPOINT)[0]
	DeploymentOrders.choose_part(st, reactor)
	t.assert_eq(st.player_mech.components.size(), parts_before - 1, "the chosen component is stripped out")
	t.assert_true(not st.cargo.items.has(reactor), "gone for the run, not stowed")
	var st2: RunData = _take("stripped_frame")[0]
	var hps := st2.player_mech.components.filter(func(c): return c.category == ComponentData.CATEGORY_HARDPOINT)
	for i in range(hps.size() - 1):
		st2.player_mech.components.erase(hps[i])
	t.assert_true(not DeploymentOrders.can_choose_part(st2, hps[-1]), "the last working hardpoint can't be stripped")

	var mc: RunData = _take("modular_chassis")[0]
	var neon: ComponentData = mc.player_mech.get_component("neon_axe")
	t.assert_eq([neon.max_hp, neon.current_hp], [54, 54], "Modular Chassis: the parts launched with get -10 max HP (Neon Axe 64 -> 54)")
	t.assert_eq(mc.new_part("autocannon").max_hp, int(ComponentLibrary.definition("autocannon")["hp"]), "parts gained later are full HP (swapping out escapes it)")
	t.assert_eq(mc.phase, RunData.PHASE_MAP, "no refit (it hands out no parts)")
	var mc_cells := mc.player_mech.cells.size()
	DeploymentOrders.add_cell(mc, mc.cell_options()[0])
	t.assert_true(mc.orders_pending(), "one square placed, one to go")
	DeploymentOrders.add_cell(mc, mc.cell_options()[0])
	t.assert_true(not mc.orders_pending() and mc.player_mech.cells.size() == mc_cells + 2, "two squares added")
	var mc_back := _reload(mc)
	t.assert_eq(mc_back.player_mech.get_component("neon_axe").max_hp, 54, "the HP cut survives a reload")
	t.assert_eq(mc_back.player_mech.max_hp(), mc.player_mech.max_hp(), "on exactly those parts")
	t.assert_eq(mc_back.player_mech.cells.size(), mc_cells + 2, "and so do the squares")

	var oc: RunData = _take("overclocked_core")[0]
	t.assert_eq(oc.player_mech.max_heat, 17, "Overclocked Core: +3 max heat (Bastion 14 -> 17)")
	var was_reset := HeatRules.full_reset()
	Balance.set_value("heat", "full_reset", true)
	t.assert_eq(HeatRules.amount_vented(17, 17, oc.player_mech.vent_at_max), 13, "vents 80% of its heat, not all of it (17 -> 13 vented)")
	t.assert_eq(HeatRules.amount_vented(17, 17), 17, "(all of it without it)")
	t.assert_eq(HeatRules.amount_vented(10, 17, 0.9), 9, "Heavy Plating's 90%: 10 -> 9")
	Balance.set_value("heat", "full_reset", was_reset)
	t.assert_eq(_reload(oc).player_mech.max_heat, 17, "max heat survives a reload, added once")

	var hs: RunData = _take("hot_start")[0]
	hs.prepare_player_for_fight()
	t.assert_eq([hs.player_mech.max_heat, hs.player_mech.current_heat], [16, 3], "Hot Start: +2 max heat, fights start at 3 heat")

	var req: RunData = _take("special_requisition")[0]
	t.assert_eq(req.player_mech.turn_heat, _o("special_requisition", "turn_heat"), "Special Requisition: extra heat every turn")
	t.assert_eq(_reload(req).player_mech.turn_heat, req.player_mech.turn_heat, "…kept through a reload")
	req.prepare_player_for_fight()
	var req_cm := CombatManager.new(req.player_mech, [DataLoader.load_mech_from_file("res://tests/fixtures/scrap_warden_classic.json")], 3)
	req_cm.start_combat()
	t.assert_eq(req.player_mech.current_heat, _o("special_requisition", "turn_heat"), "…the first turn starts with it")

	var sr: RunData = _take("salvage_rights")[0]
	t.assert_true(not sr.map.nodes.any(func(n): return n["kind"] == RunMap.KIND_REPAIR), "Salvage Rights: no repair bays on the map")
	_win_next_fight_prepare(sr)
	var foes := int(sr.current_node()["enemy_count"])
	sr.fight_won()
	var plain_max := Balance.get_int("economy", "scraps_base", 10) + Balance.get_int("economy", "scraps_per_enemy", 5) * foes + Balance.get_int("economy", "scraps_spread", 5)
	t.assert_true(sr.reward["scraps"] > plain_max, "fights pay 50%% more (%d, a plain fight pays at most %d)" % [sr.reward["scraps"], plain_max])
	sr.finish_reward()
	var no_repair := true
	for s in range(1, 30):
		no_repair = no_repair and not _reload(_take("salvage_rights", s)[0]).map.nodes.any(func(n): return n["kind"] == RunMap.KIND_REPAIR)
	t.assert_true(no_repair, "never any, across seeds and reloads")

	var elites_plain := 0
	var elites_hunt := 0
	var early := false
	for s in range(1, 40):
		elites_plain += _run(s).map.nodes.filter(func(n): return n["kind"] == RunMap.KIND_ELITE).size()
		var h: RunData = _take("hunters_route", s)[0]
		elites_hunt += h.map.nodes.filter(func(n): return n["kind"] == RunMap.KIND_ELITE).size()
		early = early or h.map.nodes.any(func(n): return n["kind"] == RunMap.KIND_ELITE and n["row"] == 1)
	t.assert_true(elites_hunt > elites_plain * 1.4, "Hunter's Route: more elites (%d vs %d over 39 maps)" % [elites_hunt, elites_plain])
	t.assert_true(early, "from the second row on")
	var hr: RunData = _take("hunters_route", 3)[0]
	t.assert_eq(_reload(hr).map.nodes.map(func(n): return n["kind"]), hr.map.nodes.map(func(n): return n["kind"]), "the changed map survives a reload")

	var ls: RunData = _take("loan_shark")[0]
	t.assert_eq(ls.scraps, _o("loan_shark", "scraps"), "Loan Shark: its scraps now")
	var paid := []
	var unpaid_n := _o("loan_shark", "unpaid_fights")
	for i in range(unpaid_n + 1):
		paid.append(_win_next_fight(ls)["scraps"] > 0)
	var paid_want := []
	for i in range(unpaid_n):
		paid_want.append(false)
	t.assert_eq(paid, paid_want + [true], "the first %d fights pay nothing" % unpaid_n)

	var bd: RunData = _take("blind_drop")[0]
	t.assert_true(bd.scraps == _o("blind_drop", "scraps") and int(bd.mod("fog", 0)) == 2, "Blind Drop: its scraps, the map fogged past two rows")
	t.assert_true(DeploymentOrders.pick_category(bd, "hardpoint").all(func(id): return ComponentLibrary.definition(id)["rarity"] == "prototype"), "and a Prototype pick")

	var hi: RunData = _take("hot_insertion")[0]
	for i in range(2):
		var o := DeploymentOrders.pick_category(hi, "reactor")
		DeploymentOrders.pick_part(hi, o[0])
	t.assert_true(not hi.orders_pending() and hi.cargo.items.size() == 2, "Hot Insertion: two Salvaged picks")
	var strong: Array = _sector("shipyard")["encounters"]["strong"].map(func(e): return ",".join(e["enemies"]))
	var weak: Array = _sector("shipyard")["encounters"]["weak"].map(func(e): return ",".join(e["enemies"]))
	var first_two := true
	var third_weak := false
	var strong_n := _o("hot_insertion", "strong_fights")
	for s in range(1, 20):
		var h: RunData = _take("hot_insertion", s)[0]
		h.orders["steps"] = []
		var regular := 0
		while regular < strong_n + 1:
			_win_next_fight_prepare(h)
			if h.current_node()["kind"] == RunMap.KIND_FIGHT:
				var key := ",".join(h.current_node()["enemies"])
				if regular < strong_n:
					first_two = first_two and strong.has(key)
				else:
					third_weak = third_weak or (weak.has(key) and not strong.has(key))
				regular += 1
			h.fight_won()
			h.finish_reward()
	t.assert_true(first_two, "its first %d fights come from the strong pool" % strong_n)
	t.assert_true(third_weak, "then the weak pool picks up where it was")

	var hh: RunData = _take("heavy_hauler")[0]
	t.assert_eq([hh.cargo.rows, hh.cargo.cols, hh.player_mech.max_heat], [5, 4, 13], "Heavy Hauler: Cargo 5×4, 1 less max heat")

	t.group("Gambles")
	var sp: RunData = _take("spare_parts")[0]
	t.assert_true(sp.cargo.items.size() == 2 and sp.phase == RunData.PHASE_REFIT, "Spare Parts Crate: two parts in Cargo, then a refit")
	t.assert_true((sp.cargo.items + sp.bench.items).all(func(c): return c.rarity == "surplus"), "both Surplus")

	var pc: RunData = _take("prototype_contract")[0]
	var got: Array = pc.cargo.items + pc.bench.items
	t.assert_true(got.size() == 1 and got[0].rarity == "prototype", "Prototype Contract: a Prototype part")
	t.assert_true(pc.player_mech.components.all(func(c): return c.current_hp == ceili(c.max_hp * 0.6)), "installed parts at 60% HP")

	var sc_ok := true
	for s in range(1, 25):
		var before := _run(s).player_mech.components
		var sc: RunData = _take("scramble", s)[0]
		var want := before.map(func(c): return "%s %s" % [c.category, Economy.rarity_above(c.rarity)])
		var have := (sc.cargo.items + sc.bench.items).map(func(c): return "%s %s" % [c.category, c.rarity])
		want.sort()
		have.sort()
		sc_ok = sc_ok and want == have and sc.player_mech.components.is_empty()
		sc_ok = sc_ok and sc.phase == RunData.PHASE_REFIT and (sc.orders["swaps"] as Array).size() == before.size()
	t.assert_true(sc_ok, "Scramble: every part off the chassis, its replacement (same type, a rarity up) in Cargo, and a refit")
	var sc1: RunData = _take("scramble", 1)[0]
	var sw: Dictionary = sc1.orders["swaps"][0]
	t.assert_true(sw.has("old") and sw.has("offset") and sc1.cargo.items.any(func(c): return c.id == sw["new"]), "each swap is kept for the refit to animate")

	var tm: RunData = _take("transmute")[0]
	var axe: ComponentData = tm.player_mech.get_component("neon_axe")
	var note := DeploymentOrders.choose_part(tm, axe)
	t.assert_true(not tm.player_mech.components.has(axe), "Transmute: the chosen part is replaced (%s)" % note)
	t.assert_eq(tm.phase, RunData.PHASE_REFIT, "then a refit")
	var new_hp: Array = tm.cargo.items.filter(func(c): return c.category == ComponentData.CATEGORY_HARDPOINT and c.rarity == "prototype")
	t.assert_eq(new_hp.size(), 1, "by a hardpoint one rarity up (Neon Axe is Salvaged: a Prototype)")

	t.group("Saving: the offer and the steps left survive a reload")
	var sv := _run()
	DeploymentOrders.offer(sv)
	t.assert_eq(_reload(sv).orders["offer"], sv.orders["offer"], "the offer can't be rerolled by reloading")
	var sv2: RunData = _take("hot_insertion")[0]
	DeploymentOrders.pick_category(sv2, "hardpoint")
	var back := _reload(sv2)
	t.assert_true(back.orders_pending() and DeploymentOrders.current_step(back)["options"] == DeploymentOrders.current_step(sv2)["options"], "a pick's options stay the same")

## Goes straight to a stop of `kind` (a starting spot is linked to it).
static func _enter(run: RunData, kind: String) -> void:
	for n in run.map.nodes:
		if n["kind"] == kind:
			var start: Dictionary = run.map.nodes_in_row(0)[0]
			start["next"] = [n["id"]]
			run.path.append(start["id"])
			run.choose_node(n["id"])
			return

## Walks to the next fight without winning it.
static func _win_next_fight_prepare(run: RunData) -> void:
	for _guard in range(30):
		match run.phase:
			RunData.PHASE_MAP:
				run.choose_node(run.available_nodes()[0])
			RunData.PHASE_FIGHT:
				return
			RunData.PHASE_REFIT: run.finish_refit()
			RunData.PHASE_REPAIR: run.finish_repair()
			RunData.PHASE_SHOP: run.leave_shop()
			RunData.PHASE_EVENT:
				run.resolve_event(1)
				run.finish_event()
			RunData.PHASE_REWARD: run.finish_reward()

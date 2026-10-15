class_name TestLibrary
extends RefCounted
## ComponentLibrary: every Refit Bay part loads verbatim, reactors are
## passives, and only fully implemented parts reach the reward/shop pools.

static func run_all(t: TestContext) -> void:
	_keyword_hints(t)
	t.group("ComponentLibrary: every Refit Bay part loads")
	var ids := ComponentLibrary.all_ids()
	t.assert_eq(ComponentLibrary.definition("heat_lance")["name"], "Heat Lance", "the game shows a draft's name without (C)")
	var loads_ok := true
	var reactors_passive := true
	for id in ids:
		var c := ComponentLibrary.make(id)
		var d := ComponentLibrary.definition(id)
		if c == null or c.max_hp != maxi(1, roundi(int(d["hp"]) * Balance.get_num("combat", "hp_mult", 1.0))) or c.cells.size() != (d["cells"] as Array).size() or c.rarity != d["rarity"]:
			loads_ok = false
		if c != null and c.category == ComponentData.CATEGORY_REACTOR and (c.has_cards() or not c.has_passive()):
			reactors_passive = false
	t.assert_true(loads_ok, "each part's HP (times balance.json hp_mult), shape and rarity match its Refit Bay entry")
	t.assert_true(reactors_passive, "every reactor is a passive with no card in the hand")
	_scaling(t)
	_kits(t)
	var cap := ComponentLibrary.make("capacitor_bank")
	t.assert_eq(cap.passive_text(), "Gain Absorb 10. Triggers automatically at turn start (not a played card).", "a reactor's passive text is its Refit Bay card's statuses + text")
	t.assert_eq(int(cap.passive["stacks"]), 10, "Capacitor Bank's stacks come from Refit Bay")

	t.group("ComponentLibrary: only implemented parts are offered")
	t.assert_true(["neon_axe", "voltage_spike", "scatter_shot", "redirect_spike", "capacitor_bank", "insulated_core"].all(func(id): return ComponentLibrary.is_implemented(id)), "the starting parts are implemented")
	var pool_ok := true
	for cat in ["hardpoint", "reactor", "protocol"]:
		for rarity in ["surplus", "salvaged", "prototype"]:
			for id in ComponentLibrary.pool(cat, rarity):
				var d := ComponentLibrary.definition(id)
				if d["category"] != cat or d["rarity"] != rarity or not ComponentLibrary.is_implemented(id):
					pool_ok = false
	t.assert_true(pool_ok, "pools hold only implemented parts of that category and rarity")

	t.group("Mech files name library parts by id")
	var b := DataLoader.load_mech_from_file("res://tests/fixtures/bastion_classic.json")
	t.assert_eq(b.get_component("neon_axe").placed_cells.size(), 5, "Neon Axe placed from its library shape")
	t.assert_eq(b.get_component("neon_axe").rarity, "salvaged", "and keeps its Refit Bay rarity")

	t.group("Redline and Jackal: Refit Bay chassis, all-Surplus starting loadouts")
	var chassis_data: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/chassis.json"))["chassis"]
	var chassis_ok := true
	var surplus_ok := true
	for mid in ["redline", "jackal"]:
		var pm := DataLoader.load_mech_from_file("res://data/mechs/%s.json" % mid)
		var ref: Dictionary = chassis_data.filter(func(c): return c["id"] == mid)[0]
		var ref_cells: Array[Vector2i] = []
		for c in ref["cells"]:
			ref_cells.append(Vector2i(int(c[0]), int(c[1])))
		ref_cells.sort()
		var got := pm.cells.duplicate()
		got.sort()
		chassis_ok = chassis_ok and got == ref_cells and pm.max_heat == int(ref["max_heat"])
		surplus_ok = surplus_ok and pm.components.all(func(c): return c.rarity == "surplus") \
			and pm.components.any(func(c): return c.category == ComponentData.CATEGORY_HARDPOINT)
	t.assert_true(chassis_ok, "their cells and max heat are Refit Bay's chassis")
	t.assert_true(surplus_ok, "every starting part is Surplus, with a hardpoint")

	t.group("End-of-turn heat check: over max mid-turn is fine; ending the turn over max is backlash")
	var rl := DataLoader.load_mech_from_file("res://tests/fixtures/redline_classic.json")
	var dummy_tank := TestFixtures.make_component("tank", 400)
	dummy_tank.library_id = "tank"
	var dummy := TestFixtures.make_mech("dummy", 20, [dummy_tank] as Array[ComponentData])
	var rcm := CombatManager.new(rl, [dummy] as Array[MechData], 3)
	rcm.start_combat()
	var lance := rl.get_component("thermal_lance")
	rl.current_heat = 12 - lance.cards[0].heat_cost
	var r := rcm.play_attack_card(lance.cards[0], dummy, dummy_tank) # Piercing Rush: to 12 of 10
	t.assert_true(not r.get("overheated", false) and rcm.is_player_turn(), "12 / 10 mid-turn: no backlash yet, still your turn")
	var flare := rl.get_component("flare_array")
	rcm.play_self_card(flare.cards[1]) # Heat Eject: vent 3 -> 9
	t.assert_eq(rl.current_heat, 9, "Heat Eject vents it back to 9")
	rcm.end_player_turn()
	t.assert_eq(rcm.stats.get_stat("overheats"), 0, "vented back to 9 before the end: no overheat")
	var rl2 := DataLoader.load_mech_from_file("res://tests/fixtures/redline_classic.json")
	var rcm2 := CombatManager.new(rl2, [dummy] as Array[MechData], 4)
	rcm2.start_combat()
	rl2.current_heat = 11
	rcm2.end_player_turn()
	t.assert_eq(rcm2.stats.get_stat("overheats"), 1, "ending the turn at 11 / 10: backlash")

## balance.json "combat": damage and heat scaled as parts load.
static func _scaling(t: TestContext) -> void:
	t.group("ComponentLibrary: balance.json combat scaling")
	var saved := Balance.section("combat").duplicate()
	Balance.set_value("combat", "damage_mult", 0.75)
	Balance.set_value("combat", "heat_mult", 1.5)
	Balance.set_value("combat", "heat_add", 0)
	var blade := ComponentLibrary.make("ion_blade")
	var swipe: CardData = blade.cards[0]
	var thrust: CardData = blade.cards[1]
	t.assert_eq([swipe.damage_min, swipe.damage_max], [4, 6], "Swipe 5–8 × 0.75 = 4–6 (rounded)")
	t.assert_eq(swipe.heat_cost, 2, "…and its 1 heat × 1.5 = 2")
	t.assert_eq([thrust.damage_min, thrust.damage_max, thrust.heat_cost], [9, 12, 9], "Thrust Through 12–16 for 6 → 9–12 for 9")
	var cool: CardData = ComponentLibrary.make("thermal_spike_rifle").cards.filter(func(c): return c.heat_cost < 0)[0]
	t.assert_true(cool.heat_cost < 0, "a vent card keeps its negative cost (%d)" % cool.heat_cost)
	var lock: CardData = ComponentLibrary.make("targeting_computer").cards[0]
	t.assert_eq(lock.heat_cost, 0, "a protocol isn't scaled")
	Balance.set_value("combat", "heat_mult", 1.0)
	Balance.set_value("combat", "heat_add", 1)
	var plus: ComponentData = ComponentLibrary.make("ion_blade")
	t.assert_eq([plus.cards[0].heat_cost, plus.cards[1].heat_cost], [2, 7], "heat_add 1: Swipe 1 → 2, Thrust Through 6 → 7")
	t.assert_eq(ComponentLibrary.make("targeting_computer").cards[0].heat_cost, 0, "…a free card stays free")
	Balance.set_value("combat", "heat_add", 0)
	Balance.set_value("combat", "damage_mult", 1.0)
	t.assert_eq([ComponentLibrary.make("ion_blade").cards[0].damage_min, ComponentLibrary.make("ion_blade").cards[0].heat_cost], [5, 1], "at 1.0 Refit Bay's numbers are untouched")
	for k in saved:
		Balance.set_value("combat", k, saved[k])

## Starting kits all deal about 50 a turn (Logan, 2026-09-30), on Refit
## Bay damage with the live +1 heat per card.
static func _kits(t: TestContext) -> void:
	t.group("Starting kits: about 50 damage a turn, all Surplus")
	var saved := Balance.section("combat").duplicate()
	Balance.set_value("combat", "heat_add", 1)
	for id in ["bastion", "redline", "jackal"]:
		var m := DataLoader.load_mech_from_file("res://data/mechs/%s.json" % id)
		var turn := KitMath.mech_turn(m)
		t.assert_true(turn >= 45.0 and turn <= 56.0, "%s: %.1f a turn" % [id, turn])
		t.assert_true(m.components.all(func(c): return c.rarity == "surplus"), "%s's kit is all Surplus" % id)
	for k in saved:
		Balance.set_value("combat", k, saved[k])

## Card text's statuses and keywords get a hover hint each, in one pass.
static func _keyword_hints(t: TestContext) -> void:
	t.group("StatusGlossary.annotate: keyword links")
	var a := StatusGlossary.annotate("Apply Shock 2. Vent 3. Double damage vs Frozen. Overheating hurts. [x]")
	t.assert_eq(a.count("[url="), 4, "Shock, Vent, Frozen and Overheating each get a link")
	t.assert_true(a.contains("[lb]x]"), "a literal [ is escaped")
	t.assert_eq(StatusGlossary.annotate("Pierce").count("[url="), 1, "a keyword is tagged once")
	t.assert_eq(StatusGlossary.lookup("Frozen")["label"], "Freeze", "a status's other form looks up the status")
	t.assert_eq(StatusGlossary.lookup("Overheating")["label"], "Overheat", "a keyword's other form looks up the keyword")
	t.assert_true(StatusGlossary.lookup("Shockwave").is_empty(), "a word that names nothing looks up nothing")
	var card_entries := StatusGlossary.entries_for("Reclaim 30%. Pierce.", ["shock", "shock"])
	t.assert_eq(card_entries.map(func(e): return e["label"]), ["Shock", "Pierce", "Reclaim"], "a card's statuses, then its keywords in glossary order, once each")
	t.assert_eq(StatusGlossary.annotate("Shockwave hits."), "Shockwave hits.", "only whole words")


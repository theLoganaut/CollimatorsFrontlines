class_name TestDataLoader
extends RefCounted
## Parsing helpers, rotation math, and mech files loading into parts, cards
## and passives that sit on their chassis. Refit Bay's own numbers aren't
## pinned here: they change on every import.

static func run_all(t: TestContext) -> void:
	t.group("DataLoader: parsing helpers")
	t.assert_eq(DataLoader.parse_damage_range("6-10"), [6, 10], "parses a-b damage range")
	t.assert_eq(DataLoader.parse_damage_range("0"), [0, 0], "'0' damage is [0,0]")
	t.assert_eq(DataLoader.parse_damage_range(""), [0, 0], "blank damage is [0,0]")

	t.group("CardData: damage label")
	var lbl := CardData.new()
	lbl.hits = 3; lbl.damage_min = 6; lbl.damage_max = 10
	t.assert_eq(lbl.damage_label(), "3×6–10", "multi-hit shows hits × range")
	lbl.hits = 1
	t.assert_eq(lbl.damage_label(), "6–10", "a single hit drops the implied 1×")
	lbl.damage_min = 8; lbl.damage_max = 8
	t.assert_eq(lbl.damage_label(), "8", "a fixed single hit is just the number")
	lbl.hits = 0
	t.assert_eq(lbl.damage_label(), "", "0 hits leaves the corner blank")
	t.assert_eq(DataLoader.parse_heat_cost(""), 0, "blank heat cost is 0 (Lock On)")
	t.assert_eq(DataLoader.parse_heat_cost("-3"), -3, "negative heat cost parses (vents)")
	t.assert_eq(DataLoader.parse_heat_cost("4"), 4, "positive heat cost parses")
	t.assert_eq(DataLoader.parse_hits(""), 0, "blank hits is 0")
	t.assert_eq(DataLoader.parse_hits("3"), 3, "hits parses")

	t.group("GridUtils: rotation (audited against Refit Bay's rotateCells90)")
	var neon_axe_local: Array[Vector2i] = [Vector2i(0,0), Vector2i(0,1), Vector2i(1,0), Vector2i(1,1), Vector2i(2,0)]
	var neon_axe_placed := GridUtils.place_cells(neon_axe_local, 1, Vector2i(0, 2))
	var neon_axe_expected: Array[Vector2i] = [Vector2i(0,2), Vector2i(0,3), Vector2i(0,4), Vector2i(1,3), Vector2i(1,4)]
	t.assert_eq(neon_axe_placed, neon_axe_expected, "Neon Axe (1 step, offset 0,2) matches Combat Slice §2 placed cells")

	var voltage_spike_local: Array[Vector2i] = [Vector2i(0,0), Vector2i(0,1), Vector2i(1,1), Vector2i(2,1)]
	var voltage_spike_placed := GridUtils.place_cells(voltage_spike_local, 2, Vector2i(2, 1))
	var voltage_spike_expected: Array[Vector2i] = [Vector2i(2,1), Vector2i(3,1), Vector2i(4,1), Vector2i(4,2)]
	t.assert_eq(voltage_spike_placed, voltage_spike_expected, "Voltage Spike (2 steps, offset 2,1) matches placed cells")

	var tc_local: Array[Vector2i] = [Vector2i(0,1), Vector2i(1,0), Vector2i(2,1)]
	var tc_placed := GridUtils.place_cells(tc_local, 2, Vector2i(2, 3))
	var tc_expected: Array[Vector2i] = [Vector2i(2,3), Vector2i(3,4), Vector2i(4,3)]
	t.assert_eq(tc_placed, tc_expected, "Targeting Computer (2 steps, offset 2,3) matches placed cells — non-contiguous shape")

	t.group("Mech files load: cards, passives and placement")
	var bastion := DataLoader.load_mech_from_file("res://tests/fixtures/bastion_classic.json")
	t.assert_true(bastion != null, "bastion.json loads")
	if bastion == null:
		return
	t.assert_eq(bastion.current_hp(), bastion.max_hp(), "a fresh mech starts at full HP")
	var insulated_core := bastion.get_component("insulated_core")
	t.assert_eq(insulated_core.category, ComponentData.CATEGORY_REACTOR, "Insulated Core is a REACTOR, not a hardpoint (audit fix)")
	t.assert_eq(insulated_core.passive_type(), ComponentData.PASSIVE_REDUCE_INCOMING_STATUS, "Insulated Core's passive loads")
	var extension: CardData = bastion.all_playable_cards().filter(func(c): return c.id == "extension")[0]
	t.assert_eq(extension.play_mode, CardData.PLAY_MODE_SELF, "a 0-hit card on its own mech is a self card")
	t.assert_eq(extension.statuses[0].target, StatusEffectData.TARGET_OWN_MECH, "and its status targets its own mech")
	var spike_em: CardData = bastion.all_playable_cards().filter(func(c): return c.id == "spike_em")[0]
	t.assert_eq(spike_em.play_mode, CardData.PLAY_MODE_ATTACK, "a card with hits is an attack card")
	var passive_cards := 0
	var overlaps := 0
	var outside := 0
	for id in ["bastion", "redline", "jackal", "scrap_warden"]:
		var m := DataLoader.load_mech_from_file("res://data/mechs/%s.json" % id)
		var chassis := GridUtils.cells_to_set(m.cells)
		var seen := {}
		for comp in m.components:
			if comp.has_passive() and comp.has_cards():
				passive_cards += 1
			for cell in comp.placed_cells:
				if seen.has(cell):
					overlaps += 1
				seen[cell] = true
				if not chassis.has(cell):
					outside += 1
	t.assert_eq(passive_cards, 0, "a passive part never puts a card in the hand (player mechs and the Warden)")
	t.assert_eq(overlaps, 0, "no two parts share a cell")
	t.assert_eq(outside, 0, "every part cell is on its chassis")

	t.group("Fresh instances are independent")
	var b1 := DataLoader.load_mech_from_file("res://tests/fixtures/bastion_classic.json")
	var b2 := DataLoader.load_mech_from_file("res://tests/fixtures/bastion_classic.json")
	b1.get_component("neon_axe").current_hp = 1
	t.assert_eq(b2.get_component("neon_axe").current_hp, 64, "mutating one fresh mech doesn't affect another")

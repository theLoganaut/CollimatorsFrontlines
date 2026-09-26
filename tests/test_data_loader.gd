class_name TestDataLoader
extends RefCounted
## M0's done-when: bastion.json / scrap_warden.json load and print their
## component/card lists correctly (162 HP, 7 cards, Warden 140 HP).

static func run_all(t: TestContext) -> void:
	t.group("DataLoader: parsing helpers")
	t.assert_eq(DataLoader.parse_damage_range("6-10"), [6, 10], "parses a-b damage range")
	t.assert_eq(DataLoader.parse_damage_range("0"), [0, 0], "'0' damage is [0,0]")
	t.assert_eq(DataLoader.parse_damage_range(""), [0, 0], "blank damage is [0,0]")
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

	t.group("Bastion")
	var bastion := DataLoader.load_mech_from_file("res://data/mechs/bastion.json")
	t.assert_true(bastion != null, "bastion.json loads")
	if bastion == null:
		return
	t.assert_eq(bastion.cells.size(), 18, "Bastion has 18 chassis cells")
	t.assert_eq(bastion.max_heat, 14, "Bastion max heat is 14")
	t.assert_eq(bastion.heat_check_timing, MechData.HEAT_CHECK_LIVE, "Bastion checks heat live")
	t.assert_eq(bastion.components.size(), 4, "Bastion has 4 installed components")
	t.assert_eq(bastion.max_hp(), 162, "Bastion total HP is 162")
	t.assert_eq(bastion.current_hp(), 162, "Bastion starts at full HP")

	var all_cards := bastion.all_playable_cards()
	t.assert_eq(all_cards.size(), 7, "Bastion grants 7 cards")
	var left_count := 0
	var right_count := 0
	for c in all_cards:
		if c.hand_side == "left":
			left_count += 1
		elif c.hand_side == "right":
			right_count += 1
	t.assert_eq(left_count, 4, "4 cards on the left")
	t.assert_eq(right_count, 3, "3 cards on the right")

	var neon_axe := bastion.get_component("neon_axe")
	t.assert_true(neon_axe != null, "neon_axe component found")
	t.assert_eq(neon_axe.category, ComponentData.CATEGORY_HARDPOINT, "Neon Axe is a hardpoint")
	t.assert_eq(neon_axe.max_hp, 64, "Neon Axe has 64 HP")

	var insulated_core := bastion.get_component("insulated_core")
	t.assert_true(insulated_core != null, "insulated_core component found")
	t.assert_eq(insulated_core.category, ComponentData.CATEGORY_REACTOR, "Insulated Core is a REACTOR, not a hardpoint (audit fix)")

	var wide_swing: CardData = null
	var cross_chop: CardData = null
	var extension: CardData = null
	var spike_em: CardData = null
	var lock_on: CardData = null
	for c in all_cards:
		match c.id:
			"wide_swing": wide_swing = c
			"cross_chop": cross_chop = c
			"extension": extension = c
			"spike_em": spike_em = c
			"lock_on": lock_on = c
	t.assert_true(wide_swing != null, "Wide Swing present")
	if wide_swing != null:
		t.assert_eq(wide_swing.heat_cost, 4, "Wide Swing costs 4 heat")
		t.assert_eq(wide_swing.hits, 3, "Wide Swing has 3 hits")
		t.assert_eq(wide_swing.damage_min, 6, "Wide Swing min dmg 6")
		t.assert_eq(wide_swing.damage_max, 10, "Wide Swing max dmg 10")
		t.assert_eq(wide_swing.play_mode, CardData.PLAY_MODE_ATTACK, "Wide Swing is an attack card")
	t.assert_true(cross_chop != null, "Cross Chop present")
	if cross_chop != null:
		t.assert_eq(cross_chop.heat_cost, 6, "Cross Chop costs 6 heat")
		t.assert_eq(cross_chop.damage_max, 20, "Cross Chop max dmg 20")
	t.assert_true(extension != null, "Extension present")
	if extension != null:
		t.assert_eq(extension.play_mode, CardData.PLAY_MODE_SELF, "Extension is a self card (0 hits, targets ownMech)")
		t.assert_eq(extension.statuses.size(), 1, "Extension applies one status")
		t.assert_eq(extension.statuses[0].status, "deflect", "Extension applies Deflect")
		t.assert_eq(extension.statuses[0].target, StatusEffectData.TARGET_OWN_MECH, "Extension targets own mech")
	t.assert_true(spike_em != null, "Spike 'Em present")
	if spike_em != null:
		t.assert_eq(spike_em.play_mode, CardData.PLAY_MODE_ATTACK, "Spike 'Em is an attack card (1 hit)")
		t.assert_eq(spike_em.statuses[0].status, "shock", "Spike 'Em applies Shock")
		t.assert_eq(spike_em.statuses[0].stacks, 2, "Spike 'Em applies Shock x2")
	t.assert_true(lock_on != null, "Lock On present")
	if lock_on != null:
		t.assert_eq(lock_on.heat_cost, 0, "Lock On's blank heat cost parses to 0")
		t.assert_eq(lock_on.play_mode, CardData.PLAY_MODE_SELF, "Lock On is a self card")

	t.group("Scrap Warden")
	var warden := DataLoader.load_mech_from_file("res://data/mechs/scrap_warden.json")
	t.assert_true(warden != null, "scrap_warden.json loads")
	if warden == null:
		return
	t.assert_eq(warden.cells.size(), 16, "Scrap Warden has a 4x4 (16 cell) chassis")
	t.assert_eq(warden.max_heat, 8, "Scrap Warden max heat is 8")
	t.assert_eq(warden.components.size(), 4, "Scrap Warden has 4 components")
	t.assert_eq(warden.max_hp(), 140, "Scrap Warden total HP is 140")

	var armor_plate := warden.get_component("armor_plate")
	t.assert_true(armor_plate != null and not armor_plate.has_cards(), "Armor Plate has no cards (pure tank)")
	var slag_reactor := warden.get_component("slag_reactor")
	t.assert_true(slag_reactor != null and not slag_reactor.has_cards(), "Slag Reactor has no cards")
	var scrap_cannon := warden.get_component("scrap_cannon")
	t.assert_true(scrap_cannon != null, "Scrap Cannon found")
	if scrap_cannon != null:
		t.assert_eq(scrap_cannon.max_hp, 40, "Scrap Cannon has 40 HP")
		t.assert_eq(scrap_cannon.cards.size(), 2, "Scrap Cannon grants 2 cards")

	# AI walk order: left->right by leftmost column, tie -> topmost row.
	# Armor Plate (col0,row0), Rivet Driver (col0,row2), Slag Reactor (col1),
	# Scrap Cannon (col2) — skip the two with no cards -> Rivet Driver, Scrap Cannon.
	var with_cards := warden.non_destroyed_components().filter(func(c): return c.has_cards())
	with_cards.sort_custom(func(a, b):
		if a.leftmost_column() != b.leftmost_column():
			return a.leftmost_column() < b.leftmost_column()
		return a.topmost_row() < b.topmost_row()
	)
	t.assert_eq(with_cards.size(), 2, "2 Warden components have cards")
	if with_cards.size() == 2:
		t.assert_eq(with_cards[0].id, "rivet_driver", "AI order: Rivet Driver first")
		t.assert_eq(with_cards[1].id, "scrap_cannon", "AI order: Scrap Cannon second")

	t.group("Fresh instances are independent")
	var b1 := DataLoader.load_mech_from_file("res://data/mechs/bastion.json")
	var b2 := DataLoader.load_mech_from_file("res://data/mechs/bastion.json")
	b1.get_component("neon_axe").current_hp = 1
	t.assert_eq(b2.get_component("neon_axe").current_hp, 64, "mutating one fresh mech doesn't affect another")

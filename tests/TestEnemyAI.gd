class_name TestEnemyAI
extends RefCounted
## v1 enemy AI (Combat Slice §3): walk order, affordability, and a full
## run_turn integration including the "stops if the player mech dies
## mid-turn" and "skipped if nothing is affordable" edge cases.

static func run_all(t: TestContext) -> void:
	t.group("EnemyAI: act_order (left-to-right by leftmost column, tie -> topmost row)")
	var some_card: Array[CardData] = [TestFixtures.make_card("c", "x", 1, 1, 1, 1)]
	var c_col2 := TestFixtures.make_component("col2", 40, some_card)
	c_col2.placed_cells = [Vector2i(0, 2)]
	var c_col0_row3 := TestFixtures.make_component("col0_row3", 40, some_card)
	c_col0_row3.placed_cells = [Vector2i(3, 0)]
	var c_col1 := TestFixtures.make_component("col1", 40, some_card)
	c_col1.placed_cells = [Vector2i(0, 1)]
	var c_col0_row1 := TestFixtures.make_component("col0_row1", 40, some_card)
	c_col0_row1.placed_cells = [Vector2i(1, 0)]
	var c_no_cards := TestFixtures.make_component("no_cards", 40, [])
	c_no_cards.placed_cells = [Vector2i(0, 0)]
	var warden := TestFixtures.make_mech("warden", 8, [c_col2, c_col0_row3, c_col1, c_col0_row1, c_no_cards])
	var order := EnemyAI.act_order(warden)
	t.assert_eq(order.size(), 4, "the no-cards component is excluded, not just ordered last")
	t.assert_eq(order[0].id, "col0_row1", "col0 row1 acts first (leftmost, then topmost)")
	t.assert_eq(order[1].id, "col0_row3", "col0 row3 second (same column, lower row)")
	t.assert_eq(order[2].id, "col1", "col1 third")
	t.assert_eq(order[3].id, "col2", "col2 last")

	t.group("EnemyAI: affordable_cards")
	var cheap := TestFixtures.make_card("cheap", "x", 2, 1, 1, 1)
	var mid := TestFixtures.make_card("mid", "x", 3, 1, 1, 1)
	var pricey := TestFixtures.make_card("pricey", "x", 5, 1, 1, 1)
	var comp := TestFixtures.make_component("x", 40, [cheap, mid, pricey])
	var mech8 := TestFixtures.make_mech("m", 8, [comp])
	mech8.current_heat = 6
	var pool := EnemyAI.affordable_cards(comp, mech8)
	t.assert_eq(pool.size(), 1, "only the 2-cost card fits under 8 with 6 already spent")
	t.assert_eq(pool[0].id, "cheap", "the affordable one is the cheap one")

	t.group("EnemyAI: choose_card only ever returns an affordable card")
	for seed_value in range(1, 11):
		var chosen := EnemyAI.choose_card(comp, mech8, TestFixtures.rng(seed_value))
		t.assert_true(chosen != null and chosen.id == "cheap", "seed %d picks the only affordable card" % seed_value)

	t.group("EnemyAI: choose_target skips destroyed components")
	var live1 := TestFixtures.make_component("live1", 10)
	var live2 := TestFixtures.make_component("live2", 10)
	var destroyed := TestFixtures.make_component("destroyed", 10)
	destroyed.destroyed = true
	var target_mech := TestFixtures.make_mech("targets", 14, [live1, live2, destroyed])
	for seed_value in range(1, 11):
		var target := EnemyAI.choose_target(target_mech, TestFixtures.rng(seed_value))
		t.assert_true(target.id == "live1" or target.id == "live2", "seed %d never targets the destroyed component" % seed_value)

	t.group("EnemyAI: run_turn pays heat and deals damage")
	var rivet_card := TestFixtures.make_card("rivet_burst", "rivet", 2, 2, 4, 6)
	var rivet := TestFixtures.make_component("rivet", 34, [rivet_card])
	rivet.placed_cells = [Vector2i(2, 0)]
	var cannon_card := TestFixtures.make_card("grapeshot", "cannon", 2, 3, 3, 5)
	var cannon := TestFixtures.make_component("cannon", 40, [cannon_card])
	cannon.placed_cells = [Vector2i(0, 2)]
	var live_warden := TestFixtures.make_mech("live_warden", 8, [rivet, cannon])
	var player_c1 := TestFixtures.make_component("p1", 100)
	var player_c2 := TestFixtures.make_component("p2", 100)
	var live_player := TestFixtures.make_mech("live_player", 14, [player_c1, player_c2])
	var log := EnemyAI.run_turn(live_warden, live_player, TestFixtures.rng(5))
	t.assert_eq(log.size(), 2, "both Warden components act (rivet then cannon)")
	t.assert_eq(log[0]["component"], "rivet", "rivet acts first (leftmost column)")
	t.assert_eq(log[1]["component"], "cannon", "cannon acts second")
	t.assert_eq(live_warden.current_heat, 4, "both cards' heat cost (2+2) was paid")
	t.assert_true(live_player.current_hp() < 200, "the player mech actually took damage")

	t.group("EnemyAI: run_turn skips a component that can't afford anything")
	var broke_card := TestFixtures.make_card("too_pricey", "broke", 5, 1, 1, 1)
	var broke_component := TestFixtures.make_component("broke", 34, [broke_card])
	var broke_warden := TestFixtures.make_mech("broke_warden", 1, [broke_component]) # max heat 1, card costs 5
	var target_mech2 := TestFixtures.make_mech("t2", 14, [TestFixtures.make_component("tc", 50)])
	var log2 := EnemyAI.run_turn(broke_warden, target_mech2, TestFixtures.rng(1))
	t.assert_eq(log2.size(), 0, "nothing affordable -> no action logged, not an error")
	t.assert_eq(broke_warden.current_heat, 0, "no heat paid when nothing was played")

	t.group("EnemyAI: run_turn stops once the player mech is fully destroyed mid-turn")
	var lethal_card_a := TestFixtures.make_card("lethal_a", "attacker_a", 1, 1, 999, 999)
	var attacker_a := TestFixtures.make_component("attacker_a", 40, [lethal_card_a])
	attacker_a.placed_cells = [Vector2i(0, 0)]
	var lethal_card_b := TestFixtures.make_card("lethal_b", "attacker_b", 1, 1, 999, 999)
	var attacker_b := TestFixtures.make_component("attacker_b", 40, [lethal_card_b])
	attacker_b.placed_cells = [Vector2i(0, 1)]
	var lethal_warden := TestFixtures.make_mech("lethal_warden", 20, [attacker_a, attacker_b])
	var frail_component := TestFixtures.make_component("frail", 1)
	var frail_player := TestFixtures.make_mech("frail_player", 14, [frail_component])
	var log3 := EnemyAI.run_turn(lethal_warden, frail_player, TestFixtures.rng(1))
	t.assert_eq(log3.size(), 1, "only attacker_a acts — attacker_b never gets a turn once the player mech is dead")
	t.assert_true(frail_player.is_defeated(), "the lone player component was destroyed")

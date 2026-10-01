class_name TestEnemyAI
extends RefCounted
## Enemy AI (Combat Slice §3): walk order, affordability, targeting, and the
## enemy turn stopping once the player mech dies.

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

	t.group("EnemyAI: plan_turn only plans what it can afford")
	var cheap := TestFixtures.make_card("cheap", "x", 2, 1, 1, 1)
	var mid := TestFixtures.make_card("mid", "x", 3, 1, 1, 1)
	var pricey := TestFixtures.make_card("pricey", "x", 5, 1, 1, 1)
	var comp := TestFixtures.make_component("x", 40, [cheap, mid, pricey])
	var mech8 := TestFixtures.make_mech("m", 8, [comp])
	mech8.current_heat = 6
	var only_cheap := true
	for seed_value in range(1, 11):
		var plan := EnemyAI.plan_turn(mech8, TestFixtures.rng(seed_value))
		only_cheap = only_cheap and plan.size() == 1 and plan[0]["card"].id == "cheap"
	t.assert_true(only_cheap, "with 6 of 8 heat spent, only the 2-cost card is ever planned (10 seeds)")
	var broke := TestFixtures.make_component("broke", 34, [TestFixtures.make_card("too_pricey", "broke", 5, 1, 1, 1)])
	t.assert_eq(EnemyAI.plan_turn(TestFixtures.make_mech("broke_warden", 1, [broke]), TestFixtures.rng(1)).size(), 0, "a part that can't afford any card sits the turn out")

	t.group("EnemyAI: choose_target skips destroyed components")
	var live1 := TestFixtures.make_component("live1", 10)
	var live2 := TestFixtures.make_component("live2", 10)
	var destroyed := TestFixtures.make_component("destroyed", 10)
	destroyed.destroyed = true
	var target_mech := TestFixtures.make_mech("targets", 14, [live1, live2, destroyed])
	var never_destroyed := true
	for seed_value in range(1, 11):
		never_destroyed = never_destroyed and EnemyAI.choose_target(target_mech, TestFixtures.rng(seed_value)) != destroyed
	t.assert_true(never_destroyed, "never targets the destroyed component (10 seeds)")

	t.group("Enemy turn: stops once the player mech is destroyed mid-turn")
	var attacker_a := TestFixtures.make_component("attacker_a", 40, [TestFixtures.make_card("lethal_a", "attacker_a", 1, 1, 999, 999)])
	attacker_a.placed_cells = [Vector2i(0, 0)]
	var attacker_b := TestFixtures.make_component("attacker_b", 40, [TestFixtures.make_card("lethal_b", "attacker_b", 1, 1, 999, 999)])
	attacker_b.placed_cells = [Vector2i(0, 1)]
	var lethal_warden := TestFixtures.make_mech("lethal_warden", 20, [attacker_a, attacker_b])
	var frail_player := TestFixtures.make_mech("frail_player", 14, [TestFixtures.make_component("frail", 1)])
	var cm := CombatManager.new(frail_player, [lethal_warden] as Array[MechData], 1)
	var hits := [0]
	cm.hit_landed.connect(func(_m, _c, _d): hits[0] += 1)
	cm.start_combat()
	cm.end_player_turn()
	t.assert_eq(hits[0], 1, "only attacker_a fires; attacker_b never acts once the player mech is dead")
	t.assert_eq(cm.result, CombatManager.Result.LOSE, "and the fight is lost")

	t.group("EnemyAI: Replay is never planned after an attack that Disables its own part")
	var fizzled := 0
	for seed_value in range(1, 41):
		var c := DataLoader.load_mech_from_file("res://data/mechs/cipher.json")
		var plan := EnemyAI.plan_turn(c, TestFixtures.rng(seed_value))
		for i in range(plan.size()):
			if (plan[i]["card"] as CardData).protocol() == "replay" and i > 0:
				var before: Array = plan.slice(0, i).filter(func(st): return (st["card"] as CardData).hits > 0)
				if not before.is_empty() and EnemyAI._disables_self(before[-1]["card"]):
					fizzled += 1
	t.assert_eq(fizzled, 0, "no Replay right after Cipher's Wrap Up (40 plans)")


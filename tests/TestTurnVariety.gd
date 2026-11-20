class_name TestTurnVariety
extends RefCounted
## The turn-variety rules (Logan, 2026-11-19): heat banking, analyzed parts,
## the enemy card cap with bigger intents, and the utility card buff. The
## runner turns them all off; each group turns its own on and back off.

static func run_all(t: TestContext) -> void:
	_banking(t)
	_analysis(t)
	_card_cap(t)
	_scaling(t)

static func _fight(max_heat: int = 10, enemy_tier: String = "") -> Dictionary:
	var card := TestFixtures.make_card("atk", "pc", 3, 1, 10, 10)
	var cards: Array[CardData] = [card]
	var comp := TestFixtures.make_component("pc", 100, cards)
	var player := TestFixtures.make_mech("player", max_heat, [comp])
	var e1 := TestFixtures.make_component("e1", 50)
	var e2 := TestFixtures.make_component("e2", 50)
	var enemy := TestFixtures.make_mech("enemy", 8, [e1, e2])
	enemy.tier = enemy_tier
	var cm := CombatManager.new(player, [enemy], 3)
	return {"cm": cm, "player": player, "card": card, "enemy": enemy, "e1": e1, "e2": e2}

static func _banking(t: TestContext) -> void:
	Balance.set_value("heat", "full_reset", true)
	Balance.set_value("heat", "bank", true)
	Balance.set_value("heat", "bank_share", 1.0)
	Balance.set_value("heat", "bank_max_share", 0.5)

	t.group("Heat banking: unspent heat raises next turn's max, capped at half")
	var f := _fight(10)
	var cm: CombatManager = f["cm"]
	var p: MechData = f["player"]
	cm.start_combat()
	t.assert_eq(p.heat_capacity(), 10, "turn 1: no saved heat")
	cm.play_attack_card(f["card"], f["enemy"], f["e1"])
	t.assert_eq(cm.bank_projection(), 5, "7 unspent of 10, capped at 5")
	cm.end_player_turn()
	t.assert_eq(p.banked_heat, 5, "5 saved")
	t.assert_eq(p.heat_capacity(), 15, "turn 2: max 10 + 5 saved")
	t.assert_eq(cm.bank_cap(), 5, "the cap doesn't grow with saved heat")
	t.assert_eq(cm.bank_projection(p.heat_capacity() - 2), 2, "2 unspent saves 2")

	t.group("Heat banking: an overheat saves nothing, and the fight's end clears it")
	t.assert_eq(cm.bank_projection(p.heat_capacity() + 3), 0, "over max: nothing saved")
	cm._end_game(CombatManager.Result.WIN)
	t.assert_eq(p.banked_heat, 0, "saved heat doesn't outlive the fight")

	t.group("Heat banking: bank_share saves a part of what's unspent")
	Balance.set_value("heat", "bank_share", 0.5)
	var g := _fight(10)
	(g["cm"] as CombatManager).start_combat()
	t.assert_eq((g["cm"] as CombatManager).bank_projection(7), 1, "3 unspent at 50% saves 1")
	Balance.set_value("heat", "bank_share", 1.0)

	t.group("Heat banking: off, nothing is saved")
	Balance.set_value("heat", "bank", false)
	var h := _fight(10)
	(h["cm"] as CombatManager).start_combat()
	(h["cm"] as CombatManager).end_player_turn()
	t.assert_eq((h["player"] as MechData).heat_capacity(), 10, "max Heat unchanged")
	Balance.set_value("heat", "full_reset", false)

static func _analysis(t: TestContext) -> void:
	Balance.set_value("analysis", "enabled", true)
	Balance.set_value("analysis", "damage_mult", 1.5)

	t.group("Analyzed parts: a regular enemy gets one, a different one each turn")
	var f := _fight(10, "regular")
	var cm: CombatManager = f["cm"]
	cm.start_combat()
	var first: ComponentData = cm.analyzed.get(f["enemy"], null)
	t.assert_true(first != null and first.analyzed, "turn 1: a part is analyzed")
	cm.end_player_turn()
	var second: ComponentData = cm.analyzed.get(f["enemy"], null)
	t.assert_true(second != null and second != first, "turn 2: another part")
	t.assert_true(not first.analyzed, "last turn's mark is gone")

	t.group("Analyzed parts: hits on it deal 1.5x")
	var target: ComponentData = second
	var before := target.current_hp
	cm.play_attack_card(f["card"], f["enemy"], target)
	t.assert_eq(before - target.current_hp, 15, "10 damage x 1.5")
	var other: ComponentData = f["e1"] if target == f["e2"] else f["e2"]
	t.assert_eq(CardResolver.card_multiplier(f["card"], other, f["enemy"]), 1.0, "the other part takes normal damage")

	t.group("Analyzed parts: one part across all the enemies")
	cm._end_game(CombatManager.Result.WIN) # clears its marks on the shared enemy
	var e3 := TestFixtures.make_mech("enemy2", 8, [TestFixtures.make_component("e3", 50), TestFixtures.make_component("e4", 50)])
	e3.tier = "elite"
	var boss := TestFixtures.make_mech("boss", 8, [TestFixtures.make_component("b1", 50)])
	boss.tier = "boss"
	var multi := CombatManager.new(f["player"], [f["enemy"], e3, boss], 9)
	multi.start_combat()
	for turn in range(4):
		var marked := 0
		for m in [f["enemy"], e3, boss]:
			for c in (m as MechData).components:
				if c.analyzed:
					marked += 1
		t.assert_eq(marked, 1, "turn %d: exactly one analyzed part" % (turn + 1))
		t.assert_true(not multi.analyzed.has(boss), "turn %d: not on the boss" % (turn + 1))
		multi.end_player_turn()
	multi._end_game(CombatManager.Result.WIN)

	t.group("Analyzed parts: never on a boss")
	var b := _fight(10, "boss")
	(b["cm"] as CombatManager).start_combat()
	t.assert_true((b["cm"] as CombatManager).analyzed.is_empty(), "the boss has no analyzed part")

	t.group("Analyzed parts: the same seed picks the same parts")
	var r1 := _fight(10, "regular")
	var r2 := _fight(10, "regular")
	(r1["cm"] as CombatManager).start_combat()
	(r2["cm"] as CombatManager).start_combat()
	t.assert_eq(((r1["cm"] as CombatManager).analyzed[r1["enemy"]] as ComponentData).id,
		((r2["cm"] as CombatManager).analyzed[r2["enemy"]] as ComponentData).id, "replays see the same weak point")
	(r1["cm"] as CombatManager)._end_game(CombatManager.Result.WIN)
	(r2["cm"] as CombatManager)._end_game(CombatManager.Result.WIN)
	(b["cm"] as CombatManager)._end_game(CombatManager.Result.WIN)
	Balance.set_value("analysis", "enabled", false)

static func _card_cap(t: TestContext) -> void:
	t.group("Enemy card cap: a regular plays at most max_cards a turn")
	Balance.set_value("enemy_ai", "max_cards", {"regular": 2})
	var cards: Array[CardData] = []
	for i in range(4):
		cards.append(TestFixtures.make_card("hit%d" % i, "gun", 1, 1, 3, 3))
	var gun := TestFixtures.make_component("gun", 40, cards)
	var enemy := TestFixtures.make_mech("capped", 20, [gun])
	enemy.tier = "regular"
	var pc := TestFixtures.make_component("pc", 100)
	var player := TestFixtures.make_mech("player", 10, [pc])
	var cm := CombatManager.new(player, [enemy], 5)
	cm.start_combat()
	var plan: Array = cm.enemy_plans.get(enemy, [])
	t.assert_eq(plan.size(), 2, "4 affordable cards, 2 planned")
	Balance.set_value("enemy_ai", "max_cards", {})
	var cm2 := CombatManager.new(player, [enemy], 5)
	cm2.start_combat()
	t.assert_eq((cm2.enemy_plans.get(enemy, []) as Array).size(), 4, "no cap: all 4")

static func _scaling(t: TestContext) -> void:
	t.group("Utility cards: skip heat_add and get more Deflect / Absorb")
	Balance.set_value("combat", "heat_add", 1)
	Balance.set_value("combat", "utility_skip_heat_add", true)
	Balance.set_value("combat", "utility_shield_mult", 1.25)
	var shield := CardData.new()
	shield.heat_cost = 2
	var d := StatusEffectData.new()
	d.status = "deflect"
	d.stacks = 8
	d.target = StatusEffectData.TARGET_OWN_MECH
	shield.statuses = [d]
	ComponentLibrary.scale_card(shield)
	t.assert_eq(shield.heat_cost, 2, "no +1 Heat")
	t.assert_eq(d.stacks, 10, "Deflect 8 x 1.25 = 10")
	var gun := TestFixtures.make_card("g", "x", 2, 1, 4, 6)
	ComponentLibrary.scale_card(gun)
	t.assert_eq(gun.heat_cost, 3, "a damage card still pays +1")
	Balance.set_value("combat", "heat_add", 0)
	Balance.set_value("combat", "utility_shield_mult", 1.0)

	t.group("Enemy intents: attacks scaled as an enemy loads")
	Balance.set_value("enemy_ai", "intent_damage_mult", 1.2)
	var m := DataLoader.load_mech({"id": "e", "tier": "regular", "max_heat": 8, "components": [
		{"id": "g", "name": "G", "category": "hardpoint", "hp": 10, "cells": [[0, 0]],
		 "cards": [{"id": "s", "name": "S", "heat_cost": 1, "hits": 1, "damage": "10-20"}]}]})
	var c: CardData = m.components[0].cards[0]
	t.assert_eq([c.damage_min, c.damage_max], [12, 24], "10-20 x 1.2 = 12-24")
	var pm := DataLoader.load_mech({"id": "p", "max_heat": 8, "components": [
		{"id": "g", "name": "G", "category": "hardpoint", "hp": 10, "cells": [[0, 0]],
		 "cards": [{"id": "s", "name": "S", "heat_cost": 1, "hits": 1, "damage": "10-20"}]}]})
	t.assert_eq(pm.components[0].cards[0].damage_max, 20, "the player's aren't")
	Balance.set_value("enemy_ai", "intent_damage_mult", 1.0)

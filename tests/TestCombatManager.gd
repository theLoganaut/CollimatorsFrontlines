class_name TestCombatManager
extends RefCounted
## Round structure (Combat Slice §4.1), overheat forcing a turn end, and
## win/lose. Built on small synthetic fixtures rather than real Bastion/
## Warden data so each scenario is exact and easy to reason about.

static func _build_player(card_heat: int, card_hits: int, dmg_min: int, dmg_max: int, max_heat: int = 14) -> Dictionary:
	var card := TestFixtures.make_card("atk", "pc", card_heat, card_hits, dmg_min, dmg_max)
	var comp := TestFixtures.make_component("pc", 100, [card])
	var mech := TestFixtures.make_mech("player", max_heat, [comp])
	return {"mech": mech, "comp": comp, "card": card}

static func run_all(t: TestContext) -> void:
	t.group("CombatManager: start_combat")
	var p := _build_player(4, 1, 10, 10)
	var e_comp := TestFixtures.make_component("ec", 30)
	var enemy := TestFixtures.make_mech("enemy", 8, [e_comp])
	var cm := CombatManager.new(p["mech"], [enemy], 1)
	cm.start_combat()
	t.assert_eq(cm.phase, CombatManager.Phase.PLAYER_TURN, "combat starts on the player's turn")
	t.assert_eq(cm.turn_number, 1, "starts on turn 1")

	t.group("CombatManager: play_attack_card deals damage and pays heat")
	var res := cm.play_attack_card(p["card"], enemy, e_comp)
	t.assert_true(res["ok"], "play succeeds")
	t.assert_eq(p["mech"].current_heat, 4, "heat cost paid")
	t.assert_eq(e_comp.current_hp, 20, "10 damage applied (30 - 10)")

	t.group("CombatManager: rejects illegal plays")
	var destroyed_target := TestFixtures.make_component("dt", 10)
	destroyed_target.destroyed = true
	var bad := cm.play_attack_card(p["card"], enemy, destroyed_target)
	t.assert_true(not bad["ok"] and bad["reason"] == "target_destroyed", "can't target an already-destroyed component")
	var orphan_card := TestFixtures.make_card("orphan", "missing_id", 1, 1, 1, 1)
	var bad2 := cm.play_attack_card(orphan_card, enemy, e_comp)
	t.assert_true(not bad2["ok"] and bad2["reason"] == "source_destroyed", "can't play a card whose owner component doesn't exist / is destroyed")

	t.group("CombatManager: full round structure — player heat vents at step 4, Absorb survives into the enemy's attack")
	var p2 := _build_player(0, 0, 0, 0, 14)
	var e2_card := TestFixtures.make_card("enemy_hit", "e2c", 0, 1, 20, 20)
	var e2_comp := TestFixtures.make_component("e2c", 40, [e2_card])
	var e2 := TestFixtures.make_mech("enemy2", 8, [e2_comp])
	var cm2 := CombatManager.new(p2["mech"], [e2], 2)
	cm2.start_combat()
	# Set this AFTER start_combat(): start_combat() itself runs step 1 (clear Absorb),
	# so setting it before would just be wiped immediately — this simulates state as
	# it stands right when the player presses End Turn, mid-turn.
	p2["mech"].current_heat = 10 # HeatRules: 10 -> 3
	p2["mech"].add_mech_status("absorb", 5)
	cm2.end_player_turn()
	t.assert_eq(p2["mech"].current_heat, 3, "player heat vented once via the ratio formula (10 -> 3)")
	# Absorb only clears at the START of the player's OWN next turn (step 1), so it was
	# still up when the Warden attacked this same call: 20 dmg - 5 absorbed = 15 applied.
	# The 5 prevented tries to heal "pc", which is already at full 100 HP, so no HP is gained.
	t.assert_eq(p2["mech"].get_component("pc").current_hp, 85, "Absorb (still active) cut the enemy's 20 dmg hit to 15")
	t.assert_eq(cm2.turn_number, 2, "turn number advanced")
	t.assert_eq(cm2.phase, CombatManager.Phase.PLAYER_TURN, "back to the player's turn once the enemy turn resolves")
	t.assert_eq(p2["mech"].mech_status_stacks("absorb"), 0, "Absorb was consumed by the enemy's hit, then would clear again at next turn start regardless")

	t.group("CombatManager: enemy heat vents at the start of the player's turn (step 1), not during step 4")
	var p2b := _build_player(0, 0, 0, 0, 14)
	var e2b_comp := TestFixtures.make_component("e2bc", 40, []) # no cards -> does nothing in step 5, isolating the heat math
	var e2b := TestFixtures.make_mech("enemy2b", 8, [e2b_comp])
	e2b.add_mech_status("absorb", 3)
	var cm2b := CombatManager.new(p2b["mech"], [e2b], 20)
	cm2b.start_combat()
	e2b.current_heat = 6 # set after start_combat so the initial (heat-0) vent is a no-op
	cm2b.end_player_turn()
	t.assert_eq(e2b.current_heat, HeatRules.heat_after_vent(6, 8), "Warden heat (6) vented once, by the ratio formula, at the next player-turn start")
	t.assert_eq(e2b.mech_status_stacks("absorb"), 0, "step 4 clears each Warden's Absorb as the enemy turn begins")

	t.group("CombatManager: overheat forces the turn to end")
	var p3 := _build_player(20, 0, 0, 0, 14) # any self-cost card that blows well past max heat
	var e3_comp := TestFixtures.make_component("e3c", 40)
	var e3 := TestFixtures.make_mech("enemy3", 8, [e3_comp])
	var cm3 := CombatManager.new(p3["mech"], [e3], 3)
	cm3.start_combat()
	var starting_hp: int = p3["mech"].current_hp()
	var overheat_res := cm3.play_self_card(p3["card"])
	t.assert_true(overheat_res["overheated"], "20-cost card on a 14-max mech overheats")
	t.assert_true(p3["mech"].current_hp() < starting_hp, "overheat backlash dealt damage")
	t.assert_eq(cm3.phase, CombatManager.Phase.PLAYER_TURN, "the forced turn end already ran the enemy turn and returned control to the player")
	t.assert_eq(cm3.turn_number, 2, "the overheat-forced end still advanced the turn counter")

	t.group("CombatManager: win — all enemies destroyed (checked immediately, no End Turn needed)")
	var p4 := _build_player(1, 1, 999, 999)
	var lone_enemy_comp := TestFixtures.make_component("le", 10)
	var lone_enemy := TestFixtures.make_mech("lone_enemy", 8, [lone_enemy_comp])
	var cm4 := CombatManager.new(p4["mech"], [lone_enemy], 4)
	cm4.start_combat()
	cm4.play_attack_card(p4["card"], lone_enemy, lone_enemy_comp)
	t.assert_eq(cm4.result, CombatManager.Result.WIN, "destroying the only enemy component wins immediately")
	t.assert_eq(cm4.phase, CombatManager.Phase.GAME_OVER, "phase is GAME_OVER")
	var post_game := cm4.play_attack_card(p4["card"], lone_enemy, lone_enemy_comp)
	t.assert_true(not post_game["ok"] and post_game["reason"] == "not_player_turn", "no more plays accepted after the game ends")

	t.group("CombatManager: lose — overheat backlash finishes off an already-weakened mech")
	# 15% of max HP can never fully destroy a mech that's still at full health in one
	# hit (0.15*H < H for any H>0) — so this scenario starts the component already
	# down to 1 HP, which floor(15% of its 20 max) = 3 backlash easily finishes.
	var lethal_card := TestFixtures.make_card("lethal_self", "fc", 50, 0, 0, 0)
	var frail_comp := TestFixtures.make_component("fc", 20, [lethal_card])
	frail_comp.current_hp = 1
	var frail_mech := TestFixtures.make_mech("frail", 1, [frail_comp]) # max_heat 1 -> a 50-cost card overheats hugely
	var e5_comp := TestFixtures.make_component("e5c", 40)
	var e5 := TestFixtures.make_mech("enemy5", 8, [e5_comp])
	var cm5 := CombatManager.new(frail_mech, [e5], 5)
	cm5.start_combat()
	cm5.play_self_card(lethal_card)
	t.assert_eq(cm5.result, CombatManager.Result.LOSE, "the player mech was fully destroyed by its own overheat backlash")
	t.assert_eq(cm5.phase, CombatManager.Phase.GAME_OVER, "phase is GAME_OVER")

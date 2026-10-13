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
	p2["mech"].current_heat = 10 # HeatRules: 10 -> 5 (80% at max)
	p2["mech"].add_mech_status("absorb", 5)
	cm2.end_player_turn()
	t.assert_eq(p2["mech"].current_heat, 5, "player heat vented once via the ratio formula (10 -> 5)")
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

	t.group("CombatManager: stepping the enemy turn (UI pacing) matches resolving it all at once")
	var snapshots: Array = []
	for auto in [true, false]:
		var sp := DataLoader.load_mech_from_file("res://tests/fixtures/bastion_classic.json")
		var sw: Array[MechData] = []
		for i in range(3):
			sw.append(DataLoader.load_mech_from_file("res://tests/fixtures/scrap_warden_classic.json"))
		var scm := CombatManager.new(sp, sw, 77)
		scm.auto_resolve_enemy_turn = auto
		var started := [0]
		scm.enemy_turn_started.connect(func(): started[0] += 1)
		scm.start_combat()
		var rounds := 0
		for round_i in range(3):
			if scm.is_game_over():
				break # an idle Bastion can go down before round 3
			rounds += 1
			scm.end_player_turn()
			if not auto:
				t.assert_eq(scm.phase, CombatManager.Phase.ENEMY_TURN, "manual mode waits in ENEMY_TURN after end_player_turn (round %d)" % round_i)
				while true:
					var action := scm.next_enemy_action()
					if action.is_empty():
						break
					scm.execute_enemy_action(action)
				scm.finish_enemy_turn()
		var snap := {"turn": scm.turn_number, "phase": scm.phase, "started": started[0], "rounds": rounds, "player_hp": [], "warden_heat": []}
		for c in sp.components:
			snap["player_hp"].append(c.current_hp)
		for w in sw:
			snap["warden_heat"].append(w.current_heat)
		snapshots.append(snap)
	t.assert_eq(snapshots[1]["player_hp"], snapshots[0]["player_hp"], "same player component HP after 3 enemy turns")
	t.assert_eq(snapshots[1]["warden_heat"], snapshots[0]["warden_heat"], "same Warden heat after 3 enemy turns")
	t.assert_eq(snapshots[1]["turn"], snapshots[0]["turn"], "same turn number")
	t.assert_eq(snapshots[1]["phase"], snapshots[0]["phase"], "same phase")
	t.assert_eq(snapshots[0]["started"], snapshots[0]["rounds"], "enemy_turn_started fired once per enemy turn")
	t.assert_true(snapshots[0]["player_hp"] != [18, 64, 54, 26], "sanity: the Wardens actually dealt damage")

	t.group("CombatManager: enemies plan their cards when the player's turn starts, then play exactly that plan")
	var ip := DataLoader.load_mech_from_file("res://tests/fixtures/bastion_classic.json")
	var iw: Array[MechData] = [DataLoader.load_mech_from_file("res://tests/fixtures/scrap_warden_classic.json")]
	var icm := CombatManager.new(ip, iw, 11)
	icm.auto_resolve_enemy_turn = false
	icm.start_combat()
	var planned: Array = icm.enemy_plans[iw[0]]
	t.assert_eq(planned.size(), 1, "a fresh Warden plans one card for its one armed component (Scatter Shot)")
	t.assert_eq(icm.upcoming_enemy_actions(iw[0]).size(), 1, "it shows as upcoming intent during the player's turn")
	var planned_ids := planned.map(func(s): return s["card"].id)
	icm.end_player_turn()
	var played_ids := []
	while true:
		var ia := icm.next_enemy_action()
		if ia.is_empty():
			break
		var up := icm.upcoming_enemy_actions(iw[0])
		t.assert_true(up.size() > 0 and up[0]["active"], "the resolving step shows as the active intent")
		played_ids.append(ia["card"].id)
		icm.execute_enemy_action(ia)
	t.assert_eq(played_ids, planned_ids, "the enemy turn played exactly the planned cards, in order")
	t.assert_eq(icm.upcoming_enemy_actions(iw[0]).size(), 0, "no intent left once every step has resolved")
	icm.finish_enemy_turn()
	t.assert_eq(icm.enemy_plans[iw[0]].size() > 0, true, "a new plan is made for the next turn")

	t.group("CombatManager: a planned step is dropped if its component is destroyed first")
	# Synthetic enemy with two armed hardpoints (the real Warden has one).
	var dp := DataLoader.load_mech_from_file("res://tests/fixtures/bastion_classic.json")
	var gun_a := TestFixtures.make_component("gun_a", 30, [TestFixtures.make_card("shot_a", "gun_a", 1, 1, 5, 5)])
	gun_a.placed_cells = [Vector2i(0, 0)]
	var gun_b := TestFixtures.make_component("gun_b", 30, [TestFixtures.make_card("shot_b", "gun_b", 1, 1, 5, 5)])
	gun_b.placed_cells = [Vector2i(0, 1)]
	var dw: Array[MechData] = [TestFixtures.make_mech("two_guns", 6, [gun_a, gun_b])]
	var dcm := CombatManager.new(dp, dw, 12)
	dcm.start_combat()
	t.assert_eq(dcm.upcoming_enemy_actions(dw[0]).size(), 2, "both guns plan a shot")
	gun_b.apply_damage(999)
	t.assert_eq(dcm.upcoming_enemy_actions(dw[0]).size(), 1, "the destroyed gun's intent disappears")
	var dp_hp := dp.current_hp()
	dcm.end_player_turn()
	t.assert_eq(dp_hp - dp.current_hp(), 5, "only the surviving gun fired")

	t.group("CardData: intent kinds")
	var ic := CardData.new()
	ic.hits = 2; ic.damage_min = 4; ic.damage_max = 6
	t.assert_eq(ic.intent(), CardData.INTENT_ATTACK, "2×4–6 (avg 10) is an attack; Blast 'Em (avg 16) is too")
	ic.hits = 6; ic.damage_min = 2; ic.damage_max = 6
	t.assert_eq(ic.intent(), CardData.INTENT_HEAVY_ATTACK, "6×2–6 (Empty Clip, avg 24) is a heavy attack")
	ic.hits = 0
	var block_s := StatusEffectData.new()
	block_s.status = "deflect"; block_s.stacks = 1; block_s.target = StatusEffectData.TARGET_OWN_MECH
	ic.statuses = [block_s]
	t.assert_eq(ic.intent(), CardData.INTENT_BLOCK, "Deflect on itself is a block")
	var debuff := StatusEffectData.new()
	debuff.status = "shock"; debuff.stacks = 2; debuff.target = StatusEffectData.TARGET_ENEMY
	ic.statuses = [debuff]
	t.assert_eq(ic.intent(), CardData.INTENT_STATUS, "Shock on the target without a hit is a status")

	t.group("MechData: a mech is destroyed once all its hardpoints are")
	var hb := DataLoader.load_mech_from_file("res://tests/fixtures/bastion_classic.json")
	hb.get_component("neon_axe").apply_damage(999)
	t.assert_true(not hb.is_defeated(), "Bastion still stands with Voltage Spike (a hardpoint) alive")
	hb.get_component("voltage_spike").apply_damage(999)
	t.assert_true(hb.is_defeated(), "Bastion is destroyed with both hardpoints gone, though its reactor and protocol live")
	var hw := DataLoader.load_mech_from_file("res://tests/fixtures/scrap_warden_classic.json")
	hw.get_component("scatter_shot").apply_damage(999)
	t.assert_true(hw.is_defeated(), "a Warden is destroyed once Scatter Shot (its only hardpoint) is gone; its reactors don't keep it alive")
	var reactor_only := TestFixtures.make_component("r", 10)
	reactor_only.category = ComponentData.CATEGORY_REACTOR
	var no_hp_mech := TestFixtures.make_mech("no_hardpoints", 8, [reactor_only])
	t.assert_true(not no_hp_mech.is_defeated(), "a mech with no hardpoints still needs every part destroyed")

	t.group("CombatManager: destroying an enemy's last hardpoint wins, even with its reactor alive")
	var wp := DataLoader.load_mech_from_file("res://tests/fixtures/bastion_classic.json")
	var ww: Array[MechData] = [DataLoader.load_mech_from_file("res://tests/fixtures/scrap_warden_classic.json")]
	var wcm := CombatManager.new(wp, ww, 13)
	wcm.start_combat()
	ww[0].get_component("redirect_spike").apply_damage(999) # otherwise it takes the hit
	var cannon_w := ww[0].get_component("scatter_shot")
	cannon_w.current_hp = 1
	wcm.play_attack_card(wp.get_component("neon_axe").cards[0], ww[0], cannon_w)
	t.assert_eq(wcm.result, CombatManager.Result.WIN, "win as soon as Scatter Shot (its last hardpoint) falls")
	t.assert_true(not ww[0].get_component("capacitor_bank").destroyed, "the Capacitor Bank was never touched")

	t.group("CombatManager: attacks step hit by hit and match the all-at-once result")
	var totals := []
	for stepped in [false, true]:
		var sp2 := DataLoader.load_mech_from_file("res://tests/fixtures/bastion_classic.json")
		var sw2: Array[MechData] = [DataLoader.load_mech_from_file("res://tests/fixtures/scrap_warden_classic.json")]
		var scm2 := CombatManager.new(sp2, sw2, 21)
		scm2.start_combat()
		var swing: CardData = sp2.get_component("neon_axe").cards[0] # Wide Swing, 3 hits
		var armor := sw2[0].get_component("redirect_spike") # aim at the Spike itself: nothing to redirect
		armor.max_hp = 100 # sturdy enough to take all three hits
		armor.current_hp = 100
		if not stepped:
			totals.append(scm2.play_attack_card(swing, sw2[0], armor)["result"]["total_damage"])
			continue
		var landed := []
		scm2.hit_landed.connect(func(_m, _c, d): landed.append(d))
		t.assert_true(scm2.begin_attack(swing, sw2[0], armor)["ok"], "begin_attack accepts the play")
		t.assert_true(not scm2.is_player_turn(), "no other card can be played while the hits resolve")
		scm2.end_player_turn()
		t.assert_eq(scm2.phase, CombatManager.Phase.PLAYER_TURN, "End Turn is ignored mid-attack")
		var steps := 0
		while not scm2.next_hit().is_empty():
			steps += 1
		t.assert_eq(steps, 3, "Wide Swing resolves as 3 separate hits")
		t.assert_eq(landed.size(), 3, "hit_landed fires once per hit")
		var fin := scm2.finish_attack()
		t.assert_eq(fin["result"]["total_damage"], landed.reduce(func(a, b): return a + b, 0), "the total is the sum of the hits")
		totals.append(fin["result"]["total_damage"])
		t.assert_true(scm2.is_player_turn(), "back to the player once the attack finishes")
	t.assert_eq(totals[1], totals[0], "stepped and all-at-once attacks deal the same damage (same seed)")

	t.group("CombatManager: hits after the target is destroyed are skipped, not stepped")
	var kp := DataLoader.load_mech_from_file("res://tests/fixtures/bastion_classic.json")
	var kw: Array[MechData] = [DataLoader.load_mech_from_file("res://tests/fixtures/scrap_warden_classic.json")]
	var kcm := CombatManager.new(kp, kw, 22)
	kcm.start_combat()
	var frail_t := kw[0].get_component("redirect_spike")
	frail_t.current_hp = 1
	kcm.begin_attack(kp.get_component("neon_axe").cards[0], kw[0], frail_t)
	var ksteps := 0
	while not kcm.next_hit().is_empty():
		ksteps += 1
	t.assert_eq(ksteps, 1, "a 1 HP target dies on the first of 3 hits; the other 2 aren't played out")
	kcm.finish_attack()

	t.group("Redirect Spike: damage aimed at any other part lands on it while it stands")
	var cvp := DataLoader.load_mech_from_file("res://tests/fixtures/bastion_classic.json")
	var cvw: Array[MechData] = [DataLoader.load_mech_from_file("res://tests/fixtures/scrap_warden_classic.json")]
	var cvcm := CombatManager.new(cvp, cvw, 31)
	cvcm.start_combat()
	var cv_spike := cvw[0].get_component("redirect_spike")
	var cv_cannon := cvw[0].get_component("scatter_shot")
	for id in ["scatter_shot", "capacitor_bank"]:
		t.assert_eq(cvw[0].cover_for(cvw[0].get_component(id)), cv_spike, "hits on %s are redirected to the Redirect Spike" % id)
	t.assert_eq(cvw[0].cover_for(cv_spike), null, "the Spike doesn't redirect hits aimed at itself")
	cvcm.play_attack_card(cvp.get_component("voltage_spike").cards[0], cvw[0], cv_cannon) # Spike 'Em, 1 hit
	t.assert_true(cv_spike.current_hp < cv_spike.max_hp, "the hit aimed at Scatter Shot landed on the Redirect Spike")
	t.assert_eq(cv_cannon.current_hp, cv_cannon.max_hp, "Scatter Shot took nothing")
	t.assert_true(cv_cannon.status_stacks("shock") > 0, "the card's Shock still goes on the part you aimed at")
	cv_spike.apply_damage(999)
	t.assert_eq(cvw[0].cover_for(cv_cannon), null, "a destroyed Redirect Spike redirects nothing")

	t.group("Redirect Spike: a multi-hit card breaks through once the Spike is destroyed")
	var bp := DataLoader.load_mech_from_file("res://tests/fixtures/bastion_classic.json")
	var bw: Array[MechData] = [DataLoader.load_mech_from_file("res://tests/fixtures/scrap_warden_classic.json")]
	var bcm := CombatManager.new(bp, bw, 32)
	bcm.start_combat()
	bw[0].get_component("redirect_spike").current_hp = 1
	var hit_parts := []
	bcm.hit_landed.connect(func(_m, c, _d): hit_parts.append(c.id))
	bcm.play_attack_card(bp.get_component("neon_axe").cards[0], bw[0], bw[0].get_component("scatter_shot")) # 3 hits
	t.assert_eq(hit_parts[0], "redirect_spike", "hit 1 lands on (and breaks) the 1 HP Redirect Spike")
	t.assert_eq(hit_parts.slice(1), ["scatter_shot", "scatter_shot"], "hits 2 and 3 reach Scatter Shot")

	t.group("Capacitor Bank: Absorb 10 on its own mech at the start of that mech's turn")
	var cbp := DataLoader.load_mech_from_file("res://tests/fixtures/bastion_classic.json")
	var cbw: Array[MechData] = [DataLoader.load_mech_from_file("res://tests/fixtures/scrap_warden_classic.json")]
	var cbcm := CombatManager.new(cbp, cbw, 33)
	cbcm.start_combat()
	t.assert_eq(cbw[0].mech_status_stacks("absorb"), 0, "no Absorb yet: the Warden's first turn hasn't started")
	cbcm.end_player_turn() # the Wardens' turn start (step 4) fires it; it lasts into the player's turn
	t.assert_eq(cbw[0].mech_status_stacks("absorb"), 10, "Absorb 10 is up for the player's next turn")
	cbw[0].get_component("capacitor_bank").apply_damage(999)
	cbcm.end_player_turn()
	t.assert_eq(cbw[0].mech_status_stacks("absorb"), 0, "a destroyed Capacitor Bank adds nothing")

	t.group("Insulated Core: incoming Acid/Shock stacks on its mech are cut by 1")
	var icp := DataLoader.load_mech_from_file("res://tests/fixtures/bastion_classic.json")
	var icw := DataLoader.load_mech_from_file("res://tests/fixtures/scrap_warden_classic.json")
	var ic_axe := icp.get_component("neon_axe")
	var ic_src := icw.get_component("scatter_shot")
	var shock2 := StatusEffectData.new("shock", 2, StatusEffectData.TARGET_ENEMY)
	var ic_by := CardResolver.apply_card_status(shock2, icw, ic_src, icp, ic_axe)
	t.assert_eq(ic_axe.status_stacks("shock"), 1, "Shock 2 aimed at the Bastion lands as Shock 1")
	t.assert_eq(ic_by, icp.get_component("insulated_core"), "the resolver reports Insulated Core as the cause")
	CardResolver.apply_card_status(StatusEffectData.new("shock", 1, StatusEffectData.TARGET_ENEMY), icw, ic_src, icp, ic_axe)
	t.assert_eq(ic_axe.status_stacks("shock"), 1, "Shock 1 is cut to nothing")
	CardResolver.apply_card_status(StatusEffectData.new("disabled", 1, StatusEffectData.TARGET_ENEMY), icw, ic_src, icp, ic_axe)
	t.assert_eq(ic_axe.status_stacks("disabled"), 1, "other statuses go through untouched")
	icp.get_component("insulated_core").apply_damage(999)
	CardResolver.apply_card_status(shock2, icw, ic_src, icp, ic_axe)
	t.assert_eq(ic_axe.status_stacks("shock"), 3, "a destroyed Insulated Core stops reducing (1 + 2)")
	var ic_cm := CombatManager.new(DataLoader.load_mech_from_file("res://tests/fixtures/bastion_classic.json"), [DataLoader.load_mech_from_file("res://tests/fixtures/scrap_warden_classic.json")] as Array[MechData], 34)
	ic_cm.start_combat()
	var w_target := ic_cm.enemies[0].get_component("redirect_spike")
	ic_cm.play_attack_card(ic_cm.player_mech.get_component("voltage_spike").cards[0], ic_cm.enemies[0], w_target) # Spike 'Em: Shock 2
	t.assert_eq(w_target.status_stacks("shock"), 2, "the Warden has no Insulated Core: Spike 'Em's Shock 2 lands in full")

	t.group("passive_triggered: fires when a passive does something")
	var ptp := DataLoader.load_mech_from_file("res://tests/fixtures/bastion_classic.json")
	var ptw: Array[MechData] = [DataLoader.load_mech_from_file("res://tests/fixtures/scrap_warden_classic.json")]
	var ptcm := CombatManager.new(ptp, ptw, 35)
	var fired := []
	ptcm.passive_triggered.connect(func(_m, c): fired.append(c.id))
	ptcm.start_combat()
	t.assert_eq(fired, [], "nothing fires at combat start (the Bastion has no turn-start passive)")
	ptcm.play_attack_card(ptp.get_component("voltage_spike").cards[0], ptw[0], ptw[0].get_component("scatter_shot"))
	t.assert_eq(fired, ["redirect_spike"], "a hit pulled onto the Redirect Spike fires it")
	fired.clear()
	ptcm.play_attack_card(ptp.get_component("voltage_spike").cards[0], ptw[0], ptw[0].get_component("redirect_spike"))
	t.assert_eq(fired, [], "a hit aimed at the Spike itself doesn't")
	ptcm.end_player_turn()
	t.assert_true(fired.has("capacitor_bank"), "Capacitor Bank fires at the Warden's turn start")

	t.group("HP threshold: a Warden is destroyed at 40% of max HP, whatever part the damage hit")
	var tw := DataLoader.load_mech_from_file("res://tests/fixtures/scrap_warden_classic.json")
	t.assert_eq(tw.defeat_hp_threshold(), 40, "Warden: floor(102 x 0.4) = 40")
	tw.get_component("redirect_spike").apply_damage(32)
	tw.get_component("capacitor_bank").apply_damage(24)
	t.assert_true(not tw.is_defeated(), "both reactors gone (48 HP left) isn't enough")
	tw.get_component("scatter_shot").apply_damage(6)
	t.assert_true(tw.is_defeated(), "40 HP left: destroyed, though Scatter Shot still stands")

	_audit_fixes(t)

## Bugs found in the 2026-09-28 audit, each played through the real flow.
static func _audit_fixes(t: TestContext) -> void:
	t.group("Salvo: killing the last enemy with guns still to fire wins at once")
	var sp := TestEffects._mech([["fire_control_relay", Vector2i(0, 2)]])
	sp.components.append(TestEffects._gun("left", 999, 1, 1, Vector2i(0, 0)))
	sp.components.append(TestEffects._gun("right", 999, 1, 1, Vector2i(0, 5)))
	var se := TestEffects._dummy(10)
	var scm := TestEffects._cm(sp, [se] as Array[MechData])
	var broken := []
	scm.component_destroyed.connect(func(_m, c): broken.append(c.id))
	scm.play_attack_card(TestEffects._card(sp, "fire_control_relay", "salvo"), se, se.components[0])
	t.assert_eq(scm.result, CombatManager.Result.WIN, "the first gun's kill wins, though the second gun had no target left")
	t.assert_eq(broken, ["tank"], "and the kill is announced once")

	t.group("Side targets: a part an arc destroys is announced")
	var ap := TestEffects._mech([["arc_thrower", Vector2i(0, 0)]])
	var ta := TestFixtures.make_component("a", 100)
	var tb := TestFixtures.make_component("b", 1)
	tb.placed_cells = [Vector2i(0, 1)]
	var ae := TestFixtures.make_mech("e", 20, [ta, tb] as Array[ComponentData])
	var acm := TestEffects._cm(ap, [ae] as Array[MechData])
	var arced := []
	acm.component_destroyed.connect(func(_m, c): arced.append(c.id))
	acm.play_attack_card(TestEffects._card(ap, "arc_thrower", "arc"), ae, ta)
	t.assert_eq(arced, ["b"], "the 1 HP neighbour the Arc broke is announced (it plays its burst and log line)")

	t.group("Boss phase: falling to half HP from its own overheat still changes tactics")
	var core := TestFixtures.make_component("core", 100)
	core.current_hp = 52 # overheat backlash takes 15: down to 37 of 100
	var boss := TestFixtures.make_mech("boss", 8, [core] as Array[ComponentData])
	boss.ai = {"phase2": {"targets": "weakest"}}
	var bcm := TestEffects._cm(TestEffects._dummy(), [boss] as Array[MechData])
	var changed := [0]
	bcm.boss_phase_changed.connect(func(_m): changed[0] += 1)
	boss.current_heat = 30
	bcm.end_player_turn()
	t.assert_eq(changed[0], 1, "the phase change fires on the backlash")

	_single_use(t)

	t.group("Hangar loadouts: stale parts are dropped, and a loadout without a hardpoint falls back")
	var gd = load("res://scripts/data/GameData.gd").new()
	var default_ids := (gd.player_mech("bastion") as MechData).components.map(func(c): return c.id)
	var no_weapon: MechData = gd.player_mech("bastion", [{"id": "no_such_part", "offset": [0, 0], "rotation": 0}])
	t.assert_eq(no_weapon.components.map(func(c): return c.id), default_ids, "a loadout of only a removed part gives the default loadout")
	var stale: MechData = gd.player_mech("bastion", [{"id": "voltage_spike", "offset": [2, 1], "rotation": 2}, {"id": "no_such_part", "offset": [3, 0], "rotation": 0}])
	t.assert_eq(stale.components.map(func(c): return c.id), ["voltage_spike"], "a removed part is left out, the rest kept")
	var off_frame: MechData = gd.player_mech("bastion", [{"id": "voltage_spike", "offset": [2, 1], "rotation": 2}, {"id": "grinder_maw", "offset": [9, 9], "rotation": 0}])
	t.assert_eq(off_frame.components.map(func(c): return c.id), ["voltage_spike"], "a part that no longer fits the chassis is left out")
	var salvaged: MechData = gd.player_mech("bastion", [{"id": "voltage_spike", "offset": [2, 1], "rotation": 2}, {"id": "neon_axe", "offset": [0, 2], "rotation": 1}])
	t.assert_eq(salvaged.components.map(func(c): return c.id), ["voltage_spike"], "a non-Surplus part saved before the Hangar went Surplus-only is left out")
	gd.free()

## Single-use cards (Decided, Logan 2026-09-30: once per turn, back next
## turn) and the Vent action.
static func _single_use(t: TestContext) -> void:
	t.group("Single-use: a card plays once a turn, and is back next turn")
	var p := _build_player(1, 1, 5, 5)
	var ec := TestFixtures.make_component("ec", 500)
	var e := TestFixtures.make_mech("e", 8, [ec] as Array[ComponentData])
	var cm := CombatManager.new(p["mech"], [e] as Array[MechData], 1)
	cm.start_combat()
	t.assert_eq(cm.cards_left(p["mech"]), 1, "one card to play")
	t.assert_true(cm.play_attack_card(p["card"], e, ec)["ok"], "first play works")
	t.assert_true(cm.is_spent(p["card"]) and not cm.can_play(p["card"]), "then it's spent")
	t.assert_eq(cm.play_attack_card(p["card"], e, ec).get("reason", ""), "spent", "a second play this turn is refused")
	t.assert_eq(cm.hand_cards().size(), 0, "it's out of the playable hand")
	t.assert_eq(cm.hand_cards(true).size(), 1, "but still shown (greyed) with include_spent")
	t.assert_true(cm.out_of_cards(p["mech"]), "out of cards this turn")
	cm.end_player_turn()
	t.assert_true(cm.can_play(p["card"]), "back next turn")

	t.group("Single-use: self cards and protocols are spent too")
	var self_card := TestFixtures.make_card("buff", "sc", 1, 0, 0, 0)
	var sc := TestFixtures.make_component("sc", 50, [self_card] as Array[CardData])
	var pm := TestFixtures.make_mech("p", 14, [sc] as Array[ComponentData])
	var cm3 := CombatManager.new(pm, [TestFixtures.make_mech("e3", 8, [TestFixtures.make_component("x", 50)] as Array[ComponentData])] as Array[MechData], 3)
	cm3.start_combat()
	t.assert_true(cm3.play_self_card(self_card)["ok"], "self card plays")
	t.assert_eq(cm3.play_self_card(self_card).get("reason", ""), "spent", "and not twice")

	t.group("Single-use: enemies spend their cards too, and vent when they can't play")
	var ecard := TestFixtures.make_card("zap", "ew", 3, 1, 3, 3)
	var ew := TestFixtures.make_component("ew", 60, [ecard] as Array[CardData])
	var en := TestFixtures.make_mech("en", 10, [ew] as Array[ComponentData])
	var pp := _build_player(0, 0, 0, 0)
	var cm4 := CombatManager.new(pp["mech"], [en] as Array[MechData], 4)
	cm4.start_combat()
	t.assert_eq((cm4.enemy_plans[en] as Array).size(), 1, "turn 1: it plans its one card")
	var spent_seen := [false]
	cm4.enemy_action.connect(func(_e): spent_seen[0] = cm4.is_spent(ecard))
	cm4.end_player_turn()
	t.assert_true(spent_seen[0], "the enemy's card is spent once it fires")
	t.assert_eq((cm4.enemy_plans[en] as Array).size(), 1, "and back for its next turn")
	var hot := TestFixtures.make_mech("hot", 10, [TestFixtures.make_component("hw", 60, [TestFixtures.make_card("big", "hw", 11, 1, 3, 3)] as Array[CardData])] as Array[ComponentData])
	var cm5b := CombatManager.new(_build_player(0, 0, 0, 0)["mech"], [hot] as Array[MechData], 8)
	cm5b.start_combat()
	t.assert_eq((cm5b.enemy_plans[hot] as Array).size(), 0, "an enemy that can't afford its card plans nothing")
	t.assert_true(not cm5b.enemy_venting(hot), "and at 0 heat it just idles")
	hot.current_heat = 5
	cm5b.end_player_turn()
	t.assert_true(cm5b.enemy_venting(hot), "with heat and nothing to play, it vents")
	en = hot
	cm4 = cm5b
	var vents := [0]
	cm4.mech_vented.connect(func(_m, _a): vents[0] += 1)
	en.current_heat = 5
	cm4.end_player_turn()
	t.assert_eq(en.current_heat, 1, "Vent: 80% of 5 = 4 vented (the ratio would vent 2)")
	t.assert_eq(vents[0], 1, "mech_vented fired")

	t.group("Vent action: only before a card, ends the turn, vents the flat share")
	var pv := _build_player(2, 1, 1, 1)
	var ev := TestFixtures.make_mech("ev", 8, [TestFixtures.make_component("evc", 500)] as Array[ComponentData])
	var cm5 := CombatManager.new(pv["mech"], [ev] as Array[MechData], 5)
	cm5.start_combat()
	t.assert_true(not cm5.can_vent(), "no heat: nothing to vent")
	pv["mech"].current_heat = 7
	t.assert_true(cm5.can_vent(), "with heat and no card played: can vent")
	t.assert_true(cm5.vent_action(), "vents")
	t.assert_eq(pv["mech"].current_heat, 2, "7 - floor(7 × 0.8) = 2 (the ratio alone would leave 5)")
	t.assert_eq(cm5.turn_number, 2, "and the turn ended")
	cm5.play_attack_card(pv["card"], ev, ev.components[0])
	t.assert_true(not cm5.can_vent(), "after playing a card this turn: no Vent")

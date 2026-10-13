class_name TestCommands
extends RefCounted
## Command-driven combat (CombatManager.apply): a fight driven by commands
## replays exactly from its log on a fresh fight with the same seed, paced
## and unpaced plays resolve the same, and rejected commands aren't logged.

static func run_all(t: TestContext) -> void:
	_replays_exactly(t)
	_paced_matches_unpaced(t)
	_rejected_not_logged(t)
	_overheat_predictions(t)
	_damage_preview(t)
	_fight_record(t)

static func _mech(id: String) -> MechData:
	return DataLoader.load_mech_from_file("res://data/mechs/%s.json" % id)

static func _fight(player: String, foes: Array, seed_value: int) -> CombatManager:
	var ws: Array[MechData] = []
	for id in foes:
		ws.append(_mech(id))
	var cm := CombatManager.new(_mech(player), ws, seed_value)
	cm.start_combat()
	return cm

## Heat, statuses and HP of every part, the result, and the RNG state.
static func _snapshot(cm: CombatManager) -> String:
	var out := PackedStringArray(["r%d t%d rng %s" % [cm.result, cm.turn_number, cm.rng.state]])
	for i in range(cm.enemies.size() + 1):
		var m := cm.mech_at(i)
		out.append("%s h%d %s" % [m.id, m.current_heat, ",".join(m.mech_statuses.map(func(s): return "%s%d" % [s.status, s.stacks]))])
		for c in m.components:
			out.append("%s:%d%s%s" % [c.id, c.current_hp, "D" if c.destroyed else "", ",".join(c.statuses.map(func(s): return "%s%d" % [s.status, s.stacks]))])
	return " ".join(out)

## A plain bot: each turn plays every card it can afford (attacks at the
## first living part of the first living enemy), then ends the turn.
static func _drive(cm: CombatManager, paced: bool, turns: int = 25) -> void:
	var p := cm.player_mech
	while not cm.is_game_over() and cm.turn_number <= turns:
		for card in cm.hand_cards():
			if not cm.is_player_turn():
				break
			if not cm.can_play(card) or p.current_heat + cm.effective_cost(card) > p.heat_capacity():
				continue
			var cmd := cm.play_command(card)
			if card.is_attack():
				var foes := cm.living_enemies()
				if foes.is_empty() or foes[0].non_destroyed_components().is_empty():
					break
				cmd = cm.play_command(card, foes[0], foes[0].non_destroyed_components()[0])
			if card.protocol() == "reroute":
				cmd["options"] = {"status": "acid"}
			if paced:
				cmd["paced"] = true
			var r := cm.apply(cmd)
			if paced and r.get("ok", false) and cm.has_pending_attack():
				while not cm.next_hit().is_empty():
					pass
				cm.finish_attack()
		if not cm.is_game_over() and cm.is_player_turn():
			cm.apply({"type": "end_turn"})

static func _replays_exactly(t: TestContext) -> void:
	t.group("commands: replay")
	for setup in [["bastion", ["caustic_engine", "needle_drone"], 3], ["redline", ["rivet_brute", "scrap_warden"], 7],
			["jackal", ["cipher"], 11], ["bastion", ["anchor"], 5]]:
		var live := _fight(setup[0], setup[1], setup[2])
		_drive(live, false)
		t.assert_true(live.command_log.size() > 3, "%s: the fight logged its commands" % setup[0])
		var again := _fight(setup[0], setup[1], setup[2])
		again.replay(live.command_log)
		t.assert_eq(_snapshot(again), _snapshot(live), "%s vs %s: the log replays the same fight" % [setup[0], ", ".join(setup[1])])
		t.assert_eq(again.command_log, live.command_log, "%s: the replay logs the same commands" % setup[0])

static func _paced_matches_unpaced(t: TestContext) -> void:
	t.group("commands: paced")
	var a := _fight("bastion", ["scrap_warden", "needle_drone"], 21)
	_drive(a, false)
	var b := _fight("bastion", ["scrap_warden", "needle_drone"], 21)
	_drive(b, true)
	t.assert_eq(_snapshot(b), _snapshot(a), "stepping hits one at a time resolves the same")
	t.assert_true(b.command_log.all(func(c): return not c.has("paced")), "the log leaves out pacing")

static func _rejected_not_logged(t: TestContext) -> void:
	t.group("commands: rejected")
	var cm := _fight("bastion", ["scrap_warden"], 2)
	t.assert_eq(cm.apply({"type": "fly"})["ok"], false, "an unknown command is refused")
	t.assert_eq(cm.apply({"type": "play", "card": "nope/nope"})["ok"], false, "an unknown card is refused")
	var attack: CardData = null
	for c in cm.hand_cards():
		if c.is_attack():
			attack = c
			break
	t.assert_eq(cm.apply(cm.play_command(attack))["ok"], false, "an attack without a target is refused")
	t.assert_eq(cm.command_log.size(), 0, "refused commands aren't logged")
	cm.apply({"type": "end_turn"})
	t.assert_eq(cm.command_log, [{"type": "end_turn"}], "an accepted command is logged")

static func _overheat_predictions(t: TestContext) -> void:
	t.group("commands: overheat warnings")
	var cm := _fight("bastion", ["scrap_warden"], 4)
	var p := cm.player_mech
	var costly: CardData = null
	var free: CardData = null
	for c in cm.hand_cards():
		if cm.effective_cost(c) >= 2 and costly == null:
			costly = c
		if cm.effective_cost(c) == 0 and free == null:
			free = c
	p.current_heat = p.heat_capacity() - 1
	t.assert_true(cm.would_overheat(costly), "a card that takes live heat over max overheats")
	if free != null:
		t.assert_true(not cm.would_overheat(free), "a free card doesn't")
	t.assert_true(not cm.overheat_could_kill(), "a healthy mech survives the backlash")
	for c in p.components:
		if c.category == ComponentData.CATEGORY_HARDPOINT:
			c.current_hp = 1
	t.assert_true(cm.overheat_could_kill(), "hardpoints at 1 HP could all fall to the backlash")
	t.assert_true(not cm.end_turn_overheats(), "a live checker doesn't overheat on End Turn")
	var rl := _fight("redline", ["scrap_warden"], 4)
	rl.player_mech.current_heat = rl.player_mech.heat_capacity() + 2
	t.assert_true(rl.end_turn_overheats(), "an end-of-turn checker over max overheats on End Turn")
	t.assert_true(not rl.would_overheat(rl.hand_cards()[0]), "…but not when it plays a card")

## The targeting preview brackets what the attack really deals, and
## previewing uses nothing up (a primed Lock On stays primed).
static func _damage_preview(t: TestContext) -> void:
	t.group("Damage preview: brackets the real damage, with no side effects")
	var inside := true
	var lock_kept := true
	var lock_inside := true
	for sd in range(1, 25):
		var cm := _fight("jackal", ["scrap_warden"], sd)
		var foe: MechData = cm.enemies[0]
		var target: ComponentData = foe.non_destroyed_components()[0]
		var card: CardData = cm.player_mech.get_component("fang_blade").cards[1] # Jab Jab Jab!: 4 hits
		var p := cm.preview_attack(card, foe, target)
		var part: ComponentData = p["part"]
		var before := part.current_hp
		cm.play_attack_card(card, foe, target)
		var dealt := before - part.current_hp
		inside = inside and (dealt >= mini(p["lo"], before) and dealt <= p["hi"])
		var cm2 := _fight("jackal", ["scrap_warden"], sd)
		var foe2: MechData = cm2.enemies[0]
		var t2: ComponentData = foe2.non_destroyed_components()[0]
		cm2.primed.append({"type": "lock_on", "card": ComponentLibrary.make("targeting_computer").cards[0], "component": cm2.player_mech.components[0]})
		var embed: CardData = cm2.player_mech.get_component("fang_blade").cards[0]
		var p2 := cm2.preview_attack(embed, foe2, t2)
		lock_kept = lock_kept and cm2.primed.size() == 1
		var part2: ComponentData = p2["part"]
		var b2 := part2.current_hp
		cm2.play_attack_card(embed, foe2, t2)
		var d2 := b2 - part2.current_hp
		lock_inside = lock_inside and d2 >= mini(p2["lo"], b2) and d2 <= p2["hi"]
	t.assert_true(inside, "a 4-hit attack lands within the preview's range (24 seeds)")
	t.assert_true(lock_kept, "previewing doesn't use up a primed Lock On")
	t.assert_true(lock_inside, "…and with Lock On primed the hit lands within the previewed range")

## FightRecord: a fight recorded from a worn mech (damage, a lost part,
## statuses, heat, a changed frame and max heat), saved as JSON and played
## back headless, ends exactly as it did.
static func _fight_record(t: TestContext) -> void:
	t.group("commands: fight records")
	for setup in [["bastion", ["caustic_engine", "needle_drone"], 3], ["redline", ["rivet_brute", "scrap_warden"], 7]]:
		var player := _mech(setup[0])
		var foes: Array[MechData] = []
		for id in setup[1]:
			foes.append(_mech(id))
		player.components[0].current_hp = maxi(1, player.components[0].current_hp / 2)
		player.components[-1].destroyed = true
		player.components[-1].current_hp = 0
		player.max_heat += 2
		player.cells.append(Vector2i(-1, 0))
		var cm := CombatManager.new(player, foes, setup[2])
		var rec := FightRecord.begin(player, foes, setup[2], ["a", "b"])
		cm.start_combat()
		player.components[1].add_status("coolant", 2) # fight-start effects go on after start_combat
		foes[0].components[0].add_status("acid", 3)
		player.current_heat = 3
		FightRecord.set_opening(rec, player, foes)
		_drive(cm, true)
		FightRecord.finish(rec, cm, FightRecord.result_name(cm.result))
		var saved = JSON.parse_string(JSON.stringify(rec))
		t.assert_true(rec["commands"].size() > 3, "%s: the record has the fight's commands" % setup[0])
		var r := FightRecord.replay(saved)
		t.assert_true(r["ok"], "%s: the saved record rebuilds its mechs" % setup[0])
		t.assert_true(r["matches"], "%s: the replay ends as recorded (%s in %d turns)" % [setup[0], rec["result"], rec["turns"]])
		t.assert_eq(_snapshot(r["combat"]), _snapshot(cm), "%s: the replay ends in exactly the same state" % setup[0])
		var back := FightRecord.mech_from_dict(saved["player"])
		t.assert_eq(back.max_heat, player.max_heat, "%s: max heat restored" % setup[0])
		t.assert_eq(back.cells.size(), player.cells.size(), "%s: frame restored" % setup[0])
	var gone := {"player": {"id": "no_such_mech"}, "enemies": [], "seed": 1}
	t.assert_true(not FightRecord.replay(gone)["ok"], "a record whose mech file is gone doesn't replay")


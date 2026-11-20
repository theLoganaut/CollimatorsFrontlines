class_name TestThreat
extends RefCounted
## Threat levels (Threat, data/threat.json, balance.json "threat"): the
## levels stack, the run carries its level, enemies get their effects,
## captured bays roll on arrival, Chips and scraps scale, and a location's
## next level unlocks when the one before is cleared.

static func _mech() -> MechData:
	return DataLoader.load_mech_from_file("res://tests/fixtures/bastion_classic.json")

static func _assault(threat: int) -> Dictionary:
	var missions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/missions.json"))["missions"]
	var m: Dictionary = missions["assault"].duplicate(true)
	m["id"] = "assault"
	return Threat.with_level(m, threat)

static func _shipyard() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/sectors.json"))["locations"][0]

## What an enemy has set up once the fight starts: charged, primed, Deflect.
static func _setup(cm: CombatManager, w: MechData) -> String:
	var deflect := 0
	for s in w.mech_statuses:
		if s.status == "deflect":
			deflect += s.stacks
	return "%s/%s/%d" % [cm.enemy_charged.has(w), cm.enemy_primed.has(w), deflect]

static func run_all(t: TestContext) -> void:
	t.group("Threat levels: 0-5, each keeping the ones below")
	t.assert_eq(Threat.max_level(), 5, "five levels past the plain mission")
	var named := true
	for n in range(0, 6):
		named = named and Threat.level_def(n).has("name")
	t.assert_true(named, "every level 0-5 has a name in threat.json")
	t.assert_eq(Threat.effects_up_to(0).size(), 0, "level 0 adds nothing")
	t.assert_eq(Threat.effects_up_to(3).size(), 3, "level 3 has the effects of levels 1, 2 and 3")
	t.assert_true(Threat.effect(1).contains("10%") and Threat.effect(5).contains("25%"), "the numbers come from balance.json")
	t.assert_true(is_equal_approx(Threat.chips_mult(2), 1.2) and is_equal_approx(Threat.chips_mult(5), 1.5), "+10% Chips a level, added")
	t.assert_eq(Threat.level(_assault(3)), 3, "the run's mission carries its level")
	t.assert_eq(Threat.level(_assault(9)), 5, "capped at the top level")
	t.assert_eq(Threat.level(Threat.with_level({"training": true}, 3)), 0, "training stays at 0")
	t.assert_eq(Threat.level(Threat.with_level({"daily": "2026-11-19"}, 3)), 0, "the Daily stays at 0")
	t.assert_true(is_equal_approx(Threat.scraps_mult(_assault(4)), 1.0) and is_equal_approx(Threat.scraps_mult(_assault(5)), 0.75), "25% fewer scraps from level 5")

	t.group("Threat: the enemies of a fight")
	var plain: Array[MechData] = [DataLoader.load_mech_from_file("res://data/mechs/dock_breaker.json"), DataLoader.load_mech_from_file("res://data/mechs/anchor.json")]
	var hard: Array[MechData] = [DataLoader.load_mech_from_file("res://data/mechs/dock_breaker.json"), DataLoader.load_mech_from_file("res://data/mechs/anchor.json")]
	Threat.apply_to_enemies(_assault(4), hard)
	var hp_ok := true
	for i in range(plain[0].components.size()):
		hp_ok = hp_ok and hard[0].components[i].max_hp == roundi(plain[0].components[i].max_hp * 1.1) and hard[0].components[i].current_hp == hard[0].components[i].max_hp
	t.assert_true(hp_ok, "Veterans: every part has 10% more HP, at full HP")
	t.assert_eq(hard[0].threat, 4, "they carry the level (chevrons on the name plate)")
	t.assert_eq(hard[0].threat_openers.size(), 1, "the elite gets one extra opener")
	t.assert_true(hard[1].phase2_reached and not plain[1].phase2_reached, "the boss is on alert: phase 2 from the start")
	var low: Array[MechData] = [DataLoader.load_mech_from_file("res://data/mechs/dock_breaker.json"), DataLoader.load_mech_from_file("res://data/mechs/anchor.json")]
	Threat.apply_to_enemies(_assault(1), low)
	t.assert_true(low[0].threat_openers.is_empty() and not low[1].phase2_reached, "level 1: Veterans only")
	var none: Array[MechData] = [DataLoader.load_mech_from_file("res://data/mechs/dock_breaker.json")]
	Threat.apply_to_enemies(_assault(0), none)
	t.assert_true(none[0].threat == 0 and none[0].components[0].max_hp == plain[0].components[0].max_hp, "level 0 changes nothing")
	var rec := FightRecord.mech_from_dict(FightRecord.mech_to_dict(hard[0]))
	t.assert_true(rec.threat == 4 and rec.threat_openers.size() == 1, "a fight record keeps the level and the extra opener")

	t.group("Threat 2: an elite's extra opener sets something up")
	var differs := 0
	for id in ["dock_breaker", "bore_crawler", "breakwater", "caustic_engine", "relay_sentinel", "siege_warden", "pile_driver"]:
		var w1 := DataLoader.load_mech_from_file("res://data/mechs/%s.json" % id)
		var w2 := DataLoader.load_mech_from_file("res://data/mechs/%s.json" % id)
		w2.threat_openers.append({"type": "threat_extra"})
		var cm1 := CombatManager.new(_mech(), [w1] as Array[MechData], 5)
		var cm2 := CombatManager.new(_mech(), [w2] as Array[MechData], 5)
		cm1.start_combat()
		cm2.start_combat()
		if _setup(cm1, w1) != _setup(cm2, w2):
			differs += 1
	t.assert_eq(differs, 7, "every elite opens with a charge laid, a protocol primed or Deflect it didn't have")

	t.group("Threat 3: captured bays roll on arrival")
	var run := RunData.new(_shipyard(), _mech(), 61, _assault(3))
	var bay := {}
	var into := {}
	var pre_boss := {}
	for n in run.map.nodes:
		if n["kind"] != RunMap.KIND_REPAIR:
			continue
		if Threat.before_boss(run.map, n):
			pre_boss = n
			continue
		for p in run.map.nodes:
			if (p["next"] as Array).has(n["id"]) and p["kind"] == RunMap.KIND_FIGHT and bay.is_empty():
				bay = n
				into = p
	t.assert_true(not bay.is_empty(), "the map has a repair bay to test (seed 61)")
	t.assert_true(not pre_boss.is_empty(), "and the bay before the boss")
	run.ambush_chance = 1.0
	t.assert_true(not Threat.ambush_roll(run, pre_boss) and is_equal_approx(run.ambush_chance, 1.0), "the bay before the boss never counts")
	run.ambush_chance = 0.0
	t.assert_true(not Threat.ambush_roll(run, bay) and is_equal_approx(run.ambush_chance, 0.15), "a free bay: the chance rises 15 points")
	run.ambush_chance = 1.0
	t.assert_true(Threat.ambush_roll(run, bay) and is_equal_approx(run.ambush_chance, 0.05), "a taken bay: the chance drops to 5%")
	var calm := RunData.new(_shipyard(), _mech(), 61, _assault(2))
	calm.ambush_chance = 1.0
	t.assert_true(not Threat.ambush_roll(calm, bay), "below level 3 no bay is taken")
	var fresh := RunData.new(_shipyard(), _mech(), 61, _assault(3))
	t.assert_true(is_equal_approx(fresh.ambush_chance, -1.0), "a run starts with no bay rolled (20% for the first)")

	t.group("Threat 3: a taken bay is a fight, then the repair")
	run.ambush_chance = 1.0
	run.path.append(into["id"])
	run.phase = RunData.PHASE_MAP
	t.assert_true(run.choose_node(bay["id"]), "the pilot goes to the bay")
	t.assert_eq(run.phase, RunData.PHASE_FIGHT, "enemies were waiting: a fight")
	t.assert_true(run.is_ambush() and not run.encounter_enemies().is_empty(), "with enemies from the location's pools")
	var saved := RunData.from_dict(run.to_dict(), _shipyard(), run.mission)
	t.assert_true(saved.is_ambush() and saved.ambush_chance == run.ambush_chance and saved.fight_rolls.has(bay["id"]), "a save keeps the taken bay and the odds")
	run.fight_won()
	t.assert_eq(run.phase, RunData.PHASE_REWARD, "the fight pays as usual")
	run.finish_reward()
	t.assert_eq(run.phase, RunData.PHASE_REPAIR, "then the bay repairs")
	t.assert_true(run.repair_pool > 0, "with its usual pool")
	run.finish_repair()
	t.assert_eq(run.path[-1], int(bay["id"]), "and the stop is done")
	t.assert_eq(run.stats.get_stat("bays_retaken"), 1, "counted as a bay retaken")

	t.group("Threat: Chips")
	var c0 := RunData.new(_shipyard(), _mech(), 62, _assault(0))
	var c2 := RunData.new(_shipyard(), _mech(), 62, _assault(2))
	for r in [c0, c2]:
		r.stats.add("fights_won", 5)
		r.result = RunData.Result.CLEARED
	t.assert_eq(Meta.chips_for_run(c2), roundi(Meta.chips_for_run(c0) * 1.2), "level 2 pays 20% more")

	t.group("Threat: a location's next level unlocks when the one before is cleared")
	var p = load("res://scripts/run/Profile.gd").new()
	p.saving_off = true
	t.assert_eq(p.threat_unlocked("shipyard"), 0, "a new pilot starts at 0")
	p.pick_threat("shipyard", 3)
	t.assert_eq(p.threat_picked("shipyard"), 0, "can't pick a level not unlocked")
	p._clear_threat("shipyard", 0)
	t.assert_eq(p.threat_unlocked("shipyard"), 1, "clearing 0 opens 1")
	t.assert_eq(p.threat_unlocked("mining_grounds"), 0, "only at that location")
	p.pick_threat("shipyard", 1)
	t.assert_eq(p.threat_picked("shipyard"), 1, "the pick is kept")
	p._clear_threat("shipyard", 0)
	t.assert_eq(p.threat_unlocked("shipyard"), 1, "clearing a lower level again changes nothing")
	p._clear_threat("shipyard", 5)
	t.assert_eq(p.threat_unlocked("shipyard"), 5, "never past the top level")
	p.free()

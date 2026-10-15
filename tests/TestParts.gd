class_name TestParts
extends RefCounted
## Claude's 70 drafted parts (Phase 10): one check per new mechanic, using
## the real parts from the library.

static func _m(parts: Array, max_heat: int = 30, timing: String = MechData.HEAT_CHECK_END_OF_TURN) -> MechData:
	var m := TestEffects._mech(parts, max_heat)
	m.heat_check_timing = timing
	return m

static func _tank(id: String, hp: int, cell: Vector2i) -> ComponentData:
	var c := TestFixtures.make_component(id, hp)
	c.category = ComponentData.CATEGORY_HARDPOINT
	c.library_id = id
	c.placed_cells = [cell]
	return c

static func _card(m: MechData, comp_id: String, card_id: String) -> CardData:
	return TestEffects._card(m, comp_id, card_id)

static func _lost(c: ComponentData) -> int:
	return c.max_hp - c.current_hp

static func run_all(t: TestContext) -> void:
	_heat_cards(t)
	_hit_cards(t)
	_reactors(t)
	_protocols(t)
	_classes(t)

static func _heat_cards(t: TestContext) -> void:
	t.group("Heat Lance: damage grows with your Heat; Redline Burst hits harder over max")
	var p := _m([["heat_lance", Vector2i(0, 0)]])
	var e := TestEffects._dummy(9999)
	var cm := TestEffects._cm(p, [e] as Array[MechData])
	p.current_heat = 8 # 11 after paying 3: +5
	cm.play_attack_card(_card(p, "heat_lance", "searing_line"), e, e.components[0])
	var d := _lost(e.components[0])
	t.assert_true(d >= 17 and d <= 21, "Searing Line at 11 Heat: 12-16 +5 (%d)" % d)
	var p2 := _m([["heat_lance", Vector2i(0, 0)]], 10)
	var e2 := TestEffects._dummy(9999)
	var cm2 := TestEffects._cm(p2, [e2] as Array[MechData])
	p2.current_heat = 9 # 14 after paying: over max
	cm2.play_attack_card(_card(p2, "heat_lance", "redline_burst"), e2, e2.components[0])
	d = _lost(e2.components[0])
	t.assert_true(d >= 33 and d <= 42, "Redline Burst over max: 22-28 ×1.5 (%d)" % d)

	t.group("Vent Cannon: Steam Slug pushes Heat into the target mech; Blow-Off vents")
	var p3 := _m([["vent_cannon", Vector2i(0, 0)]])
	var e3 := TestEffects._dummy(9999)
	var cm3 := TestEffects._cm(p3, [e3] as Array[MechData])
	cm3.play_attack_card(_card(p3, "vent_cannon", "steam_slug"), e3, e3.components[0])
	t.assert_eq(e3.current_heat, 2, "the target mech gains 2 Heat")
	p3.current_heat = 5
	cm3.play_attack_card(_card(p3, "vent_cannon", "blow_off"), e3, e3.components[0])
	t.assert_eq(p3.current_heat, 3, "Blow-Off vents 2")

	t.group("Plasma Rapier: Lunge +2 per Heat; Overclock Heart: +1 per hit per 2 Heat")
	var p4 := _m([["plasma_rapier", Vector2i(0, 0)], ["overclock_heart", Vector2i(0, 2)]])
	var e4 := TestEffects._dummy(9999)
	var cm4 := TestEffects._cm(p4, [e4] as Array[MechData])
	p4.current_heat = 5 # 8 after paying 3: Lunge +16, Heart +4
	cm4.play_attack_card(_card(p4, "plasma_rapier", "lunge"), e4, e4.components[0])
	d = _lost(e4.components[0])
	t.assert_true(d >= 34 and d <= 38, "14-18 +16 +4 (%d)" % d)

	t.group("Overheat Fuse: the first overheat doesn't happen")
	var p5 := _m([["overheat_fuse", Vector2i(0, 0)], ["pile_driver", Vector2i(1, 0)]], 6, MechData.HEAT_CHECK_LIVE)
	var e5 := TestEffects._dummy(9999)
	var cm5 := TestEffects._cm(p5, [e5] as Array[MechData])
	var hp := p5.current_hp()
	p5.current_heat = 4
	var res := cm5.play_attack_card(_card(p5, "pile_driver", "drive"), e5, e5.components[0])
	t.assert_true(p5.get_component("overheat_fuse").destroyed, "the fuse burns out")
	t.assert_eq(p5.current_heat, p5.heat_capacity(), "Heat drops to max")
	t.assert_true(not res["overheated"] and cm5.is_player_turn(), "no backlash, and the turn goes on")
	t.assert_eq(p5.current_hp(), hp - p5.get_component("overheat_fuse").max_hp, "only the fuse is lost")

	t.group("Pressure Regulator: +5 max Heat, 25% more backlash")
	var p6 := _m([["pressure_regulator", Vector2i(0, 0)]], 10)
	t.assert_eq(p6.heat_capacity(), 15, "max Heat 15")
	t.assert_eq(p6.backlash_mult(), 1.25, "backlash ×1.25")
	t.assert_eq(HeatRules.backlash_for(p6), int(HeatRules.overheat_backlash_total(p6.max_hp()) * 1.25), "and the overheat preview shows the raised backlash")

static func _hit_cards(t: TestContext) -> void:
	t.group("Flash Pistol: Quick Draw doubles as the first card of the turn only")
	var p := _m([["flash_pistol", Vector2i(0, 0)]])
	var e := TestEffects._dummy(9999)
	var cm := TestEffects._cm(p, [e] as Array[MechData])
	cm.play_attack_card(_card(p, "flash_pistol", "quick_draw"), e, e.components[0])
	var first := _lost(e.components[0])
	cm.reload(_card(p, "flash_pistol", "quick_draw"))
	cm.play_attack_card(_card(p, "flash_pistol", "quick_draw"), e, e.components[0])
	var second := _lost(e.components[0]) - first
	t.assert_true(first >= 8 and first <= 12 and second >= 4 and second <= 6, "first 8-12 (%d), then 4-6 (%d)" % [first, second])

	t.group("Coil Whip: Discharge cashes in the target's Shock")
	var p2 := _m([["coil_whip", Vector2i(0, 0)]])
	var e2 := TestEffects._dummy(9999)
	var cm2 := TestEffects._cm(p2, [e2] as Array[MechData])
	e2.components[0].add_status("shock", 2)
	cm2.play_attack_card(_card(p2, "coil_whip", "discharge"), e2, e2.components[0])
	var d := _lost(e2.components[0])
	t.assert_true(d >= 18 and d <= 21, "8-11 +10 (%d)" % d)
	t.assert_eq(e2.components[0].status_stacks("shock"), 0, "and the Shock is gone")

	t.group("Arc Thrower: Arc also hits a part next to the target")
	var p3 := _m([["arc_thrower", Vector2i(0, 0)]])
	var e3 := TestFixtures.make_mech("e", 20, [_tank("a", 100, Vector2i(0, 0)), _tank("b", 100, Vector2i(0, 1)), _tank("c", 100, Vector2i(3, 3))] as Array[ComponentData])
	var cm3 := TestEffects._cm(p3, [e3] as Array[MechData])
	cm3.play_attack_card(_card(p3, "arc_thrower", "arc"), e3, e3.get_component("a"))
	t.assert_true(_lost(e3.get_component("a")) > 0 and _lost(e3.get_component("b")) > 0, "the target and its neighbour both take it")
	t.assert_eq(_lost(e3.get_component("c")), 0, "a part that isn't next to it doesn't")

	t.group("Mortar Pod: Lob's hits land on random parts")
	var spread := {}
	for s in range(12):
		var pm := _m([["mortar_pod", Vector2i(0, 0)]])
		var em := TestFixtures.make_mech("e", 20, [_tank("a", 500, Vector2i(0, 0)), _tank("b", 500, Vector2i(2, 2)), _tank("c", 500, Vector2i(4, 4))] as Array[ComponentData])
		var cmm := TestEffects._cm(pm, [em] as Array[MechData], s + 1)
		cmm.play_attack_card(_card(pm, "mortar_pod", "lob"), em, em.get_component("a"))
		for c in em.components:
			if _lost(c) > 0:
				spread[c.id] = true
	t.assert_eq(spread.size(), 3, "every part gets hit across a dozen Lobs")

	t.group("Hook Lance: Reel In doubles on a Disabled target; Trick Shot +1 hit per status")
	var p4 := _m([["hook_lance", Vector2i(0, 0)], ["ricochet_pistols", Vector2i(3, 0)]])
	var e4 := TestEffects._dummy(9999)
	var cm4 := TestEffects._cm(p4, [e4] as Array[MechData])
	e4.components[0].add_status("disabled", 1)
	cm4.play_attack_card(_card(p4, "hook_lance", "reel_in"), e4, e4.components[0])
	d = _lost(e4.components[0])
	t.assert_true(d >= 12 and d <= 18, "6-9 ×2 (%d)" % d)
	e4.components[0].add_status("acid", 1)
	e4.components[0].add_status("burn", 1)
	var hits := [0]
	cm4.hit_landed.connect(func(m, _c, _d): if m == e4: hits[0] += 1)
	cm4.play_attack_card(_card(p4, "ricochet_pistols", "trick_shot"), e4, e4.components[0])
	t.assert_eq(hits[0], 6, "3 hits +3 statuses (Disabled, Acid, Burn)")

	t.group("Grinder Maw: Chew heals your most damaged part by 30% of the damage")
	var p5 := _m([["grinder_maw", Vector2i(0, 0)], ["rivet_gun", Vector2i(3, 0)]])
	var e5 := TestEffects._dummy(9999)
	var cm5 := TestEffects._cm(p5, [e5] as Array[MechData])
	p5.get_component("rivet_gun").current_hp = 10
	cm5.play_attack_card(_card(p5, "grinder_maw", "chew"), e5, e5.components[0])
	t.assert_true(p5.get_component("rivet_gun").current_hp > 10, "the Rivet Gun got HP back")

	t.group("Nova Cannon: hits every enemy, and the cannon takes 6")
	var p6 := _m([["nova_cannon", Vector2i(0, 0)]])
	var ea := TestEffects._dummy(9999)
	var eb := TestEffects._dummy(9999)
	var cm6 := TestEffects._cm(p6, [ea, eb] as Array[MechData])
	cm6.play_attack_card(_card(p6, "nova_cannon", "nova"), ea, ea.components[0])
	t.assert_true(_lost(ea.components[0]) > 0 and _lost(eb.components[0]) > 0, "both enemies hit")
	t.assert_eq(_lost(p6.get_component("nova_cannon")), 6, "recoil 6")

	t.group("Resonance Blade: +4 for each earlier Resonate this fight")
	var p7 := _m([["resonance_blade", Vector2i(0, 0)]])
	var e7 := TestEffects._dummy(9999)
	var cm7 := TestEffects._cm(p7, [e7] as Array[MechData])
	var dealt := []
	for i in range(3):
		var before := _lost(e7.components[0])
		cm7.reload(_card(p7, "resonance_blade", "resonate"))
		cm7.play_attack_card(_card(p7, "resonance_blade", "resonate"), e7, e7.components[0])
		dealt.append(_lost(e7.components[0]) - before)
	t.assert_true(dealt[2] >= 16 and dealt[2] <= 19, "third play: 8-11 +8 (%d)" % dealt[2])

	t.group("Demolition Hammer: Wreck ignores Deflect")
	var p8 := _m([["demolition_hammer", Vector2i(0, 0)]])
	var e8 := TestEffects._dummy(9999)
	var cm8 := TestEffects._cm(p8, [e8] as Array[MechData])
	e8.add_mech_status("deflect", 50)
	cm8.play_attack_card(_card(p8, "demolition_hammer", "wreck"), e8, e8.components[0])
	t.assert_true(_lost(e8.components[0]) >= 32, "32-40 straight through 50 Deflect")

	t.group("Tesla Coil Tower: Ground Out clears Shock and Acid")
	var p9 := _m([["tesla_coil_tower", Vector2i(0, 0)], ["rivet_gun", Vector2i(4, 0)]])
	var cm9 := TestEffects._cm(p9, [TestEffects._dummy()] as Array[MechData])
	p9.get_component("rivet_gun").add_status("shock", 2)
	p9.get_component("rivet_gun").add_status("acid", 1)
	cm9.play_self_card(_card(p9, "tesla_coil_tower", "ground_out"))
	t.assert_eq(p9.get_component("rivet_gun").status_stacks("shock") + p9.get_component("rivet_gun").status_stacks("acid"), 0, "both gone")

static func _reactors(t: TestContext) -> void:
	t.group("Afterburner: +50% on the first attack of the turn")
	var p := _m([["afterburner", Vector2i(4, 0)]])
	p.components.append(TestEffects._gun("g", 20))
	var e := TestEffects._dummy(9999)
	var cm := TestEffects._cm(p, [e] as Array[MechData])
	cm.play_attack_card(p.get_component("g").cards[0], e, e.components[0])
	cm.reload(p.get_component("g").cards[0])
	cm.play_attack_card(p.get_component("g").cards[0], e, e.components[0])
	t.assert_eq(_lost(e.components[0]), 30 + 20, "30, then 20")

	t.group("Juggernaut Treads: each attack this turn +3 per hit over the last")
	var pj := _m([["juggernaut_treads", Vector2i(4, 0)]])
	pj.components.append(TestEffects._gun("g", 10))
	var ej := TestEffects._dummy(9999)
	var cmj := TestEffects._cm(pj, [ej] as Array[MechData])
	for i in range(3):
		cmj.reload(pj.get_component("g").cards[0])
		cmj.play_attack_card(pj.get_component("g").cards[0], ej, ej.components[0])
	t.assert_eq(_lost(ej.components[0]), 10 + 13 + 16, "10, 13, 16")

	t.group("Relay Booster: +3 per hit for the hardpoint it points at")
	var pr := _m([["relay_booster", Vector2i(0, 0)]])
	pr.components.append(TestEffects._gun("g", 10, 1, 1, Vector2i(0, 2)))
	pr.components.append(TestEffects._gun("far", 10, 1, 1, Vector2i(4, 4)))
	var er := TestEffects._dummy(9999)
	var cmr := TestEffects._cm(pr, [er] as Array[MechData])
	cmr.play_attack_card(pr.get_component("g").cards[0], er, er.components[0])
	t.assert_eq(_lost(er.components[0]), 13, "the linked gun: 13")
	cmr.play_attack_card(pr.get_component("far").cards[0], er, er.components[0])
	t.assert_eq(_lost(er.components[0]), 23, "an unlinked one: 10")

	t.group("Spiked Plating / Mirror Plating: the attacker's part takes damage back")
	var p2 := _m([])
	p2.components.append(TestEffects._gun("g", 5))
	var e2 := _m([["spiked_plating", Vector2i(0, 0)], ["mirror_plating", Vector2i(2, 0)]])
	var cm2 := TestEffects._cm(p2, [e2] as Array[MechData])
	cm2.play_attack_card(p2.get_component("g").cards[0], e2, e2.get_component("spiked_plating"))
	t.assert_eq(_lost(p2.get_component("g")), 6 + 5, "6 from the spikes it hit, 5 from the mirror")

	t.group("Field Medic Unit heals what it points at; Fortress Core Deflects per reactor")
	var p3 := _m([["field_medic_unit", Vector2i(1, 0)], ["fortress_core", Vector2i(3, 3)]])
	var patient := _tank("patient", 50, Vector2i(0, 0))
	patient.current_hp = 30
	p3.components.append(patient)
	var cm3 := TestEffects._cm(p3, [TestEffects._dummy()] as Array[MechData])
	cm3.end_player_turn()
	t.assert_eq(patient.current_hp, 42, "+6 at each turn start (the first turn and the next)")
	t.assert_true(p3.mech_status_stacks("deflect") >= 8, "2 reactors: Deflect 8 (%d)" % p3.mech_status_stacks("deflect"))

	t.group("Bulwark Frame: no single hit over 10 on the part it points at")
	var p4 := _m([])
	p4.components.append(TestEffects._gun("g", 40))
	var e4 := _m([["bulwark_frame", Vector2i(1, 0)]])
	var guarded := _tank("guarded", 100, Vector2i(0, 0))
	e4.components.append(guarded)
	var cm4 := TestEffects._cm(p4, [e4] as Array[MechData])
	cm4.play_attack_card(p4.get_component("g").cards[0], e4, guarded)
	t.assert_eq(_lost(guarded), 10, "40 capped to 10")

	t.group("Heat Sink Array vents 3 when an attack damages its mech; Blowout Vent vents 4 on a kill")
	var p5 := _m([["heat_sink_array", Vector2i(0, 0)], ["blowout_vent", Vector2i(2, 0)]])
	p5.components.append(TestEffects._gun("g", 50))
	var e5 := TestEffects._dummy(40)
	var cm5 := TestEffects._cm(p5, [e5, TestEffects._dummy()] as Array[MechData])
	p5.current_heat = 10
	cm5.play_attack_card(p5.get_component("g").cards[0], e5, e5.components[0])
	t.assert_eq(p5.current_heat, 10 + 1 - 4, "the kill vents 4")

	t.group("Reinforced Bulkhead: twice per fight, a part that would die is left at 1 HP")
	var p6 := _m([])
	p6.components.append(TestEffects._gun("g", 999))
	var e6 := _m([["reinforced_bulkhead", Vector2i(0, 0)]])
	var a := _tank("a", 50, Vector2i(3, 3))
	var b := _tank("b", 50, Vector2i(4, 4))
	var c3 := _tank("c3", 50, Vector2i(5, 5))
	e6.components.append(a)
	e6.components.append(b)
	e6.components.append(c3)
	var cm6 := TestEffects._cm(p6, [e6] as Array[MechData])
	cm6.play_attack_card(p6.get_component("g").cards[0], e6, a)
	cm6.reload(p6.get_component("g").cards[0])
	cm6.play_attack_card(p6.get_component("g").cards[0], e6, b)
	cm6.reload(p6.get_component("g").cards[0])
	cm6.play_attack_card(p6.get_component("g").cards[0], e6, c3)
	t.assert_true(not a.destroyed and a.current_hp == 1 and not b.destroyed and b.current_hp == 1, "the first two are saved")
	t.assert_true(c3.destroyed, "the third isn't")

	t.group("Blink Drive: the first two hits each round are dodged")
	var p7 := _m([])
	p7.components.append(TestEffects._gun("g", 10))
	var e7 := _m([["blink_drive", Vector2i(0, 0)]])
	var t7 := _tank("t7", 100, Vector2i(3, 3))
	e7.components.append(t7)
	var cm7 := TestEffects._cm(p7, [e7] as Array[MechData])
	for i in range(3):
		cm7.reload(p7.get_component("g").cards[0])
		cm7.play_attack_card(p7.get_component("g").cards[0], e7, t7)
	t.assert_eq(_lost(t7), 10, "two dodged, one landed")

	t.group("Phase Array: cards from what it points at cost 1 less")
	var p8 := _m([["phase_array", Vector2i(0, 0)]])
	p8.components.append(TestEffects._gun("g", 5, 1, 3, Vector2i(0, 2)))
	var cm8 := TestEffects._cm(p8, [TestEffects._dummy()] as Array[MechData])
	t.assert_eq(cm8.effective_cost(p8.get_component("g").cards[0]), 2, "3 → 2")

	t.group("Neural Link: a kill makes your next card free this turn")
	var p9 := _m([["neural_link", Vector2i(0, 0)]])
	p9.components.append(TestEffects._gun("g", 99, 1, 4))
	var e9 := TestEffects._dummy(50)
	var cm9 := TestEffects._cm(p9, [e9, TestEffects._dummy()] as Array[MechData])
	cm9.play_attack_card(p9.get_component("g").cards[0], e9, e9.components[0])
	t.assert_eq(cm9.effective_cost(p9.get_component("g").cards[0]), 0, "next card: 0 Heat")

	t.group("Scrap Magnet: kills pay Scraps with the salvage")
	var p10 := _m([["scrap_magnet", Vector2i(0, 0)]])
	p10.components.append(TestEffects._gun("g", 99))
	var e10 := TestEffects._dummy(50)
	var cm10 := TestEffects._cm(p10, [e10, TestEffects._dummy()] as Array[MechData])
	cm10.play_attack_card(p10.get_component("g").cards[0], e10, e10.components[0])
	t.assert_eq(cm10.stats.get_stat("magnet_scraps"), 6, "+6 Scraps")

	t.group("Static Collector: some attacks also Shock")
	var shocked := 0
	for s in range(40):
		var ps := _m([["static_collector", Vector2i(0, 0)]])
		ps.components.append(TestEffects._gun("g", 1))
		var es := TestEffects._dummy(9999)
		var cms := TestEffects._cm(ps, [es] as Array[MechData], s + 1)
		cms.play_attack_card(ps.get_component("g").cards[0], es, es.components[0])
		shocked += 1 if es.components[0].status_stacks("shock") > 0 else 0
	t.assert_true(shocked > 10 and shocked < 32, "about half the time (%d of 40)" % shocked)

	t.group("Chaos Reactor: Burn on an enemy part at turn start")
	var pc := _m([["chaos_reactor", Vector2i(0, 0)]])
	pc.components.append(TestEffects._gun("g", 1))
	var ec := TestEffects._dummy(9999)
	var cmc := TestEffects._cm(pc, [ec] as Array[MechData])
	t.assert_eq(ec.components[0].status_stacks("burn"), 5, "Burn 5 on the enemy")

static func _protocols(t: TestContext) -> void:
	t.group("Quickload / Ballast: the next card costs less, once")
	var p := _m([["quickload_chip", Vector2i(0, 0)]])
	p.components.append(TestEffects._gun("g", 1, 1, 4))
	var e := TestEffects._dummy(9999)
	var cm := TestEffects._cm(p, [e] as Array[MechData])
	cm.play_self_card(_card(p, "quickload_chip", "quickload"))
	var gun: CardData = p.get_component("g").cards[0]
	t.assert_eq(cm.effective_cost(gun), 1, "4 → 1 while primed")
	cm.play_attack_card(gun, e, e.components[0])
	t.assert_eq(p.current_heat, 1, "paid 1")
	t.assert_eq(cm.effective_cost(gun), 4, "then back to 4")

	t.group("Fan Out: the next attack hits every enemy")
	var p2 := _m([["scatter_link", Vector2i(0, 0)]])
	p2.components.append(TestEffects._gun("g", 5))
	var a := TestEffects._dummy(999)
	var b := TestEffects._dummy(999)
	var cm2 := TestEffects._cm(p2, [a, b] as Array[MechData])
	cm2.play_self_card(_card(p2, "scatter_link", "fan_out"))
	cm2.play_attack_card(p2.get_component("g").cards[0], a, a.components[0])
	t.assert_true(_lost(b.components[0]) == 5, "the other enemy takes it too")

	t.group("Siphon: the next attack heals your most damaged part by half")
	var p3 := _m([["siphon_driver", Vector2i(0, 0)]])
	p3.components.append(TestEffects._gun("g", 20))
	var hurt := _tank("hurt", 50, Vector2i(4, 4))
	hurt.current_hp = 10
	p3.components.append(hurt)
	var cm3 := TestEffects._cm(p3, [TestEffects._dummy(999)] as Array[MechData])
	cm3.play_self_card(_card(p3, "siphon_driver", "siphon"))
	cm3.play_attack_card(p3.get_component("g").cards[0], cm3.enemies[0], cm3.enemies[0].components[0])
	t.assert_eq(hurt.current_hp, 20, "+10")

	t.group("Breach / Double Tap / Execute / Loaded Dice / Ram / Invert")
	var p4 := _m([["breach_charge", Vector2i(0, 0)], ["tactical_uplink", Vector2i(1, 0)], ["kill_switch", Vector2i(2, 0)],
		["probability_engine", Vector2i(3, 0)], ["hydraulic_ram", Vector2i(0, 3)], ["polarity_inverter", Vector2i(1, 3)]])
	p4.components.append(TestEffects._gun("g", 10))
	var e4 := TestEffects._dummy(1000)
	var cm4 := TestEffects._cm(p4, [e4] as Array[MechData])
	var g4: CardData = p4.get_component("g").cards[0]
	e4.add_mech_status("deflect", 50)
	cm4.play_self_card(_card(p4, "breach_charge", "breach"))
	cm4.reload(g4)
	cm4.play_attack_card(g4, e4, e4.components[0])
	t.assert_eq(_lost(e4.components[0]), 10, "Breach: straight through Deflect (Pierce)")
	e4.clear_mech_status("deflect")
	cm4.play_self_card(_card(p4, "tactical_uplink", "double_tap"))
	cm4.reload(g4)
	cm4.play_attack_card(g4, e4, e4.components[0])
	t.assert_eq(_lost(e4.components[0]), 20, "Double Tap: no attack shown, so only the target is hit (10 more)")
	e4.components[0].current_hp = 300
	cm4.play_self_card(_card(p4, "kill_switch", "execute"))
	cm4.reload(g4)
	cm4.play_attack_card(g4, e4, e4.components[0])
	t.assert_eq(e4.components[0].current_hp, 270, "Execute: ×3 at half HP or less")
	cm4.play_self_card(_card(p4, "hydraulic_ram", "ram"))
	cm4.reload(g4)
	cm4.play_attack_card(g4, e4, e4.components[0])
	t.assert_eq(e4.components[0].status_stacks("disabled"), 1, "Ram: the target is Disabled")
	p4.get_component("g").remove_status("disabled", 9) # Ram disabled the gun
	cm4.primed.clear()
	e4.current_heat = 7
	var mine := p4.current_heat
	cm4.play_self_card(_card(p4, "polarity_inverter", "invert"))
	cm4.reload(g4)
	cm4.play_attack_card(g4, e4, e4.components[0])
	t.assert_eq(p4.current_heat, 7, "Invert: you take its Heat")
	t.assert_eq(e4.current_heat, mine + 1, "and it takes yours")

	var p5 := _m([["probability_engine", Vector2i(0, 0)], ["needle_carbine", Vector2i(2, 0)]])
	var e5 := TestEffects._dummy(9999)
	var cm5 := TestEffects._cm(p5, [e5] as Array[MechData])
	cm5.play_self_card(_card(p5, "probability_engine", "loaded_dice"))
	cm5.play_attack_card(_card(p5, "needle_carbine", "needle_storm"), e5, e5.components[0])
	t.assert_eq(_lost(e5.components[0]), 30, "Loaded Dice: 5 hits, none miss, all max (6)")

	t.group("Recall: the next card plays again next turn for free")
	var p6 := _m([["salvage_recursor", Vector2i(0, 0)]])
	p6.components.append(TestEffects._gun("g", 10, 1, 3))
	var e6 := TestEffects._dummy(9999)
	var cm6 := TestEffects._cm(p6, [e6] as Array[MechData])
	cm6.play_self_card(_card(p6, "salvage_recursor", "recall"))
	cm6.play_attack_card(p6.get_component("g").cards[0], e6, e6.components[0])
	cm6.end_player_turn()
	t.assert_eq(_lost(e6.components[0]), 20, "hit again at the start of the next turn")

	t.group("Fortify: the next card gives Deflect equal to four times its Heat")
	var p7 := _m([["rampart_protocol", Vector2i(0, 0)]])
	p7.components.append(TestEffects._gun("g", 1, 1, 4))
	var cm7 := TestEffects._cm(p7, [TestEffects._dummy(999)] as Array[MechData])
	cm7.play_self_card(_card(p7, "rampart_protocol", "fortify"))
	cm7.play_attack_card(p7.get_component("g").cards[0], cm7.enemies[0], cm7.enemies[0].components[0])
	t.assert_eq(p7.mech_status_stacks("deflect"), 16, "4 Heat → Deflect 16")

	t.group("Last Stand: 0 Heat at half HP or less; Feedback: vent 2 per hit")
	var p8 := _m([["last_stand_protocol", Vector2i(0, 0)], ["feedback_loop", Vector2i(1, 0)]])
	p8.components.append(TestEffects._gun("g", 100, 1, 0))
	var filler := _tank("filler", 1000, Vector2i(5, 0))
	filler.current_hp = 500
	p8.components.append(filler)
	var e8 := TestEffects._dummy(9999)
	var cm8 := TestEffects._cm(p8, [e8] as Array[MechData])
	var lost := 1.0 - float(p8.current_hp()) / p8.max_hp()
	cm8.play_self_card(_card(p8, "last_stand_protocol", "last_stand"))
	cm8.play_attack_card(p8.get_component("g").cards[0], e8, e8.components[0])
	t.assert_eq(_lost(e8.components[0]), 100, "Last Stand doesn't add damage any more (%d%% HP lost; it's a 0-Heat discount: TestProtocols)" % int(lost * 100))
	p8.current_heat = 7
	cm8.play_self_card(_card(p8, "feedback_loop", "feedback"))
	var g8 := TestFixtures.make_card("multi", "g", 0, 3, 1, 1)
	p8.get_component("g").cards.append(g8)
	cm8.play_attack_card(g8, e8, e8.components[0])
	t.assert_eq(p8.current_heat, 1, "3 hits vent 6")

static func _classes(t: TestContext) -> void:
	t.group("Weight classes: Light / Medium / Heavy parts fit only their class")
	t.assert_true(ComponentLibrary.fits_class("heat_lance", "light"), "a Light part fits Redline")
	t.assert_true(not ComponentLibrary.fits_class("pile_driver", "light"), "a Heavy one doesn't")
	t.assert_true(ComponentLibrary.fits_class("autocannon", "heavy"), "General fits everything")
	var loc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sectors.json"))["locations"][0]
	var run := RunData.new(loc, DataLoader.load_mech_from_file("res://data/mechs/redline.json"), 3)
	run.phase = RunData.PHASE_REFIT
	var heavy := run.new_part("pile_driver")
	run.cargo.add(heavy)
	var placed := false
	for r in range(6):
		for c in range(6):
			for rot in range(4):
				placed = placed or run.can_install(heavy, rot, Vector2i(r, c))
	t.assert_true(not placed, "a refit won't put a Heavy part on Redline")
	var ok := true
	for s in range(40):
		var rr := RandomNumberGenerator.new()
		rr.seed = s
		for cat in Economy.CATEGORIES:
			for id in Economy.roll_options(cat, rr, 1, "light"):
				if not ComponentLibrary.fits_class(id, "light"):
					ok = false
	t.assert_true(ok, "salvage for a Light mech only offers parts it can fit")

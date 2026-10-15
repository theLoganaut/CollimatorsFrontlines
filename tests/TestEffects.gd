class_name TestEffects
extends RefCounted
## Phase 2: every status, card effect, reactor passive and protocol from
## Refit Bay, played through the real CombatManager. Rulings are Logan's
## (Decided) or Notion "Phase 2 rulings to vet" (Proposed).

## A mech on an open 6×6 chassis with library parts at [id, offset, rotation?].
static func _mech(parts: Array, max_heat: int = 30) -> MechData:
	var m := MechData.new()
	m.id = "test"
	m.name = "Test"
	m.max_heat = max_heat
	m.heat_check_timing = MechData.HEAT_CHECK_LIVE
	for r in range(6):
		for c in range(6):
			m.cells.append(Vector2i(r, c))
	var used := {}
	for p in parts:
		var comp := ComponentLibrary.make(p[0])
		var id: String = p[0]
		var n := 2
		while used.has(id):
			id = "%s_%d" % [p[0], n]
			n += 1
		used[id] = true
		comp.set_instance_id(id)
		comp.place(p[2] if p.size() > 2 else 0, p[1])
		m.components.append(comp)
	return m

## A 1-cell test gun with one fixed-damage card, at `cell`.
static func _gun(id: String, dmg: int, hits: int = 1, heat: int = 1, cell := Vector2i(5, 5)) -> ComponentData:
	var card := TestFixtures.make_card(id + "_shot", id, heat, hits, dmg, dmg)
	var c := TestFixtures.make_component(id, 60, [card] as Array[CardData])
	c.library_id = id
	c.placed_cells = [cell]
	return c

## An enemy that never acts: one big hardpoint with no cards.
static func _dummy(hp: int = 300) -> MechData:
	var tank := TestFixtures.make_component("tank", hp)
	tank.library_id = "tank"
	return TestFixtures.make_mech("dummy", 20, [tank] as Array[ComponentData])

static func _cm(player: MechData, enemies: Array[MechData], seed_value: int = 1) -> CombatManager:
	var cm := CombatManager.new(player, enemies, seed_value)
	cm.start_combat()
	return cm

static func _card(m: MechData, comp_id: String, card_id: String) -> CardData:
	for c in m.get_component(comp_id).cards:
		if c.id == card_id:
			return c
	return null

static func run_all(t: TestContext) -> void:
	_statuses(t)
	_cards(t)
	_reactors(t)
	_protocols(t)
	_links(t)

# ---------- statuses ----------

static func _statuses(t: TestContext) -> void:
	t.group("Acid: the part takes 1/3 more damage")
	var p := _mech([])
	p.components.append(_gun("g", 30))
	var e := _dummy()
	var cm := _cm(p, [e] as Array[MechData])
	e.components[0].add_status("acid", 1)
	cm.play_attack_card(p.components[0].cards[0], e, e.components[0])
	t.assert_eq(e.components[0].max_hp - e.components[0].current_hp, 40, "30 + 1/3 = 40")

	t.group("Burn: +1 heat per stack at the start of its owner's turn, then decays")
	var bp := _mech([])
	bp.components.append(_gun("g", 1))
	var bcm := _cm(bp, [_dummy()] as Array[MechData])
	bp.components[0].add_status("burn", 3)
	bcm.end_player_turn() # decays at the end of the player's turn: 3 -> 2
	t.assert_eq(bp.components[0].status_stacks("burn"), 2, "Burn lost a stack at the end of its owner's turn")
	t.assert_eq(bp.current_heat, 2, "and heated the Bastion 2 at its next turn start")

	t.group("Disabled / Offline: the part can't be used; Offline clears when the fight ends")
	var dp := _mech([])
	dp.components.append(_gun("g", 5))
	var dcm := _cm(dp, [_dummy()] as Array[MechData])
	var gun := dp.components[0]
	gun.add_status("disabled", 1)
	t.assert_true(not dcm.can_play(gun.cards[0]), "a Disabled part's card can't be played")
	t.assert_eq(dcm.play_attack_card(gun.cards[0], dcm.enemies[0], dcm.enemies[0].components[0])["reason"], "source_unusable", "trying is refused")
	dcm.end_player_turn()
	t.assert_true(dcm.can_play(gun.cards[0]), "Disabled 1 wears off at the end of its owner's turn")
	var rail_p := _mech([["railspike", Vector2i(0, 0)]])
	var rcm := _cm(rail_p, [_dummy()] as Array[MechData])
	var rail := rail_p.get_component("railspike")
	rcm.play_attack_card(_card(rail_p, "railspike", "100_power_rail"), rcm.enemies[0], rcm.enemies[0].components[0])
	t.assert_eq(rail.status_stacks("offline"), 1, "100% Power Rail sends its own part Offline")
	rcm.end_player_turn()
	t.assert_true(not rail.is_usable(), "Offline lasts past the turn")
	rcm.enemies[0].components[0].apply_damage(9999)
	rcm._check_game_over()
	t.assert_eq(rail.status_stacks("offline"), 0, "and clears when the fight ends")

	t.group("Freeze: using the part removes Freeze and sends it Offline")
	var fp := _mech([])
	fp.components.append(_gun("g", 5))
	var fcm := _cm(fp, [_dummy()] as Array[MechData])
	fp.components[0].add_status("freeze", 2)
	fcm.play_attack_card(fp.components[0].cards[0], fcm.enemies[0], fcm.enemies[0].components[0])
	t.assert_eq(fp.components[0].status_stacks("freeze"), 0, "Freeze is gone")
	t.assert_eq(fp.components[0].status_stacks("offline"), 1, "the part is Offline")

	t.group("Coolant / Jam: −1 / +1 heat on the part's cards, a stack used per play")
	var cp := _mech([])
	cp.components.append(_gun("g", 5, 1, 3))
	var ccm := _cm(cp, [_dummy()] as Array[MechData])
	var cg := cp.components[0]
	cg.add_status("coolant", 1)
	t.assert_eq(ccm.effective_cost(cg.cards[0]), 2, "Coolant: 3 heat costs 2")
	ccm.play_attack_card(cg.cards[0], ccm.enemies[0], ccm.enemies[0].components[0])
	t.assert_eq(cp.current_heat, 2, "and it paid 2")
	t.assert_eq(cg.status_stacks("coolant"), 0, "Coolant used up")
	cg.add_status("jam", 2)
	t.assert_eq(ccm.effective_cost(cg.cards[0]), 4, "Jam: 3 heat costs 4")

	t.group("Smoke: venting is reduced by its stacks, each point vented clearing one")
	var sp := _mech([])
	sp.components.append(_gun("g", 1))
	var scm := _cm(sp, [_dummy()] as Array[MechData])
	sp.current_heat = 20 # of 30: ratio vent floor(400 × 0.8 / 30) = 10
	sp.add_mech_status("smoke", 3)
	scm.end_player_turn()
	t.assert_eq(sp.current_heat, 12, "Smoke decays to 2 at the turn's end, then vent 10 − 2 = 8 (20 → 12)")
	t.assert_eq(sp.mech_status_stacks("smoke"), 0, "and venting used up the remaining Smoke")

# ---------- hardpoint card effects ----------

static func _cards(t: TestContext) -> void:
	t.group("Rapid Fire: hits fire at 100 / 90 / 70 / 40 / 20% (Logan's falloff)")
	var fired := 0
	var runs := 400
	for s in range(runs):
		var p := _mech([["autocannon", Vector2i(0, 0)]])
		var e := _dummy(9999)
		var cm := _cm(p, [e] as Array[MechData], s + 1)
		var count := [0]
		cm.hit_landed.connect(func(_m, _c, _d): count[0] += 1)
		cm.play_attack_card(_card(p, "autocannon", "rapid_fire"), e, e.components[0])
		fired += count[0]
	var avg := float(fired) / runs
	t.assert_true(absf(avg - 3.2) < 0.15, "about 3.2 of 5 hits fire on average (%.2f)" % avg)

	t.group("Shock Round: its Shock applies every time")
	var shocked := 0
	for s in range(20):
		var p := _mech([["hv_rifle", Vector2i(0, 0)]])
		var e := _dummy()
		var cm := _cm(p, [e] as Array[MechData], s + 7)
		cm.play_attack_card(_card(p, "hv_rifle", "shock_round"), e, e.components[0])
		if e.components[0].status_stacks("shock") > 0:
			shocked += 1
	t.assert_eq(shocked, 20, "20 of 20 shocked")

	t.group("EMP Round: triple damage to a shocked hardpoint")
	var dmg_plain := 0
	var dmg_shocked := 0
	for shocked_first in [false, true]:
		var p := _mech([["hv_rifle", Vector2i(0, 0)]])
		var e := _dummy()
		var cm := _cm(p, [e] as Array[MechData], 3)
		if shocked_first:
			e.components[0].add_status("shock", 1)
		cm.play_attack_card(_card(p, "hv_rifle", "emp_round"), e, e.components[0])
		var d := e.components[0].max_hp - e.components[0].current_hp
		if shocked_first:
			dmg_shocked = d
		else:
			dmg_plain = d
	t.assert_eq(dmg_shocked, dmg_plain * 3, "same roll, ×3 when the hardpoint holds Shock")

	t.group("Thrust Through: double damage to a hardpoint at half HP or lower")
	var tp := _mech([["ion_blade", Vector2i(0, 0)]])
	var te := _dummy(100)
	var tcm := _cm(tp, [te] as Array[MechData], 5)
	te.components[0].current_hp = 50
	tcm.play_attack_card(_card(tp, "ion_blade", "thrust_through"), te, te.components[0])
	var dealt := 50 - te.components[0].current_hp
	t.assert_true(dealt >= 24 and dealt <= 32, "12–16 doubled (%d)" % dealt)

	t.group("Optical Pinpoint: the targeted hardpoint is Disabled")
	var op := _mech([["laser_drive", Vector2i(0, 0)]])
	var oe := _dummy()
	var ocm := _cm(op, [oe] as Array[MechData])
	ocm.play_attack_card(_card(op, "laser_drive", "optical_pinpoint"), oe, oe.components[0])
	t.assert_eq(oe.components[0].status_stacks("disabled"), 1, "Disabled 1 on the target")

	t.group("Spillage: repeats on the same part at the start of the next 2 turns")
	var sp := _mech([["caustic_schism", Vector2i(0, 0)]])
	var se := _dummy()
	var scm := _cm(sp, [se] as Array[MechData], 9)
	var hits := [0]
	scm.hit_landed.connect(func(m, _c, _d):
		if m == se:
			hits[0] += 1)
	scm.play_attack_card(_card(sp, "caustic_schism", "spillage"), se, se.components[0])
	scm.end_player_turn()
	scm.end_player_turn()
	scm.end_player_turn()
	t.assert_eq(hits[0], 3, "1 hit now + 1 on each of the next 2 turns, then it stops")

	t.group("Self Splash: vents 3 heat and Caustic Schism takes the 24–32 (Logan)")
	var ss := _mech([["caustic_schism", Vector2i(0, 0)]])
	var sscm := _cm(ss, [_dummy()] as Array[MechData])
	ss.current_heat = 5
	var schism := ss.get_component("caustic_schism")
	sscm.play_self_card(_card(ss, "caustic_schism", "self_splash"))
	t.assert_eq(ss.current_heat, 2, "5 − 3 heat")
	var lost := schism.max_hp - schism.current_hp
	t.assert_true(lost >= 24 and lost <= 32, "Caustic Schism took 24–32 (%d)" % lost)

	t.group("Lay Waste: hits every enemy; Burn on each part hit")
	var lp := _mech([["firestorm", Vector2i(0, 0)]])
	var e1 := _dummy()
	var e2 := _dummy()
	var lcm := _cm(lp, [e1, e2] as Array[MechData])
	lcm.play_attack_card(_card(lp, "firestorm", "lay_waste"), e1, e1.components[0])
	t.assert_true(e2.components[0].current_hp < e2.components[0].max_hp, "the other enemy was hit too")
	t.assert_eq(e1.components[0].status_stacks("burn"), 1, "Burn 1 on the target")
	t.assert_eq(e2.components[0].status_stacks("burn"), 1, "and on the other enemy's part")

# ---------- reactors ----------

static func _reactors(t: TestContext) -> void:
	t.group("Thermal Core / Overpressure Valve / Coolant Loop: heat capacity, backlash and Coolant")
	var hp := _mech([["thermal_core", Vector2i(0, 0)], ["overpressure_valve", Vector2i(0, 2)]], 10)
	t.assert_eq(hp.heat_capacity(), 14, "10 + 2 + 2 (Logan: Overpressure +2)")
	t.assert_eq(hp.backlash_mult(), 1.25, "Overpressure: overheat backlash +25%")
	hp.get_component("thermal_core").apply_damage(999)
	t.assert_eq(hp.heat_capacity(), 12, "a destroyed Thermal Core stops giving its +2")
	var cl := _mech([["coolant_loop", Vector2i(0, 0)]], 10)
	cl.components.append(_gun("g", 1))
	_cm(cl, [_dummy()] as Array[MechData])
	t.assert_eq(cl.get_component("g").status_stacks("coolant"), 1, "Coolant Loop: Coolant 1 on a hardpoint at turn start")

	t.group("Nano Bots: heals 5 to the lowest-HP part at turn start (Logan)")
	var np := _mech([["nano_bots", Vector2i(0, 0)], ["impact_hammer", Vector2i(2, 0)]])
	var ncm := _cm(np, [_dummy()] as Array[MechData])
	var hammer := np.get_component("impact_hammer")
	hammer.current_hp = 20
	ncm.end_player_turn()
	t.assert_eq(hammer.current_hp, 25, "+5 at the start of the next turn")

	t.group("Redundant Wiring: saves one part at 1 HP once, then it's destroyed")
	var rp := _mech([["redundant_wiring", Vector2i(0, 0)]])
	var victim := _gun("v", 5)
	rp.components.append(victim)
	var r := CardResolver.deal_damage(rp, victim, 999)
	t.assert_eq(victim.current_hp, 1, "left at 1 HP")
	t.assert_true(rp.get_component("redundant_wiring").destroyed, "Redundant Wiring is used up")
	CardResolver.deal_damage(rp, victim, 999)
	t.assert_true(victim.destroyed, "the next lethal hit goes through")
	t.assert_true(r["saved_by"] != null, "the save is reported")

	t.group("Plated Housing (arrow up): soaks hits aimed at the part above it")
	var pp := _mech([["plated_housing", Vector2i(2, 0)]])
	var above := _gun("above", 5, 1, 1, Vector2i(1, 0))
	var elsewhere := _gun("away", 5, 1, 1, Vector2i(5, 5))
	pp.components.append(above)
	pp.components.append(elsewhere)
	t.assert_eq(pp.cover_for(above), pp.get_component("plated_housing"), "hits on the part above land on Plated Housing")
	t.assert_eq(pp.cover_for(elsewhere), null, "a part it doesn't face isn't covered")
	pp.get_component("plated_housing").place(2, Vector2i(2, 0)) # turned 180°: now faces down
	t.assert_eq(pp.cover_for(above), null, "rotated, it faces the other way")

	t.group("Coolant Flush (arrow down): Coolant 1 on the part below it, at the start of combat only")
	var fp := _mech([["coolant_flush", Vector2i(0, 0)]])
	var below := _gun("below", 5, 1, 2, Vector2i(2, 0))
	fp.components.append(below)
	var fcm := _cm(fp, [_dummy()] as Array[MechData])
	t.assert_eq(below.status_stacks("coolant"), 1, "Coolant 1 as the fight starts")
	t.assert_eq(fcm.effective_cost(below.cards[0]), 1, "so its 2-heat card costs 1")
	fcm.end_player_turn()
	fcm.end_player_turn()
	t.assert_eq(below.status_stacks("coolant"), 1, "unused, it keeps that 1, and no more comes later (Logan, 2026-09-30)")

	t.group("Reactive Plating: Deflect 5 once per enemy attack that damages you")
	var rep := _mech([["reactive_plating", Vector2i(0, 0)]])
	rep.components.append(_gun("g", 1))
	var atk := _mech([])
	atk.components.append(_gun("e", 4, 3, 1)) # 3 hits of 4
	var rcm := CombatManager.new(rep, [atk] as Array[MechData], 2)
	rcm.start_combat()
	rcm.execute_enemy_action({"mech": atk, "component": atk.components[0], "card": atk.components[0].cards[0], "target": rep.get_component("g")})
	t.assert_eq(rep.mech_status_stacks("deflect"), 5, "one attack of 3 hits: Deflect 5 once, not per hit")

	t.group("Overclock Shunt: the first card each turn costs 1 less")
	var op := _mech([["overclock_shunt", Vector2i(0, 0)]])
	op.components.append(_gun("g", 1, 1, 3))
	var ocm := _cm(op, [_dummy()] as Array[MechData])
	var oc := op.get_component("g").cards[0]
	t.assert_eq(ocm.effective_cost(oc), 2, "first card: 3 → 2")
	ocm.play_attack_card(oc, ocm.enemies[0], ocm.enemies[0].components[0])
	t.assert_eq(ocm.effective_cost(oc), 3, "second card: full price")

	t.group("High Five: the 5th attack card in a turn resolves twice")
	var hf := _mech([["high_five", Vector2i(0, 0)]])
	hf.components.append(_gun("g", 1, 1, 0))
	var he := _dummy()
	var hcm := _cm(hf, [he] as Array[MechData])
	for i in range(5):
		hcm.reload(hf.get_component("g").cards[0]) # single-use: back in hand for the test
		hcm.play_attack_card(hf.get_component("g").cards[0], he, he.components[0])
	t.assert_eq(he.components[0].max_hp - he.components[0].current_hp, 6, "hits 1 + 1 + 1 + 1 + 2")

	t.group("Recycling Loops: heat vented by a card boosts the next attack")
	var rl := _mech([["recycling_loops", Vector2i(0, 0)], ["flare_array", Vector2i(2, 0)]])
	rl.components.append(_gun("g", 10, 1, 0))
	var re := _dummy()
	var rlcm := _cm(rl, [re] as Array[MechData])
	rl.current_heat = 5
	rlcm.play_self_card(_card(rl, "flare_array", "heat_eject")) # vents 3
	rlcm.play_attack_card(rl.get_component("g").cards[0], re, re.components[0])
	t.assert_eq(re.components[0].max_hp - re.components[0].current_hp, 13, "10 + 3 vented")

	t.group("Exhaust Fans: incoming Smoke −1")
	var ef := _mech([["exhaust_fans", Vector2i(0, 0)]])
	CardResolver.add_status_to(ef, null, "smoke", 3, true)
	t.assert_eq(ef.mech_status_stacks("smoke"), 2, "Smoke 3 lands as 2")

# ---------- protocols ----------

static func _protocols(t: TestContext) -> void:
	t.group("Protocols: priming, one of each, used by the next card they affect")
	var p := _mech([["targeting_computer", Vector2i(0, 0)]])
	p.components.append(_gun("g", 20, 1, 0))
	var e := _dummy()
	var cm := _cm(p, [e] as Array[MechData])
	var lock := _card(p, "targeting_computer", "lock_on")
	cm.play_self_card(lock)
	cm.play_self_card(lock)
	t.assert_eq(cm.primed.size(), 1, "Lock On primed once (a second prime does nothing)")
	t.assert_eq(p.current_heat, 0, "protocols cost no heat")
	cm.play_attack_card(p.get_component("g").cards[0], e, e.components[0])
	var d := e.components[0].max_hp - e.components[0].current_hp
	t.assert_eq(d, 20, "Lock On: a part that isn't attacking takes normal damage (×2 vs an attacker: TestProtocols)")
	t.assert_eq(cm.primed.size(), 0, "and it's used up")

	t.group("Protocols: one waits at a time; a new one replaces it")
	var op := _mech([["targeting_computer", Vector2i(0, 0)], ["munitions_splitter", Vector2i(0, 4)]])
	op.components.append(_gun("g", 10, 2, 0))
	var oe := _dummy()
	var ocm := _cm(op, [oe] as Array[MechData])
	var on := [0]
	ocm.hit_landed.connect(func(_m, _c, _d): on[0] += 1)
	ocm.play_self_card(_card(op, "targeting_computer", "lock_on"))
	ocm.play_self_card(_card(op, "munitions_splitter", "split_feed"))
	t.assert_eq(ocm.primed.size(), 1, "only one primed")
	t.assert_eq(ocm.primed[0]["type"], "split_feed", "the newest")
	ocm.play_attack_card(op.get_component("g").cards[0], oe, oe.components[0])
	t.assert_eq(oe.components[0].max_hp - oe.components[0].current_hp, 20, "Split Feed alone: 4 hits of 5, no Lock On")
	t.assert_eq(on[0], 4, "2 hits became 4")

	t.group("Split Feed: double the hits at half the damage")
	var sp := _mech([["munitions_splitter", Vector2i(0, 0)]])
	sp.components.append(_gun("g", 10, 2, 0))
	var se := _dummy()
	var scm := _cm(sp, [se] as Array[MechData])
	var n := [0]
	scm.hit_landed.connect(func(_m, _c, _d): n[0] += 1)
	scm.play_self_card(_card(sp, "munitions_splitter", "split_feed"))
	scm.play_attack_card(sp.get_component("g").cards[0], se, se.components[0])
	t.assert_eq(n[0], 4, "2 hits become 4")
	t.assert_eq(se.components[0].max_hp - se.components[0].current_hp, 20, "of 5 each")

	t.group("Catalyze: +2 stacks of every status the next card applies")
	var cp := _mech([["catalyst_injector", Vector2i(0, 0)], ["voltage_spike", Vector2i(3, 0)]])
	var ce := _dummy()
	var ccm := _cm(cp, [ce] as Array[MechData])
	ccm.play_self_card(_card(cp, "catalyst_injector", "catalyze"))
	ccm.play_attack_card(_card(cp, "voltage_spike", "spike_em"), ce, ce.components[0])
	t.assert_eq(ce.components[0].status_stacks("shock"), 4, "Shock 2 + 2")

	t.group("Reroute: swaps the next card's status for the one picked")
	var rp := _mech([["payload_converter", Vector2i(0, 0)], ["voltage_spike", Vector2i(3, 0)]])
	var re := _dummy()
	var rcm := _cm(rp, [re] as Array[MechData])
	rcm.play_self_card(_card(rp, "payload_converter", "reroute"), {"status": "burn"})
	rcm.play_attack_card(_card(rp, "voltage_spike", "spike_em"), re, re.components[0])
	t.assert_eq(re.components[0].status_stacks("burn"), 2, "Shock 2 became Burn 2")
	t.assert_eq(re.components[0].status_stacks("shock"), 0, "no Shock")

	t.group("Standby: the next card is set aside and plays itself next turn for 0 heat")
	var qp := _mech([["queue_processor", Vector2i(0, 0)]])
	qp.components.append(_gun("g", 7, 1, 3))
	var qe := _dummy()
	var qcm := _cm(qp, [qe] as Array[MechData])
	qcm.play_self_card(_card(qp, "queue_processor", "standby"))
	qcm.play_attack_card(qp.get_component("g").cards[0], qe, qe.components[0])
	t.assert_eq(qe.components[0].current_hp, qe.components[0].max_hp, "nothing happens now")
	t.assert_eq(qp.current_heat, 0, "and no heat paid")
	qcm.end_player_turn()
	t.assert_eq(qe.components[0].max_hp - qe.components[0].current_hp, 7, "it fires at the start of the next turn")

	t.group("Overdrive: the hit, then the part that played it is Disabled")
	var odp := _mech([["overdrive_chip", Vector2i(0, 0)]])
	odp.components.append(_gun("g", 9, 1, 0))
	var ode := _dummy()
	var odcm := _cm(odp, [ode] as Array[MechData])
	odcm.play_self_card(_card(odp, "overdrive_chip", "overdrive"))
	odcm.play_attack_card(odp.get_component("g").cards[0], ode, ode.components[0])
	t.assert_eq(ode.components[0].max_hp - ode.components[0].current_hp, 9, "9 (and every other hardpoint of the target: TestProtocols)")
	t.assert_eq(odp.get_component("g").status_stacks("disabled"), 1, "the gun is Disabled")

	t.group("Replay: the last card again, same target, for its heat +2")
	var ep := _mech([["echo_buffer", Vector2i(0, 0)]])
	ep.components.append(_gun("g", 6, 1, 1))
	var ee := _dummy()
	var ecm := _cm(ep, [ee] as Array[MechData])
	t.assert_eq(ecm.play_self_card(_card(ep, "echo_buffer", "replay"))["reason"], "nothing_to_replay", "nothing played yet: refused")
	ecm.play_attack_card(ep.get_component("g").cards[0], ee, ee.components[0])
	var rr := ecm.play_self_card(_card(ep, "echo_buffer", "replay"))
	if rr.get("started_attack", false):
		ecm.finish_attack()
	t.assert_eq(ee.components[0].max_hp - ee.components[0].current_hp, 12, "hit twice")
	t.assert_eq(ep.current_heat, 1 + 3, "1 heat, then 1 + 2")

	t.group("Salvo: every hardpoint in the relay's row fires its cheapest attack")
	var fp := _mech([["fire_control_relay", Vector2i(0, 2)]])
	fp.components.append(_gun("left", 4, 1, 1, Vector2i(0, 0)))
	fp.components.append(_gun("right", 5, 1, 2, Vector2i(0, 5)))
	fp.components.append(_gun("other_row", 50, 1, 1, Vector2i(3, 3)))
	var fe := _dummy()
	var fcm := _cm(fp, [fe] as Array[MechData])
	fcm.play_attack_card(_card(fp, "fire_control_relay", "salvo"), fe, fe.components[0])
	t.assert_eq(fe.components[0].max_hp - fe.components[0].current_hp, 9, "4 + 5 from the two guns in its row")
	t.assert_eq(fp.current_heat, 3, "paying their heat (1 + 2)")

	t.group("Bleed Off: the next card's heat is paid in HP by the part linked above")
	var bp := _mech([["thermal_transfer_bus", Vector2i(2, 0)]])
	bp.components.append(_gun("g", 1, 1, 4, Vector2i(5, 5)))
	var payer := _gun("payer", 1, 1, 1, Vector2i(1, 1)) # above the bus's (0,1) cell at (2,1)
	bp.components.append(payer)
	var bcm := _cm(bp, [_dummy()] as Array[MechData])
	bcm.play_self_card(_card(bp, "thermal_transfer_bus", "bleed_off"))
	bcm.play_attack_card(bp.get_component("g").cards[0], bcm.enemies[0], bcm.enemies[0].components[0])
	t.assert_eq(bp.current_heat, 0, "no heat")
	t.assert_eq(payer.max_hp - payer.current_hp, 4, "the linked part paid 4 HP")

	t.group("Intercept: a one-use copy of the enemy's next planned attack")
	var ip := _mech([["signal_interceptor", Vector2i(0, 0)]])
	var iw := DataLoader.load_mech_from_file("res://tests/fixtures/scrap_warden_classic.json")
	var icm := _cm(ip, [iw] as Array[MechData], 4)
	var planned: CardData = icm.enemy_plans[iw][0]["card"]
	icm.play_attack_card(_card(ip, "signal_interceptor", "intercept"), iw, iw.components[0])
	t.assert_eq(icm.bonus_cards.size(), 1, "a card joins the hand")
	var copy: CardData = icm.bonus_cards[0]
	t.assert_eq([copy.hits, copy.damage_min, copy.damage_max], [planned.hits, planned.damage_min, planned.damage_max], "a copy of %s, damage range included" % planned.name)
	t.assert_true(icm.hand_cards().has(copy), "playable from the hand")
	icm.play_attack_card(copy, iw, iw.get_component("scatter_shot"))
	t.assert_eq(icm.bonus_cards.size(), 0, "one use")

# ---------- links ----------

static func _links(t: TestContext) -> void:
	t.group("Links: facing arrows turn with the part")
	t.assert_eq(Links.rotate_dir("up", 1), "right", "up turned once is right")
	t.assert_eq(Links.rotate_dir("up", 2), "down", "twice is down")
	t.assert_eq(Links.rotate_dir("left", 3), "down", "left turned 3 times is down")
	var m := _mech([["fire_control_relay", Vector2i(1, 1)]])
	var reached := Links.reached_cells(m, m.get_component("fire_control_relay"), ["left", "right"], Links.REACH_VECTOR)
	t.assert_eq(reached.size(), 3, "a 3-wide relay at column 1 reaches the rest of its row (6 − 3 = 3 cells)")

	t.group("Every Refit Bay part is implemented")
	var missing := []
	for id in ComponentLibrary.all_ids():
		if not ComponentLibrary.is_implemented(id):
			missing.append(id)
	t.assert_eq(missing, [], "all 112 parts play")

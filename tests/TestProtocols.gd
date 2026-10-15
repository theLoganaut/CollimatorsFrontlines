class_name TestProtocols
extends RefCounted
## Every protocol card, checked against its card text as written today
## (Logan, 2026-10-15: a protocol audit). One group per protocol part; the
## assertion messages quote the text they check. Numbers are Refit Bay's
## (run_tests turns the combat scaling off).

## A player mech with these Refit Bay parts ([id, cell, rotation]) and a
## 1-cell test gun "g" (dmg × hits, heat) at (5,5).
static func _player(parts: Array, dmg: int = 10, hits: int = 1, heat: int = 1) -> MechData:
	var p := TestEffects._mech(parts, 40)
	p.components.append(TestEffects._gun("g", dmg, hits, heat))
	return p

## An enemy with two parts side by side: "gun" (shows an attack this turn
## once _plan() is called) and "plate" (never attacks). 300 HP each.
static func _enemy() -> MechData:
	var shot := TestFixtures.make_card("e_shot", "gun", 1, 1, 8, 8)
	var gun := TestFixtures.make_component("gun", 300, [shot] as Array[CardData])
	gun.library_id = "gun"
	var plate := TestFixtures.make_component("plate", 300)
	plate.library_id = "plate"
	gun.placed_cells = [Vector2i(0, 0)]
	plate.placed_cells = [Vector2i(0, 1)] # side by side
	var m := TestFixtures.make_mech("target", 20, [gun, plate] as Array[ComponentData])
	return m

## The enemy shows its gun's attack this turn (an intent).
static func _plan(cm: CombatManager, e: MechData) -> void:
	var gun := e.get_component("gun")
	cm.enemy_plans[e] = [{"component": gun, "card": gun.cards[0], "target": cm.player_mech.components[0]}]

static func _card(m: MechData, comp_id: String, card_id: String) -> CardData:
	return TestEffects._card(m, comp_id, card_id)

static func _lost(c: ComponentData) -> int:
	return c.max_hp - c.current_hp

static func _gun(m: MechData) -> CardData:
	return m.get_component("g").cards[0]

## Plays a card at a part and lets any attack it starts finish.
static func _hit(cm: CombatManager, card: CardData, mech: MechData, comp: ComponentData) -> Dictionary:
	cm.reload(card)
	var r := cm.play_attack_card(card, mech, comp)
	if cm.has_pending_attack():
		cm.finish_attack()
	return r

static func _self(cm: CombatManager, card: CardData, options: Dictionary = {}) -> Dictionary:
	cm.reload(card)
	var r := cm.play_self_card(card, options)
	if r.get("started_attack", false) and cm.has_pending_attack():
		cm.finish_attack()
	return r

## The enemy's gun fires its card at one of the player's parts now.
static func _enemy_hits(cm: CombatManager, e: MechData, target: ComponentData) -> int:
	var before := target.current_hp
	var gun := e.get_component("gun")
	cm._attack = {}
	CombatAttack.start(cm, gun.cards[0], e, gun, cm.player_mech, target, {})
	CombatAttack.resolve_now(cm, cm.player_mech, target)
	return before - target.current_hp

static func run_all(t: TestContext) -> void:
	_echo_buffer(t)
	_targeting_computer(t)
	_munitions_splitter(t)
	_catalyst_injector(t)
	_payload_converter(t)
	_queue_processor(t)
	_overdrive_chip(t)
	_thermal_transfer_bus(t)
	_signal_interceptor(t)
	_quickload_chip(t)
	_scatter_link(t)
	_siphon_driver(t)
	_breach_charge(t)
	_chain_relay(t)
	_hydraulic_ram(t)
	_ballast_tank(t)
	_tactical_uplink(t)
	_kill_switch(t)
	_coordinated_strike(t)
	_rampart(t)
	_probability_engine(t)
	_salvage_recursor(t)
	_feedback_loop(t)
	_polarity_inverter(t)
	_last_stand(t)
	_as_read(t)

static func _echo_buffer(t: TestContext) -> void:
	t.group("Protocols · Echo Buffer")
	var p := _player([["echo_buffer", Vector2i(0, 0)], ["targeting_computer", Vector2i(0, 3)]], 6, 1, 1)
	var e := _enemy()
	var cm := TestEffects._cm(p, [e] as Array[MechData])
	_hit(cm, _gun(p), e, e.get_component("plate"))
	_self(cm, _card(p, "targeting_computer", "zero_lock")) # a protocol card in between
	cm.primed.clear()
	var r := _self(cm, _card(p, "echo_buffer", "replay"))
	t.assert_true(r.get("ok", false), "Replay: plays after a protocol card was used")
	t.assert_eq(_lost(e.get_component("plate")), 12, "Replay: \"the last hardpoint card you used\" hits again (6 + 6)")
	t.assert_eq(p.current_heat, 1 + 3, "Replay: \"for +2 Heat\" (1, then 1 + 2)")

	var p2 := _player([["echo_buffer", Vector2i(0, 0)]])
	var e2 := _enemy()
	var cm2 := TestEffects._cm(p2, [e2] as Array[MechData])
	var lock := _card(p2, "echo_buffer", "replay") # any protocol card will do as the enemy's
	cm2.enemy_primed[e2] = [{"type": "pierce", "card": lock, "component": e2.get_component("gun")}]
	_self(cm2, _card(p2, "echo_buffer", "echo"))
	t.assert_true(not cm2.enemy_primed.has(e2) or (cm2.enemy_primed[e2] as Array).is_empty(), "Echo: \"Take the protocol an enemy has waiting\": the enemy loses it")
	t.assert_true(cm2.primed.any(func(x): return x["type"] == "pierce"), "Echo: \"it's primed for you instead\"")

static func _targeting_computer(t: TestContext) -> void:
	t.group("Protocols · Targeting Computer")
	var p := _player([["targeting_computer", Vector2i(0, 0)]], 10)
	var e := _enemy()
	var cm := TestEffects._cm(p, [e] as Array[MechData])
	_plan(cm, e)
	_self(cm, _card(p, "targeting_computer", "lock_on"))
	_hit(cm, _gun(p), e, e.get_component("gun"))
	t.assert_eq(_lost(e.get_component("gun")), 20, "Lock On: \"double damage vs a part attacking this turn\" (10 × 2)")
	_self(cm, _card(p, "targeting_computer", "lock_on"))
	_hit(cm, _gun(p), e, e.get_component("plate"))
	t.assert_eq(_lost(e.get_component("plate")), 10, "Lock On: a part not attacking takes normal damage")

	var p2 := _player([["targeting_computer", Vector2i(0, 0)]], 10, 4)
	var e2 := _enemy()
	e2.add_mech_status("deflect", 3)
	var cm2 := TestEffects._cm(p2, [e2] as Array[MechData])
	var landed := [0]
	cm2.hit_landed.connect(func(_m, _c, _d): landed[0] += 1)
	_self(cm2, _card(p2, "targeting_computer", "zero_lock"))
	_hit(cm2, _gun(p2), e2, e2.get_component("plate"))
	t.assert_eq(landed[0], 4, "Zero Lock: \"every hit lands\" (4 of 4)")

static func _munitions_splitter(t: TestContext) -> void:
	t.group("Protocols · Munitions Splitter")
	var p := _player([["munitions_splitter", Vector2i(0, 0)]], 10, 2)
	var e := _enemy()
	var cm := TestEffects._cm(p, [e] as Array[MechData])
	var n := [0]
	cm.hit_landed.connect(func(_m, _c, _d): n[0] += 1)
	_self(cm, _card(p, "munitions_splitter", "split_feed"))
	_hit(cm, _gun(p), e, e.get_component("plate"))
	t.assert_eq(n[0], 4, "Split Feed: \"double the hits\" (2 → 4)")
	t.assert_eq(_lost(e.get_component("plate")), 20, "Split Feed: \"at half the damage per hit\" (4 × 5)")

	var p2 := _player([["munitions_splitter", Vector2i(0, 0)]], 10)
	var e2 := _enemy()
	var cm2 := TestEffects._cm(p2, [e2] as Array[MechData])
	_self(cm2, _card(p2, "munitions_splitter", "ricochet_feed"))
	_hit(cm2, _gun(p2), e2, e2.get_component("plate"))
	t.assert_eq(_lost(e2.get_component("plate")), 10, "Ricochet Feed: the target takes the hit")
	t.assert_true(_lost(e2.get_component("gun")) > 0, "Ricochet Feed: \"also hits an adjacent part\"")

static func _catalyst_injector(t: TestContext) -> void:
	t.group("Protocols · Catalyst Injector")
	var p := _player([["catalyst_injector", Vector2i(0, 0)], ["voltage_spike", Vector2i(3, 0)]])
	var e := _enemy()
	var cm := TestEffects._cm(p, [e] as Array[MechData])
	_self(cm, _card(p, "catalyst_injector", "catalyze"))
	_hit(cm, _card(p, "voltage_spike", "spike_em"), e, e.get_component("plate"))
	t.assert_eq(e.get_component("plate").status_stacks("shock"), 4, "Catalyze: \"+2 stacks of every status it already applies\" (Shock 2 → 4)")

	var p2 := _player([["catalyst_injector", Vector2i(0, 0)], ["voltage_spike", Vector2i(3, 0)]])
	var cm2 := TestEffects._cm(p2, [_enemy()] as Array[MechData])
	var vs := p2.get_component("voltage_spike")
	vs.add_status("shock", 2)
	vs.add_status("acid", 2)
	vs.add_status("burn", 2)
	_self(cm2, _card(p2, "catalyst_injector", "purify"))
	_self(cm2, _card(p2, "voltage_spike", "spike_setup")) # a card that targets your own mech
	t.assert_eq([vs.status_stacks("shock"), vs.status_stacks("acid"), vs.status_stacks("burn")], [0, 0, 0],
		"Purify: \"Your next card that targets your own mech also removes Shock, Acid and Burn from your parts\"")

static func _payload_converter(t: TestContext) -> void:
	t.group("Protocols · Payload Converter")
	t.assert_true(not CombatManager.REROUTE_OPTIONS.has("disabled"), "Reroute: Disabled isn't a choice any more")
	var p := _player([["payload_converter", Vector2i(0, 0)], ["voltage_spike", Vector2i(3, 0)]])
	var e := _enemy()
	var cm := TestEffects._cm(p, [e] as Array[MechData])
	_self(cm, _card(p, "payload_converter", "reroute"), {"status": "burn"})
	_hit(cm, _card(p, "voltage_spike", "spike_em"), e, e.get_component("plate"))
	t.assert_eq([e.get_component("plate").status_stacks("burn"), e.get_component("plate").status_stacks("shock")], [2, 0],
		"Reroute: \"Swap the status on your next card for a different one\" (Shock 2 → Burn 2)")

	var p2 := _player([["payload_converter", Vector2i(0, 0)]], 10)
	var e2 := _enemy()
	var cm2 := TestEffects._cm(p2, [e2] as Array[MechData])
	e2.get_component("plate").add_status("burn", 3)
	_self(cm2, _card(p2, "payload_converter", "detonate"))
	_hit(cm2, _gun(p2), e2, e2.get_component("plate"))
	t.assert_eq(_lost(e2.get_component("plate")), 10 + 12, "Detonate: \"+4 damage per stack\" of Burn (10 + 3 × 4)")
	t.assert_eq(e2.get_component("plate").status_stacks("burn"), 0, "Detonate: \"consumes the target's Burn\"")

static func _queue_processor(t: TestContext) -> void:
	t.group("Protocols · Queue Processor")
	var p := _player([["queue_processor", Vector2i(0, 0)]], 7, 1, 3)
	var e := _enemy()
	var cm := TestEffects._cm(p, [e] as Array[MechData])
	cm.auto_resolve_enemy_turn = true
	_self(cm, _card(p, "queue_processor", "standby"))
	_hit(cm, _gun(p), e, e.get_component("plate"))
	t.assert_eq(_lost(e.get_component("plate")), 0, "Standby: \"Set a card aside\" (nothing now)")
	t.assert_eq(p.current_heat, 0, "Standby: no Heat now")
	cm.end_player_turn()
	t.assert_eq(_lost(e.get_component("plate")), 7, "Standby: \"it plays automatically at the start of your next turn\"")

	var p2 := _player([["queue_processor", Vector2i(0, 0)]], 7, 1, 3)
	var e2 := _enemy()
	var cm2 := TestEffects._cm(p2, [e2] as Array[MechData])
	_self(cm2, _card(p2, "queue_processor", "batch"))
	_hit(cm2, _gun(p2), e2, e2.get_component("plate"))
	t.assert_eq(p2.current_heat, 0, "Batch: \"Your next card costs 0 Heat now\"")
	t.assert_eq(_lost(e2.get_component("plate")), 7, "Batch: the card still plays now")
	var heat_before_vent := cm2.deferred_heat
	t.assert_eq(heat_before_vent, 3, "Batch: \"you pay its Heat at the start of your next turn\" (3 owed)")

static func _overdrive_chip(t: TestContext) -> void:
	t.group("Protocols · Overdrive Chip")
	var p := _player([["overdrive_chip", Vector2i(0, 0)]], 9, 1, 0)
	var e := _enemy()
	var hp2 := TestFixtures.make_component("gun2", 300, [TestFixtures.make_card("s2", "gun2", 1, 1, 5, 5)] as Array[CardData])
	hp2.library_id = "gun2"
	e.components.append(hp2)
	var cm := TestEffects._cm(p, [e] as Array[MechData])
	_self(cm, _card(p, "overdrive_chip", "overdrive"))
	_hit(cm, _gun(p), e, e.get_component("gun"))
	t.assert_eq(_lost(e.get_component("gun")), 9, "Overdrive: the target takes the hit")
	t.assert_eq(_lost(e.get_component("gun2")), 9, "Overdrive: \"also hits every other hardpoint of the target mech\"")
	t.assert_eq(p.get_component("g").status_stacks("disabled"), 1, "Overdrive: \"then the part that played it is Disabled\"")

	var p2 := _player([["overdrive_chip", Vector2i(0, 0)]], 5, 1, 4)
	var cm2 := TestEffects._cm(p2, [_enemy()] as Array[MechData])
	_self(cm2, _card(p2, "overdrive_chip", "overclock"))
	t.assert_eq(p2.get_component("overdrive_chip").status_stacks("burn"), 1, "Overclock: \"Burn 1 on this part\"")
	_hit(cm2, _gun(p2), cm2.enemies[0], cm2.enemies[0].get_component("plate"))
	t.assert_eq(p2.current_heat, 2, "Overclock: \"Your next card costs 2 less Heat\" (4 → 2)")

static func _thermal_transfer_bus(t: TestContext) -> void:
	t.group("Protocols · Thermal Transfer Bus")
	# Bleed Off is checked with its link in TestEffects ("Bleed Off: ...").
	var p := _player([["thermal_transfer_bus", Vector2i(0, 0)]], 5, 1, 1)
	var e := _enemy()
	var cm := TestEffects._cm(p, [e] as Array[MechData])
	p.current_heat = 10
	e.current_heat = 0
	_self(cm, _card(p, "thermal_transfer_bus", "heat_transfer"))
	_hit(cm, _gun(p), e, e.get_component("plate"))
	t.assert_eq(e.current_heat, 3, "Heat Transfer: \"moves 3 of your Heat onto the target mech\" (it gains 3)")
	t.assert_eq(p.current_heat, 10 + 1 - 3, "Heat Transfer: and you lose 3 (10 + 1 for the card − 3)")

static func _signal_interceptor(t: TestContext) -> void:
	t.group("Protocols · Signal Interceptor")
	# Intercept is checked in TestEffects ("Intercept: ...").
	var p := _player([["signal_interceptor", Vector2i(0, 0)]])
	var e := _enemy()
	var e2 := _enemy()
	var cm := TestEffects._cm(p, [e, e2] as Array[MechData])
	var any_card := _card(p, "signal_interceptor", "intercept")
	cm.enemy_primed[e] = [{"type": "pierce", "card": any_card, "component": e.get_component("gun")}]
	cm.enemy_primed[e2] = [{"type": "max_roll", "card": any_card, "component": e2.get_component("gun")}]
	_self(cm, _card(p, "signal_interceptor", "scramble_signal"))
	var left := 0
	for m in cm.enemy_primed:
		left += (cm.enemy_primed[m] as Array).size()
	t.assert_eq(left, 0, "Scramble Signal: \"Clear every protocol the enemies have waiting\"")

static func _quickload_chip(t: TestContext) -> void:
	t.group("Protocols · Quickload Chip")
	var p := _player([["quickload_chip", Vector2i(0, 0)]], 5, 1, 5)
	var cm := TestEffects._cm(p, [_enemy()] as Array[MechData])
	_self(cm, _card(p, "quickload_chip", "quickload"))
	t.assert_eq(p.mech_status_stacks("smoke"), 1, "Quickload: \"Smoke 1 on your mech\"")
	_hit(cm, _gun(p), cm.enemies[0], cm.enemies[0].get_component("plate"))
	t.assert_eq(p.current_heat, 2, "Quickload: \"Next card costs 3 less Heat\" (5 → 2)")

	var p2 := _player([["quickload_chip", Vector2i(0, 0)]], 5, 1, 5)
	var cm2 := TestEffects._cm(p2, [_enemy()] as Array[MechData])
	p2.current_heat = 10
	_self(cm2, _card(p2, "quickload_chip", "borrow_time"))
	t.assert_eq(p2.current_heat, 8, "Borrow Time: \"Vent 2\"")
	_hit(cm2, _gun(p2), cm2.enemies[0], cm2.enemies[0].get_component("plate"))
	t.assert_eq(p2.current_heat, 8 + 6, "Borrow Time: \"Your next card costs 1 more Heat\" (5 → 6)")

static func _scatter_link(t: TestContext) -> void:
	t.group("Protocols · Scatter Link")
	var p := _player([["scatter_link", Vector2i(0, 0)]], 10)
	var e := _enemy()
	var e2 := _enemy()
	var cm := TestEffects._cm(p, [e, e2] as Array[MechData])
	_self(cm, _card(p, "scatter_link", "fan_out"))
	_hit(cm, _gun(p), e, e.get_component("plate"))
	t.assert_eq(_lost(e.get_component("plate")), 10, "Fan Out: the target takes the hit")
	var other := _lost(e2.get_component("gun")) + _lost(e2.get_component("plate"))
	t.assert_true(other > 0, "Fan Out: \"Next attack also hits every other enemy\"")

	var p2 := _player([["scatter_link", Vector2i(0, 0)]])
	var e3 := _enemy()
	var cm2 := TestEffects._cm(p2, [e3] as Array[MechData])
	_self(cm2, _card(p2, "scatter_link", "ghost_signal"))
	t.assert_eq(p2.current_heat, 2, "Ghost Signal: costs 2 Heat")
	var picked := {}
	for i in range(20):
		var target := p2.get_component("g")
		var before := {}
		for c in p2.components:
			before[c] = c.current_hp
		_enemy_hits(cm2, e3, target)
		for c in p2.components:
			if c.current_hp < before[c]:
				picked[c] = true
		for c in p2.components:
			c.current_hp = c.max_hp
	t.assert_true(picked.size() > 1, "Ghost Signal: \"enemy attacks hit random parts of yours\" (%d different parts hit)" % picked.size())

static func _siphon_driver(t: TestContext) -> void:
	t.group("Protocols · Siphon Driver")
	var p := _player([["siphon_driver", Vector2i(0, 0)]], 20)
	var e := _enemy()
	var cm := TestEffects._cm(p, [e] as Array[MechData])
	var hurt := p.get_component("siphon_driver")
	hurt.current_hp = hurt.max_hp - 15
	_self(cm, _card(p, "siphon_driver", "siphon"))
	_hit(cm, _gun(p), e, e.get_component("plate"))
	t.assert_eq(hurt.max_hp - hurt.current_hp, 5, "Siphon: \"Reclaim 50%\": 20 dealt heals your most damaged part 10")

	var p2 := _player([["siphon_driver", Vector2i(0, 0)]], 20)
	var e2 := _enemy()
	e2.add_mech_status("deflect", 4)
	e2.add_mech_status("absorb", 3)
	var cm2 := TestEffects._cm(p2, [e2] as Array[MechData])
	_self(cm2, _card(p2, "siphon_driver", "leech_field"))
	_hit(cm2, _gun(p2), e2, e2.get_component("plate"))
	t.assert_eq([e2.mech_status_stacks("deflect"), e2.mech_status_stacks("absorb")], [0, 0], "Leech Field: the target mech loses its Deflect and Absorb")
	t.assert_eq([p2.mech_status_stacks("deflect"), p2.mech_status_stacks("absorb")], [4, 3], "Leech Field: \"for your mech\"")

static func _breach_charge(t: TestContext) -> void:
	t.group("Protocols · Breach Charge")
	var p := _player([["breach_charge", Vector2i(0, 0)]], 10)
	var e := _enemy()
	e.add_mech_status("deflect", 50)
	var cm := TestEffects._cm(p, [e] as Array[MechData])
	_self(cm, _card(p, "breach_charge", "breach"))
	_hit(cm, _gun(p), e, e.get_component("plate"))
	t.assert_eq(_lost(e.get_component("plate")), 10, "Breach: \"Next attack: Pierce\" (straight through Deflect 50)")

	var p2 := _player([["breach_charge", Vector2i(0, 0)]], 10)
	var e2 := _enemy()
	var cm2 := TestEffects._cm(p2, [e2] as Array[MechData])
	_self(cm2, _card(p2, "breach_charge", "crack_open"))
	_hit(cm2, _gun(p2), e2, e2.get_component("plate"))
	t.assert_eq(e2.get_component("plate").status_stacks("acid"), 2, "Crack Open: \"also applies Acid 2\"")

static func _chain_relay(t: TestContext) -> void:
	t.group("Protocols · Chain Relay")
	var p := _player([["chain_relay", Vector2i(0, 0)], ["voltage_spike", Vector2i(3, 0)]])
	var e := TestEffects._dummy(300)
	var left := TestFixtures.make_component("left", 100)
	left.library_id = "left"
	e.components[0].placed_cells = [Vector2i(1, 1)]
	left.placed_cells = [Vector2i(1, 0)]
	var far := TestFixtures.make_component("far", 100)
	far.library_id = "far"
	far.placed_cells = [Vector2i(4, 4)]
	e.components.append(left)
	e.components.append(far)
	var cm := TestEffects._cm(p, [e] as Array[MechData])
	_self(cm, _card(p, "chain_relay", "chain"))
	_hit(cm, _card(p, "voltage_spike", "spike_em"), e, e.components[0])
	t.assert_eq(left.status_stacks("shock"), 2, "Chain: \"statuses also land on every part adjacent to its target\"")
	t.assert_eq(far.status_stacks("shock"), 0, "Chain: not on a part that isn't adjacent")

	var p2 := _player([["chain_relay", Vector2i(0, 0)]])
	var e2 := _enemy()
	var cm2 := TestEffects._cm(p2, [e2] as Array[MechData])
	_self(cm2, _card(p2, "chain_relay", "backlash_link"))
	_enemy_hits(cm2, e2, p2.get_component("g"))
	t.assert_eq(e2.get_component("gun").status_stacks("jam"), 1, "Backlash Link: \"every enemy part that hits you gets Jam 1\"")

static func _hydraulic_ram(t: TestContext) -> void:
	t.group("Protocols · Hydraulic Ram")
	var p := _player([["hydraulic_ram", Vector2i(0, 0)]], 10)
	var e := _enemy()
	var cm := TestEffects._cm(p, [e] as Array[MechData])
	_self(cm, _card(p, "hydraulic_ram", "ram"))
	_hit(cm, _gun(p), e, e.get_component("plate"))
	t.assert_eq(e.get_component("plate").status_stacks("disabled"), 1, "Ram: \"Next attack also applies Disabled 1\"")
	t.assert_eq(p.get_component("g").status_stacks("disabled"), 1, "Ram: \"the part that plays it is Disabled 1\"")

	var p2 := _player([["hydraulic_ram", Vector2i(0, 0)]], 10)
	var e2 := _enemy()
	var cm2 := TestEffects._cm(p2, [e2] as Array[MechData])
	_plan(cm2, e2)
	_self(cm2, _card(p2, "hydraulic_ram", "push_back"))
	_hit(cm2, _gun(p2), e2, e2.get_component("gun"))
	t.assert_true(cm2.turned.has(e2.get_component("gun")), "Push Back: \"vs a part attacking this turn, its attacks this turn hit its own mech\"")

static func _ballast_tank(t: TestContext) -> void:
	t.group("Protocols · Ballast Tank")
	var p := _player([["ballast_tank", Vector2i(0, 0)]], 5, 1, 6)
	var cm := TestEffects._cm(p, [_enemy()] as Array[MechData])
	_self(cm, _card(p, "ballast_tank", "ballast"))
	t.assert_eq(p.mech_status_stacks("smoke"), 2, "Ballast: \"Smoke 2 on your mech\"")
	_hit(cm, _gun(p), cm.enemies[0], cm.enemies[0].get_component("plate"))
	t.assert_eq(p.current_heat, 2, "Ballast: \"Next card costs 4 less Heat\" (6 → 2)")

	var p2 := _player([["ballast_tank", Vector2i(0, 0)]])
	var cm2 := TestEffects._cm(p2, [_enemy()] as Array[MechData])
	_self(cm2, _card(p2, "ballast_tank", "ballast_brace"))
	t.assert_eq([p2.mech_status_stacks("deflect"), p2.mech_status_stacks("smoke"), p2.current_heat], [6, 1, 2], "Ballast Brace: Deflect 6 and Smoke 1 on your mech, for 2 Heat")

static func _tactical_uplink(t: TestContext) -> void:
	t.group("Protocols · Tactical Uplink")
	var p := _player([["tactical_uplink", Vector2i(0, 0)]], 10)
	var e := _enemy()
	var cm := TestEffects._cm(p, [e] as Array[MechData])
	_plan(cm, e)
	_self(cm, _card(p, "tactical_uplink", "double_tap"))
	_hit(cm, _gun(p), e, e.get_component("plate"))
	t.assert_eq(_lost(e.get_component("plate")), 10, "Double Tap: the target takes the hit")
	t.assert_eq(_lost(e.get_component("gun")), 10, "Double Tap: \"also hits the enemy part with the biggest attack shown this turn\"")

	var p3 := _player([["tactical_uplink", Vector2i(0, 0)]], 10)
	var e3 := _enemy()
	var cm3 := TestEffects._cm(p3, [e3] as Array[MechData])
	cm3.enemy_plans[e3] = [] # nothing shown this turn
	_self(cm3, _card(p3, "tactical_uplink", "double_tap"))
	_hit(cm3, _gun(p3), e3, e3.get_component("plate"))
	t.assert_eq(_lost(e3.get_component("plate")) + _lost(e3.get_component("gun")), 10, "Double Tap: with no attack shown, there's nothing more to hit")

	var p2 := _player([["tactical_uplink", Vector2i(0, 0)]], 10)
	var e2 := _enemy()
	var cm2 := TestEffects._cm(p2, [e2] as Array[MechData])
	_plan(cm2, e2)
	_self(cm2, _card(p2, "tactical_uplink", "overlay"))
	_hit(cm2, _gun(p2), e2, e2.get_component("gun"))
	t.assert_eq(e2.get_component("gun").status_stacks("shock"), 2, "Overlay: \"Vs a part attacking this turn: Shock 2\"")

static func _kill_switch(t: TestContext) -> void:
	t.group("Protocols · Kill Switch")
	var p := _player([["kill_switch", Vector2i(0, 0)]], 10)
	var e := _enemy()
	var cm := TestEffects._cm(p, [e] as Array[MechData])
	e.get_component("plate").current_hp = 150
	_self(cm, _card(p, "kill_switch", "execute"))
	_hit(cm, _gun(p), e, e.get_component("plate"))
	t.assert_eq(e.get_component("plate").current_hp, 120, "Execute: \"triple damage vs a part at or below half HP\" (150 → 120)")
	_self(cm, _card(p, "kill_switch", "execute"))
	_hit(cm, _gun(p), e, e.get_component("gun"))
	t.assert_eq(_lost(e.get_component("gun")), 10, "Execute: a part above half HP takes normal damage")

	var p2 := _player([["kill_switch", Vector2i(0, 0)]], 10)
	var e2 := _enemy()
	var cm2 := TestEffects._cm(p2, [e2] as Array[MechData])
	e2.get_component("plate").current_hp = 5
	p2.current_heat = 8
	_self(cm2, _card(p2, "kill_switch", "kill_order"))
	_hit(cm2, _gun(p2), e2, e2.get_component("plate"))
	t.assert_eq(p2.current_heat, 8 + 1 - 5, "Kill Order: \"if it destroys a part, Vent 5\"")

static func _coordinated_strike(t: TestContext) -> void:
	t.group("Protocols · Coordinated Strike Suite")
	# Coordinated Strike is a Salvo (checked with its links in TestEffects).
	var p := _player([["coordinated_strike_suite", Vector2i(0, 0)]])
	var e := _enemy()
	var cm := TestEffects._cm(p, [e] as Array[MechData])
	_self(cm, _card(p, "coordinated_strike_suite", "hold_the_line"))
	var shot := TestFixtures.make_card("big", "gun", 1, 1, 30, 30)
	e.get_component("gun").cards[0] = shot
	var took := _enemy_hits(cm, e, p.get_component("g"))
	t.assert_eq(took, 12, "Hold the Line: \"no hit deals more than 12 to one of your parts\" (30 → 12)")

static func _rampart(t: TestContext) -> void:
	t.group("Protocols · Rampart Protocol")
	var p := _player([["rampart_protocol", Vector2i(0, 0)]], 1, 1, 4)
	var cm := TestEffects._cm(p, [_enemy()] as Array[MechData])
	_self(cm, _card(p, "rampart_protocol", "fortify"))
	_hit(cm, _gun(p), cm.enemies[0], cm.enemies[0].get_component("plate"))
	t.assert_eq(p.mech_status_stacks("deflect"), 16, "Fortify: \"gain Deflect 4 per Heat it costs\" (4 Heat → 16)")

	var p2 := _player([["rampart_protocol", Vector2i(0, 0)], ["ballast_tank", Vector2i(3, 0)]])
	var e2 := _enemy()
	var cm2 := TestEffects._cm(p2, [e2] as Array[MechData])
	_self(cm2, _card(p2, "rampart_protocol", "rampart"))
	_self(cm2, _card(p2, "ballast_tank", "ballast_brace")) # a shield card
	p2.clear_mech_status("deflect")
	_enemy_hits(cm2, e2, p2.get_component("g"))
	t.assert_eq(_lost(e2.get_component("gun")), 4, "Rampart: \"every enemy part that hits you takes 4\"")

static func _probability_engine(t: TestContext) -> void:
	t.group("Protocols · Probability Engine")
	var p := _player([["probability_engine", Vector2i(0, 0)], ["needle_carbine", Vector2i(2, 0)]])
	var e := TestEffects._dummy(9999)
	var cm := TestEffects._cm(p, [e] as Array[MechData])
	var needle := _card(p, "needle_carbine", "needle_storm")
	_self(cm, _card(p, "probability_engine", "loaded_dice"))
	_hit(cm, needle, e, e.components[0])
	t.assert_eq(_lost(e.components[0]), needle.hits * needle.damage_max, "Loaded Dice: \"never misses and rolls max damage\" (%d × %d)" % [needle.hits, needle.damage_max])
	var before := _lost(e.components[0])
	_hit(cm, needle, e, e.components[0])
	t.assert_true(_lost(e.components[0]) - before <= needle.hits * needle.damage_min, "Loaded Dice: \"the attack after it rolls min damage\"")

	var p2 := _player([["probability_engine", Vector2i(0, 0)]], 10)
	var e2 := _enemy()
	var cm2 := TestEffects._cm(p2, [e2] as Array[MechData])
	e2.get_component("plate").current_hp = 70
	_self(cm2, _card(p2, "probability_engine", "long_odds"))
	_hit(cm2, _gun(p2), e2, e2.get_component("plate"))
	t.assert_eq(e2.get_component("plate").current_hp, 30, "Long Odds: \"x4 damage vs a part at a quarter HP or less\" (70 → 30)")

static func _salvage_recursor(t: TestContext) -> void:
	t.group("Protocols · Salvage Recursor")
	var p := _player([["salvage_recursor", Vector2i(0, 0)]], 10, 1, 3)
	var e := _enemy()
	var cm := TestEffects._cm(p, [e] as Array[MechData])
	_self(cm, _card(p, "salvage_recursor", "recall"))
	_hit(cm, _gun(p), e, e.get_component("plate"))
	var heat := p.current_heat
	cm.end_player_turn()
	t.assert_eq(_lost(e.get_component("plate")), 20, "Recall: \"Next card plays again next turn\"")

	var p2 := _player([["salvage_recursor", Vector2i(0, 0)]], 10)
	var e2 := _enemy()
	var cm2 := TestEffects._cm(p2, [e2] as Array[MechData])
	var hurt := p2.get_component("salvage_recursor")
	hurt.current_hp = hurt.max_hp - 20
	e2.get_component("plate").current_hp = 5
	_self(cm2, _card(p2, "salvage_recursor", "scavenge"))
	_hit(cm2, _gun(p2), e2, e2.get_component("plate"))
	t.assert_eq(hurt.max_hp - hurt.current_hp, 5, "Scavenge: \"if it destroys a part, heal your most damaged part 15\"")

static func _feedback_loop(t: TestContext) -> void:
	t.group("Protocols · Feedback Loop")
	var p := _player([["feedback_loop", Vector2i(0, 0)]], 1, 3, 1)
	var cm := TestEffects._cm(p, [TestEffects._dummy(9999)] as Array[MechData])
	p.current_heat = 10
	_self(cm, _card(p, "feedback_loop", "feedback"))
	_hit(cm, _gun(p), cm.enemies[0], cm.enemies[0].components[0])
	t.assert_eq(p.current_heat, 10 + 1 - 6, "Feedback: \"Vent 2 per hit\" (3 hits vent 6)")

	var p2 := _player([["feedback_loop", Vector2i(0, 0)]])
	var e2 := _enemy()
	var cm2 := TestEffects._cm(p2, [e2] as Array[MechData])
	_self(cm2, _card(p2, "feedback_loop", "feedback_field"))
	e2.current_heat = 0
	_enemy_hits(cm2, e2, p2.get_component("g"))
	t.assert_eq(e2.current_heat, 2, "Feedback Field: \"every enemy attack that hits you gives its mech 2 Heat\"")

static func _polarity_inverter(t: TestContext) -> void:
	t.group("Protocols · Polarity Inverter")
	var p := _player([["polarity_inverter", Vector2i(0, 0)]], 10, 1, 1)
	var e := _enemy()
	var cm := TestEffects._cm(p, [e] as Array[MechData])
	p.current_heat = 3
	e.current_heat = 9
	_self(cm, _card(p, "polarity_inverter", "invert"))
	_hit(cm, _gun(p), e, e.get_component("plate"))
	t.assert_eq([p.current_heat, e.current_heat], [9, 4], "Invert: \"swap Heat with the target mech\" (you 3 + 1 ↔ it 9)")

	var p2 := _player([["polarity_inverter", Vector2i(0, 0)]], 10)
	var e2 := _enemy()
	var cm2 := TestEffects._cm(p2, [e2] as Array[MechData])
	p2.get_component("g").add_status("acid", 2)
	e2.get_component("plate").add_status("shock", 3)
	_self(cm2, _card(p2, "polarity_inverter", "reverse_polarity"))
	_hit(cm2, _gun(p2), e2, e2.get_component("plate"))
	t.assert_eq([p2.get_component("g").status_stacks("shock"), p2.get_component("g").status_stacks("acid")], [3, 0],
		"Reverse Polarity: the part that fires it takes the target's statuses")
	t.assert_eq([e2.get_component("plate").status_stacks("acid"), e2.get_component("plate").status_stacks("shock")], [2, 0],
		"Reverse Polarity: and the target takes the firing part's")

static func _last_stand(t: TestContext) -> void:
	t.group("Protocols · Last Stand Protocol")
	var p := _player([["last_stand_protocol", Vector2i(0, 0)]], 10, 1, 5)
	var tank := TestParts._tank("filler", 1000, Vector2i(4, 4))
	tank.current_hp = 100
	p.components.append(tank)
	var cm := TestEffects._cm(p, [_enemy()] as Array[MechData])
	_self(cm, _card(p, "last_stand_protocol", "last_stand"))
	_hit(cm, _gun(p), cm.enemies[0], cm.enemies[0].get_component("plate"))
	t.assert_eq(p.current_heat, 0, "Last Stand: \"Your next card costs 0 Heat while your mech is at half HP or less\"")

	var p3 := _player([["last_stand_protocol", Vector2i(0, 0)]], 10, 1, 5)
	var cm3 := TestEffects._cm(p3, [_enemy()] as Array[MechData])
	_self(cm3, _card(p3, "last_stand_protocol", "last_stand"))
	_hit(cm3, _gun(p3), cm3.enemies[0], cm3.enemies[0].get_component("plate"))
	t.assert_eq(p3.current_heat, 5, "Last Stand: above half HP the card costs its Heat")

	var p2 := _player([["last_stand_protocol", Vector2i(0, 0)]])
	var e2 := _enemy()
	var cm2 := TestEffects._cm(p2, [e2] as Array[MechData])
	_self(cm2, _card(p2, "last_stand_protocol", "final_order"))
	var g := p2.get_component("g")
	g.current_hp = 5
	_enemy_hits(cm2, e2, g)
	t.assert_eq(g.current_hp, 1, "Final Order: \"your parts can't drop below 1 HP\"")

## The second pass (Logan, 2026-10-15: "make sure none of them are bugged
## based on how they're read"): each clause of the text, edge cases included.
static func _as_read(t: TestContext) -> void:
	t.group("Protocols as read · Coordinated Strike: \"Linked hardpoints fire their cheapest card\"")
	var cp := TestEffects._mech([["coordinated_strike_suite", Vector2i(0, 0)]], 40)
	var near := TestEffects._gun("near", 7, 1, 1, Vector2i(2, 1))
	var far := TestEffects._gun("far", 50, 1, 1, Vector2i(5, 5))
	cp.components.append(near)
	cp.components.append(far)
	var ce := _enemy()
	var ccm := TestEffects._cm(cp, [ce] as Array[MechData])
	var cs := _card(cp, "coordinated_strike_suite", "coordinated_strike")
	t.assert_true(Links.linked(cp, cp.get_component("coordinated_strike_suite")).has(near), "(the test gun sits on its link)")
	t.assert_true(cs.is_attack(), "it's dropped on an enemy part, like Fire Control Relay's Salvo")
	_hit(ccm, cs, ce, ce.get_component("plate"))
	t.assert_eq(_lost(ce.get_component("plate")), 7, "the linked gun fires (7), the unlinked one doesn't")

	t.group("Protocols as read · Overlay: \"can't be covered, dodged or parried\" (not Zero Lock's \"redirected\" or \"every hit lands\")")
	var op := _player([["tactical_uplink", Vector2i(0, 0)]], 10)
	var oc := _card(op, "tactical_uplink", "overlay")
	var zl_like: bool = oc.rule.get("grant", {}).get("sure_hit", false)
	t.assert_true(not zl_like, "Overlay doesn't make the attack a sure hit")
	var ope := _enemy()
	ope.get_component("plate").category = ComponentData.CATEGORY_REACTOR
	var ocm := TestEffects._cm(op, [ope] as Array[MechData])
	ocm.guards[ope] = [{"type": "decoy", "component": ope.get_component("gun")}]
	_self(ocm, oc)
	_hit(ocm, _gun(op), ope, ope.get_component("plate"))
	t.assert_eq(_lost(ope.get_component("plate")), 10, "a decoy only pulls hits aimed at hardpoints, so the plate is hit")
	var op2 := _player([["tactical_uplink", Vector2i(0, 0)]], 10)
	var ope2 := _enemy()
	ope2.get_component("plate").category = ComponentData.CATEGORY_HARDPOINT
	var ocm2 := TestEffects._cm(op2, [ope2] as Array[MechData])
	ocm2.guards[ope2] = [{"type": "decoy", "component": ope2.get_component("gun")}]
	_self(ocm2, _card(op2, "tactical_uplink", "overlay"))
	_hit(ocm2, _gun(op2), ope2, ope2.get_component("plate"))
	t.assert_eq(_lost(ope2.get_component("gun")), 10, "Overlay can still be redirected (Decoy Flares pull it)")
	var op3 := _player([["tactical_uplink", Vector2i(0, 0)]], 10)
	var ope3 := _enemy()
	var ocm3 := TestEffects._cm(op3, [ope3] as Array[MechData])
	ocm3.guards[ope3] = [{"type": "parry", "component": ope3.get_component("gun"), "damage": 0}]
	_self(ocm3, _card(op3, "tactical_uplink", "overlay"))
	_hit(ocm3, _gun(op3), ope3, ope3.get_component("plate"))
	t.assert_eq(_lost(ope3.get_component("plate")), 10, "Overlay can't be parried")

	t.group("Protocols as read · Loaded Dice: \"never misses\"")
	var lp := _player([["probability_engine", Vector2i(0, 0)]], 10, 2)
	var le := _enemy()
	var lcm := TestEffects._cm(lp, [le] as Array[MechData])
	lcm.guards[le] = [{"type": "parry", "component": le.get_component("gun"), "damage": 0}]
	_self(lcm, _card(lp, "probability_engine", "loaded_dice"))
	_hit(lcm, _gun(lp), le, le.get_component("plate"))
	t.assert_eq(_lost(le.get_component("plate")), 20, "a parry doesn't make it miss (both hits land)")

	t.group("Protocols as read · Heat Transfer: \"moves 3 of your Heat\"")
	var hp := _player([["thermal_transfer_bus", Vector2i(0, 0)]], 5, 1, 0)
	var he := _enemy()
	var hcm := TestEffects._cm(hp, [he] as Array[MechData])
	hp.current_heat = 1
	he.current_heat = 0
	_self(hcm, _card(hp, "thermal_transfer_bus", "heat_transfer"))
	_hit(hcm, _gun(hp), he, he.get_component("plate"))
	t.assert_eq([hp.current_heat, he.current_heat], [0, 1], "with only 1 Heat, it moves 1 (it can't move Heat you don't have)")

	t.group("Protocols as read · Bleed Off: \"with HP from the linked component\"")
	var bp := _player([["thermal_transfer_bus", Vector2i(0, 0)]], 5, 1, 3)
	var bcm := TestEffects._cm(bp, [_enemy()] as Array[MechData])
	_self(bcm, _card(bp, "thermal_transfer_bus", "bleed_off"))
	_hit(bcm, _gun(bp), bcm.enemies[0], bcm.enemies[0].get_component("plate"))
	t.assert_true(bcm.is_primed("bleed_off"), "with nothing linked to pay, it waits (it isn't used up for nothing)")

	t.group("Protocols as read · Recall: \"Next card plays again next turn\", even with a Standby card waiting")
	var rp := _player([["salvage_recursor", Vector2i(0, 0)], ["queue_processor", Vector2i(0, 3)]], 10, 1, 1)
	var other := TestEffects._gun("other", 4, 1, 1, Vector2i(5, 4))
	rp.components.append(other)
	var re := _enemy()
	var rcm := TestEffects._cm(rp, [re] as Array[MechData])
	_self(rcm, _card(rp, "queue_processor", "standby"))
	_hit(rcm, other.cards[0], re, re.get_component("gun")) # set aside: 4 next turn
	_self(rcm, _card(rp, "salvage_recursor", "recall"))
	_hit(rcm, _gun(rp), re, re.get_component("plate")) # 10 now, 10 again next turn
	rcm.end_player_turn()
	t.assert_eq(_lost(re.get_component("gun")), 4, "the Standby card fires")
	t.assert_eq(_lost(re.get_component("plate")), 20, "and the recalled card plays again too")

	t.group("Protocols as read · Echo: \"Take the protocol an enemy has waiting\", Standby included")
	var ep := _player([["echo_buffer", Vector2i(0, 0)]])
	var ee := _enemy()
	var ecm := TestEffects._cm(ep, [ee] as Array[MechData])
	ecm._enemy_standby_pending[ee] = true
	_self(ecm, _card(ep, "echo_buffer", "echo"))
	t.assert_true(ecm.is_primed("standby"), "an enemy's waiting Standby becomes yours")
	t.assert_true(not ecm._enemy_standby_pending.has(ee), "and the enemy loses it")

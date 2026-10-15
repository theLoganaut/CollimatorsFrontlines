class_name CombatAttack
extends RefCounted
## The hit pipeline, for CombatManager: an attack card becomes the pending
## attack (start), resolves one hit at a time (next_hit), then lands its
## statuses and after-effects (finish_statuses). Also the damage modifiers
## protocols and passives put on an attack, and the per-hit bookkeeping
## (reclaim, thorns, kills, stats). Static and stateless: the fight's
## state (the pending attack in `_attack`, the RNG, the stats) lives on the
## CombatManager passed in, and signals are emitted on it.

static func start(cm: CombatManager, card: CardData, attacker_mech: MechData, attacker_component: ComponentData, defender_mech: MechData, target: ComponentData, mods: Dictionary = {}) -> void:
	mods = mods.duplicate()
	var vs_attacking := false
	if card.hits > 0 and target != null and attacker_mech != defender_mech:
		# Yank Aim: a turned part's attacks land on its own mech.
		if cm.turned.has(attacker_component):
			var own := attacker_mech.non_destroyed_components()
			if not own.is_empty():
				defender_mech = attacker_mech
				target = own[cm.rng.randi() % own.size()]
		elif not card.rule.get("sure_hit", false):
			target = guarded_target(cm, defender_mech, target)
		vs_attacking = is_attacking(cm, defender_mech, target)
		var va: Dictionary = card.rule.get("vs_attacking", {})
		if vs_attacking and va.has("mult"):
			mods["mult"] = float(mods.get("mult", 1.0)) * float(va["mult"])
		var bts: Dictionary = card.rule.get("bonus_if_target_status", {})
		if not bts.is_empty() and CardResolver.target_has_status(target, defender_mech, bts["status"]):
			mods["flat"] = int(mods.get("flat", 0)) + int(bts.get("flat", 0))
		if card.rule.get("strip_shields", false):
			defender_mech.clear_mech_status("deflect")
			defender_mech.clear_mech_status("absorb")
		if card.rule.get("steal_shields", false): # Leech Field
			for st in ["deflect", "absorb"]:
				var n := defender_mech.mech_status_stacks(st)
				if n > 0:
					defender_mech.clear_mech_status(st)
					attacker_mech.add_mech_status(st, n)
	var hits := card.hits * (2 if mods.get("split", false) else 1) * (2 if mods.get("twice", false) else 1)
	if card.rule.get("hits_per_target_status", false) and target != null and hits > 0:
		hits += target.statuses.filter(func(s): return s.stacks > 0).size()
	var cs: Dictionary = card.rule.get("consume_status", {})
	if not cs.is_empty() and target != null:
		var n := target.status_stacks(cs["status"])
		if n > 0:
			target.remove_status(cs["status"], n)
			mods["bonus_first"] = int(mods.get("bonus_first", 0)) + n * int(cs.get("per_stack", 4))
	var extras := []
	if hits > 0 and target != null and (card.rule.get("arc_adjacent", false) or mods.get("chain", false)):
		var near := Links.adjacent_parts(defender_mech, target)
		if not near.is_empty():
			extras.append({"mech": defender_mech, "comp": near[cm.rng.randi() % near.size()]})
	# Overdrive: every other hardpoint of the target mech too.
	if hits > 0 and target != null and (mods.get("all_hardpoints", false) or card.rule.get("all_hardpoints", false)):
		for c in defender_mech.non_destroyed_components():
			if c != target and c.category == ComponentData.CATEGORY_HARDPOINT:
				extras.append({"mech": defender_mech, "comp": c})
	# Double Tap: the enemy part with the biggest attack shown this turn too.
	if hits > 0 and card.rule.get("hits_top_attacker", false) and attacker_mech == cm.player_mech:
		var top := top_attacker(cm)
		if not top.is_empty() and top["comp"] != target:
			extras.append(top)
	if (card.rule.get("hits_all_enemies", false) or mods.get("fan_out", false)) and attacker_mech == cm.player_mech:
		for m in cm.enemies:
			if m != defender_mech and not m.is_defeated() and not m.non_destroyed_components().is_empty():
				var parts := m.non_destroyed_components()
				extras.append({"mech": m, "comp": parts[cm.rng.randi() % parts.size()]})
	var chain: Array = cm._attack.get("chain", []) if not cm._attack.is_empty() else []
	cm._attack = {
		"card": card, "attacker_mech": attacker_mech, "attacker_component": attacker_component,
		"defender_mech": defender_mech, "target": target, "mods": mods, "extras": extras,
		"hits_total": hits, "hits_done": 0, "total": 0, "hits_landed": 0,
		"damaged": {}, # MechData -> true, for Reactive Plating
		"chain": chain, "vs_attacking": vs_attacking,
	}

## Resolves the pending attack's next hit. Empty once every hit is done,
## or once the target is destroyed (the rest are wasted, Combat Slice §4.4).
## A Salvo moves on to its next hardpoint's attack here.
static func next_hit(cm: CombatManager) -> Dictionary:
	var a := cm._attack
	if a.is_empty() or not a.has("card"):
		return {}
	var card: CardData = a["card"]
	var target: ComponentData = a["target"]
	var scatter: bool = card.rule.get("random_part_hits", false)
	if a["hits_done"] >= a["hits_total"] or (target.destroyed and not scatter) or (a["defender_mech"] as MechData).non_destroyed_components().is_empty():
		if (a["chain"] as Array).is_empty():
			return {}
		CombatProtocols.advance_chain(cm)
		return next_hit(cm)
	var i: int = a["hits_done"]
	a["hits_done"] += 1
	var damage := 0
	var missed := false
	var primary := true
	var first_target := target
	if scatter:
		var parts := (a["defender_mech"] as MechData).non_destroyed_components()
		first_target = parts[cm.rng.randi() % parts.size()]
	for t in [{"mech": a["defender_mech"], "comp": first_target}] + a["extras"]:
		var tc: ComponentData = t["comp"]
		if tc.destroyed:
			primary = false
			continue
		var sure: bool = card.rule.get("sure_hit", false)
		# Overlay can't be covered, dodged or parried (but can be redirected,
		# and later hits can still miss); Loaded Dice never misses.
		var undodgeable: bool = sure or card.rule.get("undodgeable", false) or a["mods"].get("max_roll", false)
		if not sure and not _hit_fires(cm, card, i) and not a["mods"].get("max_roll", false):
			if primary:
				missed = true
			cm.hit_missed.emit(t["mech"], tc)
			primary = false
			continue
		if not undodgeable and (_parried(cm, t["mech"], a["attacker_mech"], a["attacker_component"]) or _dodges(cm, t["mech"])):
			if primary:
				missed = true
			cm.hit_missed.emit(t["mech"], tc)
			primary = false
			continue
		var mods: Dictionary = a["mods"].duplicate()
		if i > 0 or not primary:
			mods.erase("bonus_first") # Recycling Loops boosts one hit
		if sure or card.rule.get("undodgeable", false):
			mods["no_cover"] = true
		var r := CardResolver.resolve_hit(card, a["attacker_component"], t["mech"], tc, cm.rng, mods)
		_after_hit(cm, t["mech"], tc, r)
		_on_hit_effects(cm, card, r)
		if primary:
			damage = int(r["damage_dealt"])
			a["total"] += damage
			if not r["wasted"]:
				a["hits_landed"] += 1
		primary = false
	var hits_left: int = 0 if (target.destroyed and not scatter) else a["hits_total"] - a["hits_done"]
	if hits_left <= 0 and not (a["chain"] as Array).is_empty():
		hits_left = 1 # the Salvo's next hardpoint still fires
	return {"damage": damage, "target_destroyed": target.destroyed, "hits_left": hits_left, "missed": missed}

## Resolves the pending attack at once, outside the paced flow (repeats, Standby).
static func resolve_now(cm: CombatManager, defender: MechData, target: ComponentData) -> void:
	while not next_hit(cm).is_empty():
		pass
	var a := cm._attack
	cm._attack = {}
	finish_statuses(cm, a)
	cm.component_damaged.emit(defender, target, a["total"])
	emit_destroyed_if(cm, defender, target)

## Blink Drive: the first hits a mech takes each round (its "hits", 1 by
## default) are dodged.
static func _dodges(cm: CombatManager, defender: MechData) -> bool:
	var drives := defender.living_passives("dodge_first")
	if drives.is_empty():
		return false
	var allowed := 0
	for d in drives:
		allowed += int(d.passive.get("hits", 1))
	if int(cm._dodged.get(defender, 0)) >= allowed:
		return false
	cm._dodged[defender] = int(cm._dodged.get(defender, 0)) + 1
	cm.passive_triggered.emit(defender, drives[0])
	return true

## After one hit lands: reclaim (Grinder Maw, Parasite Leech, Siphon)
## and Feedback's vent.
static func _on_hit_effects(cm: CombatManager, card: CardData, r: Dictionary) -> void:
	var dealt := int(r["damage_dealt"])
	var attacker: MechData = cm._attack["attacker_mech"]
	var frac := float(card.rule.get("heal_on_hit", 0.0)) + float(cm._attack["mods"].get("siphon", 0.0))
	if frac > 0.0 and dealt > 0:
		var lowest: ComponentData = null
		for c in attacker.non_destroyed_components():
			if c.current_hp < c.max_hp and (lowest == null or float(c.current_hp) / c.max_hp < float(lowest.current_hp) / lowest.max_hp):
				lowest = c
		if lowest != null:
			var h := lowest.heal(int(round(dealt * frac)))
			if attacker == cm.player_mech:
				cm.stats.add("damage_healed", h)
	if int(cm._attack["mods"].get("vent_on_hit", 0)) > 0 and not r["wasted"]:
		attacker.current_heat = maxi(0, attacker.current_heat - int(cm._attack["mods"]["vent_on_hit"]))

## Whether hit number `i` of `card` fires (hit_chance curve; last entry repeats).
static func _hit_fires(cm: CombatManager, card: CardData, i: int) -> bool:
	var curve: Array = card.rule.get("hit_chance", [])
	if curve.is_empty():
		return true
	var chance := float(curve[mini(i, curve.size() - 1)])
	return chance >= 1.0 or cm.rng.randf() < chance

## Bookkeeping and signals for one resolved hit on one part.
static func _after_hit(cm: CombatManager, aimed_mech: MechData, aimed: ComponentData, r: Dictionary) -> void:
	var hit_component: ComponentData = r["hit_component"]
	var defender: MechData = r.get("hit_mech", aimed_mech) # an ally's Redirect Spike may take it
	check_boss_phase(cm, defender)
	_count_hit(cm, defender, r)
	if int(r["damage_dealt"]) > 0:
		cm._attack["damaged"][defender] = true
	cm.hit_landed.emit(defender, hit_component, int(r["damage_dealt"]))
	if hit_component != aimed and not r["wasted"]:
		cm.passive_triggered.emit(defender, hit_component)
	var saver = r.get("saved_by", null)
	if saver != null:
		cm.passive_triggered.emit(defender, saver)
		if saver.destroyed:
			cm.component_destroyed.emit(defender, saver)
	var attacker: MechData = cm._attack.get("attacker_mech", null)
	if attacker != null and attacker != defender and not r["wasted"]:
		_thorns(cm, defender, hit_component, attacker, cm._attack["attacker_component"])
		if hit_component.destroyed and int(r["damage_dealt"]) > 0:
			_on_kill(cm, attacker)
	# The attack's own target is announced when the attack finishes; anything
	# else it breaks (a cover part, an arc or Lay Waste side target, a random
	# part) is announced now.
	if not (defender == cm._attack["defender_mech"] and hit_component == cm._attack["target"]) or defender != aimed_mech:
		emit_destroyed_if(cm, defender, hit_component)

## A boss that has just fallen to half HP changes tactics (once), however
## the damage got there.
static func check_boss_phase(cm: CombatManager, mech: MechData) -> void:
	if mech != cm.player_mech and not mech.phase2_reached and mech.in_phase2():
		cm.boss_phase_changed.emit(mech)

## Spiked Plating (the hit part) and Mirror Plating (the whole mech) bite back.
static func _thorns(cm: CombatManager, defender: MechData, hit: ComponentData, attacker: MechData, attacker_comp: ComponentData) -> void:
	if attacker_comp == null or attacker_comp.destroyed:
		return
	var total := 0
	var source: ComponentData = null
	if hit.passive_type() == "thorns" and hit.passive.get("scope", "self") == "self":
		total += int(hit.passive.get("damage", 0))
		source = hit
	for m in defender.living_passives("thorns"):
		if m.passive.get("scope", "self") == "mech":
			total += int(m.passive.get("damage", 0))
			source = m
	if total <= 0:
		return
	var res := CardResolver.deal_damage(attacker, attacker_comp, total)
	cm.passive_triggered.emit(defender, source)
	cm.hit_landed.emit(attacker, attacker_comp, int(res["applied"]))
	if attacker == cm.player_mech:
		cm.stats.add("damage_taken", int(res["applied"]))
	emit_destroyed_if(cm, attacker, attacker_comp)
	check_boss_phase(cm, attacker)

## An enemy part destroyed by `attacker`: Blowout Vent, Neural Link, Scrap Magnet.
static func _on_kill(cm: CombatManager, attacker: MechData) -> void:
	for c in attacker.living_passives("kill_vent"):
		attacker.current_heat = maxi(0, attacker.current_heat - int(c.passive.get("amount", 3)))
		cm.passive_triggered.emit(attacker, c)
	if attacker == cm.player_mech:
		for c in attacker.living_passives("on_kill_refund"):
			cm._refund_next = true
			cm.passive_triggered.emit(attacker, c)
		for c in attacker.living_passives("scrap_on_kill"):
			cm.stats.add("magnet_scraps", int(c.passive.get("amount", 3)))
			cm.passive_triggered.emit(attacker, c)

static func emit_destroyed_if(cm: CombatManager, mech: MechData, comp: ComponentData) -> void:
	if comp.destroyed:
		cm.component_destroyed.emit(mech, comp)

## A finished (sub-)attack's statuses, its on-hit status, repeats,
## Overdrive's Disabled and Reactive Plating.
static func finish_statuses(cm: CombatManager, a: Dictionary) -> void:
	var card: CardData = a["card"]
	var target: ComponentData = a["target"]
	var statuses := CardResolver.statuses_with_mods(card, a["mods"])
	var chance := float(card.rule.get("status_chance", 1.0))
	var rolled_ok := chance >= 1.0 or cm.rng.randf() < chance
	if not statuses.is_empty() and not rolled_ok:
		cm.chance_failed.emit(a["defender_mech"], target)
	if not statuses.is_empty() and rolled_ok:
		for s in statuses:
			if s.target == StatusEffectData.TARGET_ALL_ENEMIES and card.rule.get("hits_all_enemies", false):
				for t in [{"mech": a["defender_mech"], "comp": target}] + a["extras"]:
					var red := CardResolver.add_status_to(t["mech"], t["comp"], s.status, s.stacks, true)
					if red != null:
						cm.passive_triggered.emit(t["mech"], red)
				continue
			var reducer := CardResolver.apply_card_status(s, a["attacker_mech"], a["attacker_component"], a["defender_mech"], target)
			if reducer != null:
				cm.passive_triggered.emit(a["defender_mech"], reducer)
			# Chain: an enemy-targeted part status jumps to the target's neighbours.
			if card.rule.get("spread_status", false) and s.target == StatusEffectData.TARGET_ENEMY and not CardResolver.MECH_STATUSES.has(s.status):
				for adj in Links.adjacent_parts(a["defender_mech"], target):
					_status_with_reducer(cm, a["defender_mech"], adj, s.status, s.stacks)
	var ohs: Dictionary = card.rule.get("on_hit_status", {})
	if not ohs.is_empty() and not target.destroyed:
		if not ohs.get("hardpoint_only", false) or target.category == ComponentData.CATEGORY_HARDPOINT:
			CardResolver.add_status_to(a["defender_mech"], target, ohs["status"], int(ohs["stacks"]), true)
	if int(card.rule.get("repeat_turns", 0)) > 0 and not a.get("is_repeat", false):
		cm.repeats.append({"card": card, "attacker_mech": a["attacker_mech"], "attacker_component": a["attacker_component"],
			"defender_mech": a["defender_mech"], "target": target, "turns_left": int(card.rule["repeat_turns"])})
	if a["mods"].get("overdrive", false):
		a["attacker_component"].add_status("disabled", 1)
	var attacker: MechData = a["attacker_mech"]
	var defender: MechData = a["defender_mech"]
	if card.hits > 0 and attacker != defender:
		if int(card.rule.get("heat_to_target", 0)) > 0:
			var moved := int(card.rule["heat_to_target"])
			if card.rule.get("transfer", false): # Heat Transfer: it's yours that moves, so no more than you have
				moved = mini(moved, attacker.current_heat)
				attacker.current_heat -= moved
			defender.current_heat += moved
		for c in attacker.living_passives("status_on_attack"):
			if not target.destroyed and cm.rng.randf() < float(c.passive.get("chance", 1.0)):
				CardResolver.add_status_to(defender, target, c.passive.get("status", "shock"), int(c.passive.get("stacks", 1)), true)
				cm.passive_triggered.emit(attacker, c)
		if a["mods"].get("knockback", false) and not target.destroyed:
			target.add_status("disabled", 1)
		if a["mods"].get("invert", false):
			var h := attacker.current_heat
			attacker.current_heat = defender.current_heat
			defender.current_heat = h
		if int(card.rule.get("recoil", 0)) > 0 and not a.get("is_repeat", false):
			var ac: ComponentData = a["attacker_component"]
			var rr := CardResolver.deal_damage(attacker, ac, int(card.rule["recoil"]))
			cm.hit_landed.emit(attacker, ac, int(rr["applied"]))
			if attacker == cm.player_mech:
				cm.stats.add("damage_taken", int(rr["applied"]))
			emit_destroyed_if(cm, attacker, ac)
			check_boss_phase(cm, attacker)
	if card.hits > 0 and attacker != defender:
		_card_pass_effects(cm, a)
	elif card.hits <= 0 and card.protocol() == "":
		self_rules(cm, card, attacker, a["attacker_component"]) # an enemy's self card
	for m in a["damaged"].keys():
		_reactive_plating(cm, m)
		for hs in m.living_passives("on_damaged_vent"):
			m.current_heat = maxi(0, m.current_heat - int(hs.passive.get("amount", 1)))
			cm.passive_triggered.emit(m, hs)

## The card pass's after-attack rules (Notion: Dynamic Turn Rework, Phase 5):
## statuses vs a part attacking this turn (Tracer Burst, Tranq Dart) and
## turning it (Yank Aim), a status vs a part already holding one (Lockout
## Round, Twist), venting on a kill (Devour), and the defender's Static Field.
static func _card_pass_effects(cm: CombatManager, a: Dictionary) -> void:
	var card: CardData = a["card"]
	var target: ComponentData = a["target"]
	var attacker: MechData = a["attacker_mech"]
	var defender: MechData = a["defender_mech"]
	var va: Dictionary = card.rule.get("vs_attacking", {})
	if a.get("vs_attacking", false) and not target.destroyed:
		if va.has("status"):
			_status_with_reducer(cm, defender, target, va["status"], int(va.get("stacks", 1)))
		if va.get("turn", false):
			cm.turned[target] = true
	var sts: Dictionary = card.rule.get("status_if_target_status", {})
	if not sts.is_empty() and not target.destroyed and CardResolver.target_has_status(target, defender, sts["if"]):
		_status_with_reducer(cm, defender, target, sts["status"], int(sts.get("stacks", 1)))
	if int(card.rule.get("vent_on_kill", 0)) > 0 and target.destroyed and int(a["total"]) > 0:
		attacker.current_heat = maxi(0, attacker.current_heat - int(card.rule["vent_on_kill"]))
	if int(card.rule.get("heal_on_kill", 0)) > 0 and target.destroyed and int(a["total"]) > 0:
		var low := _most_damaged(attacker)
		if low != null:
			var h := low.heal(int(card.rule["heal_on_kill"]))
			if attacker == cm.player_mech:
				cm.stats.add("damage_healed", h)
	# Hammer Down / Heavy Round: the hit leaves the target mech braced.
	var gift: Dictionary = card.rule.get("gift_status", {})
	if not gift.is_empty() and int(a["hits_landed"]) > 0:
		CardResolver.add_status_to(defender, target, gift["status"], int(gift.get("stacks", 1)), false)
	var ac: ComponentData = a["attacker_component"]
	if card.rule.get("self_disable", false) and ac != null and not ac.destroyed:
		ac.add_status("disabled", 1)
	# Reverse Polarity: the firing part and its target trade statuses (Offline stays put).
	if card.rule.get("swap_statuses", false) and ac != null and not ac.destroyed and not target.destroyed:
		var mine: Array[StatusInstance] = []
		var theirs: Array[StatusInstance] = []
		for x in ac.statuses.duplicate():
			if x.status != "offline":
				mine.append(x)
				ac.statuses.erase(x)
		for x in target.statuses.duplicate():
			if x.status != "offline":
				theirs.append(x)
				target.statuses.erase(x)
		ac.statuses.append_array(theirs)
		target.statuses.append_array(mine)
	if int(a["hits_landed"]) > 0 and ac != null and not ac.destroyed:
		for g in guards_of(cm, defender, "thorns"):
			var res := CardResolver.deal_damage(attacker, ac, int(g.get("damage", 4)))
			cm.hit_landed.emit(attacker, ac, int(res["applied"]))
			cm.passive_triggered.emit(defender, g["component"])
			emit_destroyed_if(cm, attacker, ac)
	if int(a["hits_landed"]) > 0:
		for g in guards_of(cm, defender, "heat_back"):
			attacker.current_heat += int(g.get("amount", 2))
			cm.passive_triggered.emit(defender, g["component"])
	if int(a["hits_landed"]) > 0 and ac != null and not ac.destroyed:
		for g in guards_of(cm, defender, "static_field"):
			_status_with_reducer(cm, attacker, ac, g.get("status", "shock"), int(g.get("stacks", 1)))
			cm.passive_triggered.emit(defender, g["component"])

static func _status_with_reducer(cm: CombatManager, mech: MechData, comp: ComponentData, status: String, stacks: int) -> void:
	var red := CardResolver.add_status_to(mech, comp, status, stacks, true)
	if red != null:
		cm.passive_triggered.emit(mech, red)

## A self card's rules beyond its statuses, for either side: a guard that
## lasts until the player's next turn (Foresight's parry, Static Field,
## Decoy Flares, Smoke Screen), a status on every enemy part attacking this
## turn (Arc Lash), extra stacks against a heavy attack (Hunker), a heal
## (Patch Job) and cleansing (Purge).
static func self_rules(cm: CombatManager, card: CardData, mech: MechData, comp: ComponentData) -> void:
	var g: Dictionary = card.rule.get("guard", {})
	if not g.is_empty():
		var e := g.duplicate()
		e["component"] = comp
		if g["type"] == "cap":
			mech.set_meta("guard_cap", int(g.get("cap", 12)))
		elif g["type"] == "floor":
			mech.set_meta("guard_floor", true)
		var list: Array = cm.guards.get(mech, [])
		list.append(e)
		cm.guards[mech] = list
	var soa: Dictionary = card.rule.get("status_on_attackers", {})
	if not soa.is_empty():
		for foe in ([cm.player_mech] if mech != cm.player_mech else cm.living_enemies()):
			for part in foe.non_destroyed_components():
				if is_attacking(cm, foe, part):
					_status_with_reducer(cm, foe, part, soa["status"], int(soa.get("stacks", 1)))
	var heavy: Dictionary = card.rule.get("if_heavy_incoming", {})
	if not heavy.is_empty() and mech == cm.player_mech and heavy_incoming(cm):
		CardResolver.add_status_to(mech, comp, heavy["status"], int(heavy.get("stacks", 0)), false)
	if int(card.rule.get("heal_lowest", 0)) > 0:
		var lowest := _most_damaged(mech)
		if lowest != null:
			var h := lowest.heal(int(card.rule["heal_lowest"]))
			if mech == cm.player_mech:
				cm.stats.add("damage_healed", h)
	if card.rule.has("cleanse"):
		CardResolver.cleanse(mech, card.rule["cleanse"])

## The part of `mech` with the lowest share of its HP (damaged ones only), or null.
static func _most_damaged(mech: MechData) -> ComponentData:
	var lowest: ComponentData = null
	for c in mech.non_destroyed_components():
		if c.current_hp < c.max_hp and (lowest == null or float(c.current_hp) / c.max_hp < float(lowest.current_hp) / lowest.max_hp):
			lowest = c
	return lowest

## The enemy part with the biggest attack shown this turn: {mech, comp}, or {}.
static func top_attacker(cm: CombatManager) -> Dictionary:
	var best := {}
	var most := 0.0
	for w in cm.living_enemies():
		for act in cm.upcoming_enemy_actions(w):
			var c: CardData = act["card"]
			if c.hits > 0 and not (act["component"] as ComponentData).destroyed and c.average_damage() > most:
				most = c.average_damage()
				best = {"mech": w, "comp": act["component"]}
	return best

## The guards of `type` a mech has up (see self_rules), dropping any whose part is gone.
static func guards_of(cm: CombatManager, mech: MechData, type: String) -> Array:
	return (cm.guards.get(mech, []) as Array).filter(func(e): return e["type"] == type and not (e["component"] as ComponentData).destroyed)

static func _use_guard(cm: CombatManager, mech: MechData, e: Dictionary) -> void:
	(cm.guards.get(mech, []) as Array).erase(e)
	cm.passive_triggered.emit(mech, e["component"])

## Where an attack on `defender` actually goes: Decoy Flares pull the next
## attack aimed at a hardpoint onto the flares; Smoke Screen sends attacks
## to a random part.
static func guarded_target(cm: CombatManager, defender: MechData, target: ComponentData) -> ComponentData:
	for e in guards_of(cm, defender, "decoy"):
		if target.category == ComponentData.CATEGORY_HARDPOINT and target != e["component"]:
			_use_guard(cm, defender, e)
			return e["component"]
	if not guards_of(cm, defender, "scatter").is_empty():
		var parts := defender.non_destroyed_components()
		if not parts.is_empty():
			return parts[cm.rng.randi() % parts.size()]
	return target

## Foresight's parry: the next hit on a guarded mech is cancelled and its
## attacker's part takes the parry's damage.
static func _parried(cm: CombatManager, defender: MechData, attacker: MechData, attacker_comp: ComponentData) -> bool:
	if attacker == null or attacker == defender:
		return false
	var list := guards_of(cm, defender, "parry")
	if list.is_empty():
		return false
	var e: Dictionary = list[0]
	_use_guard(cm, defender, e)
	if attacker_comp != null and not attacker_comp.destroyed:
		var res := CardResolver.deal_damage(attacker, attacker_comp, int(e.get("damage", 8)))
		cm.hit_landed.emit(attacker, attacker_comp, int(res["applied"]))
		if attacker == cm.player_mech:
			cm.stats.add("damage_taken", int(res["applied"]))
		emit_destroyed_if(cm, attacker, attacker_comp)
		check_boss_phase(cm, attacker)
	return true

## Whether `comp` is "attacking this turn": an enemy part with an attack in
## its shown plan, or (read by enemy cards) a player part that attacked on
## the player's last turn.
static func is_attacking(cm: CombatManager, mech: MechData, comp: ComponentData) -> bool:
	if comp == null or comp.destroyed:
		return false
	if mech == cm.player_mech:
		return cm.player_attackers.has(comp)
	if not comp.is_usable():
		return false
	for step in cm.enemy_plans.get(mech, []):
		if step["component"] == comp and (step["card"] as CardData).hits > 0:
			return true
	return false

## Whether any enemy shows a heavy attack this turn (Hunker).
static func heavy_incoming(cm: CombatManager) -> bool:
	for w in cm.living_enemies():
		for act in cm.upcoming_enemy_actions(w):
			if (act["card"] as CardData).intent() == CardData.INTENT_HEAVY_ATTACK:
				return true
	return false

## Reactive Plating: once per attack that damages its mech.
static func _reactive_plating(cm: CombatManager, mech: MechData) -> void:
	for rp in mech.living_passives(ComponentData.PASSIVE_ON_DAMAGED_STATUS):
		CardResolver.add_status_to(mech, rp, rp.passive.get("status", ""), int(rp.passive.get("stacks", 0)), false)
		cm.passive_triggered.emit(mech, rp)

static func _count_hit(cm: CombatManager, defender: MechData, r: Dictionary) -> void:
	var dealt := int(r["damage_dealt"])
	if defender == cm.player_mech:
		cm.stats.add("damage_taken", dealt)
		cm.stats.add("damage_blocked", int(r.get("blocked", 0)))
		cm.stats.add("damage_healed", int(r.get("healed", 0)))
		return
	cm.stats.add("damage_dealt", dealt)
	if dealt > 0:
		cm.stats.add("hits_landed")
	cm.stats.record_max("biggest_hit", dealt)
	cm._turn_damage += dealt
	cm.stats.record_max("best_turn_damage", cm._turn_damage)

# ---------- modifiers: Claude's parts, both sides ----------

## Attack protocols both sides can prime (Phase 10). `take(type)` uses one
## up and returns its entry ({} if none).
static func protocol_mods(take: Callable, mech: MechData, card: CardData, mods: Dictionary) -> void:
	for flag in ["fan_out", "pierce", "chain", "knockback", "max_roll", "invert"]:
		var e: Dictionary = take.call(flag)
		if not e.is_empty():
			mods[flag] = true
			# Breach / Loaded Dice can also carry a damage multiplier.
			var bonus := float(e["card"].rule.get("mult", 1.0)) if flag in ["pierce", "max_roll"] else 1.0
			if bonus != 1.0:
				mods["mult"] = float(mods.get("mult", 1.0)) * bonus
	var fb: Dictionary = take.call("vent_on_hit")
	if not fb.is_empty():
		mods["vent_on_hit"] = int(fb["card"].rule.get("amount", 1))
	var si: Dictionary = take.call("siphon")
	if not si.is_empty():
		mods["siphon"] = float(si["card"].rule.get("fraction", 0.5))
	if not (take.call("double_hits") as Dictionary).is_empty():
		mods["twice"] = true
	var ex: Dictionary = take.call("execute")
	if not ex.is_empty():
		mods["execute"] = {"fraction": float(ex["card"].rule.get("fraction", 0.34)), "mult": float(ex["card"].rule.get("mult", 3))}
	var ls: Dictionary = take.call("last_stand")
	if not ls.is_empty() and mech.max_hp() > 0:
		var lost := 1.0 - float(mech.current_hp()) / mech.max_hp()
		mods["mult"] = float(mods.get("mult", 1.0)) * (1.0 + floor(lost * 10.0) * float(ls["card"].rule.get("per_tenth", 0.1)))

## Passives and card rules that change an attack as it's played: Afterburner
## (first attack), Juggernaut Treads (each attack more), Overclock Heart and
## Heat Lance / Plasma Rapier (heat), boosters linking the weapon, Redline
## Burst (over max), Quick Draw (first card), Resonance Blade (plays so far).
static func passive_mods(cm: CombatManager, mech: MechData, card: CardData, mods: Dictionary, attack_n: int, card_n: int) -> void:
	var comp := mech.get_component(card.owner_component_id)
	var flat := int(mods.get("flat", 0))
	for c in mech.living_passives("first_attack_bonus"):
		if attack_n == 1:
			mods["mult"] = float(mods.get("mult", 1.0)) * float(c.passive.get("mult", 1.5))
			cm.passive_triggered.emit(mech, c)
	for c in mech.living_passives("momentum"):
		flat += int(c.passive.get("amount", 2)) * maxi(0, attack_n - 1)
	for c in mech.living_passives("heat_damage_bonus"):
		flat += mech.current_heat / maxi(1, int(c.passive.get("per", 3)))
	if comp != null:
		for c in mech.living_passives("linked_damage_bonus"):
			if Links.linked(mech, c).has(comp):
				flat += int(c.passive.get("amount", 2))
	var bph: Dictionary = card.rule.get("bonus_per_heat", {})
	if not bph.is_empty():
		flat += (mech.current_heat / maxi(1, int(bph.get("per", 2)))) * int(bph.get("bonus", 1))
	if card.rule.has("mult_if_over_max") and mech.current_heat > mech.heat_capacity():
		mods["mult"] = float(mods.get("mult", 1.0)) * float(card.rule["mult_if_over_max"])
	if card.rule.get("double_if_first", false) and card_n == 1:
		mods["mult"] = float(mods.get("mult", 1.0)) * 2.0
	if card.rule.has("stacking_damage"):
		var key := "%s:%s" % [mech.get_instance_id(), card.id]
		flat += int(card.rule["stacking_damage"]) * int(cm._card_plays.get(key, 0))
		cm._card_plays[key] = int(cm._card_plays.get(key, 0)) + 1
	if flat != 0:
		mods["flat"] = flat

# ---------- preview ----------

## A primed protocol of `type` that would apply to `card`, without using it.
static func _peek_primed(cm: CombatManager, type: String, card: CardData) -> Dictionary:
	if card.protocol() != "":
		return {}
	for p in cm.primed:
		if p["type"] == type and not (p["component"] as ComponentData).destroyed:
			return p
	return {}

## What the player's `card` would do to `target` right now, for the
## targeting preview (Logan, 2026-09-30), with no side effects: the hit
## pipeline (CardResolver.resolve_hit) run on the lowest and highest rolls,
## with primed Lock On / Overdrive / Split Feed / Breach / Loaded Dice,
## first-attack and heat bonuses, the card's own multipliers, Shock, Acid,
## cover, Deflect and Absorb. Assumes every hit lands.
## {lo, hi, part (the part that takes it), lethal_lo, lethal_hi, may_miss}, or {}.
static func preview(cm: CombatManager, card: CardData, defender: MechData, target: ComponentData) -> Dictionary:
	if card == null or target == null or card.hits <= 0 or card.damage_max <= 0 or target.destroyed:
		return {}
	card = CombatProtocols.peek_granted(cm, card)
	var mech := cm.player_mech
	var comp := mech.get_component(card.owner_component_id)
	var lo_mult := 1.0
	var hi_mult := 1.0
	var lock := _peek_primed(cm, "lock_on", card)
	if not lock.is_empty():
		var r: Array = lock["card"].rule.get("mult", [1.25, 1.35])
		lo_mult *= float(r[0])
		hi_mult *= float(r[1])
	var split := not _peek_primed(cm, "split_feed", card).is_empty()
	var pierce: bool = card.rule.get("pierce", false)
	var max_roll := false
	for flag in ["pierce", "max_roll"]:
		var e := _peek_primed(cm, flag, card)
		if not e.is_empty():
			var m := float(e["card"].rule.get("mult", 1.0))
			lo_mult *= m
			hi_mult *= m
			if flag == "pierce":
				pierce = true
			else:
				max_roll = true
	for c in mech.living_passives("first_attack_bonus"):
		if cm._attacks_this_turn == 0:
			lo_mult *= float(c.passive.get("mult", 1.5))
			hi_mult *= float(c.passive.get("mult", 1.5))
	if card.rule.has("mult_if_over_max") and mech.current_heat > mech.heat_capacity():
		lo_mult *= float(card.rule["mult_if_over_max"])
		hi_mult *= float(card.rule["mult_if_over_max"])
	if card.rule.get("double_if_first", false) and cm._cards_this_turn == 0:
		lo_mult *= 2.0
		hi_mult *= 2.0
	var flat := cm._recycle_bonus
	for c in mech.living_passives("momentum"):
		flat += int(c.passive.get("amount", 2)) * cm._attacks_this_turn
	for c in mech.living_passives("heat_damage_bonus"):
		flat += mech.current_heat / maxi(1, int(c.passive.get("per", 3)))
	if comp != null:
		for c in mech.living_passives("linked_damage_bonus"):
			if Links.linked(mech, c).has(comp):
				flat += int(c.passive.get("amount", 2))
	var bph: Dictionary = card.rule.get("bonus_per_heat", {})
	if not bph.is_empty():
		flat += (mech.current_heat / maxi(1, int(bph.get("per", 2)))) * int(bph.get("bonus", 1))
	if card.rule.has("stacking_damage"):
		flat += int(card.rule["stacking_damage"]) * int(cm._card_plays.get("%s:%s" % [mech.get_instance_id(), card.id], 0))
	var part := target if pierce else defender.cover_for(target)
	if part == null:
		part = target
	var card_mult := CardResolver.card_multiplier(card, target, defender)
	var va: Dictionary = card.rule.get("vs_attacking", {})
	if va.has("mult") and is_attacking(cm, defender, target):
		card_mult *= float(va["mult"])
	var bts: Dictionary = card.rule.get("bonus_if_target_status", {})
	if not bts.is_empty() and CardResolver.target_has_status(target, defender, bts["status"]):
		flat += int(bts.get("flat", 0))
	var stripped: bool = card.rule.get("strip_shields", false)
	var hits := card.hits * (2 if split else 1)
	if card.rule.get("hits_per_target_status", false):
		hits += target.statuses.filter(func(s): return s.stacks > 0).size()
	var per_hit := func(roll: int, mult: float, first: bool) -> int:
		var d := roll / 2 if split else roll
		d = int(floor(d * mult * card_mult))
		d += flat if first else flat - cm._recycle_bonus
		if comp != null:
			d = CardResolver.apply_shock(d, comp)
		return CardResolver.apply_acid_incoming(d, part)
	var total := func(roll: int, mult: float) -> int:
		var deflect := 0 if pierce or stripped else defender.mech_status_stacks("deflect")
		var absorb := 0 if pierce or stripped else defender.mech_status_stacks("absorb")
		var sum := 0
		for i in range(hits):
			var d: int = per_hit.call(roll, mult, i == 0)
			if absorb > 0 and d > 0:
				var a := mini(d, absorb)
				d -= a
				absorb = 0
			if deflect > 0 and d > 0:
				d -= mini(d, deflect)
				deflect -= (deflect + 1) / 2
			sum += maxi(0, d)
		return sum
	var lo: int = total.call(card.damage_max if max_roll else card.damage_min, lo_mult)
	var hi: int = total.call(card.damage_max, hi_mult)
	var curve: Array = card.rule.get("hit_chance", [])
	return {"lo": lo, "hi": hi, "part": part, "lethal_lo": lo >= part.current_hp, "lethal_hi": hi >= part.current_hp,
		"may_miss": curve.any(func(c): return float(c) < 1.0) and not max_roll}

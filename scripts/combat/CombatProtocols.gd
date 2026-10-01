class_name CombatProtocols
extends RefCounted
## The player's protocols, for CombatManager. The standard (Proposed,
## Notion "Phase 2 rulings to vet"): playing a protocol costs no heat and
## primes its effect; the next card it can affect uses it up. Several
## different protocols can wait at once; the same one can't be primed
## twice; they last until used. Replay, Salvo and Intercept act at once
## instead. Also the modifiers primed protocols and passives put on the
## player's next card. Static and stateless: `primed`, `standby` and the
## rest live on the CombatManager passed in.

static func prime(cm: CombatManager, type: String, card: CardData, comp: ComponentData, options: Dictionary) -> void:
	for p in cm.primed:
		if p["type"] == type:
			return
	var entry := {"type": type, "card": card, "component": comp}
	if type == "reroute":
		entry["status"] = options.get("status", CombatManager.REROUTE_OPTIONS[0])
	cm.primed.append(entry)
	cm.primed_changed.emit()

static func is_primed(cm: CombatManager, type: String) -> bool:
	return cm.primed.any(func(p): return p["type"] == type)

## Uses up a primed protocol of `type` if it applies to `card` (never to
## another protocol card). A protocol whose part was destroyed is lost.
static func take_primed(cm: CombatManager, type: String, card: CardData) -> Dictionary:
	if card.protocol() != "":
		return {}
	for p in cm.primed:
		if p["type"] == type:
			cm.primed.erase(p)
			cm.primed_changed.emit()
			if (p["component"] as ComponentData).destroyed:
				return {}
			return p
	return {}

## A card paid for: the discounts it used up (Quickload, Neural Link).
static func used_cost_mods(cm: CombatManager, card: CardData) -> void:
	if card.protocol() != "" or card.heat_cost <= 0:
		return
	take_primed(cm, "discount", card)
	cm._refund_next = false

## Protocols that act on any card (not just attacks): Fortify's Deflect
## and Recall's replay next turn.
static func any_card_protocols(cm: CombatManager, card: CardData, cost: int, target_mech: MechData, target: ComponentData) -> void:
	if card.protocol() != "":
		return
	var fort := take_primed(cm, "fortify", card)
	if not fort.is_empty() and cost > 0:
		cm.player_mech.add_mech_status("deflect", cost * int(fort["card"].rule.get("per_heat", 2)))
	if not take_primed(cm, "recall", card).is_empty() and cm.standby.is_empty():
		cm.standby = {"card": card, "target_mech": target_mech, "target": target}

## The modifiers primed protocols and passives put on the player's next card.
static func player_mods(cm: CombatManager, card: CardData) -> Dictionary:
	var mods := {}
	if card.hits > 0:
		var lock := take_primed(cm, "lock_on", card)
		if not lock.is_empty():
			var r: Array = lock["card"].rule.get("mult", [1.25, 1.35])
			mods["mult"] = float(mods.get("mult", 1.0)) * cm.rng.randf_range(float(r[0]), float(r[1]))
		var od := take_primed(cm, "overdrive", card)
		if not od.is_empty():
			mods["mult"] = float(mods.get("mult", 1.0)) * 2.0
			mods["overdrive"] = true
		if not take_primed(cm, "split_feed", card).is_empty():
			mods["split"] = true
		if cm._recycle_bonus > 0:
			mods["bonus_first"] = cm._recycle_bonus
			cm._recycle_bonus = 0
		cm._attacks_this_turn += 1
		for hf in cm.player_mech.living_passives(ComponentData.PASSIVE_NTH_ATTACK_TWICE):
			if cm._attacks_this_turn == int(hf.passive.get("n", 5)):
				mods["twice"] = true
				cm.passive_triggered.emit(cm.player_mech, hf)
		CombatAttack.protocol_mods(func(t): return take_primed(cm, t, card), cm.player_mech, card, mods)
		CombatAttack.passive_mods(cm, cm.player_mech, card, mods, cm._attacks_this_turn, cm._cards_this_turn)
	if not card.statuses.is_empty():
		var cat := take_primed(cm, "catalyze", card)
		if not cat.is_empty():
			mods["catalyze"] = int(cat["card"].rule.get("stacks", 2))
		var has_enemy_status := card.statuses.any(func(s): return s.target in [StatusEffectData.TARGET_ENEMY, StatusEffectData.TARGET_ALL_ENEMIES])
		if has_enemy_status:
			var rr := take_primed(cm, "reroute", card)
			if not rr.is_empty():
				mods["reroute"] = rr.get("status", "burn")
	return mods

## Standby: the next card is set aside (with its target) to play itself at
## the start of the next turn for 0 heat.
static func set_aside_for_standby(cm: CombatManager, card: CardData, target_mech: MechData, target: ComponentData) -> bool:
	if not cm.standby.is_empty() or card.protocol() != "" or not is_primed(cm, "standby"):
		return false
	var sb := take_primed(cm, "standby", card)
	if sb.is_empty():
		return false
	cm.standby = {"card": card, "target_mech": target_mech, "target": target}
	cm._count_card(card, 0)
	cm.card_played.emit(cm.player_mech, card)
	return true

## A card set aside by Standby plays itself now, for 0 heat.
static func run_standby(cm: CombatManager) -> void:
	if cm.standby.is_empty():
		return
	var sb := cm.standby
	cm.standby = {}
	var card: CardData = sb["card"]
	var comp := cm.player_mech.get_component(card.owner_component_id)
	if comp == null or comp.destroyed:
		return
	if card.is_attack():
		var t := retarget(cm, sb["target_mech"], sb["target"])
		if t.is_empty():
			return
		cm._attack = {}
		CombatAttack.start(cm, card, cm.player_mech, comp, t["mech"], t["comp"], {})
		CombatAttack.resolve_now(cm, t["mech"], t["comp"])
	else:
		CardResolver.resolve_self_card(card, cm.player_mech, comp)
	cm.card_played.emit(cm.player_mech, card)

## Replay: the last card played this turn again, on the same target, for
## its heat +2.
static func play_replay(cm: CombatManager, card: CardData, comp: ComponentData) -> Dictionary:
	if cm._last_played.is_empty():
		return {"ok": false, "reason": "nothing_to_replay"}
	var last: CardData = cm._last_played["card"]
	var last_comp := cm.player_mech.get_component(last.owner_component_id)
	if last_comp == null or not last_comp.is_usable():
		return {"ok": false, "reason": "source_unusable"}
	var cost := cm.effective_cost(last) + int(card.rule.get("extra_heat", 2))
	cm._pay_heat(cm.player_mech, card, cost, false)
	cm._count_card(card, cost)
	cm._after_use(comp)
	cm.card_played.emit(cm.player_mech, card)
	if last.is_attack():
		var t := retarget(cm, cm._last_played["target_mech"], cm._last_played["target"])
		if t.is_empty():
			return {"ok": true, "overheated": false}
		CombatAttack.start(cm, last, cm.player_mech, last_comp, t["mech"], t["comp"], {})
		return {"ok": true, "overheated": false, "started_attack": true}
	CardResolver.resolve_self_card(last, cm.player_mech, last_comp)
	if CombatHeat.check_player_overheat(cm):
		return {"ok": true, "overheated": true}
	return {"ok": true, "overheated": false}

## The same target if it still stands, else a living part of the same mech,
## else of any living enemy.
static func retarget(cm: CombatManager, mech: MechData, comp: ComponentData) -> Dictionary:
	if comp != null and not comp.destroyed:
		return {"mech": mech, "comp": comp}
	var pool: Array[MechData] = []
	if mech != null and not mech.is_defeated():
		pool.append(mech)
	if pool.is_empty():
		pool = cm.living_enemies()
	for m in pool:
		var parts := m.non_destroyed_components()
		if not parts.is_empty():
			return {"mech": m, "comp": parts[cm.rng.randi() % parts.size()]}
	return {}

## Salvo (Fire Control Relay): every hardpoint its link reaches fires its
## cheapest attack card at the target, one after another, paying their heat.
static func play_salvo(cm: CombatManager, card: CardData, relay: ComponentData, target_mech: MechData, target: ComponentData) -> Dictionary:
	var chain := []
	for hp in Links.linked(cm.player_mech, relay):
		if hp.category != ComponentData.CATEGORY_HARDPOINT or not hp.is_usable():
			continue
		var cheapest: CardData = null
		for c in hp.cards:
			if c.is_attack() and c.hits > 0 and not cm.is_spent(c) and (cheapest == null or cm.effective_cost(c) < cm.effective_cost(cheapest)):
				cheapest = c
		if cheapest != null:
			chain.append({"card": cheapest, "component": hp})
	cm._count_card(card, 0)
	cm._after_use(relay)
	cm.card_played.emit(cm.player_mech, card)
	if chain.is_empty():
		return {"ok": true, "no_attack": true}
	cm._attack = {"chain": chain}
	advance_chain(cm, target_mech, target)
	if cm._attack.is_empty():
		return {"ok": true, "no_attack": true}
	return {"ok": true}

## Starts the next attack in a Salvo chain (finishing the current one's statuses).
static func advance_chain(cm: CombatManager, target_mech: MechData = null, target: ComponentData = null) -> void:
	var chain: Array = cm._attack.get("chain", [])
	if cm._attack.has("card"):
		var done := cm._attack
		CombatAttack.finish_statuses(cm, done)
		cm.component_damaged.emit(done["defender_mech"], done["target"], done["total"])
		CombatAttack.emit_destroyed_if(cm, done["defender_mech"], done["target"])
		target_mech = done["defender_mech"]
		target = done["target"]
	var next: Dictionary = chain.pop_front()
	cm._spend(next["card"])
	var cost := cm.effective_cost(next["card"])
	cm._pay_heat(cm.player_mech, next["card"], cost, false)
	cm.stats.add("heat_generated", maxi(cost, 0))
	var t := retarget(cm, target_mech, target)
	if t.is_empty():
		cm._attack = {}
		return
	cm._attack = {"chain": chain}
	CombatAttack.start(cm, next["card"], cm.player_mech, next["component"], t["mech"], t["comp"], {})
	cm._after_use(next["component"])

## Intercept (Signal Interceptor): a one-use copy of the targeted enemy's
## next planned attack goes into the hand, damage range included.
static func play_intercept(cm: CombatManager, card: CardData, interceptor: ComponentData, target_mech: MechData) -> Dictionary:
	var copy: CardData = null
	for step in cm.enemy_plans.get(target_mech, []):
		var c: CardData = step["card"]
		if c.is_attack() and c.hits > 0 and not step["component"].destroyed:
			copy = c.clone()
			break
	cm._count_card(card, 0)
	cm._after_use(interceptor)
	cm.card_played.emit(cm.player_mech, card)
	if copy == null:
		return {"ok": true, "no_attack": true}
	copy.owner_component_id = interceptor.id
	copy.one_use = true
	copy.id = "%s_intercepted" % copy.id
	cm.bonus_cards.append(copy)
	cm.hand_changed.emit()
	return {"ok": true, "no_attack": true}

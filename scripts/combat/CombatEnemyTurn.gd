class_name CombatEnemyTurn
extends RefCounted
## The enemies' side of a fight, for CombatManager: stepping through their
## planned actions (targets chosen as each one comes up), their intents,
## paying for and starting their attacks, and their protocols. Enemies use
## protocols the player's way (Phase 6): Lock On, Overdrive, Split Feed and
## Catalyze prime for the enemy's next card; Replay plays its last attack
## this turn again for its heat +2; Standby sets its next attack aside to
## fire for 0 heat at the start of its next turn. A protocol step still goes
## through the paced enemy turn as an attack with no hits. Static and
## stateless: plans, AI memory and primed protocols live on the
## CombatManager passed in.

## The next planned enemy action, with its target chosen now (targets
## aren't part of the shown intent). Empty when the enemy turn is over.
## Steps whose component was destroyed, Disabled or Offlined since
## planning are skipped.
static func next_action(cm: CombatManager) -> Dictionary:
	if cm.phase != CombatManager.Phase.ENEMY_TURN:
		return {}
	while cm._enemy_idx < cm.enemies.size():
		if cm.player_mech.is_defeated():
			return {}
		var w := cm.enemies[cm._enemy_idx]
		var plan: Array = cm.enemy_plans.get(w, [])
		if w.is_defeated() or cm._enemy_step >= plan.size():
			cm._enemy_idx += 1
			cm._enemy_step = 0
			continue
		var step: Dictionary = plan[cm._enemy_step]
		cm._enemy_step += 1
		if not step["component"].is_usable():
			continue
		var card: CardData = step["card"]
		if card.protocol() != "" or step.get("charge", false):
			cm._in_flight = step
			return {"mech": w, "component": step["component"], "card": card, "target": null, "charge": step.get("charge", false)}
		var target: ComponentData = step.get("target", null)
		if target == null or target.destroyed:
			target = EnemyAI.choose_target(cm.player_mech, cm.rng, w, card, cm.ai_memory)
		if target == null:
			return {}
		if cm._enemy_standby_pending.get(w, false) and card.hits > 0 and cm.enemy_standby.get(w, {}).is_empty():
			cm._enemy_standby_pending.erase(w)
			cm._spend(card)
			cm.enemy_standby[w] = {"card": card, "component": step["component"], "target": target}
			cm.enemy_set_aside.emit(w, card)
			continue
		cm._in_flight = step
		return {"mech": w, "component": step["component"], "card": card, "target": target}
	return {}

## What each enemy still intends to do, in order: [{card, active}] — the
## step currently resolving is `active`; finished steps and steps from
## parts that can no longer act are left out.
static func upcoming_actions(cm: CombatManager, mech: MechData) -> Array:
	var out := []
	if mech.is_defeated() or cm.phase == CombatManager.Phase.GAME_OVER:
		return out
	var plan: Array = cm.enemy_plans.get(mech, [])
	var first := 0
	if cm.phase == CombatManager.Phase.ENEMY_TURN:
		var idx := cm.enemies.find(mech)
		if idx < cm._enemy_idx:
			return out
		if idx == cm._enemy_idx:
			first = cm._enemy_step
			if not cm._in_flight.is_empty():
				first -= 1
	# A charged attack fires as its turn starts (shown first, card and all).
	var player_turn := cm.phase == CombatManager.Phase.PLAYER_TURN
	if player_turn and cm.enemy_charged.has(mech):
		var ch: Dictionary = cm.enemy_charged[mech]
		var cc: ComponentData = ch["component"]
		if not cc.destroyed:
			out.append({"card": ch["card"], "active": false, "target": null, "component": cc, "charged": true, "cancelled": not cc.is_usable()})
	for i in range(first, plan.size()):
		var step: Dictionary = plan[i]
		var usable: bool = step["component"].is_usable()
		# During the player's turn a cancelled step stays on show, struck out.
		if not usable and step != cm._in_flight and (not player_turn or (step["component"] as ComponentData).destroyed):
			continue
		out.append({"card": step["card"], "active": step == cm._in_flight and not cm._in_flight.is_empty(),
			"target": step.get("target", null), "component": step["component"], "charge": step.get("charge", false),
			"cancelled": not usable and step != cm._in_flight, "added": step.get("added", false)})
	return out

## Whether an enemy's plan for this turn takes it over its max heat (a
## reckless enemy will; it takes the backlash at the end of its turn).
static func will_overheat(cm: CombatManager, mech: MechData) -> bool:
	if mech.is_defeated():
		return false
	var heat := mech.current_heat
	for step in cm.enemy_plans.get(mech, []):
		if (step["component"] as ComponentData).is_usable():
			heat += cm.effective_cost(step["card"], mech)
	return heat > mech.heat_capacity()

## Pays the heat and makes the action the pending attack; the caller steps
## it with next_hit() / finish_attack(). An enemy self card (0 hits)
## resolves as an attack with no hits whose statuses land on its own side.
static func begin_attack(cm: CombatManager, action: Dictionary) -> void:
	var warden: MechData = action["mech"]
	var card: CardData = action["card"]
	var comp: ComponentData = action["component"]
	var target: ComponentData = action["target"]
	var proto := card.protocol()
	cm._spend(card)
	if action.get("charge", false):
		_charge(cm, warden, comp, card)
		return
	if proto != "":
		_protocol(cm, warden, comp, card)
		return
	cm._pay_heat(warden, card, cm.effective_cost(card, warden), false)
	card = CombatProtocols.granted(cm.enemy_primed.get(warden, []), func(t): return _take_primed(cm, warden, t), card)
	CombatAttack.start(cm, card, warden, comp, cm.player_mech, target, mods(cm, warden, card))
	if card.hits > 0:
		cm.ai_memory[warden] = target
		cm.enemy_last[warden] = {"card": card, "component": comp, "target": target}
	cm._after_use(comp)

static func _protocol(cm: CombatManager, warden: MechData, comp: ComponentData, card: CardData) -> void:
	var type := card.protocol()
	match type:
		"replay":
			var last: Dictionary = cm.enemy_last.get(warden, {})
			if not last.is_empty() and (last["component"] as ComponentData).is_usable():
				var t: ComponentData = last["target"]
				if t == null or t.destroyed:
					t = EnemyAI.choose_target(cm.player_mech, cm.rng, warden, last["card"], cm.ai_memory)
				if t != null:
					cm._pay_heat(warden, last["card"], cm.effective_cost(last["card"], warden) + int(card.rule.get("extra_heat", 2)), false)
					CombatAttack.start(cm, last["card"], warden, last["component"], cm.player_mech, t, {})
					cm._after_use(comp)
					return
		# Echo: the player's waiting protocol becomes this enemy's.
		"steal":
			if not cm.primed.is_empty():
				var e: Dictionary = cm.primed.pop_front()
				cm.primed_changed.emit()
				cm.enemy_primed[warden] = [{"type": e["type"], "card": e["card"], "component": comp}]
		# One protocol waits at a time, as for the player: a new one replaces it.
		"standby":
			cm.enemy_primed.erase(warden)
			cm._enemy_standby_pending[warden] = card # the Standby card (Echo can take it)
		_:
			var list: Array = cm.enemy_primed.get(warden, [])
			if not list.any(func(e): return e["type"] == type):
				list = [{"type": type, "card": card, "component": comp}]
				cm._enemy_standby_pending.erase(warden)
			cm.enemy_primed[warden] = list
	CombatAttack.start(cm, card, warden, comp, cm.player_mech, _any_player_part(cm), {})
	cm._after_use(comp)

## Charge: the part pays for its attack now; it fires as this enemy's next
## turn starts (run_charged). Resolves as an attack with no hits, so the
## paced enemy turn shows it.
static func _charge(cm: CombatManager, warden: MechData, comp: ComponentData, card: CardData) -> void:
	cm._pay_heat(warden, card, cm.effective_cost(card, warden), false)
	cm.enemy_charged[warden] = {"card": card, "component": comp}
	var still := card.clone()
	still.hits = 0
	still.statuses = []
	still.rule = {}
	CombatAttack.start(cm, still, warden, comp, cm.player_mech, _any_player_part(cm), {})
	cm._after_use(comp)

## Charged attacks fire as their enemy's turn starts, free and +50%, if
## the part can still act (the Charge promise); a Disabled, Frozen or
## destroyed part's charge fizzles.
static func run_charged(cm: CombatManager) -> void:
	for w in cm.enemy_charged.keys():
		var ch: Dictionary = cm.enemy_charged[w]
		cm.enemy_charged.erase(w)
		var comp: ComponentData = ch["component"]
		var card: CardData = ch["card"]
		if w.is_defeated() or cm.player_mech.is_defeated():
			continue
		if comp.destroyed or not comp.is_usable():
			cm.ai_note.emit(w, "%s's charged %s fizzles." % [w.name, card.name])
			continue
		var t := EnemyAI.choose_target(cm.player_mech, cm.rng, w, card, cm.ai_memory)
		if t == null:
			continue
		cm._attack = {}
		cm._spend(card)
		var shot := card.clone()
		for st in shot.statuses.duplicate():
			if st.target == StatusEffectData.TARGET_SELF and st.status == "offline":
				shot.statuses.erase(st)
		var m := mods(cm, w, shot)
		m["mult"] = float(m.get("mult", 1.0)) * Balance.get_num("enemy_ai", "charge_mult", 1.5)
		CombatAttack.start(cm, shot, w, comp, cm.player_mech, t, m)
		CombatAttack.resolve_now(cm, cm.player_mech, t)
		cm.ai_note.emit(w, "%s unleashes its charged %s." % [w.name, card.name])
		cm.card_played.emit(w, card)

static func _any_player_part(cm: CombatManager) -> ComponentData:
	var parts := cm.player_mech.non_destroyed_components()
	return parts[0] if not parts.is_empty() else null

static func _take_primed(cm: CombatManager, mech: MechData, type: String) -> Dictionary:
	var list: Array = cm.enemy_primed.get(mech, [])
	for e in list:
		if e["type"] == type:
			list.erase(e)
			if (e["component"] as ComponentData).destroyed:
				return {}
			return e
	return {}

## The primed protocols an enemy's card uses up (as the player's do).
static func mods(cm: CombatManager, mech: MechData, card: CardData) -> Dictionary:
	var out := {}
	if card.hits > 0:
		var lock := _take_primed(cm, mech, "lock_on")
		if not lock.is_empty():
			var r: Array = lock["card"].rule.get("mult", [1.25, 1.35])
			out["mult"] = float(out.get("mult", 1.0)) * cm.rng.randf_range(float(r[0]), float(r[1]))
		if not _take_primed(cm, mech, "overdrive").is_empty():
			out["overdrive"] = true
			out["all_hardpoints"] = true
		if not _take_primed(cm, mech, "split_feed").is_empty():
			out["split"] = true
	if not card.statuses.is_empty():
		var cat := _take_primed(cm, mech, "catalyze")
		if not cat.is_empty():
			out["catalyze"] = int(cat["card"].rule.get("stacks", 2))
	if card.hits > 0:
		cm._enemy_attacks[mech] = int(cm._enemy_attacks.get(mech, 0)) + 1
		CombatAttack.protocol_mods(func(t): return _take_primed(cm, mech, t), mech, card, out)
		CombatAttack.passive_mods(cm, mech, card, out, int(cm._enemy_attacks[mech]), int(cm._enemy_attacks[mech]))
	return out

## Enemies' attacks set aside by Standby fire at the start of their turn, for 0 heat.
static func run_standby(cm: CombatManager) -> void:
	for w in cm.enemy_standby.keys():
		var sb: Dictionary = cm.enemy_standby[w]
		cm.enemy_standby.erase(w)
		if w.is_defeated() or (sb["component"] as ComponentData).destroyed or cm.player_mech.is_defeated():
			continue
		var t: ComponentData = sb["target"]
		if t == null or t.destroyed:
			t = EnemyAI.choose_target(cm.player_mech, cm.rng, w, sb["card"], cm.ai_memory)
		if t == null:
			continue
		cm._attack = {}
		CombatAttack.start(cm, sb["card"], w, sb["component"], cm.player_mech, t, mods(cm, w, sb["card"]))
		CombatAttack.resolve_now(cm, cm.player_mech, t)
		cm.card_played.emit(w, sb["card"])

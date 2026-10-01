class_name EnemyAI
extends RefCounted
## Enemy AI (Phase 6, Logan 2026-09-28: "enemies aren't dumb, but they
## aren't optimal"). Each enemy plays to its own profile (the "ai" block
## in its mech JSON, see MechData.ai):
##
## - heat:    "careful" never plans past max heat; "reckless" (Anchor) will
##            push up to reckless_overheat over it and eat the backlash.
## - cards:   how a part picks its card: "damage" (most expected damage),
##            "heavy" (the biggest it can afford), "status" (anything that
##            puts a status on you first), "random".
## - targets: which of your parts it aims at: "hardpoints" (disarm you),
##            "weakest" (finish off parts), "strongest" (smash the big
##            ones), "focus" (keep hitting what it hit last), "spread"
##            (status cards go to parts that don't have that status yet),
##            "systems" (reactors and protocols first), "random".
## - slip:    the chance any one choice is made at random instead — the
##            "not optimal" part.
## - protocols: the chance it primes a protocol it owns before its best
##            attack (Lock On, Overdrive, Split Feed, Catalyze, Standby,
##            Replay).
## - guard:   below this share of its HP, a self card that shields it
##            (Deflect / Absorb) is worth playing.
## - phase2:  a boss's overrides once it falls to half HP.
##
## Cards are single-use (Decided 2026-09-29): a card played this fight is
## out of the pool. An enemy with nothing it can play vents instead
## (CombatManager.venting), or idles at 0 heat.
##
## Walk order is unchanged: each usable part with cards acts once, left to
## right by leftmost column (tie: topmost row); a protocol primes first.
## Cards and targets are chosen when the player's turn starts (plan_turn)
## so the intent can show them; if a planned target is gone by the time
## the step resolves, a new one is picked the same way.

## Protocols enemies know how to use.
const ENEMY_PROTOCOLS := ["lock_on", "overdrive", "split_feed", "catalyze", "standby", "replay",
	"pierce", "chain", "knockback", "double_hits", "execute", "max_roll", "last_stand", "siphon", "vent_on_hit"]

const DEFAULT_AI := {"heat": "careful", "cards": "random", "targets": "random", "slip": 0.3, "protocols": 0.7, "guard": 0.5}

## The enemy's profile, with a boss's phase-2 overrides applied once it's
## down to half HP.
static func profile(mech: MechData) -> Dictionary:
	var p := DEFAULT_AI.duplicate()
	for k in mech.ai:
		if k != "phase2":
			p[k] = mech.ai[k]
	if mech.in_phase2():
		var p2: Dictionary = mech.ai.get("phase2", {})
		for k in p2:
			p[k] = p2[k]
	return p

static func heat_limit(mech: MechData) -> int:
	var reckless := str(profile(mech).get("heat", mech.ai_profile)) == "reckless" or mech.ai_profile == "reckless"
	return mech.heat_capacity() + (Balance.get_int("enemy_ai", "reckless_overheat", 4) if reckless else 0)

## Components that act this turn, in walk order. Components with no cards
## are left out entirely (they're skipped, not "acted on and did nothing").
static func act_order(mech: MechData) -> Array[ComponentData]:
	var acting := mech.non_destroyed_components().filter(func(c): return c.has_cards() and c.is_usable())
	acting.sort_custom(func(a, b):
		if a.leftmost_column() != b.leftmost_column():
			return a.leftmost_column() < b.leftmost_column()
		return a.topmost_row() < b.topmost_row()
	)
	return acting

## A living part of `defender_mech` to aim at: random without an attacker,
## otherwise the attacker's way.
static func choose_target(defender_mech: MechData, rng: RandomNumberGenerator, attacker: MechData = null, card: CardData = null, memory: Dictionary = {}) -> ComponentData:
	var pool := defender_mech.non_destroyed_components()
	if pool.is_empty():
		return null
	if attacker == null:
		return pool[rng.randi() % pool.size()]
	var p := profile(attacker)
	if rng.randf() < float(p["slip"]):
		return pool[rng.randi() % pool.size()]
	var best: ComponentData = null
	var best_score := -INF
	for c in pool:
		var s := _target_score(c, str(p["targets"]), card, attacker, memory) + rng.randf() * 3.0
		if s > best_score:
			best_score = s
			best = c
	return best

static func _target_score(c: ComponentData, style: String, card: CardData, attacker: MechData, memory: Dictionary) -> float:
	var hardpoint := c.category == ComponentData.CATEGORY_HARDPOINT
	var bonus := 0.0
	if card != null and _multiplies_on(card, c) > 1.0:
		bonus = 150.0 # EMP Round into a shocked weapon, Thrust Through into a half-broken one
	return bonus + _style_score(c, style, card, attacker, memory)

static func _style_score(c: ComponentData, style: String, card: CardData, attacker: MechData, memory: Dictionary) -> float:
	var hardpoint := c.category == ComponentData.CATEGORY_HARDPOINT
	match style:
		"hardpoints":
			return (100.0 if hardpoint else 0.0) - c.current_hp * 0.5
		"weakest":
			return -float(c.current_hp)
		"strongest":
			return float(c.current_hp)
		"focus":
			var last = memory.get(attacker, null)
			if last != null and last == c:
				return 1000.0
			return float(c.current_hp) # starts on the biggest part, then won't let go
		"spread":
			var bonus := 0.0
			if card != null:
				for s in card.statuses:
					if s.target == StatusEffectData.TARGET_ENEMY and c.status_stacks(s.status) == 0:
						bonus += 60.0
			return bonus + (30.0 if hardpoint else 0.0) + c.current_hp * 0.1
		"systems":
			return (80.0 if not hardpoint else 0.0) - c.current_hp * 0.3
	return 0.0

## Picks from affordable cards: the preferred one by style, or (slip) any.
static func _pick_card(pool: Array[CardData], mech: MechData, p: Dictionary, rng: RandomNumberGenerator, defender: MechData = null) -> CardData:
	if pool.size() == 1:
		return pool[0]
	if rng.randf() < float(p["slip"]) or str(p["cards"]) == "random":
		return pool[rng.randi() % pool.size()]
	var best: CardData = null
	var best_score := -INF
	var hurt := mech.max_hp() > 0 and float(mech.current_hp()) / mech.max_hp() < float(p.get("guard", 0.5))
	for c in pool:
		var s := _card_score(c, str(p["cards"]), hurt, _best_multiplier(c, defender)) + rng.randf() * 2.0
		if s > best_score:
			best_score = s
			best = c
	return best

static func _card_score(c: CardData, style: String, hurt: bool, mult: float = 1.0) -> float:
	var dmg := _expected_damage(c) * mult
	var shields := c.intent() == CardData.INTENT_BLOCK
	var status := c.statuses.any(func(s): return s.target in [StatusEffectData.TARGET_ENEMY, StatusEffectData.TARGET_ALL_ENEMIES])
	var score := 0.0
	match style:
		"damage":
			score = dmg
		"heavy":
			score = c.heat_cost * 10.0 + dmg * 0.1
		"status":
			score = (100.0 if status else 0.0) + dmg
	if shields:
		score = 150.0 if hurt else score * 0.2 + 1.0
	return score - _self_cost(c)

## What a card costs its own part, as a score penalty (balance.json
## enemy_ai): Offline for the rest of the fight (Precision Throw), or turns
## Disabled / Frozen (Wrap Up). 0 = the AI ignores it.
static func _self_cost(c: CardData) -> float:
	var cost := 0.0
	for st in c.statuses:
		if st.target != StatusEffectData.TARGET_SELF:
			continue
		match st.status:
			"offline":
				cost += Balance.get_num("enemy_ai", "self_offline_penalty", 0.0)
			"disabled", "freeze":
				cost += Balance.get_num("enemy_ai", "self_disable_penalty", 0.0) * maxi(1, st.stacks)
	return cost

## Average damage with hit chances counted (Rapid Fire's falloff).
static func _expected_damage(c: CardData) -> float:
	var curve: Array = c.rule.get("hit_chance", [])
	var per_hit := (c.damage_min + c.damage_max) / 2.0
	if curve.is_empty():
		return c.hits * per_hit
	var total := 0.0
	for i in range(c.hits):
		total += per_hit * float(curve[mini(i, curve.size() - 1)])
	return total

## The enemy's next turn: [{component, card, target}] in order, before any
## of it resolves (shown as intent). Heat is simulated forward so each pick
## is affordable after the ones before it; a protocol it owns may prime
## first. Protocol steps have no target.
static func plan_turn(warden: MechData, rng: RandomNumberGenerator, cm: CombatManager = null, defender: MechData = null) -> Array:
	var p := profile(warden)
	var plan := []
	var sim_heat := warden.current_heat
	var limit := heat_limit(warden)
	var protocols: Array = []
	for component in act_order(warden):
		var pool: Array[CardData] = []
		for c in component.cards:
			if cm != null and cm.is_spent(c):
				continue # single-use: played already this fight
			if c.protocol() != "":
				if ENEMY_PROTOCOLS.has(c.protocol()):
					protocols.append({"component": component, "card": c})
				continue
			var cost := cm.effective_cost(c, warden) if cm != null else c.heat_cost
			if sim_heat + cost <= limit:
				pool.append(c)
		if pool.is_empty():
			continue # can't afford anything right now — skipped, not "no-opped"
		var card := _pick_card(pool, warden, p, rng, defender)
		sim_heat += cm.effective_cost(card, warden) if cm != null else card.heat_cost
		plan.append({"component": component, "card": card})
	_shuffle(protocols, rng)
	for pr in protocols:
		_add_protocol(plan, [pr], p, rng, sim_heat, limit)
	if defender != null:
		var memory: Dictionary = cm.ai_memory if cm != null else {}
		for step in plan:
			if (step["card"] as CardData).is_attack() and (step["card"] as CardData).protocol() == "":
				step["target"] = choose_target(defender, rng, warden, step["card"], memory)
	return plan

static func _shuffle(list: Array, rng: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = list[i]
		list[i] = list[j]
		list[j] = tmp

## Maybe primes one protocol ahead of the attack it helps most (each
## protocol it owns gets its own roll, so a protocol-heavy boss chains them).
static func _add_protocol(plan: Array, protocols: Array, p: Dictionary, rng: RandomNumberGenerator, sim_heat: int, limit: int) -> void:
	var attacks := plan.filter(func(s): return (s["card"] as CardData).hits > 0)
	if protocols.is_empty() or attacks.is_empty() or rng.randf() >= float(p.get("protocols", 0.7)):
		return
	var pick: Dictionary = protocols[rng.randi() % protocols.size()]
	var type: String = (pick["card"] as CardData).protocol()
	var best: Dictionary = attacks[0]
	for s in attacks:
		if _expected_damage(s["card"]) > _expected_damage(best["card"]):
			best = s
	match type:
		"catalyze":
			var with_status := attacks.filter(func(s): return not (s["card"] as CardData).statuses.is_empty())
			if with_status.is_empty():
				return
			best = with_status[0]
		"replay":
			# plays the last card again for its heat +2: after the best attack
			# that leaves its part able to act (Wrap Up Disables its own
			# Arc Whip, so a Replay after it would fizzle), if there's room
			var replayable := attacks.filter(func(s): return not _disables_self(s["card"]))
			if replayable.is_empty():
				return
			best = replayable[0]
			for s in replayable:
				if _expected_damage(s["card"]) > _expected_damage(best["card"]):
					best = s
			if sim_heat + (best["card"] as CardData).heat_cost + 2 > limit:
				return
			plan.insert(plan.find(best) + 1, pick)
			return
	plan.insert(plan.find(best), pick)

## Whether playing `card` stops its own part from acting again this turn.
static func _disables_self(card: CardData) -> bool:
	return card.statuses.any(func(st): return st.target == StatusEffectData.TARGET_SELF and st.status in ["disabled", "offline", "freeze"])

## The damage multiplier `card` gets against `c` from its own rule (EMP
## Round x3 on a shocked hardpoint, Thrust Through x2 on one at half HP).
static func _multiplies_on(card: CardData, c: ComponentData) -> float:
	var hardpoint := c.category == ComponentData.CATEGORY_HARDPOINT
	var ms: Dictionary = card.rule.get("mult_if_target_status", {})
	if not ms.is_empty() and (hardpoint or not ms.get("hardpoint_only", false)) and c.status_stacks(ms["status"]) > 0:
		return float(ms.get("mult", 1))
	var mb: Dictionary = card.rule.get("mult_if_target_below", {})
	if not mb.is_empty() and (hardpoint or not mb.get("hardpoint_only", false)) and c.current_hp <= c.max_hp * float(mb.get("fraction", 0.5)):
		return float(mb.get("mult", 1))
	return 1.0

## The best multiplier `card` could get on any of `defender`'s living parts.
static func _best_multiplier(card: CardData, defender: MechData) -> float:
	var best := 1.0
	if defender == null:
		return best
	for c in defender.non_destroyed_components():
		best = maxf(best, _multiplies_on(card, c))
	return best

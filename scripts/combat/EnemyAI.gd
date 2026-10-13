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
	"pierce", "chain", "knockback", "double_hits", "execute", "max_roll", "last_stand", "siphon", "vent_on_hit",
	"grant", "steal"]

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
		for k in design(mech).get("phase2", {}):
			if not k in ["rhythms", "note"]:
				p[k] = design(mech)["phase2"][k]
	for e in lost_entries(mech):
		for k in e["entry"]:
			if not k in ["rhythms", "note"]:
				p[k] = e["entry"][k]
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
	if attacker != null and memory.get("squad_mark", null) == c and _role(attacker) in ["striker", "cover", "pressure"]:
		bonus += 300.0 # the squad's marked part
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

# ---------- Phase 6: themed turns (Notion: Dynamic Turn Rework, Phases 3-4) ----------
#
# Each enemy runs two-turn rhythms from data/enemy_ai.json (its archetype's
# shape: Bruiser charge -> combo, Turtle guard -> assault...). The first
# turn's theme is shown in full; the second is held. A theme orders the
# enemy's cards, and it plays every card it can afford in that order
# (Decided). Charge: a part pays for its biggest attack now and fires it
# for free, +50%, as the enemy's next turn starts, unless it's been
# Disabled, Frozen or destroyed by then (the Charge promise, Decided).

const THEMES := ["assault", "guard", "charge", "afflict", "recover", "combo"]
const SETUP_THEMES := ["charge", "afflict", "guard"]
const PAYOFF_THEMES := ["assault", "combo"]

static var _designs: Dictionary = {}

## The enemy's entry in data/enemy_ai.json ({} if none).
static func design(mech: MechData) -> Dictionary:
	if _designs.is_empty():
		var f := FileAccess.open("res://data/enemy_ai.json", FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			_designs = d if d is Dictionary else {"_": {}}
		else:
			_designs = {"_": {}}
	return _designs.get(mech.id, {})

## The on_lost entries whose part this mech has lost: [{key, entry}].
static func lost_entries(mech: MechData) -> Array:
	var out := []
	var lost: Dictionary = design(mech).get("on_lost", {})
	for key in lost:
		for c in mech.components:
			if c.destroyed and (c.library_id == key or c.id == key):
				out.append({"key": key, "entry": lost[key]})
				break
	return out

## Its rhythms now: phase 2's for a boss past half HP, then a lost part's.
static func rhythms(mech: MechData) -> Array:
	var d := design(mech)
	var out: Array = d.get("rhythms", [])
	if mech.in_phase2() and d.get("phase2", {}).has("rhythms"):
		out = d["phase2"]["rhythms"]
	for e in lost_entries(mech):
		if e["entry"].has("rhythms"):
			out = e["entry"]["rhythms"]
	if out.is_empty():
		out = [{"name": "Assault", "turns": ["assault", "assault"], "weight": 1}]
	return out

static func condition(cm: CombatManager, mech: MechData, cond: String) -> bool:
	if cm == null:
		return false
	var player := cm.player_mech
	match cond:
		"player_hot":
			return cm.player_heat_last >= 0.6
		"player_shielded":
			return player.mech_status_stacks("deflect") > 0 or player.mech_status_stacks("absorb") > 0
		"player_damaged":
			return player.non_destroyed_components().any(func(c): return c.current_hp <= c.max_hp * 0.6)
		"player_primed":
			return not cm.primed.is_empty()
		"self_hurt":
			return mech.max_hp() > 0 and float(mech.current_hp()) / mech.max_hp() < float(profile(mech).get("guard", 0.5))
		"ally_hurt":
			return cm.living_enemies().any(func(m): return m != mech and float(m.current_hp()) / maxf(1.0, m.max_hp()) < 0.5)
		"has_charge":
			return charge_card(cm, mech) != null
		"squad":
			return cm.living_enemies().size() > 1
	return false

static func _weight(cm: CombatManager, mech: MechData, r: Dictionary) -> float:
	var w := float(r.get("weight", 1))
	var when = r.get("when", [])
	for cond in (when if when is Array else [when]):
		if condition(cm, mech, str(cond)):
			return w * 3.0
	return w

static func _pick_rhythm(cm: CombatManager, mech: MechData, rng: RandomNumberGenerator) -> Dictionary:
	var list := rhythms(mech)
	var total := 0.0
	for r in list:
		total += _weight(cm, mech, r)
	var roll := rng.randf() * total
	for r in list:
		roll -= _weight(cm, mech, r)
		if roll <= 0.0:
			return r
	return list[0]

## This turn's theme: the next turn of its committed rhythm, or a new
## rhythm when that one's done (or its rhythms changed: phase 2, a lost part).
static func next_theme(cm: CombatManager, mech: MechData, rng: RandomNumberGenerator) -> String:
	var sig := str(rhythms(mech))
	var st: Dictionary = cm.enemy_rhythm.get(mech, {})
	if st.is_empty() or st["sig"] != sig or int(st["i"]) >= (st["r"]["turns"] as Array).size():
		st = {"r": _pick_rhythm(cm, mech, rng), "i": 0, "sig": sig}
	var theme: String = st["r"]["turns"][int(st["i"])]
	st["i"] = int(st["i"]) + 1
	cm.enemy_rhythm[mech] = st
	return theme

## Plans every living enemy's turn (CombatManager, at the start of the
## player's turn): themes first, the squad rule, then each plan (markers
## first, so strikers can aim at what they marked).
static func plan_all(cm: CombatManager) -> void:
	var side := cm.living_enemies()
	cm.ai_memory.erase("squad_mark")
	for w in side:
		for e in lost_entries(w):
			if not cm.enemy_lost_seen.has("%s:%s" % [w.get_instance_id(), e["key"]]):
				cm.enemy_lost_seen["%s:%s" % [w.get_instance_id(), e["key"]]] = true
				if e["entry"].has("note"):
					cm.ai_note.emit(w, "%s %s." % [w.name, e["entry"]["note"]])
		var theme := next_theme(cm, w, cm.rng)
		if theme == "charge" and (cm.enemy_charged.has(w) or charge_card(cm, w) == null):
			theme = "afflict" # one charge at a time, and something to charge
		cm.enemy_theme[w] = theme
	_squad_rule(cm, side)
	var order := side.duplicate()
	order.sort_custom(func(a, b): return _role(a) == "marker" and _role(b) != "marker")
	for w in order:
		cm.enemy_plans[w] = plan_turn(w, cm.rng, cm, cm.player_mech)
		cm.enemy_last.erase(w)
		if (cm.enemy_plans[w] as Array).is_empty() and w.current_heat > 0:
			cm.venting[w] = true

static func _role(mech: MechData) -> String:
	return str(design(mech).get("squad_role", ""))

## Squad rule (Decided as a trial): whenever every enemy shows a payoff
## turn, one of them (a marker first) sets up instead, so there's always
## something to answer before it lands.
static func _squad_rule(cm: CombatManager, side: Array) -> void:
	if side.size() < 2 or side.any(func(m): return SETUP_THEMES.has(cm.enemy_theme.get(m, ""))):
		return
	var pool := side.duplicate()
	pool.sort_custom(func(a, b): return _role(a) == "marker" and _role(b) != "marker")
	for m in pool:
		for r in rhythms(m):
			var first: String = r["turns"][0]
			if SETUP_THEMES.has(first) and not (first == "charge" and (cm.enemy_charged.has(m) or charge_card(cm, m) == null)):
				cm.enemy_theme[m] = first
				cm.enemy_rhythm[m] = {"r": r, "i": 1, "sig": str(rhythms(m))}
				return

## The attack a part would charge: its biggest affordable one, or null. A
## charged shot never takes its own part Offline (Phase 4's "Spin-up").
static func charge_card(cm: CombatManager, mech: MechData) -> CardData:
	var best: CardData = null
	for comp in act_order(mech):
		for c in comp.cards:
			if c.hits <= 0 or c.protocol() != "":
				continue
			if cm != null and cm.effective_cost(c, mech) > heat_limit(mech) - mech.current_heat:
				continue
			if best == null or _expected_damage(c) > _expected_damage(best):
				best = c
	return best

static func _self_offline(c: CardData) -> bool:
	return c.statuses.any(func(st): return st.target == StatusEffectData.TARGET_SELF and st.status == "offline")

static func _afflicts(c: CardData) -> bool:
	return c.statuses.any(func(s): return s.target in [StatusEffectData.TARGET_ENEMY, StatusEffectData.TARGET_ALL_ENEMIES]) \
		or c.rule.get("vs_attacking", {}).has("status") or c.rule.has("status_if_target_status") or c.rule.has("heat_to_target")

static func _guards(c: CardData) -> bool:
	return c.intent() == CardData.INTENT_BLOCK or c.rule.has("guard")

static func _recovers(c: CardData) -> bool:
	return c.rule.has("heal_lowest") or c.rule.has("cleanse") or c.rule.get("self_damage", false) or c.rule.get("vents", false) or c.heat_cost < 0

## How much `theme` wants `c` (higher plays first; below 0 it sits out).
static func theme_score(theme: String, c: CardData, mech: MechData, defender: MechData, p: Dictionary, rng: RandomNumberGenerator) -> float:
	var mult := _best_multiplier(c, defender)
	var dmg := _expected_damage(c) * mult
	var heavy := c.intent() == CardData.INTENT_HEAVY_ATTACK
	var hurt := mech.max_hp() > 0 and float(mech.current_hp()) / mech.max_hp() < float(p.get("guard", 0.5))
	var s := 0.0
	match theme:
		"guard":
			s = (300.0 if _guards(c) else 0.0) + (60.0 if c.hits > 0 and not heavy else 0.0) + dmg * 0.1 - (200.0 if heavy else 0.0)
		"afflict":
			s = (300.0 if _afflicts(c) else 0.0) + dmg * 0.4 + (40.0 if _guards(c) else 0.0)
		"charge":
			s = (200.0 if _guards(c) else 0.0) + (150.0 if _afflicts(c) else 0.0) + dmg * 0.2 - (200.0 if heavy else 0.0)
		"recover":
			s = (300.0 if _recovers(c) else 0.0) + (150.0 if _guards(c) else 0.0) + (40.0 if c.hits > 0 and not heavy else 0.0)
		"combo":
			s = (300.0 if mult > 1.0 else 0.0) + dmg + (100.0 if _afflicts(c) else 0.0) + (30.0 if heavy else 0.0)
		_: # assault
			s = dmg + (15.0 if _afflicts(c) else 0.0) - (40.0 if _guards(c) and not hurt else 0.0) + (120.0 if _guards(c) and hurt else 0.0)
	if c.hits <= 0 and not _guards(c) and not _afflicts(c) and not _recovers(c):
		s += 10.0 # a buff with no tag: cheap filler
	return s - _self_cost(c) + rng.randf() * 20.0 * float(p.get("slip", 0.3))

## The enemy's next turn: [{component, card, target, charge?}] in order,
## before any of it resolves (shown as intent). Its theme orders the cards
## and it plays every one it can afford (self-Disabling cards last on their
## part); a protocol it owns may prime ahead of the attack it helps. Each
## card plays once a turn.
static func plan_turn(warden: MechData, rng: RandomNumberGenerator, cm: CombatManager = null, defender: MechData = null) -> Array:
	var p := profile(warden)
	var theme: String = cm.enemy_theme.get(warden, "assault") if cm != null else "assault"
	var plan := []
	var sim_heat := warden.current_heat
	var limit := heat_limit(warden)
	var cost_of := func(c: CardData) -> int: return cm.effective_cost(c, warden) if cm != null else c.heat_cost
	var charged: CardData = null
	if theme == "charge":
		charged = charge_card(cm, warden) if cm != null else null
		if charged != null:
			var comp := warden.get_component(charged.owner_component_id)
			plan.append({"component": comp, "card": charged, "charge": true})
			sim_heat += cost_of.call(charged)
	# A charged attack fires as this turn starts: that card is used this turn.
	var firing: CardData = cm.enemy_charged.get(warden, {}).get("card", null) if cm != null else null
	var desperate := warden.max_hp() > 0 and float(warden.current_hp()) / warden.max_hp() < float(design(warden).get("desperate", 0.3))
	var protocols: Array = []
	var pool: Array = []
	for component in act_order(warden):
		for c in component.cards:
			if (cm != null and cm.is_spent(c)) or c == charged or c == firing:
				continue
			if c.protocol() != "":
				if ENEMY_PROTOCOLS.has(c.protocol()) and not (c.protocol() == "grant" and str(c.rule.get("on", "attack")) != "attack"):
					protocols.append({"component": component, "card": c})
				continue
			if _self_offline(c) and not desperate:
				continue # Precision Throw: a desperation play only (Decided)
			var sc := theme_score(theme, c, warden, defender, p, rng)
			if sc >= 0.0:
				pool.append({"component": component, "card": c, "score": sc})
	pool.sort_custom(func(a, b): return a["score"] > b["score"])
	var picked := []
	for e in pool:
		var cost: int = cost_of.call(e["card"])
		if sim_heat + cost <= limit:
			picked.append(e)
			sim_heat += cost
	# A card that Disables or Offlines its own part goes after the rest.
	for e in picked.filter(func(x): return not _self_stops(x["card"])) + picked.filter(func(x): return _self_stops(x["card"])):
		plan.append({"component": e["component"], "card": e["card"]})
	if theme in ["assault", "combo", "afflict"]:
		_shuffle(protocols, rng)
		for pr in protocols:
			_add_protocol(plan, [pr], p, rng, sim_heat, limit)
	if defender != null:
		var memory: Dictionary = cm.ai_memory if cm != null else {}
		for step in plan:
			if (step["card"] as CardData).is_attack() and (step["card"] as CardData).protocol() == "" and not step.get("charge", false):
				step["target"] = choose_target(defender, rng, warden, step["card"], memory)
				if cm != null and _role(warden) == "marker" and not memory.has("squad_mark"):
					memory["squad_mark"] = step["target"]
	return plan

static func _self_stops(c: CardData) -> bool:
	return c.statuses.any(func(st): return st.target == StatusEffectData.TARGET_SELF and st.status in ["disabled", "offline", "freeze"])

## After a player command: the shown plan is repaired, not remade. Steps
## aimed at a destroyed part get a new target now; Heat freed by steps the
## player cancelled (Disabled, Frozen, destroyed parts) goes to any card the
## enemy can still use (Decided), shown as added steps.
static func repair(cm: CombatManager, w: MechData) -> void:
	if w.is_defeated() or cm.phase != CombatManager.Phase.PLAYER_TURN:
		return
	var plan: Array = cm.enemy_plans.get(w, [])
	var sim_heat := w.current_heat
	var cancelled := false
	var used := {}
	for step in plan:
		used[step["card"]] = true
		if not (step["component"] as ComponentData).is_usable():
			if not step.get("refilled", false):
				cancelled = true
				step["refilled"] = true
			continue
		sim_heat += cm.effective_cost(step["card"], w)
		var t = step.get("target", null)
		if t != null and (t as ComponentData).destroyed and not step.get("charge", false):
			step["target"] = choose_target(cm.player_mech, cm.rng, w, step["card"], cm.ai_memory)
	if not cancelled:
		return
	var p := profile(w)
	var theme: String = cm.enemy_theme.get(w, "assault")
	var limit := heat_limit(w)
	var pool := []
	for comp in act_order(w):
		for c in comp.cards:
			if used.has(c) or cm.is_spent(c) or c.protocol() != "" or _self_offline(c):
				continue
			var sc := theme_score(theme, c, w, cm.player_mech, p, cm.rng)
			if sc >= 0.0:
				pool.append({"component": comp, "card": c, "score": sc})
	pool.sort_custom(func(a, b): return a["score"] > b["score"])
	for e in pool:
		var cost := cm.effective_cost(e["card"], w)
		if sim_heat + cost <= limit:
			sim_heat += cost
			var step := {"component": e["component"], "card": e["card"], "added": true}
			if (e["card"] as CardData).is_attack():
				step["target"] = choose_target(cm.player_mech, cm.rng, w, e["card"], cm.ai_memory)
			plan.append(step)

## Fight-start setups (data/enemy_ai.json "opener"), so turn 1 already has
## a threat to answer.
static func apply_openers(cm: CombatManager) -> void:
	for w in cm.enemies:
		var op = design(w).get("opener", [])
		var notes := []
		for o in (op if op is Array else [op]):
			match str(o.get("type", "")):
				"charged":
					var c := charge_card(null, w)
					if c != null:
						cm.enemy_charged[w] = {"card": c, "component": w.get_component(c.owner_component_id)}
				"primed":
					for comp in w.non_destroyed_components():
						for c in comp.cards:
							if c.protocol() != "" and (str(o.get("card", "")) == c.id or (not o.has("card") and ENEMY_PROTOCOLS.has(c.protocol()))) and not cm.enemy_primed.has(w):
								cm.enemy_primed[w] = [{"type": c.protocol(), "card": c, "component": comp}]
				"player_status":
					var part := _opener_target(cm, str(o.get("target", "any")))
					if part != null:
						CardResolver.add_status_to(cm.player_mech, part, str(o["status"]), int(o.get("stacks", 1)), true)
				"self_status":
					var parts := w.non_destroyed_components()
					if not parts.is_empty():
						CardResolver.add_status_to(w, parts[0], str(o["status"]), int(o.get("stacks", 1)), false)
			if o.has("note"):
				notes.append(str(o["note"]))
		if not notes.is_empty():
			cm.ai_note.emit(w, "%s: %s." % [w.name, ", ".join(notes)])

static func _opener_target(cm: CombatManager, kind: String) -> ComponentData:
	var parts := cm.player_mech.non_destroyed_components()
	if parts.is_empty():
		return null
	var best: ComponentData = null
	match kind:
		"strongest_weapon":
			for c in parts:
				if c.category == ComponentData.CATEGORY_HARDPOINT and (best == null or _best_card_damage(c) > _best_card_damage(best)):
					best = c
		"most_damaged":
			for c in parts:
				if best == null or float(c.current_hp) / c.max_hp < float(best.current_hp) / best.max_hp:
					best = c
	return best if best != null else parts[cm.rng.randi() % parts.size()]

static func _best_card_damage(c: ComponentData) -> float:
	var best := 0.0
	for card in c.cards:
		best = maxf(best, _expected_damage(card))
	return best

static func _shuffle(list: Array, rng: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = list[i]
		list[i] = list[j]
		list[j] = tmp

## Maybe primes one protocol ahead of the attack it helps most (each
## protocol it owns gets its own roll, so a protocol-heavy boss spreads them
## over its attacks; one waits at a time, so never two before the same attack).
static func _add_protocol(plan: Array, protocols: Array, p: Dictionary, rng: RandomNumberGenerator, sim_heat: int, limit: int) -> void:
	var attacks := plan.filter(func(s): return (s["card"] as CardData).hits > 0 and not _primed_before(plan, s))
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

## Whether a priming protocol (not Replay, which acts at once) sits right
## before `step` in the plan.
static func _primed_before(plan: Array, step: Dictionary) -> bool:
	var i := plan.find(step)
	if i <= 0:
		return false
	var proto := (plan[i - 1]["card"] as CardData).protocol()
	return proto != "" and proto != "replay"

## Whether playing `card` stops its own part from acting again this turn.
static func _disables_self(card: CardData) -> bool:
	return card.statuses.any(func(st): return st.target == StatusEffectData.TARGET_SELF and st.status in ["disabled", "offline", "freeze"])

## The damage multiplier `card` gets against `c` from its own rule (EMP
## Round x3 on a shocked hardpoint, Thrust Through x2 on one at half HP).
static func _multiplies_on(card: CardData, c: ComponentData, defender: MechData = null) -> float:
	return CardResolver.card_multiplier(card, c, defender)

## The best multiplier `card` could get on any of `defender`'s living parts.
static func _best_multiplier(card: CardData, defender: MechData) -> float:
	var best := 1.0
	if defender == null:
		return best
	for c in defender.non_destroyed_components():
		best = maxf(best, _multiplies_on(card, c, defender))
	return best

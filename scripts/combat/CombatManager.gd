class_name CombatManager
extends RefCounted
## The round state machine (Combat Slice §4.1) and win/lose check. Owns one
## seeded RNG for the whole fight so tests and bug repros are deterministic.
## Pure/headless: no scene tree dependency, so it's fully unit-testable
## (tests/TestCombatManager.gd) and the UI layer is just a thin wrapper
## around this + its signals.
##
## Everything a card or part can do is resolved here and in CardResolver
## (rules from data/component_rules.json): card costs after Coolant / Jam /
## Overclock Shunt, parts that can't act (Disabled / Offline, Freeze going
## Offline on use), hit chances, multi-target hits, repeating attacks,
## primed protocols (see the Protocols section), and the passives that fire
## on turns, hits and destruction.
##
## The fight's state lives here; its rules are split into static helpers
## that take this manager: CombatAttack (the hit pipeline and attack
## modifiers), CombatProtocols (the player's protocols), CombatEnemyTurn
## (the enemies' actions and protocols) and CombatHeat (overheat and
## venting). The underscored state below is shared with them.

enum Phase { PLAYER_TURN, ENEMY_TURN, GAME_OVER }
enum Result { NONE, WIN, LOSE }

signal component_damaged(mech: MechData, component: ComponentData, amount: int)
signal component_destroyed(mech: MechData, component: ComponentData)
signal card_played(mech: MechData, card: CardData)
signal overheated(mech: MechData, backlash: int)
signal turn_changed(phase: Phase, turn_number: int)
signal enemy_action(log_entry: Dictionary)
signal game_over(result: Result)
signal enemy_turn_started()
## One hit of an attack card landed (or was fully blocked: damage 0).
signal hit_landed(mech: MechData, component: ComponentData, damage: int)
## One hit didn't fire (a hit-chance card, e.g. Rapid Fire's later hits).
signal hit_missed(mech: MechData, component: ComponentData)
## A component's passive just did something (Capacitor Bank charged,
## Redirect Spike took a hit, Insulated Core cut incoming stacks).
signal passive_triggered(mech: MechData, component: ComponentData)
## The cards in hand changed (Intercept's copy added or used up).
signal hand_changed()
## A protocol was primed or used up.
signal primed_changed()
## A boss fell to half HP and changed how it fights.
signal boss_phase_changed(mech: MechData)
## An enemy's Standby set its next attack aside for its next turn.
signal enemy_set_aside(mech: MechData, card: CardData)
## A card's chance-based effect didn't happen (its status roll failed).
signal chance_failed(mech: MechData, component: ComponentData)
## A mech used the Vent action: its heat just dispersed at the flat share.
signal mech_vented(mech: MechData, amount: int)
## An enemy left the fight: no part could give it a card again (a kill).
signal enemy_retreated(mech: MechData)

## Enemies that started the fight with cards: only they can run out and
## retreat (a part with no cards at all, like a test dummy, stays).
var _armed: Array = []
## A line about what an enemy is up to (its opener, a charge fizzling, a lost part), for the combat log.
signal ai_note(mech: MechData, text: String)

const PROTOCOLS_PRIMED := ["lock_on", "split_feed", "catalyze", "reroute", "standby", "overdrive", "bleed_off",
	"discount", "fan_out", "siphon", "pierce", "chain", "knockback", "double_hits", "execute", "max_roll",
	"invert", "last_stand", "vent_on_hit", "fortify", "recall", "grant", "defer_heat"]
## Statuses Reroute can swap to (enemy-applied ones).
const REROUTE_OPTIONS := ["shock", "acid", "burn", "disabled", "freeze", "jam", "smoke"]

var player_mech: MechData
var enemies: Array[MechData] = []
var rng: RandomNumberGenerator
var phase: Phase = Phase.PLAYER_TURN
var turn_number: int = 1
var result: Result = Result.NONE
## true: end_player_turn() resolves the whole enemy turn at once (tests).
## false: it stops after enemy_turn_started and the caller steps through it.
var auto_resolve_enemy_turn: bool = true

## Each living enemy's cards for its next turn, chosen when the player's
## turn starts (MechData -> [{component, card}]). Shown as intent.
var enemy_plans: Dictionary = {}
## Enemy AI memory: the player part each enemy last attacked (MechData -> ComponentData).
var ai_memory: Dictionary = {}
## Enemies' primed protocols (MechData -> [{type, card, component}]), their
## last attack this turn (for Replay) and an attack set aside by Standby
## ({card, component, target}), and whether a Standby waits for its next attack.
var enemy_primed: Dictionary = {}
var enemy_last: Dictionary = {}
var enemy_standby: Dictionary = {}
var _enemy_standby_pending: Dictionary = {}

## Protocols primed and waiting for the next card they apply to:
## [{"type", "card", "component", "status" (Reroute)}].
var primed: Array = []
## One-use cards added to the hand (Intercept).
var bonus_cards: Array[CardData] = []
## A card set aside by Standby: {card, target_mech, target}, played at the
## start of the next player turn for 0 heat.
var standby: Dictionary = {}
## Attacks repeating on later turns (Spillage): [{card, attacker_mech,
## attacker_component, defender_mech, target, turns_left}].
var repeats: Array = []

## Single-use cards (Decided, Logan 2026-09-30): every card can be played
## once per turn, by the player and enemies alike, and comes back when the
## next round starts (the player's turn). Nothing more, nothing less.
## CardData -> true. Intercept's copies are one-use and leave the hand instead.
var spent: Dictionary = {}
## Mechs that took the Vent action this turn (MechData -> true): their next
## heat dispersal vents heat.vent_action_share of their heat instead of the ratio.
var venting: Dictionary = {}

var _enemy_idx: int = 0
var _enemy_step: int = 0
var _in_flight: Dictionary = {} # the step next_enemy_action returned, until it resolves
## The attack card currently resolving hit by hit (see begin_attack), or {}.
var _attack: Dictionary = {}

## Per player turn: cards and attack cards played, the last card played
## (Replay), and heat vented by cards waiting to boost an attack (Recycling Loops).
var _cards_this_turn: int = 0
var _attacks_this_turn: int = 0
var _last_played: Dictionary = {}
var _recycle_bonus: int = 0

## This fight's counters for the debrief (RunData merges them into the run's).
var stats := RunStats.new()
var _turn_damage: int = 0
var _player_parts_at_start: int = 0

## Per fight / per turn state for Claude's parts (Phase 10): who has dodged
## this round (Blink Drive), a free next card (Neural Link), how often each
## card was played (Resonance Blade), enemies' attacks this turn.
var _dodged: Dictionary = {}
var _refund_next: bool = false
var _card_plays: Dictionary = {}
var _enemy_attacks: Dictionary = {}
## Card pass (Notion: Dynamic Turn Rework, Phase 5). Guards a self card put
## up until its side's next turn: mech -> [{type, component, ...}]
## (CombatAttack.self_rules). Enemy parts turned by Yank Aim this round
## (their attacks hit their own mech). Player parts that attacked this
## turn, which enemy cards read as "attacking". Drive: no more cards.
var guards: Dictionary = {}
var turned: Dictionary = {}
var player_attackers: Dictionary = {}
var _last_card: bool = false
## Batch: Heat the player pays at the start of their next turn. Loaded
## Dice: the player's next attack rolls min.
var deferred_heat: int = 0
## Phase 6 enemy AI (EnemyAI): this turn's theme per enemy, its committed
## two-turn rhythm ({r, i, sig}), charged attacks waiting to fire as its
## next turn starts ({card, component}), lost-part notes already given,
## and the share of max Heat the player ended their last turn at.
var enemy_theme: Dictionary = {}
var enemy_rhythm: Dictionary = {}
var enemy_charged: Dictionary = {}
var enemy_lost_seen: Dictionary = {}
var player_heat_last: float = 0.0
var _min_roll_next: bool = false

func _init(p_player: MechData, p_enemies: Array[MechData], seed_value: int = -1) -> void:
	player_mech = p_player
	enemies = p_enemies
	rng = RandomNumberGenerator.new()
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()

func start_combat() -> void:
	_player_parts_at_start = player_mech.non_destroyed_components().size()
	_armed = enemies.filter(func(w): return w.has_cards_left())
	spent.clear()
	venting.clear()
	for m in [player_mech] + enemies:
		for c in m.components:
			c.set_meta("save_used", 0) # Reinforced Bulkhead: saves used this fight
	turn_number = 1
	result = Result.NONE
	phase = Phase.PLAYER_TURN
	EnemyAI.apply_openers(self)
	_start_player_turn()

func is_player_turn() -> bool:
	return phase == Phase.PLAYER_TURN and result == Result.NONE and _attack.is_empty()

func has_pending_attack() -> bool:
	return not _attack.is_empty()

func is_game_over() -> bool:
	return phase == Phase.GAME_OVER

## The part the pending attack is aimed at ({"mech", "comp"}), or {}.
## The targeting preview: what `card` would do to `target` now (CombatAttack.preview).
func preview_attack(card: CardData, defender: MechData, target: ComponentData) -> Dictionary:
	return CombatAttack.preview(self, card, defender, target)

## The card whose hits are resolving (a Salvo moves on card by card), or null.
func pending_card() -> CardData:
	return _attack.get("card", null)

## The part whose card is resolving (for its hit sound), or null.
func pending_attacker_component() -> ComponentData:
	return _attack.get("attacker_component", null)

func pending_target() -> Dictionary:
	if not _attack.has("card"):
		return {}
	return {"mech": _attack["defender_mech"], "comp": _attack["target"]}

func living_enemies() -> Array[MechData]:
	return enemies.filter(func(m): return not m.is_defeated())

# ---------- commands ----------
## Every player decision can go through apply() as a plain dictionary that
## names things by id, so the UI, the sim, tests or (later) a co-op peer can
## drive a fight, and the same seed plus `command_log` replays it exactly:
##   {"type": "play", "card": "<part id>/<card id>", "target": [mech, "<part id>"], "options": {...}}
##   {"type": "vent"}
##   {"type": "end_turn"}
## `target` is for attack cards only (mech 0 is the player, 1.. the enemies
## in order); `options` for Reroute's pick ({"status"}). A play with
## "paced": true only begins its attack, and the caller steps it with
## next_hit() / finish_attack() (the UI paces hits that way); the log
## leaves "paced" out. Only commands that went through are logged.

## The player's accepted commands, in order.
var command_log: Array = []

## Runs one command. Returns what the call it maps to returns ({"ok", ...}).
func apply(cmd: Dictionary) -> Dictionary:
	var paced: bool = cmd.get("paced", false)
	var res := {}
	match str(cmd.get("type", "")):
		"play":
			var card := find_card(str(cmd.get("card", "")))
			if card == null:
				return {"ok": false, "reason": "no_card"}
			if card.is_attack():
				var t: Array = cmd.get("target", [])
				var mech := mech_at(int(t[0])) if t.size() == 2 else null
				var comp := mech.get_component(str(t[1])) if mech != null else null
				if comp == null:
					return {"ok": false, "reason": "no_target"}
				res = begin_attack(card, mech, comp)
				if res["ok"] and not paced and has_pending_attack():
					res = finish_attack()
			else:
				res = play_self_card(card, cmd.get("options", {}))
				if res["ok"] and res.get("started_attack", false) and not paced:
					res = finish_attack()
		"vent":
			res = {"ok": vent_action()}
		"end_turn":
			res = {"ok": is_player_turn()}
			end_player_turn()
		_:
			return {"ok": false, "reason": "unknown_command"}
	if res.get("ok", false):
		var entry := cmd.duplicate(true)
		entry.erase("paced")
		command_log.append(entry)
	return res

## Plays a command log from the start (on a fresh fight with the same mechs
## and seed, after start_combat).
func replay(commands: Array) -> void:
	for cmd in commands:
		apply(cmd)

## A card's id in commands: "<part id>/<card id>".
static func card_key(card: CardData) -> String:
	return "%s/%s" % [card.owner_component_id, card.id]

## The card in the player's hand (spent or not) with that key, or null.
func find_card(key: String) -> CardData:
	for c in hand_cards(true):
		if card_key(c) == key:
			return c
	return null

## Mechs by index: 0 is the player, 1.. the enemies in order.
func mech_at(i: int) -> MechData:
	if i == 0:
		return player_mech
	return enemies[i - 1] if i >= 1 and i <= enemies.size() else null

func mech_index(mech: MechData) -> int:
	return 0 if mech == player_mech else enemies.find(mech) + 1

## A play command for `card` (at `target` on `mech` for an attack).
func play_command(card: CardData, mech: MechData = null, target: ComponentData = null, options: Dictionary = {}) -> Dictionary:
	var cmd := {"type": "play", "card": card_key(card)}
	if mech != null and target != null:
		cmd["target"] = [mech_index(mech), target.id]
	if not options.is_empty():
		cmd["options"] = options
	return cmd

# ---------- cards: cost, playability, the hand ----------

## The cards in the player's hand: every living part's cards not yet
## played this fight, plus one-use extras. `include_spent`: the spent ones
## too (the hand shows them greyed).
func hand_cards(include_spent: bool = false) -> Array[CardData]:
	var out: Array[CardData] = []
	for c in player_mech.all_playable_cards():
		if include_spent or not is_spent(c):
			out.append(c)
	for c in bonus_cards:
		out.append(c)
	return out

# ---------- single-use cards ----------

func is_spent(card: CardData) -> bool:
	return spent.has(card)

func _spend(card: CardData) -> void:
	if not card.one_use:
		spent[card] = true

## Returns a spent card to the hand (tests use it to play a card twice in
## one turn; no game rule does). Returns whether it was spent.
func reload(card: CardData) -> bool:
	if not spent.erase(card):
		return false
	hand_changed.emit()
	return true

## How many of `mech`'s cards (on living parts) are still unplayed this turn.
func cards_left(mech: MechData) -> int:
	return mech.all_playable_cards().filter(func(c): return not is_spent(c)).size()

## Whether every card `mech` has left standing has been played.
func out_of_cards(mech: MechData) -> bool:
	return cards_left(mech) == 0 and (mech != player_mech or bonus_cards.is_empty())

# ---------- the Vent action ----------
## Proposed default (the vent itself is Decided; its details are the open
## "enemy vent details" item): Vent takes the whole turn. It's only
## allowed before any card this turn, ends the turn, and the mech's next
## dispersal vents a flat share of its heat (as if it were at max).

func can_vent() -> bool:
	return is_player_turn() and _cards_this_turn == 0 and player_mech.current_heat > 0

## The player's Vent action. Returns whether it happened.
func vent_action() -> bool:
	if not can_vent():
		return false
	venting[player_mech] = true
	stats.add("vents")
	end_player_turn()
	return true

## Whether this enemy's plan for its coming turn is to vent.
func enemy_venting(mech: MechData) -> bool:
	return venting.has(mech) and not mech.is_defeated()

## What `card` costs to play right now: Coolant −1 and Jam +1 while the part
## holds them, Overclock Shunt −1 on the first card of the turn. Discounts
## never take a positive cost below 0, and don't touch venting cards.
func effective_cost(card: CardData, mech: MechData = null) -> int:
	if mech == null:
		mech = player_mech
	var comp := mech.get_component(card.owner_component_id)
	var cost := card.heat_cost
	if comp == null or card.heat_cost <= 0:
		return cost
	if comp.status_stacks("jam") > 0:
		cost += 1
	if comp.status_stacks("coolant") > 0:
		cost -= 1
	if mech == player_mech and _cards_this_turn == 0:
		for s in mech.living_passives(ComponentData.PASSIVE_FIRST_CARD_DISCOUNT):
			cost -= int(s.passive.get("amount", 0))
	for pa in mech.living_passives("linked_cost_down"):
		if Links.linked(mech, pa).has(comp):
			cost -= int(pa.passive.get("amount", 1))
	if mech == player_mech and card.protocol() == "":
		for p in primed:
			if p["type"] == "discount":
				# Last Stand: only while the mech is at or below that share of its HP.
				var below: float = float(p["card"].rule.get("if_below", 1.0))
				if below >= 1.0 or float(mech.current_hp()) <= mech.max_hp() * below:
					cost -= int(p["card"].rule.get("amount", 2))
		if _refund_next:
			cost = 0
	return maxi(cost, 0)

## Whether playing `card` now would overheat the player at once (a live
## heat check, and no Overheat Fuse to take it). An end-of-turn checker
## (Redline) overheats on End Turn instead: end_turn_overheats().
func would_overheat(card: CardData) -> bool:
	if player_mech.heat_check_timing == MechData.HEAT_CHECK_END_OF_TURN:
		return false
	return HeatRules.is_overheated(player_mech.current_heat + effective_cost(card), player_mech.heat_capacity()) \
		and player_mech.living_passives("overheat_fuse").is_empty()

## Whether ending the turn now overheats the player (end-of-turn checkers).
func end_turn_overheats() -> bool:
	return player_mech.heat_check_timing == MechData.HEAT_CHECK_END_OF_TURN \
		and HeatRules.is_overheated(player_mech.current_heat, player_mech.heat_capacity()) \
		and player_mech.living_passives("overheat_fuse").is_empty()

## Whether an overheat now could lose the fight: its backlash (spread one
## point at a time over random parts) is at least the HP left on the
## player's hardpoints.
func overheat_could_kill() -> bool:
	var left := 0
	for c in player_mech.non_destroyed_components():
		if c.category == ComponentData.CATEGORY_HARDPOINT:
			left += c.current_hp
	return HeatRules.backlash_for(player_mech) >= left

## Whether the player can play `card` now (its part standing and usable).
func can_play(card: CardData) -> bool:
	if not is_player_turn():
		return false
	var comp := player_mech.get_component(card.owner_component_id)
	return comp != null and comp.is_usable() and not is_spent(card) and not _last_card

## Heat change for playing a card: its cost, unless Bleed Off is primed
## (then a linked part pays it in HP). Negative costs vent, floored at 0
## heat; venting feeds Recycling Loops. Returns the heat actually added.
func _pay_heat(mech: MechData, card: CardData, cost: int, allow_bleed: bool) -> int:
	if allow_bleed and cost > 0:
		var bleed := CombatProtocols.take_primed(self, "bleed_off", card)
		if not bleed.is_empty():
			var bus: ComponentData = bleed["component"]
			var linked := Links.linked(mech, bus)
			if not linked.is_empty():
				var payer: ComponentData = linked[0]
				var r := CardResolver.deal_damage(mech, payer, cost)
				stats.add("damage_taken", int(r["applied"]))
				hit_landed.emit(mech, payer, int(r["applied"]))
				CombatAttack.emit_destroyed_if(self, mech, payer)
				return 0
	var before := mech.current_heat
	mech.current_heat = maxi(0, mech.current_heat + cost)
	var vented := before - mech.current_heat
	if vented > 0 and mech == player_mech and not mech.living_passives(ComponentData.PASSIVE_RECYCLE_VENT).is_empty():
		_recycle_bonus += vented
		passive_triggered.emit(mech, mech.living_passives(ComponentData.PASSIVE_RECYCLE_VENT)[0])
	return mech.current_heat - before

## After a part is used: Coolant/Jam lose a stack, Freeze turns it Offline.
func _after_use(comp: ComponentData) -> void:
	for s in ["coolant", "jam"]:
		if comp.status_stacks(s) > 0:
			comp.remove_status(s, 1)
	if comp.status_stacks("freeze") > 0:
		comp.remove_status("freeze", 99)
		comp.add_status("offline", 1)

# ---------- player attacks ----------

## Plays an attack card from the player's hand at one enemy component,
## all at once. Combat Slice §4.4: precise targeting only, all hits/damage/
## statuses go to this one component.
func play_attack_card(card: CardData, target_mech: MechData, target_component: ComponentData) -> Dictionary:
	var begun := begin_attack(card, target_mech, target_component)
	if not begun["ok"] or not has_pending_attack():
		return begun
	return finish_attack()

## Step-wise play_attack_card, so the UI can pace the hits: begin_attack()
## pays the heat, next_hit() resolves one hit at a time, finish_attack()
## applies the card's statuses and runs the after-card checks (overheat,
## win/lose). Resolves exactly like play_attack_card, same RNG order.
## Returns {"ok", "reason"?, "no_attack"?: true when nothing is left to
## step through (Standby set it aside, Intercept took a copy)}.
func begin_attack(card: CardData, target_mech: MechData, target_component: ComponentData) -> Dictionary:
	if not is_player_turn():
		return {"ok": false, "reason": "not_player_turn"}
	if target_component == null or target_component.destroyed:
		return {"ok": false, "reason": "target_destroyed"}
	var attacker_component := player_mech.get_component(card.owner_component_id)
	if attacker_component == null or attacker_component.destroyed:
		return {"ok": false, "reason": "source_destroyed"}
	if not attacker_component.is_usable():
		return {"ok": false, "reason": "source_unusable"}
	if is_spent(card):
		return {"ok": false, "reason": "spent"}
	if _last_card:
		return {"ok": false, "reason": "last_card"}
	if card.rule.get("no_hardpoints", false) and target_component.category == ComponentData.CATEGORY_HARDPOINT:
		return {"ok": false, "reason": "no_hardpoints"}

	match card.protocol():
		"intercept":
			return CombatProtocols.play_intercept(self, card, attacker_component, target_mech)
		"salvo":
			return CombatProtocols.play_salvo(self, card, attacker_component, target_mech, target_component)
	if CombatProtocols.set_aside_for_standby(self, card, target_mech, target_component):
		return {"ok": true, "no_attack": true}

	var cost := effective_cost(card)
	cost = CombatProtocols.defer_heat(self, card, cost)
	_pay_heat(player_mech, card, cost, true)
	CombatProtocols.used_cost_mods(self, card)
	_count_card(card, cost)
	_note_played(card, attacker_component, target_mech, target_component)
	CombatProtocols.any_card_protocols(self, card, cost, target_mech, target_component)
	if card.hits > 0:
		player_attackers[attacker_component] = true
	if card.rule.get("last_card", false):
		_last_card = true
	var played := CombatProtocols.player_granted(self, card)
	CombatAttack.start(self, played, player_mech, attacker_component, target_mech, target_component, CombatProtocols.player_mods(self, played))
	_after_use(attacker_component)
	card_played.emit(player_mech, card)
	return {"ok": true}

## Resolves the pending attack's next hit (CombatAttack.next_hit). Empty
## once every hit is done, or once the target is destroyed.
func next_hit() -> Dictionary:
	return CombatAttack.next_hit(self)

## Finishes the pending attack (resolving any hits not yet stepped through).
## Player attacks return like play_attack_card; enemy attacks return the
## enemy_action log entry.
func finish_attack() -> Dictionary:
	if _attack.has("card"):
		while not next_hit().is_empty():
			pass
	if not _attack.has("card"):
		_attack = {}
		# A Salvo that ran out of targets (it destroyed the last enemy with
		# hardpoints still to fire): the fight may be won, or the heat over.
		if phase == Phase.PLAYER_TURN and result == Result.NONE:
			var over := CombatHeat.check_player_overheat(self)
			_check_game_over()
			return {"ok": true, "result": {"total_damage": 0, "hits_landed": 0, "target_destroyed": true}, "overheated": over}
		return {}
	var a := _attack
	_attack = {}
	var card: CardData = a["card"]
	var target: ComponentData = a["target"]
	CombatAttack.finish_statuses(self, a)
	var res := {"total_damage": a["total"], "hits_landed": a["hits_landed"], "target_destroyed": target.destroyed}

	if a["attacker_mech"] != player_mech:
		_in_flight = {}
		var entry := {
			"mech": a["attacker_mech"], "component": a["attacker_component"].id, "card": card.id,
			"target": target.id, "damage": a["total"], "target_destroyed": target.destroyed,
			"protocol": card.protocol(),
		}
		enemy_action.emit(entry)
		if target.destroyed:
			component_destroyed.emit(a["defender_mech"], target) # Yank Aim can turn it on its own mech
		return entry

	if card.one_use:
		_use_up(card)
	_repair_enemy_plans()
	component_damaged.emit(a["defender_mech"], target, res["total_damage"])
	if target.destroyed:
		component_destroyed.emit(a["defender_mech"], target)
	if CombatHeat.check_player_overheat(self):
		return {"ok": true, "result": res, "overheated": true}
	_check_game_over()
	return {"ok": true, "result": res, "overheated": false}

## Plays a self card (Extension, Spike Setup, a protocol, Self Splash...).
## `options`: {"status": ...} for Reroute's pick. Returns {"ok", "overheated",
## "started_attack": true when a Replay began an attack to step through}.
func play_self_card(card: CardData, options: Dictionary = {}) -> Dictionary:
	if not is_player_turn():
		return {"ok": false, "reason": "not_player_turn"}
	var owner_component := player_mech.get_component(card.owner_component_id)
	if owner_component == null or owner_component.destroyed:
		return {"ok": false, "reason": "source_destroyed"}
	if not owner_component.is_usable():
		return {"ok": false, "reason": "source_unusable"}
	if is_spent(card):
		return {"ok": false, "reason": "spent"}
	if _last_card:
		return {"ok": false, "reason": "last_card"}
	var proto := card.protocol()
	if proto == "replay":
		return CombatProtocols.play_replay(self, card, owner_component)
	if proto == "steal":
		return CombatProtocols.play_steal(self, card, owner_component)
	if proto == "clear_enemy":
		return CombatProtocols.play_clear_enemy(self, card, owner_component)
	if proto == "" and CombatProtocols.set_aside_for_standby(self, card, null, null):
		return {"ok": true, "overheated": false}

	var cost := effective_cost(card)
	if proto == "":
		cost = CombatProtocols.defer_heat(self, card, cost)
	_pay_heat(player_mech, card, cost, proto == "")
	CombatProtocols.used_cost_mods(self, card)
	_count_card(card, cost)
	if PROTOCOLS_PRIMED.has(proto):
		CombatProtocols.prime(self, proto, card, owner_component, options)
	else:
		CombatProtocols.any_card_protocols(self, card, cost, null, null)
		var played := CombatProtocols.player_granted(self, card)
		var mods := CombatProtocols.player_mods(self, played)
		CardResolver.resolve_self_card(played, player_mech, owner_component, mods)
		CombatAttack.self_rules(self, played, player_mech, owner_component)
		if card.rule.get("self_damage", false):
			var dmg := CardResolver.roll_damage(card, rng)
			var r := CardResolver.deal_damage(player_mech, owner_component, dmg)
			stats.add("damage_taken", int(r["applied"]))
			hit_landed.emit(player_mech, owner_component, int(r["applied"]))
			CombatAttack.emit_destroyed_if(self, player_mech, owner_component)
		_note_played(card, owner_component, null, null)
	_after_use(owner_component)
	_repair_enemy_plans()
	card_played.emit(player_mech, card)

	if _check_game_over():
		return {"ok": true, "overheated": false}
	if CombatHeat.check_player_overheat(self):
		return {"ok": true, "overheated": true}
	return {"ok": true, "overheated": false}

func is_primed(type: String) -> bool:
	return CombatProtocols.is_primed(self, type)

func _use_up(card: CardData) -> void:
	bonus_cards.erase(card)
	hand_changed.emit()

func _note_played(card: CardData, _comp: ComponentData, target_mech: MechData, target: ComponentData) -> void:
	if card.protocol() == "":
		_last_played = {"card": card, "target_mech": target_mech, "target": target}

# ---------- turns ----------

## End Turn button (or the forced end from an overheat). Runs round
## structure steps 3-6 then loops back into step 1 for the next player turn.
func end_player_turn() -> void:
	if phase != Phase.PLAYER_TURN or result != Result.NONE or not _attack.is_empty():
		return

	# End-of-turn heat check (Redline): over max now = backlash.
	if player_mech.heat_check_timing == MechData.HEAT_CHECK_END_OF_TURN \
			and HeatRules.is_overheated(player_mech.current_heat, player_mech.heat_capacity()) \
			and not CombatHeat.burn_fuse(self, player_mech):
		CombatHeat.backlash(self, player_mech)
		if _check_game_over():
			return

	# Step 3: end-of-turn decay on the player's own components.
	CardResolver.decay_end_of_turn_statuses(player_mech)

	phase = Phase.ENEMY_TURN
	turn_changed.emit(phase, turn_number)

	player_heat_last = float(player_mech.current_heat) / maxf(1.0, float(player_mech.heat_capacity()))
	# Step 4: player heat disperses; each living Warden's turn starts
	# (Absorb clears, Burn heats it, turn-start passives, repeating attacks).
	CombatHeat.vent(self, player_mech)
	_refund_next = false
	for w in enemies:
		_dodged[w] = 0
		_enemy_attacks[w] = 0
		w.clear_mech_status("absorb")
		_drop_guards(w)
		if not w.is_defeated():
			CardResolver.apply_burn(w)
			_apply_turn_start_passives(w) # e.g. Capacitor Bank
	# An enemy that can never play a card again retreats as its turn starts
	# (Logan, 2026-10-13: it counts as a kill, bosses included).
	for w in enemies:
		if _armed.has(w) and not w.is_defeated() and not w.has_cards_left():
			w.retreated = true
			enemy_retreated.emit(w)
	_run_repeats(false)
	CombatEnemyTurn.run_standby(self)
	CombatEnemyTurn.run_charged(self)
	if _check_game_over():
		return

	# Step 5: Warden 1 -> 2 -> 3, each acting fully before the next.
	_enemy_idx = 0
	_enemy_step = 0
	_in_flight = {}
	enemy_turn_started.emit()
	if not auto_resolve_enemy_turn:
		return # the UI drives next_enemy_action / execute_enemy_action / finish_enemy_turn
	while true:
		var action := next_enemy_action()
		if action.is_empty():
			break
		execute_enemy_action(action)
	finish_enemy_turn()

## The next planned enemy action, with its target chosen now; empty when
## the enemy turn is over (CombatEnemyTurn.next_action).
func next_enemy_action() -> Dictionary:
	return CombatEnemyTurn.next_action(self)

## What each enemy still intends to do, in order: [{card, active, target,
## component}] (CombatEnemyTurn.upcoming_actions).
func upcoming_enemy_actions(mech: MechData) -> Array:
	return CombatEnemyTurn.upcoming_actions(self, mech)

## Whether an enemy's plan for this turn takes it over its max heat.
func enemy_will_overheat(mech: MechData) -> bool:
	return CombatEnemyTurn.will_overheat(self, mech)

## Resolves a planned enemy action all at once (auto mode, tests).
func execute_enemy_action(action: Dictionary) -> void:
	begin_enemy_attack(action)
	finish_attack()

## Step-wise execute_enemy_action: pays the heat and makes the action the
## pending attack; the caller steps it with next_hit() / finish_attack().
func begin_enemy_attack(action: Dictionary) -> void:
	CombatEnemyTurn.begin_attack(self, action)

## Steps 5 (end) and 6: game-over check, Warden overheat and decay, next player turn.
func finish_enemy_turn() -> void:
	if phase != Phase.ENEMY_TURN:
		return
	if _check_game_over():
		return

	# Step 6: Wardens check heat at the end of their turn, then decay.
	for w in enemies:
		if not w.is_defeated() and HeatRules.is_overheated(w.current_heat, w.heat_capacity()) and not CombatHeat.burn_fuse(self, w):
			CombatHeat.backlash(self, w)
		CardResolver.decay_end_of_turn_statuses(w)
	if _check_game_over():
		return

	turn_number += 1
	_start_player_turn()

## Step 1 of the next player turn: enemy heat disperses, Bastion's Absorb
## clears, Burn heats it, turn-start passives, repeats and Standby fire.
func _start_player_turn() -> void:
	for w in enemies:
		if not w.is_defeated():
			CombatHeat.vent(self, w)
	player_mech.clear_mech_status("absorb")
	_dodged[player_mech] = 0
	_cards_this_turn = 0
	_attacks_this_turn = 0
	_last_played = {}
	_recycle_bonus = 0
	_turn_damage = 0
	_drop_guards(player_mech)
	turned.clear()
	player_attackers.clear()
	_last_card = false
	spent.clear() # once per turn: every card is back as the round starts
	var burn := CardResolver.apply_burn(player_mech)
	player_mech.current_heat += deferred_heat # Batch
	deferred_heat = 0
	player_mech.current_heat += player_mech.turn_heat # Special Requisition
	_apply_turn_start_passives(player_mech)
	# Enemies choose next turn's cards now (after venting), so the player
	# sees what's coming for the whole of their turn.
	enemy_plans.clear()
	# Nothing it can play (spent or too hot): it vents on its turn (EnemyAI.plan_all).
	EnemyAI.plan_all(self)
	_assign_spikes()
	phase = Phase.PLAYER_TURN
	turn_changed.emit(phase, turn_number)
	_run_repeats(true)
	CombatProtocols.run_standby(self)
	if _check_game_over():
		return
	if burn > 0 or player_mech.turn_heat > 0:
		CombatHeat.check_player_overheat(self)

func _apply_turn_start_passives(mech: MechData) -> void:
	for c in CardResolver.apply_turn_start_passives(mech, turn_number == 1):
		passive_triggered.emit(mech, c)
	# Fortress Core: 2 Deflect per living reactor.
	for c in mech.living_passives("fortress"):
		var reactors := mech.non_destroyed_components().filter(func(x): return x.category == ComponentData.CATEGORY_REACTOR).size()
		mech.add_mech_status("deflect", reactors * int(c.passive.get("per", 2)))
		passive_triggered.emit(mech, c)
	# Coolant Loop: Coolant on a random hardpoint of its own mech.
	for c in mech.living_passives("turn_start_coolant"):
		var hardpoints := mech.non_destroyed_components().filter(func(x): return x.category == ComponentData.CATEGORY_HARDPOINT)
		if not hardpoints.is_empty():
			hardpoints[rng.randi() % hardpoints.size()].add_status("coolant", int(c.passive.get("stacks", 1)))
			passive_triggered.emit(mech, c)
	# Chaos Reactor: Burn on a random enemy part, Coolant on a random one of yours.
	for c in mech.living_passives("turn_start_chaos"):
		var foes: Array = []
		for m in ([player_mech] if mech != player_mech else living_enemies()):
			for part in m.non_destroyed_components():
				foes.append([m, part])
		if not foes.is_empty():
			var pick: Array = foes[rng.randi() % foes.size()]
			CardResolver.add_status_to(pick[0], pick[1], "burn", int(c.passive.get("burn", 2)), true)
		var own := mech.non_destroyed_components()
		if not own.is_empty():
			own[rng.randi() % own.size()].add_status("coolant", int(c.passive.get("coolant", 1)))
		passive_triggered.emit(mech, c)

## After a player command: each enemy's shown turn is repaired (EnemyAI.repair).
func _repair_enemy_plans() -> void:
	for w in living_enemies():
		EnemyAI.repair(self, w)

## A side's guards end as its turn starts (Hold the Line's cap and Final
## Order's floor are read off the mech).
func _drop_guards(mech: MechData) -> void:
	guards.erase(mech)
	mech.remove_meta("guard_cap")
	mech.remove_meta("guard_floor")

## Redirect Spike in a squad: each round, each enemy's Spike covers
## whichever living mech on its side is most hurt (by share of HP), itself
## or an ally (Logan, 2026-10-13). One Spike per covered mech; alone, a
## Spike covers its own mech as before.
func _assign_spikes() -> void:
	var side := living_enemies()
	for m in side:
		m.covered_by = null
		m.covered_by_mech = null
		m.spike_away = false
	if side.size() < 2:
		return
	for m in side:
		var spikes := m.living_passives(ComponentData.PASSIVE_REDIRECT)
		if spikes.is_empty():
			continue
		var best: MechData = m
		for other in side:
			if other.covered_by == null and _hp_share(other) < _hp_share(best):
				best = other
		if best != m:
			best.covered_by = spikes[0]
			best.covered_by_mech = m
			m.spike_away = true

static func _hp_share(m: MechData) -> float:
	return float(m.current_hp()) / maxf(1.0, float(m.max_hp()))

## Repeating attacks (Spillage) of one side fire at the start of its turn.
func _run_repeats(players: bool) -> void:
	for rep in repeats.duplicate():
		if (rep["attacker_mech"] == player_mech) != players:
			continue
		var target: ComponentData = rep["target"]
		if target.destroyed or (rep["defender_mech"] as MechData).is_defeated():
			repeats.erase(rep)
			continue
		_attack = {}
		CombatAttack.start(self, rep["card"], rep["attacker_mech"], rep["attacker_component"], rep["defender_mech"], target, {})
		_attack["is_repeat"] = true
		CombatAttack.resolve_now(self, rep["defender_mech"], target)
		rep["turns_left"] -= 1
		if rep["turns_left"] <= 0:
			repeats.erase(rep)

func _check_game_over() -> bool:
	if result != Result.NONE:
		return true
	if player_mech.is_defeated():
		_end_game(Result.LOSE)
		return true
	for w in enemies:
		if not w.is_defeated():
			return false
	_end_game(Result.WIN)
	return true

func _end_game(r: Result) -> void:
	result = r
	# Counted from the final state, however the parts were lost.
	stats.add("turns_taken", turn_number)
	stats.add("parts_lost", _player_parts_at_start - player_mech.non_destroyed_components().size())
	for w in enemies:
		if w.is_defeated():
			stats.add("enemies_destroyed")
		for c in w.components:
			if c.destroyed:
				stats.add("enemy_parts_destroyed")
	if r == Result.WIN:
		stats.add("fights_won")
		stats.record_min("fastest_fight", turn_number)
	for c in player_mech.components:
		c.remove_status("offline", 99) # Offline clears when the fight ends
	phase = Phase.GAME_OVER
	game_over.emit(r)

## Every player play path counts here, so this is where a card is spent.
func _count_card(card: CardData, cost: int) -> void:
	_spend(card)
	_cards_this_turn += 1
	stats.add("cards_played")
	stats.add("heat_generated", maxi(cost, 0))

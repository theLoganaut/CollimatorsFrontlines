class_name RunData
extends RefCounted
## One run through one location. Pure data, no scene tree, so it's unit-
## tested directly and saved to disk whole (to_dict / from_dict).
##
## - The encounter map and every roll come from the run's seed.
## - The player's mech is one MechData for the whole run. Full carry-over
##   (Logan, 2026-09-27): HP and destroyed parts persist; heat and statuses
##   reset before each fight.
## - `phase` says which screen the run is on, so Continue can resume there:
##   map → fight → reward → (refit) → map, or map → repair / shop → map.
## - After each fight: a reward (scraps to take, plus one part from a
##   two-stage pick), rolled once and kept so a reload can't reroll it.
## - Refits are only offered after the mission's fixed rows (Logan: after
##   stops 2, 4 and 6; Deep Recon also after 8).
## - The mission type (data/missions.json) shapes the map: Assault and
##   Rescue end in a boss stop; Deep Recon is longer with lighter regulars
##   and escorted elites; Rescue's Alert level rises with every turn spent
##   fighting and makes later fights harder.
## - Parts not installed live in Cargo (a 3×3 shaped grid to start).
## - Regular fights are rolled when entered, Slay-the-Spire style (Logan,
##   2026-09-28): the first few from the location's weak encounter pool,
##   later ones from its strong pool (where three-enemy fights live), never
##   repeating a recent encounter. Seeded by the run seed, the node and the
##   fights so far, and saved once rolled.
## - Deployment orders (DeploymentOrders, Logan 2026-09-29): three offers
##   after Launch; one is taken before the first stop. Their lasting effects
##   sit in `mods` and are read where they apply (mod()).
##
## The map, fights and rewards are here; events, autonomous bays, parts and
## Cargo, and saving are in static helpers that take the run (RunEvents,
## RunShop, RunParts, RunSave). The methods below that only call one of
## them keep the run's API in one place for the screens, the sim and tests.

enum Result { NONE, CLEARED, EJECTED }

const PHASE_MAP := "map"
const PHASE_FIGHT := "fight"
const PHASE_REWARD := "reward"
const PHASE_REFIT := "refit"
const PHASE_REPAIR := "repair"
const PHASE_SHOP := "shop"
const PHASE_EVENT := "event"
const EVENTS_PATH := "res://data/events.json"

const REFIT_AFTER_ROWS := [1, 3, 5] # default when a mission doesn't say
const MECH_PATH := "res://data/mechs/bastion.json"
const NO_STOCK := "-"
const BENCH_SIZE := 6
const MECH := "mech"
const CARGO := "cargo"
const BENCH := "bench"

var location: Dictionary
var mission: Dictionary
var seed_value: int
var map: RunMap
var player_mech: MechData
var cargo := CargoGrid.new()
## The 6×6 workbench at refits and autonomous bays (Logan, 2026-09-28): room
## to lay parts out and mix and match. Whatever is left on it when the
## player leaves is scrapped for scraps (scrap_bench).
var bench := CargoGrid.new(BENCH_SIZE, BENCH_SIZE)
var scraps: int = 0
var stats := RunStats.new()
var rng := RandomNumberGenerator.new() # rewards and shops (the map has its own)

var phase: String = PHASE_MAP
var current_node_id: int = -1 # the node being played (-1 = on the map)
var path: Array[int] = []     # nodes finished, in order
var fights_won: int = 0
var result: Result = Result.NONE
## How the run ended, for the Pilot Log ("Lost to Rivet Brute, Scrap Warden
## at encounter 9", "Ejected at encounter 4"); "" while it's going or when cleared.
var end_cause: String = ""

## After a fight: {"scraps", "scraps_taken", "options": {category: [ids]},
## "category" (chosen, "" until then), "part_taken"}.
var reward: Dictionary = {}
## At an autonomous bay: {"parts": [ids; "" once bought; NO_STOCK if the
## category has nothing implemented yet], "upgrade_bought"}.
var shop: Dictionary = {}
var cargo_upgrades: int = 0
var cells_bought: int = 0 # frame squares bought at autonomous bays this run
## The chassis' original bounding box, in the frame's current coordinates
## (it moves when a square added above or left shifts the frame). Squares
## can only be added inside it or one ring beyond (Decided, Logan 2026-09-29).
var base_bounds: Rect2i

## Save format version (SaveMigration upgrades older ones). v2: the
## mission snapshot, frame ring bounds.
const SAVE_VERSION := 2
## At a repair bay: HP left to hand out.
var repair_pool: int = 0
## At an event: {"id", "resolved": bool, "result": text}.
var event: Dictionary = {}
## Statuses waiting for the next fight (events): [{side, status, stacks, parts}].
var next_fight: Array = []
## Rescue: turns spent fighting so far (the Alert level comes from this).
var alert_turns: int = 0
## Deep Recon intel held going in (set by RunState from the profile), and
## whether this run's boss fight used it.
var boss_intel: bool = false
var boss_intel_used: bool = false
var bosses_met: Array = []
## Regular fights rolled so far (node id -> mech ids), and their order.
var fight_rolls: Dictionary = {}
var encounter_history: Array = []
## Event ids this run has had (RunEvents.pick doesn't repeat them).
var events_seen: Array = []
## Every fight this run, for the Pilot Log: [{enemies: [ids], kind, won, turns,
## damage_taken, hp_left, hp_max, replay (its Replays file, if recorded)}].
var fight_log: Array = []
## Each time this run was continued from its save: {at (date and time),
## phase, stops (taken so far), crash (CrashLog's report file if the game
## hadn't quit before it, else "")}.
var resumes: Array = []
## The file the fight being logged was recorded to (Replays), set by the
## combat screen just before fight_won / fight_lost. Not saved.
var last_replay: String = ""
## Deployment orders: {"offer": [3 ids], "chosen": id ("" until taken),
## "steps": [what's left for the pilot to do], "cargo_size": [rows, cols]
## (Cargo's real size while it's 5×5 for the opening refit), "swaps" (for
## the refit to animate), "swaps_shown"}; {} = none offered (training).
var orders: Dictionary = {}
## The taken order's lasting effects (DeploymentOrders.choose):
## max_heat, vent_at_max, start_heat, repair_mult, scraps_mult,
## unpaid_fights, elite_rolls, strong_fights, cold_start_fights / _stacks,
## wider_fights / _options, free_parts, fog (rows seen ahead), map_odds
## (MapGenerator "odds"). Counters count down as they're used.
var mods: Dictionary = {}

## `p_mission`: a mission type (data/missions.json, with "id"); {} = a plain
## map from the location's own enemy_ramp (tests).
func _init(p_location: Dictionary, p_player: MechData, p_seed: int, p_mission: Dictionary = {}) -> void:
	location = p_location
	player_mech = p_player
	seed_value = p_seed
	mission = p_mission
	base_bounds = GridUtils.bounds_of(p_player.cells)
	build_map()
	rng.seed = p_seed * 7919 + 13

## (Re)builds the encounter map from the seed, the mission and any map_odds
## (a deployment order taken before the first stop can change it).
func build_map() -> void:
	var map_rng := RandomNumberGenerator.new()
	map_rng.seed = seed_value
	var ramp: Array = mission.get("enemy_ramp", location.get("enemy_ramp", []))
	if ramp.is_empty():
		for i in range(int(mission.get("rows", 7))):
			ramp.append(1)
	var opts := {
		"encounter_pools": location.has("encounters"),
		"boss": mission.get("boss", false),
		# not when a deployment order took repair bays off the map (Salvage Rights)
		"repair_before_boss": mission.get("repair_before_boss", false) and float(mods.get("map_odds", {}).get("repair_chance", 1.0)) > 0.0,
		"regulars": location.get("regulars", [location.get("enemy", "scrap_warden")]),
		"elites": location.get("elites", []),
		"boss_id": location.get("boss", "anchor"),
		"elite_escort_from_row": int(mission.get("elite_escort_from_row", 4)),
		"max_shops": int(mission.get("max_shops", 0)), # 0 = no cap (older saves' missions)
		"odds": _map_odds(),
	}
	map = MapGenerator.generate(map_rng, ramp, opts)

## The stop odds this map uses: a deployment order's, and a mission
## variant's elite multiplier (Supply Line) on top.
func _map_odds() -> Dictionary:
	var odds: Dictionary = mods.get("map_odds", {}).duplicate()
	var mult := Conditions.elite_chance_mult(mission)
	if mult != 1.0:
		odds["elite_chance"] = float(odds.get("elite_chance", Balance.get_num("map", "elite_chance", 0.1))) * mult
	return odds

func is_over() -> bool:
	return result != Result.NONE

## A lasting effect of the deployment order taken (`fallback` if none).
func mod(key: String, fallback = 0):
	return mods.get(key, fallback)

## Counts a counter mod down by one (the effect was used once).
func _use_mod(key: String) -> void:
	if int(mods.get(key, 0)) > 0:
		mods[key] = int(mods[key]) - 1

## Whether the deployment orders still need the pilot (an order to take, or
## a part to pick, squares to place...). The map waits until they're done.
func orders_pending() -> bool:
	return not orders.is_empty() and (orders.get("chosen", "") == "" or not (orders.get("steps", []) as Array).is_empty())

## Applies the order's mech effects to the mech. Once per mech: when the
## order is taken, and on a mech just loaded from a save.
func apply_mech_mods() -> void:
	player_mech.max_heat += int(mod("max_heat"))
	player_mech.vent_at_max = float(mod("vent_at_max", -1.0))
	player_mech.turn_heat = int(mod("turn_heat"))

func encounter_count() -> int:
	return map.row_count

# ---------- moving on the map ----------

## Node ids the pilot can go to next: the starting row before the first
## stop, afterwards the links out of the last node finished.
func available_nodes() -> Array[int]:
	var out: Array[int] = []
	if is_over() or phase != PHASE_MAP:
		return out
	if path.is_empty():
		for n in map.nodes_in_row(0):
			out.append(n["id"])
	else:
		for id in map.get_map_node(path[-1])["next"]:
			out.append(id)
	return out

## Goes to a node: its kind decides the phase (a fight, a repair bay, a shop).
func choose_node(id: int) -> bool:
	if not available_nodes().has(id) or orders_pending():
		return false
	current_node_id = id
	match current_node()["kind"]:
		RunMap.KIND_EVENT:
			# some signals lead to an abandoned autonomous bay (Logan, 2026-09-30: 10%)
			if rng.randf() < Balance.get_num("map", "event_shop_chance", 0.1):
				phase = PHASE_SHOP
				_stock_shop()
				shop["from_event"] = true
				stats.add("autonomous_bays")
			else:
				phase = PHASE_EVENT
				event = {"id": RunEvents.pick(self), "step": "", "resolved": false, "result": ""}
		RunMap.KIND_REPAIR:
			phase = PHASE_REPAIR
			repair_pool = Economy.repair_pool(player_mech.max_hp(), float(mod("repair_mult", 1.0)))
			stats.add("repair_bays")
		RunMap.KIND_SHOP:
			phase = PHASE_SHOP
			_stock_shop()
			stats.add("autonomous_bays")
		RunMap.KIND_FIGHT:
			phase = PHASE_FIGHT
			if (current_node()["enemies"] as Array).is_empty() and location.has("encounters"):
				_set_fight_enemies(id, roll_encounter(id))
		_:
			phase = PHASE_FIGHT
	return true

## Regular fights done so far on this run.
func regular_fights_done() -> int:
	return path.filter(func(nid): return map.get_map_node(nid)["kind"] == RunMap.KIND_FIGHT).size()

## Picks a regular fight's enemies from the location's encounter pools:
## weak for the first few fights, strong after; weighted; a mission's
## max_enemies caps the size; recent encounters aren't repeated.
func roll_encounter(node_id: int) -> Array:
	if mission.has("encounter"): # a fixed fight (training)
		return (mission["encounter"] as Array).duplicate()
	var pools: Dictionary = location.get("encounters", {})
	var done := regular_fights_done()
	var weak_n := int(mission.get("weak_fights", Balance.get_int("encounters", "weak_fights", 3)))
	var weak := done < weak_n and done >= int(mod("strong_fights")) # Hot Insertion: the first few are strong
	var pool: Array = pools.get("weak" if weak else "strong", [])
	if pool.is_empty():
		pool = pools.get("weak", [])
	var max_e := int(mission.get("max_enemies", 99))
	var options := pool.filter(func(e): return (e["enemies"] as Array).size() <= max_e)
	if options.is_empty():
		options = pool
	var recent := encounter_history.slice(maxi(0, encounter_history.size() - Balance.get_int("encounters", "no_repeat", 2)))
	var fresh := options.filter(func(e): return not recent.has(",".join(e["enemies"])))
	if not fresh.is_empty():
		options = fresh
	if options.is_empty():
		return [location.get("enemy", "scrap_warden")]
	var roll := RandomNumberGenerator.new()
	roll.seed = hash([seed_value, node_id, done])
	var total := 0.0
	for e in options:
		total += float(e.get("weight", 1))
	var r := roll.randf() * total
	var chosen: Dictionary = options[-1]
	for e in options:
		r -= float(e.get("weight", 1))
		if r < 0.0:
			chosen = e
			break
	encounter_history.append(",".join(chosen["enemies"]))
	return (chosen["enemies"] as Array).duplicate()

func _set_fight_enemies(node_id: int, ids: Array) -> void:
	fight_rolls[node_id] = ids
	var n := map.get_map_node(node_id)
	n["enemies"] = ids.duplicate()
	n["enemy_count"] = ids.size()

func current_node() -> Dictionary:
	return map.get_map_node(current_node_id)

## The node finished: onward to a refit (on the refit rows), the map, or
## the end of the location.
func _finish_node() -> void:
	var row: int = current_node()["row"]
	path.append(current_node_id)
	current_node_id = -1
	if map.is_last_row(row):
		result = Result.CLEARED
		phase = PHASE_MAP
	elif is_refit_row(row):
		phase = PHASE_REFIT
	else:
		phase = PHASE_MAP

func refit_rows() -> Array:
	var out: Array = []
	for r in mission.get("refit_after_rows", REFIT_AFTER_ROWS):
		out.append(int(r))
	return out

func is_refit_row(row: int) -> bool:
	return refit_rows().has(row) and not map.is_last_row(row)

func mission_name() -> String:
	return mission.get("name", "")

# ---------- fights ----------

## Fresh enemies for the chosen node's fight (Rescue at high Alert adds a
## regular to fights with fewer than 3).
func encounter_enemies() -> Array[MechData]:
	var out: Array[MechData] = []
	var node := current_node()
	var ids: Array = node.get("enemies", []).duplicate()
	if ids.is_empty():
		for i in range(int(node.get("enemy_count", 0))):
			ids.append(location.get("enemy", "scrap_warden"))
	var alert: Dictionary = mission.get("alert", {})
	if not alert.is_empty() and node["kind"] != RunMap.KIND_BOSS and alert_tier() >= int(alert.get("extra_enemy_from_tier", 99)) and ids.size() < 3:
		var regs: Array = location.get("regulars", ["scrap_warden"])
		ids.append(regs[(seed_value + int(node["id"])) % regs.size()])
	for id in ids:
		out.append(DataLoader.load_mech_from_file("res://data/mechs/%s.json" % id))
	if node["kind"] == RunMap.KIND_BOSS and not ids.is_empty() and not bosses_met.has(ids[0]):
		bosses_met.append(ids[0])
		stats.add("bosses_reached")
	return out

## Rescue's Alert level (0 = calm), from turns spent fighting.
func alert_tier() -> int:
	var alert: Dictionary = mission.get("alert", {})
	if alert.is_empty():
		return 0
	return mini(int(alert.get("max_tier", 4)), alert_turns / maxi(int(alert.get("turns_per_tier", 6)), 1))

## Statuses that go on at the start of this fight, once the combat has
## started: events' next-fight effects, Rescue's Alert (every enemy braced
## with Deflect), Deep Recon intel (a boss's hardpoints Disabled for its
## first turn), and the location's modifiers and mission variant
## (Conditions: Rain, Jamming, Dust, Hardened, Blackout). Returns lines for
## the combat log.
func apply_fight_start_effects(player: MechData, enemies: Array[MechData]) -> Array[String]:
	var log: Array[String] = []
	var effects := next_fight.duplicate()
	next_fight = []
	var alert: Dictionary = mission.get("alert", {})
	if alert_tier() > 0:
		effects.append({"side": "enemy", "status": "deflect", "stacks": alert_tier() * int(alert.get("deflect_per_tier", 2)), "parts": "mech"})
		log.append("Alert %d: the enemy is braced." % alert_tier())
	if current_node().get("kind", "") == RunMap.KIND_BOSS and boss_intel and not boss_intel_used:
		effects.append({"side": "enemy", "status": "disabled", "stacks": 1, "parts": "hardpoints"})
		boss_intel_used = true
		log.append("Recon intel: the boss's weapons are down for its first turn.")
	for e in Conditions.fight_start(location, mission): # location modifiers and the mission variant
		effects.append(e)
	var drop := Conditions.vent_drop(location, mission)
	if drop > 0.0: # Rain: every mech vents less at max heat
		var base := 1.0 if HeatRules.full_reset() else Balance.get_num("heat", "vent_at_max", 0.8)
		player.vent_at_max = (float(mod("vent_at_max", -1.0)) if float(mod("vent_at_max", -1.0)) >= 0.0 else base) - drop
		for e in enemies:
			e.vent_at_max = (e.vent_at_max if e.vent_at_max >= 0.0 else base) - drop
	for id in Conditions.modifiers(location, mission):
		log.append("%s: %s" % [Conditions.modifier_name(id), Conditions.modifier_text(id)])
	if int(mod("cold_start_fights")) > 0:
		effects.append({"side": "player", "status": "coolant", "stacks": int(mod("cold_start_stacks", 2)), "parts": "hardpoints"})
		_use_mod("cold_start_fights")
		log.append("Cold Start: your hardpoints run cold.")
	for e in effects:
		var mechs: Array[MechData] = []
		if e["side"] == "player":
			mechs.append(player)
		else:
			mechs = enemies
		for m in mechs:
			if e["parts"] == "mech":
				CardResolver.add_status_to(m, null, e["status"], int(e["stacks"]), false)
			else:
				for c in m.non_destroyed_components():
					if e["parts"] == "all" or c.category == ComponentData.CATEGORY_HARDPOINT:
						c.add_status(e["status"], int(e["stacks"]))
	return log

## Before each fight: heat and every status reset; HP and destroyed parts
## stay. (Hot Start: fights start with some heat.)
func prepare_player_for_fight() -> void:
	player_mech.current_heat = int(mod("start_heat"))
	player_mech.mech_statuses.clear()
	for c in player_mech.components:
		c.statuses.clear()

## A fight won: its stats join the run's, and the reward is rolled.
func fight_won(fight_stats: RunStats = null) -> void:
	if phase != PHASE_FIGHT or is_over():
		return
	_log_fight(true, fight_stats)
	if fight_stats != null:
		stats.merge(fight_stats)
		if not mission.get("alert", {}).is_empty():
			alert_turns += fight_stats.get_stat("turns_taken")
	fights_won += 1
	var magnet := fight_stats.get_stat("magnet_scraps") if fight_stats != null else 0
	var kind: String = current_node().get("kind", RunMap.KIND_FIGHT)
	if kind == RunMap.KIND_ELITE:
		stats.add("elites_beaten")
	elif kind == RunMap.KIND_BOSS:
		stats.add("bosses_beaten")
		# The boss is the last fight: no salvage, the run is cleared (Logan, 2026-09-30).
		_finish_node()
		return
	var better := Balance.get_int("economy", "elite_boss_rarity_rolls", 2) if kind in [RunMap.KIND_ELITE, RunMap.KIND_BOSS] else 1 # elites and bosses roll rarity more, keep the best
	if kind == RunMap.KIND_ELITE:
		better = maxi(better, int(mod("elite_rolls"))) # Hunter's Route
	var count := -1
	if int(mod("wider_fights")) > 0: # Wider Picks
		count = int(mod("wider_options", 4))
		_use_mod("wider_fights")
	var options := {}
	for cat in Economy.CATEGORIES:
		options[cat] = Economy.roll_options(cat, rng, better, player_mech.weight_class, "", count)
	var scraps_won := int(round((Economy.scraps_for_fight(int(current_node().get("enemy_count", 1)), rng, kind) + magnet) * float(mod("scraps_mult", 1.0)) * Conditions.scraps_mult(mission)))
	var note := ""
	if int(mod("unpaid_fights")) > 0: # Loan Shark
		scraps_won = 0
		_use_mod("unpaid_fights")
		note = "Loan Shark: no scraps from this fight (%d more to go)" % int(mod("unpaid_fights")) if int(mod("unpaid_fights")) > 0 else "Loan Shark: paid off, scraps from the next fight on"
	reward = {
		"scraps": scraps_won, "note": note,
		"scraps_taken": false, "options": options, "category": "", "part_taken": false,
	}
	take_reward_scraps() # scraps are banked at once (Logan, 2026-09-28: no click to take them)
	phase = PHASE_REWARD

func fight_lost(fight_stats: RunStats = null) -> void:
	_log_fight(false, fight_stats)
	if fight_stats != null:
		stats.merge(fight_stats)
	result = Result.EJECTED
	var names: Array[String] = []
	for m in encounter_enemies():
		if not names.has(m.name):
			names.append(m.name)
	var turns := fight_stats.get_stat("turns_taken") if fight_stats != null else 0
	end_cause = "Lost to %s at encounter %d%s" % [", ".join(names), path.size(), ", turn %d" % turns if turns > 0 else ""]

# ---------- events ----------

func event_def() -> Dictionary:
	return RunEvents.event_def(self)

## Plays one of the event's choices. Returns the result text to show.
func resolve_event(choice: int) -> String:
	return RunEvents.resolve_event(self, choice)

func finish_event() -> void:
	if phase == PHASE_EVENT:
		event = {}
		_finish_node()

func _log_fight(won: bool, fight_stats: RunStats) -> void:
	var node := current_node()
	var ids: Array = node.get("enemies", []).duplicate()
	if ids.is_empty():
		ids = fight_rolls.get(current_node_id, [])
	var entry := {"enemies": ids, "kind": node.get("kind", RunMap.KIND_FIGHT), "won": won,
		"turns": fight_stats.get_stat("turns_taken") if fight_stats != null else 0,
		"damage_taken": fight_stats.get_stat("damage_taken") if fight_stats != null else 0,
		"hp_left": player_mech.current_hp(), "hp_max": player_mech.max_hp()}
	if last_replay != "":
		entry["replay"] = last_replay
		last_replay = ""
	fight_log.append(entry)

func eject() -> void:
	result = Result.EJECTED
	if end_cause == "":
		end_cause = "Ejected at encounter %d" % path.size()

# ---------- rewards ----------

func take_reward_scraps() -> int:
	if reward.is_empty() or reward["scraps_taken"]:
		return 0
	reward["scraps_taken"] = true
	add_scraps(reward["scraps"])
	return reward["scraps"]

## The two-stage pick's first step. Once a category is chosen it's final.
func choose_reward_category(category: String) -> Array:
	if reward.is_empty() or reward["part_taken"]:
		return []
	if reward["category"] == "":
		reward["category"] = category
	return reward["options"].get(reward["category"], [])

## Takes one of the chosen category's parts into Cargo. Returns the new
## part, or null if it doesn't fit (the caller can make room and retry).
func take_reward_part(component_id: String) -> ComponentData:
	if reward.is_empty() or reward["part_taken"] or not reward["options"].get(reward["category"], []).has(component_id):
		return null
	var comp := new_part(component_id)
	if not cargo.add(comp):
		return null
	reward["part_taken"] = true
	stats.add("parts_acquired")
	return comp

## What skipping the pick pays (Logan, 2026-09-30): balance.json
## economy.skip_scraps, or the sell value of the cheapest part offered if
## that's more (so taking a part just to sell it never beats skipping).
## 0 once a part is taken or skipped.
func skip_payout() -> int:
	if reward.is_empty() or reward["part_taken"]:
		return 0
	var pay := Balance.get_int("economy", "skip_scraps", 10)
	var cheapest := -1
	for id in reward["options"].get(reward["category"], []):
		var v := Economy.sell_value(id)
		cheapest = v if cheapest < 0 else mini(cheapest, v)
	return maxi(pay, cheapest)

## Skips the pick for skip_payout() scraps. Returns what it paid.
func skip_reward_part() -> int:
	var pay := skip_payout()
	if reward.is_empty() or reward["part_taken"]:
		return 0
	reward["part_taken"] = true
	reward["skipped"] = pay
	add_scraps(pay)
	return pay

## Leaves the reward screen (untaken scraps are left behind).
func finish_reward() -> void:
	if phase != PHASE_REWARD:
		return
	reward = {}
	_finish_node()

# ---------- parts, Cargo and refits ----------

## A fresh copy of a Refit Bay part with an id unique on this run.
func new_part(library_id: String) -> ComponentData:
	return RunParts.new_part(self, library_id)

func discard_from_cargo(comp: ComponentData) -> void:
	RunParts.discard_from_cargo(self, comp)

func chassis_cells() -> Dictionary:
	return RunParts.chassis_cells(self)

func mech_occupied(except: ComponentData = null) -> Dictionary:
	return RunParts.mech_occupied(self, except)

func can_install(comp: ComponentData, steps: int, offset: Vector2i) -> bool:
	return RunParts.can_install(self, comp, steps, offset)

## Whether a part's weight class fits this run's mech (General fits all).
func fits_class(comp: ComponentData) -> bool:
	return RunParts.fits_class(self, comp)

## Refit: moves a part (from Cargo, or elsewhere on the mech) onto the chassis.
func install(comp: ComponentData, steps: int, offset: Vector2i) -> bool:
	return RunParts.install(self, comp, steps, offset)

## Refit: moves a part (from the mech, or elsewhere in Cargo) into Cargo.
func stow(comp: ComponentData, steps: int, offset: Vector2i) -> bool:
	return RunParts.stow(self, comp, steps, offset)

## Whether parts can be moved around here: the chassis only at a refit,
## Cargo and the workbench at a refit or an autonomous bay.
func can_rearrange(to: String) -> bool:
	return RunParts.can_rearrange(self, to)

## Whether `comp` fits at `offset` (turned `steps`) on the chassis, in Cargo
## or on the workbench.
func can_move(comp: ComponentData, to: String, steps: int, offset: Vector2i) -> bool:
	return RunParts.can_move(self, comp, to, steps, offset)

## Moves a part (from anywhere it is) onto the chassis, into Cargo or onto
## the workbench.
func move_part(comp: ComponentData, to: String, steps: int, offset: Vector2i) -> bool:
	return RunParts.move_part(self, comp, to, steps, offset)

## Scraps for the parts on the workbench (what leaving would pay).
func bench_value() -> int:
	return RunParts.bench_value(self)

## Leaving a refit or autonomous bay: every part left on the workbench is
## scrapped for scraps. Returns {"names": [...], "scraps": n}.
func scrap_bench() -> Dictionary:
	return RunParts.scrap_bench(self)

## Destroyed parts are gone for the run: a refit clears their wrecks off
## the chassis. Returns the names scrapped.
func scrap_destroyed() -> Array[String]:
	return RunParts.scrap_destroyed(self)

## A refit can only end with at least one working hardpoint installed.
func can_finish_refit() -> bool:
	return RunParts.can_finish_refit(self)

## The opening refit (a deployment order that hands out parts): Cargo's
## real size while it's 5×5, else ZERO.
func opening_cargo_size() -> Vector2i:
	return RunParts.opening_cargo_size(self)

## Parts in the opening refit's Cargo outside its real size (scrapped when
## the refit ends).
func cargo_overflow() -> Array[ComponentData]:
	return RunParts.cargo_overflow(self)

## Parts scrapped by leaving now (the workbench, plus the opening refit's
## Cargo overflow), and what they pay.
func leave_scrap_count() -> int:
	return RunParts.leave_scrap_count(self)

func leave_scrap_value() -> int:
	return RunParts.leave_scrap_value(self)

func finish_refit() -> bool:
	return RunParts.finish_refit(self)

# ---------- repair bays ----------

## Heals up to `amount` into one living part, drawing on the pool. Returns
## the HP actually healed.
func repair(comp: ComponentData, amount: int) -> int:
	if phase != PHASE_REPAIR or comp.destroyed:
		return 0
	var healed := comp.heal(mini(amount, repair_pool))
	repair_pool -= healed
	stats.add("damage_healed", healed)
	return healed

## Repair all: the pool goes into damaged living parts one at a time, the
## ones missing the least first (so the most parts end up whole). Returns HP healed.
func repair_all() -> int:
	var parts := player_mech.non_destroyed_components().filter(func(c): return c.current_hp < c.max_hp)
	parts.sort_custom(func(a, b): return a.max_hp - a.current_hp < b.max_hp - b.current_hp)
	var total := 0
	for c in parts:
		if repair_pool <= 0:
			break
		total += repair(c, c.max_hp - c.current_hp)
	return total

## Even out: 1 HP at a time to whichever living part has the lowest share
## of its HP, until the pool or the damage runs out. Returns HP healed.
func repair_even() -> int:
	var total := 0
	while repair_pool > 0:
		var worst: ComponentData = null
		for c in player_mech.non_destroyed_components():
			if c.current_hp < c.max_hp and (worst == null or float(c.current_hp) / c.max_hp < float(worst.current_hp) / worst.max_hp):
				worst = c
		if worst == null:
			break
		total += repair(worst, 1)
	return total

func finish_repair() -> void:
	if phase == PHASE_REPAIR:
		repair_pool = 0
		_finish_node()

# ---------- scraps and autonomous bays ----------

func add_scraps(n: int) -> void:
	scraps += n
	stats.add("scraps_earned", n)

## An autonomous bay's stock (shop rework, 2026-09-30, numbers Proposed):
## economy.shop_offers parts of each category, each with its own rarity
## roll, no repeats. Saved in `shop`, so a reload doesn't reroll it.
func _stock_shop() -> void:
	RunShop.stock_shop(self)

## Selling a part from Cargo or the workbench pays what scrapping it would.
func can_sell(comp: ComponentData) -> bool:
	return RunShop.can_sell(self, comp)

func sell_part(comp: ComponentData) -> int:
	return RunShop.sell_part(self, comp)

## Refining (once a visit): a part in Cargo or on the bench becomes a random
## part of its type one rarity up. The price is by its current rarity; -1
## when it can't be refined (Prototype, or no part one rarity up).
func refine_price(comp: ComponentData) -> int:
	return RunShop.refine_price(self, comp)

func can_refine(comp: ComponentData) -> bool:
	return RunShop.can_refine(self, comp)

## Returns the new part, or null (can't, or nothing one rarity up, or no room).
func refine_part(comp: ComponentData) -> ComponentData:
	return RunShop.refine_part(self, comp)

## Buys the shop's part in `slot` onto the workbench (into Cargo if the
## bench is full). Returns the new part, or null (sold out, not enough
## scraps, or no room anywhere).
func buy_part(slot: int) -> ComponentData:
	return RunShop.buy_part(self, slot)

## A shop part's price here (Friendly Merchant: free while it lasts).
func part_price(id: String) -> int:
	return RunShop.part_price(self, id)

func cargo_upgrade_price() -> int:
	return RunShop.cargo_upgrade_price(self)

## +1 row (`add_row`) or +1 column of Cargo.
func buy_cargo_upgrade(add_row: bool) -> bool:
	return RunShop.buy_cargo_upgrade(self, add_row)

## A frame square at an autonomous bay (Logan, 2026-09-28): 25 scraps, then
## 25 more than the last one each time (balance.json cell_price_*).
func cell_price() -> int:
	return RunShop.cell_price(self)

## The squares that can be added: empty ones touching the frame (holes in
## it included), no further than one ring around the chassis' original
## bounds (frame_ring). May sit at row or column -1.
func cell_options() -> Array[Vector2i]:
	return RunShop.cell_options(self)

## Where frame squares may go: the original bounds grown by one ring.
func frame_ring() -> Rect2i:
	return RunShop.frame_ring(self)

## Adds `cell` to the frame. A square above or left of the frame shifts the
## whole frame (and its parts) so cells stay at row/col 0 and up.
func buy_cell(cell: Vector2i) -> bool:
	return RunShop.buy_cell(self, cell)

## Adds a square to the frame (bought, or free from a deployment order).
func add_frame_cell(cell: Vector2i) -> bool:
	return RunShop.add_frame_cell(self, cell)

func leave_shop() -> void:
	RunShop.leave_shop(self)

# ---------- saving ----------

func to_dict() -> Dictionary:
	return RunSave.to_dict(self)

static func from_dict(d: Dictionary, p_location: Dictionary, p_mission: Dictionary = {}) -> RunData:
	return RunSave.from_dict(d, p_location, p_mission)


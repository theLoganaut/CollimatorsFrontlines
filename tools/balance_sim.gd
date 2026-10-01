extends SceneTree
## Balance sim (run with tools/balance_sim.sh [runs]). Plays whole runs of
## every mission with full carry-over, using the real map, encounters,
## enemies and AI. Bots fight; between fights they take scraps, use repair
## bays fully, take one of the three deployment orders offered and pick a
## random event choice, so the numbers are a floor, not what a person
## gets. Four bots:
##   smart   - finishes the enemy closest to its defeat line, aiming at
##             its weakest hardpoint
##   focused - hits the weakest weapon on the field
##   casual  - hits a random part
##   builder - fights like smart, and also takes a salvage hardpoint,
##             installs Cargo parts at refits (wrecks cleared first) and
##             buys hardpoints at autonomous bays: closer to a real player
## Every bot installs what a deployment order hands out at the opening
## refit (Scramble and Transmute take parts off the frame).
## Prints each mission × bot: clear rate, how often the boss was reached
## and beaten, and the stops where runs died most; then per fight: turns,
## cards played, dead turns (nothing played: out of cards or too hot) and
## Vent actions; then per run: stops, scraps, shops and Chips earned.
##
## Options:
##   <runs>                  runs per mission per bot per sweep (default 150)
##   --report                also write tools/reports/sim_<date>.md: clear
##                           rates, enemies, deployment orders, event
##                           choices and parts (builder)
##   --set=section.key=value try a balance.json value without editing it
##   --mech=<id>.<key>=<v>   try an enemy change without editing it: max_heat,
##                           defeat_hp_fraction, heat_check_timing, ai.<key>,
##                           swap=<part id>:<Refit Bay part id>, or
##                           add=<Refit Bay part id> (into free frame cells)
##   --pilot=<mech id>       the player's mech (default bastion)
##   --orders=random|none|<order id>  what the bots take (default random:
##                           one of the three offered)
##   --events=random|first   event choices (default random)
##   --variants=random|none|<id>  mission variants (default random, by the
##                           weights in balance.json conditions)
##   --seed-start=<n>        first run seed (default 1)
##   --sweeps=<k>            k blocks of <runs> seeds each; prints the spread
##                           of clear rates between blocks
##   --trace=<path>          write the golden-master trace (tools/golden.sh)

var N := 150
var report := false
var _lines: Array[String] = []
## Per enemy id, over every fight it was in: [fights, player wins, damage
## the player took in those fights, damage this enemy's own attacks dealt].
var _enemy_stats := {}
var _overrides: Array[String] = []
## --trace=<path>: also write every combat signal, each mech's state after
## every player turn and the run's state after every step to <path>. The
## golden master for refactors (tools/golden.sh): same seeds, same trace.
var trace_path := ""
var _trace := PackedStringArray()
var pilot := "bastion"
var orders_mode := "random"
var events_mode := "random"
var variants_mode := "random"
var seed_start := 1
var sweeps := 1
## --mech overrides: enemy id -> [[key, value]].
var _mech_overrides := {}
var _warned := {}

var casual := false
var smart := false
var builder := false
## Per mission × bot: fights, turns, cards played, dead turns, vents, fights where the bot ran out of cards.
var _fs := {}
## Deployment orders taken: id -> {runs, clears, builder_runs, builder_clears}.
var _order_stats := {}
## Event choices: "event:choice" -> {picked, clears}.
var _event_stats := {}
## Builder parts by library id: {offered, taken, runs (runs that took it
## at least once), clears (of those runs)}. Counting runs that took a part,
## not runs that ended with it, keeps out survivorship (a part only stays
## installed on runs that got far).
var _part_stats := {}
var _run_parts := {} # library ids the builder took this run
var _builder_runs := 0
var _builder_clears := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			N = int(a)
		elif a == "--report":
			report = true
		elif a.begins_with("--trace="):
			trace_path = a.trim_prefix("--trace=")
		elif a.begins_with("--pilot="):
			pilot = a.trim_prefix("--pilot=")
		elif a.begins_with("--orders="):
			orders_mode = a.trim_prefix("--orders=")
		elif a.begins_with("--events="):
			events_mode = a.trim_prefix("--events=")
		elif a.begins_with("--variants="):
			variants_mode = a.trim_prefix("--variants=")
		elif a.begins_with("--seed-start="):
			seed_start = int(a.trim_prefix("--seed-start="))
		elif a.begins_with("--sweeps="):
			sweeps = maxi(1, int(a.trim_prefix("--sweeps=")))
		elif a.begins_with("--mech="):
			# --mech=caustic_engine.max_heat=7 : try an enemy change without editing its file
			var kv := a.trim_prefix("--mech=").split("=", true, 1)
			var id := kv[0].get_slice(".", 0)
			var key := kv[0].substr(id.length() + 1)
			if not FileAccess.file_exists("res://data/mechs/%s.json" % id):
				push_warning("--mech: no enemy %s" % id)
			var list: Array = _mech_overrides.get(id, [])
			list.append([key, kv[1]])
			_mech_overrides[id] = list
			print("mech override %s.%s = %s" % [id, key, kv[1]])
			_overrides.append("%s.%s = %s" % [id, key, kv[1]])
		elif a.begins_with("--set=") and a.contains("=") and a.contains("."):
			# --set=economy.scraps_base=25 : try a balance value without editing the file
			var kv := a.trim_prefix("--set=").split("=", true, 1)
			var path := kv[0].split(".")
			var raw := kv[1]
			var v = JSON.parse_string(raw) if (raw.is_valid_float() or raw in ["true", "false"] or raw.begins_with("[") or raw.begins_with("{")) else raw
			Balance.set_value(path[0], path[1], v)
			print("override %s = %s" % [kv[0], kv[1]])
			_overrides.append("%s = %s" % [kv[0], kv[1]])

func _process(_delta: float) -> bool:
	_run()
	return true

func _run() -> void:
	var sectors = JSON.parse_string(FileAccess.get_file_as_string("res://data/sectors.json"))["locations"]
	var missions = JSON.parse_string(FileAccess.get_file_as_string("res://data/missions.json"))["missions"]
	var total := N * sweeps
	for mid in ["assault", "deep_recon", "rescue"]:
		var mdef: Dictionary = missions[mid].duplicate(true)
		mdef["id"] = mid
		for mode in ["smart", "focused", "casual", "builder"]:
			casual = mode == "casual"
			builder = mode == "builder"
			smart = mode == "smart" or builder
			var cleared := 0
			var block_clears: Array[float] = []
			var died_at := {}
			var boss_reached := 0
			var boss_won := 0
			var per_boss := {} # boss id -> [reached, won]
			_fs = {"fights": 0, "turns": 0, "cards": 0, "dead": 0, "vents": 0, "ran_out": 0}
			var rs := {"stops": 0, "scraps": 0, "shops": 0, "shop_scraps": 0, "chips": 0, "memorial": 0}
			for block in range(sweeps):
				var block_cleared := 0
				for run_seed in range(seed_start + block * N, seed_start + block * N + N):
					var loc: Dictionary = sectors[run_seed % sectors.size()]
					var vrng := RandomNumberGenerator.new()
					vrng.seed = run_seed * 13 + 1
					var variant := "standard" if variants_mode == "none" else (Conditions.roll_variant(vrng) if variants_mode == "random" else variants_mode)
					var run := RunData.new(loc, DataLoader.load_mech_from_file("res://data/mechs/%s.json" % pilot), run_seed, Conditions.with_variant(mdef, variant))
					var pick := RandomNumberGenerator.new()
					pick.seed = run_seed * 31
					var choices := RandomNumberGenerator.new() # orders and events: kept apart so `pick` rolls the same map path
					choices.seed = run_seed * 97 + 5
					_t("== %s %s seed %d" % [mid, mode, run_seed])
					var order := _take_order(run, choices)
					_run_parts = {}
					var events_picked: Array[String] = []
					var guard := 0
					while not run.is_over() and guard < 200:
						guard += 1
						match run.phase:
							"map":
								var opts := run.available_nodes()
								run.choose_node(opts[pick.randi_range(0, opts.size() - 1)])
							"fight":
								run.prepare_player_for_fight()
								var p := run.player_mech
								var ws := run.encounter_enemies()
								_apply_mech_overrides(ws)
								var is_boss: bool = run.current_node()["kind"] == "boss"
								if is_boss:
									boss_reached += 1
									var bid: String = ws[0].id
									if not per_boss.has(bid):
										per_boss[bid] = [0, 0]
									per_boss[bid][0] += 1
								var cm := CombatManager.new(p, ws, run_seed * 100 + run.path.size())
								var dealt := {}
								cm.enemy_action.connect(func(e): dealt[e["mech"]] = int(dealt.get(e["mech"], 0)) + int(e["damage"]))
								var mechs: Array = [p]
								mechs.append_array(ws)
								_trace_fight(cm, mechs)
								cm.start_combat()
								run.apply_fight_start_effects(p, ws)
								var turns := 0
								var ran_out := false
								while not cm.is_game_over() and turns < 40:
									turns += 1
									var before := cm.stats.get_stat("cards_played")
									var vented := _player_turn(cm, p, ws)
									if cm.stats.get_stat("cards_played") == before:
										_fs["dead"] += 1
									_fs["vents"] += 1 if vented else 0
									ran_out = ran_out or cm.out_of_cards(p)
									if not cm.is_game_over() and cm.is_player_turn():
										cm.apply({"type": "end_turn"})
									_t(_state(cm, mechs))
								_fs["fights"] += 1
								for w in ws:
									var es: Array = _enemy_stats.get(w.id, [0, 0, 0, 0])
									es[0] += 1
									es[1] += 1 if cm.result == CombatManager.Result.WIN else 0
									es[2] += cm.stats.get_stat("damage_taken")
									es[3] += int(dealt.get(w, 0))
									_enemy_stats[w.id] = es
								_fs["turns"] += turns
								_fs["cards"] += cm.stats.get_stat("cards_played")
								_fs["ran_out"] += 1 if ran_out else 0
								if cm.result == CombatManager.Result.WIN:
									if is_boss:
										boss_won += 1
										per_boss[ws[0].id][1] += 1
									run.fight_won(cm.stats)
								else:
									var key := "%s r%d" % [run.current_node()["kind"], run.current_node()["row"]]
									died_at[key] = int(died_at.get(key, 0)) + 1
									run.fight_lost(cm.stats)
							"reward":
								run.take_reward_scraps()
								if builder:
									_take_best(run)
								run.finish_reward()
							"refit":
								# the opening refit (a deployment order handed out parts): every bot installs
								if builder or run.path.is_empty():
									_refit(run)
								run.finish_refit()
							"repair":
								for c in run.player_mech.components:
									run.repair(c, 999)
								run.finish_repair()
							"shop":
								rs["shops"] += 1
								rs["shop_scraps"] += run.scraps
								_shop(run)
								run.leave_shop()
							"event":
								var n: int = run.event_def().get("choices", []).size()
								var ci := choices.randi_range(0, n - 1) if events_mode == "random" and n > 0 else 0
								events_picked.append("%s:%d" % [run.event.get("id", ""), ci])
								run.resolve_event(ci)
								run.finish_event()
						_t("run %s node %d scraps %d rng %s %s" % [run.phase, run.current_node_id, run.scraps, run.rng.state, JSON.stringify(run.to_dict()).md5_text()])
					var won := run.result == RunData.Result.CLEARED
					if won:
						cleared += 1
						block_cleared += 1
					rs["stops"] += run.path.size()
					rs["scraps"] += run.stats.get_stat("scraps_earned")
					rs["chips"] += Meta.chips_for_run(run)
					rs["memorial"] += Meta.memorial_points_for(run.stats.get_stat("elites_beaten"), run.stats.get_stat("bosses_beaten"))
					_count_run(order, events_picked, run, won)
				block_clears.append(100.0 * block_cleared / N)
			var top := died_at.keys()
			top.sort_custom(func(a, b): return died_at[a] > died_at[b])
			var worst := []
			for k in top.slice(0, 4):
				worst.append("%s:%d" % [k, died_at[k]])
			var bosses := []
			for b in per_boss:
				bosses.append("%s %d/%d" % [b, per_boss[b][1], per_boss[b][0]])
			var spread := ""
			if sweeps > 1:
				spread = " (blocks %.1f–%.1f%%)" % [block_clears.min(), block_clears.max()]
			_lines.append("| %s | %s | %.1f%%%s | %d/%d | %s | %s | %.0f |" % [mid, mode, 100.0 * cleared / total, spread, boss_won, boss_reached, ", ".join(bosses), ", ".join(worst), float(rs["chips"]) / total])
			print("%-10s %-8s clear %5.1f%%%s  boss won/reached %3d/%3d (%s)  deaths at %s" % [mid, mode, 100.0 * cleared / total, spread, boss_won, boss_reached, ", ".join(bosses), ", ".join(worst)])
			var f := maxf(1.0, _fs["fights"])
			print("%-10s %-8s   per fight: %.1f turns, %.1f cards, %.2f dead turns, %.2f vents; out of cards in %.0f%% of fights" % [mid, mode,
				_fs["turns"] / f, _fs["cards"] / f, _fs["dead"] / f, _fs["vents"] / f, 100.0 * _fs["ran_out"] / f])
			print("%-10s %-8s   per run: %.1f stops, %.0f scraps earned, %.2f shops visited (%.0f scraps on hand at each), %.0f Chips, %.1f memorial points" % [mid, mode,
				float(rs["stops"]) / total, float(rs["scraps"]) / total, float(rs["shops"]) / total, float(rs["shop_scraps"]) / maxf(1.0, rs["shops"]), float(rs["chips"]) / total, float(rs["memorial"]) / total])
	var eids := _enemy_stats.keys()
	eids.sort()
	for id in eids:
		var es: Array = _enemy_stats[id]
		print("enemy %-16s %5d fights, player won %5.1f%%, %.0f damage taken, %.0f dealt by it" % [id, es[0], 100.0 * es[1] / es[0], float(es[2]) / es[0], float(es[3]) / es[0]])
	if report:
		_write_report()
	if trace_path != "":
		var tf := FileAccess.open(trace_path, FileAccess.WRITE)
		tf.store_string("\n".join(_trace) + "\n")
		print("trace: %s (%d lines)" % [trace_path, _trace.size()])
	quit()

# ---------- deployment orders ----------

## Offers the three orders (as a real run does after Launch) and takes one:
## a random one of the three, or the one --orders names (offered alone).
## Then does the order's steps. Returns the order taken ("" for none).
func _take_order(run: RunData, choices: RandomNumberGenerator) -> String:
	if orders_mode == "none":
		return ""
	DeploymentOrders.offer(run)
	var id := orders_mode
	if orders_mode == "random":
		var offer: Array = run.orders["offer"]
		id = offer[choices.randi_range(0, offer.size() - 1)]
	else:
		run.orders["offer"] = [id]
	DeploymentOrders.choose(run, id)
	var guard := 0
	while not DeploymentOrders.current_step(run).is_empty() and guard < 20:
		guard += 1
		var step := DeploymentOrders.current_step(run)
		match step["type"]:
			DeploymentOrders.STEP_PICK:
				var opts: Array = DeploymentOrders.pick_category(run, "hardpoint")
				opts.sort_custom(func(a, b): return _punch(ComponentLibrary.make(a)) > _punch(ComponentLibrary.make(b)))
				if opts.is_empty() or DeploymentOrders.pick_part(run, opts[0]) == "":
					(run.orders["steps"] as Array).pop_front()
			DeploymentOrders.STEP_CELLS:
				var cells := run.cell_options()
				if cells.is_empty() or not DeploymentOrders.add_cell(run, cells[0]):
					(run.orders["steps"] as Array).pop_front()
			DeploymentOrders.STEP_REMOVE, DeploymentOrders.STEP_TRANSMUTE:
				# strip the weakest part it can; transmute the weakest hardpoint
				var parts := run.player_mech.components.filter(func(c): return DeploymentOrders.can_choose_part(run, c))
				if step["type"] == DeploymentOrders.STEP_TRANSMUTE:
					var hps := parts.filter(func(c): return c.category == ComponentData.CATEGORY_HARDPOINT)
					if not hps.is_empty():
						parts = hps
				parts.sort_custom(func(a, b): return _punch(a) + a.max_hp * 0.1 < _punch(b) + b.max_hp * 0.1)
				if parts.is_empty() or DeploymentOrders.choose_part(run, parts[0]) == "":
					(run.orders["steps"] as Array).pop_front()
	return id

# ---------- enemy overrides ----------

## --mech overrides on this fight's enemies.
func _apply_mech_overrides(ws: Array[MechData]) -> void:
	for w in ws:
		for kv in _mech_overrides.get(w.id, []):
			var key: String = kv[0]
			var raw: String = kv[1]
			if key == "swap":
				_swap_part(w, raw.get_slice(":", 0), raw.get_slice(":", 1))
			elif key == "add":
				_swap_part(w, "", raw)
			elif key.begins_with("ai."):
				w.ai[key.trim_prefix("ai.")] = float(raw) if raw.is_valid_float() else raw
			elif key in ["max_heat"]:
				w.max_heat = int(raw)
			elif key == "defeat_hp_fraction":
				w.defeat_hp_fraction = float(raw)
			elif key == "heat_check_timing":
				w.heat_check_timing = raw
			else:
				push_warning("--mech: unknown key %s" % key)

## Replaces one of an enemy's parts with a Refit Bay part, placed where the
## old one was (another rotation, then any spot on the frame, if it doesn't
## fit that way).
func _swap_part(w: MechData, old_id: String, new_id: String) -> void:
	var old := w.get_component(old_id) if old_id != "" else null
	var comp := ComponentLibrary.make(new_id)
	if (old == null and old_id != "") or comp == null:
		push_warning("--mech swap: no %s on %s, or no part %s" % [old_id, w.id, new_id])
		return
	var occupied := {}
	for c in w.components:
		if c != old:
			for cell in c.placed_cells:
				occupied[cell] = true
	var frame := GridUtils.cells_to_set(w.cells)
	var offsets: Array = [old.offset] if old != null else []
	for cell in w.cells:
		offsets.append(cell)
	for off in offsets:
		for rot in ([old.rotation_steps] if old != null else []) + [0, 1, 2, 3]:
			if GridUtils.can_place(comp.cells, rot, off, frame, occupied):
				comp.set_instance_id(new_id if w.get_component(new_id) == null else "%s_2" % new_id)
				comp.place(rot, off)
				if old != null:
					w.components[w.components.find(old)] = comp
				else:
					w.components.append(comp)
				return
	var warn := "%s:%s:%s" % [w.id, old_id, new_id]
	if not _warned.has(warn):
		_warned[warn] = true
		push_warning("--mech: %s doesn't fit anywhere on %s%s" % [new_id, w.id, "" if old_id == "" else " once %s is out" % old_id])

# ---------- report stats ----------

func _count_run(order: String, events_picked: Array[String], run: RunData, won: bool) -> void:
	if order != "":
		var o: Dictionary = _order_stats.get(order, {"runs": 0, "clears": 0, "builder_runs": 0, "builder_clears": 0})
		o["runs"] += 1
		o["clears"] += 1 if won else 0
		if builder:
			o["builder_runs"] += 1
			o["builder_clears"] += 1 if won else 0
		_order_stats[order] = o
	for key in events_picked:
		var e: Dictionary = _event_stats.get(key, {"picked": 0, "clears": 0})
		e["picked"] += 1
		e["clears"] += 1 if won else 0
		_event_stats[key] = e
	if builder:
		_builder_runs += 1
		_builder_clears += 1 if won else 0
		for id in _run_parts:
			var ps := _part(id)
			ps["runs"] += 1
			ps["clears"] += 1 if won else 0

func _part(id: String) -> Dictionary:
	if not _part_stats.has(id):
		_part_stats[id] = {"offered": 0, "taken": 0, "runs": 0, "clears": 0}
	return _part_stats[id]

func _t(line: String) -> void:
	if trace_path != "":
		_trace.append(line)

## Logs every signal of one fight (mechs: player first, then the enemies).
func _trace_fight(cm: CombatManager, mechs: Array) -> void:
	if trace_path == "":
		return
	var tag := func(m: MechData) -> String: return "%s#%d" % [m.id, mechs.find(m)]
	var cid := func(c: ComponentData) -> String: return c.id if c != null else "-"
	cm.component_damaged.connect(func(m, c, n): _t("damaged %s %s %d" % [tag.call(m), cid.call(c), n]))
	cm.component_destroyed.connect(func(m, c): _t("destroyed %s %s" % [tag.call(m), cid.call(c)]))
	cm.card_played.connect(func(m, card): _t("card %s %s/%s" % [tag.call(m), card.owner_component_id, card.id]))
	cm.overheated.connect(func(m, n): _t("overheat %s %d" % [tag.call(m), n]))
	cm.turn_changed.connect(func(ph, n): _t("turn %d %d" % [ph, n]))
	cm.enemy_action.connect(func(e): _t("enemy %s %s/%s -> %s %d %s" % [tag.call(e["mech"]), e["component"], e["card"], e["target"], e["damage"], e["target_destroyed"]]))
	cm.game_over.connect(func(r): _t("game_over %d" % r))
	cm.enemy_turn_started.connect(func(): _t("enemy_turn"))
	cm.hit_landed.connect(func(m, c, n): _t("hit %s %s %d" % [tag.call(m), cid.call(c), n]))
	cm.hit_missed.connect(func(m, c): _t("miss %s %s" % [tag.call(m), cid.call(c)]))
	cm.passive_triggered.connect(func(m, c): _t("passive %s %s" % [tag.call(m), cid.call(c)]))
	cm.hand_changed.connect(func(): _t("hand"))
	cm.primed_changed.connect(func(): _t("primed %s" % ",".join(cm.primed.map(func(p): return p["type"]))))
	cm.boss_phase_changed.connect(func(m): _t("boss_phase %s" % tag.call(m)))
	cm.enemy_set_aside.connect(func(m, card): _t("set_aside %s %s" % [tag.call(m), card.id]))
	cm.chance_failed.connect(func(m, c): _t("chance_failed %s %s" % [tag.call(m), cid.call(c)]))
	cm.mech_vented.connect(func(m, n): _t("vented %s %d" % [tag.call(m), n]))

## Every mech's heat, statuses and parts, and the fight's RNG state.
func _state(cm: CombatManager, mechs: Array) -> String:
	var out := PackedStringArray(["state rng %s" % cm.rng.state])
	for m in mechs:
		var ms := ",".join(m.mech_statuses.map(func(s): return "%s%d" % [s.status, s.stacks]))
		var parts := PackedStringArray()
		for c in m.components:
			parts.append("%s:%d%s[%s]" % [c.id, c.current_hp, "D" if c.destroyed else "", ",".join(c.statuses.map(func(s): return "%s%d" % [s.status, s.stacks]))])
		out.append("%s h%d [%s] %s" % [m.id, m.current_heat, ms, " ".join(parts)])
	return " | ".join(out)

## tools/reports/sim_<date>.md: clear rates and per-enemy results.
func _write_report() -> void:
	var date := Time.get_date_string_from_system()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/reports"))
	var path := "res://tools/reports/sim_%s.md" % date
	var md := "# Balance sim, %s\n\n%d runs per mission per bot%s, seeds from %d, pilot %s, orders %s, events %s.%s\n\n" % [date, N * sweeps,
		"" if sweeps == 1 else " (%d blocks of %d)" % [sweeps, N], seed_start, pilot, orders_mode, events_mode,
		"" if _overrides.is_empty() else " Overrides: " + ", ".join(_overrides) + "."]
	md += "## Clear rates\n\n| Mission | Bot | Clear | Boss won/reached | By boss | Most deaths | Chips/run |\n|---|---|---|---|---|---|---|\n"
	md += "\n".join(_lines) + "\n\n"
	md += "## Enemies (every bot, every fight they were in)\n\n| Enemy | Fights | Player won | Damage the player took | Dealt by this enemy |\n|---|---|---|---|---|\n"
	var ids := _enemy_stats.keys()
	ids.sort_custom(func(a, b): return float(_enemy_stats[a][1]) / _enemy_stats[a][0] < float(_enemy_stats[b][1]) / _enemy_stats[b][0])
	for id in ids:
		var es: Array = _enemy_stats[id]
		md += "| %s | %d | %.0f%% | %.0f | %.0f |\n" % [id, es[0], 100.0 * es[1] / es[0], float(es[2]) / es[0], float(es[3]) / es[0]]
	if not _order_stats.is_empty():
		md += "\n## Deployment orders (runs that took it)\n\n| Order | Kind | Runs | Clear (all bots) | Builder runs | Builder clear |\n|---|---|---|---|---|---|\n"
		var oids := _order_stats.keys()
		oids.sort_custom(func(a, b): return _rate(_order_stats[a], "clears", "runs") > _rate(_order_stats[b], "clears", "runs"))
		for id in oids:
			var o: Dictionary = _order_stats[id]
			md += "| %s | %s | %d | %.1f%% | %d | %.1f%% |\n" % [id, DeploymentOrders.def(id).get("kind", ""), o["runs"], _rate(o, "clears", "runs"), o["builder_runs"], _rate(o, "builder_clears", "builder_runs")]
	if not _event_stats.is_empty():
		md += "\n## Event choices (runs that took it)\n\n| Event | Choice | Picked | Clear |\n|---|---|---|---|\n"
		var eids := _event_stats.keys()
		eids.sort()
		for key in eids:
			var e: Dictionary = _event_stats[key]
			var ev := _event_def(key.get_slice(":", 0))
			var ch: Array = ev.get("choices", [])
			var ci := int(key.get_slice(":", 1))
			md += "| %s | %s | %d | %.1f%% |\n" % [ev.get("title", key), ch[ci].get("label", str(ci)) if ci < ch.size() else str(ci), e["picked"], _rate(e, "clears", "picked")]
	if not _part_stats.is_empty():
		md += "\n## Hardpoints (builder: offered at salvage and bays, taken, and the clear rate of runs that took it; the builder clears %.1f%% overall)\n\n| Part | Category | Offered | Taken | Pick rate | Runs that took it | Clear |\n|---|---|---|---|---|---|---|\n" % (100.0 * _builder_clears / maxf(1.0, _builder_runs))
		var pids := _part_stats.keys()
		pids.sort_custom(func(a, b): return _rate(_part_stats[a], "clears", "runs") > _rate(_part_stats[b], "clears", "runs"))
		for id in pids:
			var ps: Dictionary = _part_stats[id]
			md += "| %s | %s | %d | %d | %s | %d | %s |\n" % [ComponentLibrary.definition(id).get("name", id), ComponentLibrary.definition(id).get("category", ""),
				ps["offered"], ps["taken"], "%.0f%%" % _rate(ps, "taken", "offered") if ps["offered"] > 0 else "–", ps["runs"],
				"%.1f%%" % _rate(ps, "clears", "runs") if ps["runs"] > 0 else "–"]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(md)
	print("report: ", path)

static func _rate(d: Dictionary, num: String, den: String) -> float:
	return 100.0 * float(d[num]) / maxf(1.0, float(d[den]))

static func _event_def(id: String) -> Dictionary:
	for e in RunEvents.events():
		if e["id"] == id:
			return e
	return {}

## A part's best card's expected damage (how the builder rates weapons).
static func _punch(comp: ComponentData) -> float:
	var best := 0.0
	for c in comp.cards:
		best = maxf(best, c.average_damage())
	return best

## Salvage: the hardpoint with the biggest hit, if Cargo has room.
func _take_best(run: RunData) -> void:
	var opts: Array = run.choose_reward_category("hardpoint")
	for id in opts:
		_part(id)["offered"] += 1
	opts.sort_custom(func(a, b): return _punch(ComponentLibrary.make(a)) > _punch(ComponentLibrary.make(b)))
	for id in opts:
		if run.take_reward_part(id) != null:
			_part(id)["taken"] += 1
			_run_parts[id] = true
			return
	run.skip_reward_part()

## Refit: clear the wrecks, then install whatever in Cargo fits (weapons first).
func _refit(run: RunData) -> void:
	run.scrap_destroyed()
	var parts := run.cargo.items.duplicate()
	parts.sort_custom(func(a, b): return _punch(a) > _punch(b))
	for comp in parts:
		if not run.fits_class(comp):
			continue
		var done := false
		for rot in range(4):
			for r in range(-1, 9):
				for c in range(-1, 9):
					if not done and run.can_install(comp, rot, Vector2i(r, c)):
						done = run.move_part(comp, RunData.MECH, rot, Vector2i(r, c))

## Autonomous bay: buy hardpoints while they're affordable and Cargo has room.
func _shop(run: RunData) -> void:
	if not builder:
		return
	for slot in range(run.shop["parts"].size()):
		var id: String = run.shop["parts"][slot]
		if id == "" or id == RunData.NO_STOCK or ComponentLibrary.definition(id).get("category", "") != "hardpoint":
			continue
		_part(id)["offered"] += 1
		if run.scraps < run.part_price(id) or run.cargo.find_fit(ComponentLibrary.make(id)).is_empty():
			continue
		var comp := run.buy_part(slot)
		if comp != null:
			_part(id)["taken"] += 1
			_run_parts[id] = true
		if comp != null and run.bench.items.has(comp):
			var fit := run.cargo.find_fit(comp)
			run.move_part(comp, RunData.CARGO, fit["rotation"], fit["offset"])

## A card that takes its own part Offline for the fight (Precision Throw).
static func _self_offline(card: CardData) -> bool:
	return card.statuses.any(func(st): return st.status == "offline" and st.target == StatusEffectData.TARGET_SELF)

## Whether `card` could bring some enemy down to its defeat line.
static func _could_finish(card: CardData, ws: Array[MechData]) -> bool:
	return ws.any(func(w): return not w.is_defeated() and w.current_hp() - w.defeat_hp_threshold() <= card.average_damage())

## Heat-aware, focused: never exceeds max heat; each pass plays the
## affordable unspent attack with the highest expected damage at the living
## enemy weapon (component with cards) with the lowest HP, falling back to
## any living part; spends leftover heat on a defensive self card. With
## unspent cards but none affordable, it vents instead. A card that knocks
## its own part Offline is kept for a finishing blow. Returns whether it vented.
func _player_turn(cm: CombatManager, p: MechData, ws: Array[MechData]) -> bool:
	if cm.can_vent():
		var any_left := false
		var affordable := false
		for card in cm.hand_cards():
			if not cm.can_play(card):
				continue
			any_left = true
			if p.current_heat + cm.effective_cost(card) <= p.max_heat:
				affordable = true
		if any_left and not affordable:
			return cm.apply({"type": "vent"})["ok"]
	var guard := 0
	while cm.is_player_turn() and guard < 20:
		guard += 1
		var best: CardData = null
		var best_dmg := -1.0
		var fallback: CardData = null
		for card in cm.hand_cards():
			if not cm.can_play(card) or p.current_heat + cm.effective_cost(card) > p.max_heat:
				continue
			if card.is_attack():
				if _self_offline(card) and not _could_finish(card, ws):
					continue # don't knock your own weapon out for good, unless it ends someone
				if card.average_damage() > best_dmg:
					best_dmg = card.average_damage()
					best = card
			elif card.heat_cost > 0 and fallback == null and card.statuses.size() > 0:
				fallback = card
		if best != null:
			var target_mech: MechData = null
			var target: ComponentData = null
			if smart:
				var best_w: MechData = null
				for w in ws:
					if w.is_defeated():
						continue
					if best_w == null or w.current_hp() - w.defeat_hp_threshold() < best_w.current_hp() - best_w.defeat_hp_threshold():
						best_w = w
				if best_w == null:
					return false
				target_mech = best_w
				if true:
					for c in best_w.non_destroyed_components():
						if c.category == ComponentData.CATEGORY_HARDPOINT and (target == null or c.current_hp < target.current_hp):
							target = c
				if target == null:
					target = best_w.non_destroyed_components()[0]
			elif casual:
				var all_parts := []
				for w in ws:
					for c in w.non_destroyed_components():
						all_parts.append([w, c])
				if all_parts.is_empty():
					return false
				var pick: Array = all_parts[(guard * 7919 + cm.turn_number * 104729 + all_parts.size()) % all_parts.size()]
				target_mech = pick[0]
				target = pick[1]
			else:
				for w in ws:
					for c in w.non_destroyed_components():
						var score := c.current_hp - (1000 if c.has_cards() else 0)
						if target == null or score < target.current_hp - (1000 if target.has_cards() else 0):
							target = c
							target_mech = w
			if target == null:
				return false
			cm.apply(cm.play_command(best, target_mech, target))
		elif fallback != null:
			cm.apply(cm.play_command(fallback))
		else:
			return false
	return false

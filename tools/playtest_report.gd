extends SceneTree
## Reads playtest reports (PlaytestReport) and prints what happened in them.
##   Godot --headless --path . --script res://tools/playtest_report.gd -- [file or folder] [--turns]
## With no path it reads every report in user://playtests/ (where the game
## writes them on this machine). For each report: the run (mech, location,
## mission, order, result), then each fight: enemies, result, turns, damage
## dealt per turn, damage taken, HP left. Every fight is replayed headless
## from its record; "replays" says whether it still plays the same on
## today's rules and data ("CHANGED" when the data has moved on since the
## report was written, or "OUT OF STEP" when it hasn't and still differs,
## which is a bug). --turns adds each fight's damage turn by turn.
## Ends with averages over every fight read.

var _turns_detail := false
var _all_turns: Array[int] = []
var _all_per_turn: Array[float] = []
var _won := 0
var _lost := 0

func _initialize() -> void:
	var paths: Array[String] = []
	for a in OS.get_cmdline_user_args():
		if a == "--turns":
			_turns_detail = true
		elif not a.begins_with("--"):
			paths.append(a)
	if paths.is_empty():
		paths.append(PlaytestReport.DIR)
	var files: Array[String] = []
	for p in paths:
		if DirAccess.dir_exists_absolute(p):
			var names := Array(DirAccess.get_files_at(p)).filter(func(f): return f.ends_with(".json"))
			names.sort()
			for n in names:
				files.append(p.path_join(n))
		elif FileAccess.file_exists(p):
			files.append(p)
	if files.is_empty():
		print("No playtest reports found in %s" % ", ".join(paths))
		quit(0)
		return
	var today := PlaytestReport.game_info()
	for f in files:
		_read(f, today)
	print("")
	if _all_turns.is_empty():
		print("No fights in these reports.")
	else:
		var t := 0.0
		for n in _all_turns:
			t += n
		var d := 0.0
		for x in _all_per_turn:
			d += x
		print("== %d fights: %d won, %d lost · %.1f turns a fight · %.0f damage a turn ==" % [
			_all_turns.size(), _won, _lost, t / _all_turns.size(), d / maxf(1.0, _all_per_turn.size())])
	quit(0)

func _read(path: String, today: Dictionary) -> void:
	var rep = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(rep) != TYPE_DICTIONARY:
		print("%s: not a playtest report" % path)
		return
	print("")
	print("%s · %s" % [path.get_file(), rep.get("game", {}).get("build", "build unknown")])
	var same_data: bool = str(rep.get("game", {}).get("data_hash", "")) == str(today["data_hash"])
	if rep.get("kind", "") == "run":
		var r: Dictionary = rep.get("run", {})
		print("  %s · %s · %s · %s (%d stops)%s%s" % [str(r.get("mech", "")).capitalize(), r.get("location", ""), r.get("mission", ""),
			str(r.get("result", "")).to_upper(), int(r.get("stops", 0)),
			" · order " + DeploymentOrders.title(r["order"]) if str(r.get("order", "")) != "" else "",
			" · " + str(r["cause"]) if str(r.get("cause", "")) != "" else ""])
	else:
		var s: Dictionary = rep.get("save", {})
		print("  Mid-run snapshot · %s · stop %d · %d scraps" % [str(s.get("location_id", "")), (s.get("path", []) as Array).size(), int(s.get("scraps", 0))])
	if not same_data:
		print("  (played on different data than today's: fights may not replay the same)")
	var crashes: Dictionary = rep.get("crashes", {})
	for res in rep.get("resumes", []):
		var crash := str(res.get("crash", ""))
		print("  Continued at %s, stop %d%s" % [res.get("at", "?"), int(res.get("stops", 0)), " · after a crash (%s)" % crash if crash != "" else ""])
		if crash != "":
			for line in str(crashes.get(crash, "")).split("\n"):
				if line.begins_with("Verdict") or line.begins_with("Last action") or line.begins_with("  The game") or line.begins_with("  gpu") or line.begins_with("  graphics_api") or line.begins_with("  os"):
					print("      " + line.strip_edges())
	var i := 0
	for rec in rep.get("fights", []):
		i += 1
		_fight(i, rec, same_data)

func _fight(i: int, rec: Dictionary, same_data: bool) -> void:
	var names: Array = rec.get("labels", [])
	if names.is_empty():
		names = rec.get("enemies", []).map(func(e): return e.get("name", e.get("id", "?")))
	var st: Dictionary = rec.get("stats", {})
	var turns := int(rec.get("turns", 0))
	var dealt := int(st.get("damage_dealt", 0))
	var p: Dictionary = rec.get("player", {})
	var hp_max := 0
	for part in p.get("parts", []):
		hp_max += int(part.get("max_hp", 0))
	var line := "  %2d  %-34s %-11s %2d turns  dealt %4d (%3.0f/turn)  taken %3d" % [
		i, ", ".join(names).left(34), str(rec.get("result", "")), turns, dealt, dealt / maxf(1.0, turns), int(st.get("damage_taken", 0))]
	var per_turn := _replay_by_turn(rec)
	if per_turn.is_empty():
		line += "  replays: can't (a mech file is gone)"
	elif per_turn["matches"]:
		line += "  replays: ok"
	else:
		line += "  replays: %s" % ("CHANGED" if not same_data else "OUT OF STEP")
	print(line)
	if _turns_detail and not per_turn.is_empty():
		print("        dealt by turn: %s" % " ".join(per_turn["dealt"].map(func(n): return str(n))))
		print("        taken by turn: %s" % " ".join(per_turn["taken"].map(func(n): return str(n))))
	if str(rec.get("result", "")) in ["win", "loss"]:
		_all_turns.append(turns)
		_all_per_turn.append(dealt / maxf(1.0, turns))
		if rec["result"] == "win":
			_won += 1
		else:
			_lost += 1

## Replays the record headless, noting damage dealt and taken each turn.
func _replay_by_turn(rec: Dictionary) -> Dictionary:
	var ms := FightRecord.mechs(rec)
	if ms.is_empty():
		return {}
	var cm := CombatManager.new(ms["player"], ms["enemies"], int(rec["seed"]))
	cm.start_combat()
	FightRecord.apply_opening(rec, ms["player"], ms["enemies"])
	var dealt: Array = []
	var taken: Array = []
	var d0 := 0
	var t0 := 0
	var refused := 0
	for cmd in rec.get("commands", []):
		if not cm.apply(cmd).get("ok", false):
			refused += 1
		if cmd.get("type", "") == "end_turn" or cm.is_game_over():
			dealt.append(cm.stats.get_stat("damage_dealt") - d0)
			taken.append(cm.stats.get_stat("damage_taken") - t0)
			d0 = cm.stats.get_stat("damage_dealt")
			t0 = cm.stats.get_stat("damage_taken")
	var res := FightRecord.result_name(cm.result)
	var want := str(rec.get("result", ""))
	var matches := refused == 0 and cm.stats.get_stat("damage_dealt") == int(rec.get("stats", {}).get("damage_dealt", 0)) \
		and (res == want or (res == "" and want in ["ejected", "in progress"]))
	return {"dealt": dealt, "taken": taken, "matches": matches}

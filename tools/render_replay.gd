extends Node
## Dev tool: plays a recorded fight in the combat screen's replay mode and
## quits a few seconds after it ends. Run under Godot's Movie Maker
## (--write-movie) it renders the fight to video frame-perfect, at any
## resolution; tools/render_replay.sh does that and makes an mp4.
##   Godot --path . --resolution 1920x1080 --fixed-fps 60 --write-movie out.avi res://tools/RenderReplay.tscn -- <file> [--fight=N] [--speed=1.0] [--clean] [--hold=3]
## <file>: a fight record (user://replays/*.json), a playtest report
## (user://playtests/*.json, or fight_replay.json from a feedback zip;
## --fight=N picks its Nth fight, default the last), or a replay's name.
## --clean hides the REPLAY strip. Mouse input is ignored, so a stray
## cursor never hovers anything into the shot. Settings are never saved.

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var file := ""
	var fight := -1
	var hold := 3.0
	var clean := false
	GameSettings.speed = 1.0
	for a in args:
		if a.begins_with("--fight="):
			fight = int(a.get_slice("=", 1)) - 1
		elif a.begins_with("--speed="):
			GameSettings.speed = float(a.get_slice("=", 1))
		elif a.begins_with("--hold="):
			hold = float(a.get_slice("=", 1))
		elif a == "--clean":
			clean = true
		elif not a.begins_with("--"):
			file = a
	var rec := _load(file, fight)
	if rec.is_empty():
		printerr("render_replay: no fight in '%s'" % file)
		get_tree().quit(1)
		return
	GameSettings.operator_tips = false
	GameSettings.apply()
	get_tree().root.gui_disable_input = true
	CombatScene.replay_record = rec
	CombatScene.replay_return = SceneRouter.WAR_ROOM
	var cs: Node = load(SceneRouter.COMBAT).instantiate()
	get_tree().root.add_child.call_deferred(cs)
	get_tree().set_deferred("current_scene", cs)
	print("render_replay: %s, %d commands, recorded %s" % [rec.get("location", "?"), rec.get("commands", []).size(), rec.get("result", "?")])
	# a cap so a replay that stalls can't render forever (game time)
	var limit := 60.0 * 20
	var t := 0.0
	while t < limit:
		await get_tree().process_frame
		t += get_process_delta_time()
		if clean and cs._replay_bar != null:
			cs._replay_bar.visible = false
		if cs.end_screen != null and cs.end_screen.visible:
			break
	await get_tree().create_timer(hold).timeout
	print("render_replay: done at %.1f s (%s)" % [t, FightRecord.result_name(cs.combat.result) if cs.combat != null else "?"])
	get_tree().quit()

## The fight record in `file`: a record itself, or the Nth (default last)
## fight of a playtest report.
func _load(file: String, fight: int) -> Dictionary:
	if file == "":
		return {}
	if not FileAccess.file_exists(file) and Replays.exists(file):
		return Replays.load_record(file)
	var d = JSON.parse_string(FileAccess.get_file_as_string(file))
	if typeof(d) != TYPE_DICTIONARY:
		return {}
	if d.has("commands"):
		return d
	var fights: Array = d.get("fights", [])
	if fights.is_empty():
		return {}
	return fights[fight] if fight >= 0 and fight < fights.size() else fights[-1]

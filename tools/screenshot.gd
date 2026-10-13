extends Node
## Dev tool: opens one run screen in a set-up state and saves a PNG, to
## check layouts without playing to them. Needs a window (not --headless):
##   Godot --path . res://tools/Screenshot.tscn -- <shop|combat|combat_play|map|refit|event>[_settings] <out.png> [seconds] [event id] [choice taken]
##        [--colorblind] [--reduce-motion] [--pad-page (with _settings: the gamepad controls page)]
##        [--enemies=needle_drone,scrap_warden (combat: fight these)]
## A screen name ending in _settings opens the settings menu over it.
## "hub_<station>" [tab] opens a War Room station (hub_pilot_log mechs).
## "daily" opens the War Room, zooms into the War Table and opens the Daily
## Operation's pop-up (it reads the real profile but never saves it).
## combat_keys does the same with key presses (number keys, Tab, Enter, E).
## combat_reveal just waits (the opening passive reveal, with no card played).
## combat_preview primes a protocol, then hovers an attack card that would overheat (the red edge
## glow, the backlash on the player's health bar) while aiming it at the
## weakest enemy part (the damage on its health bar, the part it destroys).
## combat_play drives three turns through the combat screen's own handlers
## (card drops on enemy parts, End Turn) and prints the command log: a smoke
## test of the UI path.
## combat_record plays a whole fight that way (up to 15 turns, at 3× speed),
## writes its recording (FightRecord) to <out.png>.json, and checks that it
## replays headless to the same end: the UI path and the rules agree.
## combat_pad fakes a gamepad (Input.parse_input_event): RB picks a card,
## A fires it, the stick moves the cursor; prints what happened.
## replay <out.png> [seconds] <record.json> opens a recorded fight in the
## combat screen's replay mode and prints whether it ended as recorded.
## profile_<screen> (profile_combat, profile_map) measures instead of saving:
## vsync off, then frame time and draw calls over 6 seconds,
## once as is and once with each experiment (no MSAA on HoloTerrain, no rain).
## It never saves the run or touches the profile.

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	# display settings for this shot only (never saved): --colorblind --reduce-motion
	for a in args.duplicate():
		if a.begins_with("--"):
			args.erase(a)
			if a == "--colorblind":
				GameSettings.colorblind = true
			elif a == "--reduce-motion":
				GameSettings.reduce_motion = true
			elif a == "--seen-all": # the codex as if every enemy and order had been met (not saved)
				for f in DirAccess.get_files_at("res://data/mechs"):
					Profile.seen_enemies.append(f.get_basename())
				for o in DeploymentOrders.all():
					Profile.seen_orders.append(o["id"])
	GameSettings.apply()
	var what: String = args[0] if args.size() > 0 else "shop"
	var settings := what.ends_with("_settings") # open the settings menu over the screen
	if settings:
		what = what.trim_suffix("_settings")
	var profiling := what.begins_with("profile_")
	if profiling:
		what = what.trim_prefix("profile_")
	var out: String = args[1] if args.size() > 1 else "/tmp/shot.png"
	var wait: float = float(args[2]) if args.size() > 2 else 2.5
	if what.begins_with("hub_"): # a War Room station: hub_pilot_log [tab], hub_info_bay [tab], hub_directives...
		var station: Node = load(SceneRouter.get(what.trim_prefix("hub_").to_upper())).instantiate()
		get_tree().root.add_child.call_deferred(station)
		get_tree().set_deferred("current_scene", station)
		await get_tree().create_timer(1.0).timeout
		if args.size() > 3 and "_tab" in station:
			station._tab = args[3]
			station._rebuild() if station.has_method("_rebuild") else station._fill()
		await get_tree().create_timer(wait).timeout
		get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
		get_tree().quit()
		return
	if what == "continue" or what == "warroom": # the War Room (its Operator line); "continue" opens a saved run's box (read only)
		var wr: Node = load(SceneRouter.WAR_ROOM).instantiate()
		get_tree().root.add_child.call_deferred(wr)
		get_tree().set_deferred("current_scene", wr)
		await get_tree().create_timer(1.5).timeout
		if Tutorial.has_method("skip"):
			Tutorial._root.visible = false
		if what == "continue" and SaveGame.has_save():
			wr.popup.open_continue(SaveGame.summary())
		await get_tree().create_timer(wait).timeout
		get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
		get_tree().quit()
		return
	if what == "daily": # the War Table, zoomed in, with the Daily Operation's pop-up open
		var room: Node = load(SceneRouter.WAR_ROOM).instantiate()
		get_tree().root.add_child.call_deferred(room)
		get_tree().set_deferred("current_scene", room)
		await get_tree().create_timer(1.0).timeout
		room._zoom_in()
		await get_tree().create_timer(2.5).timeout
		room._on_daily()
		await get_tree().create_timer(wait).timeout
		get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
		get_tree().quit()
		return
	if what == "replay": # a recorded fight, played back
		var rec = JSON.parse_string(FileAccess.get_file_as_string(args[3]))
		GameSettings.speed = 3.0
		CombatScene.replay_record = rec
		var cs_inst: Node = load(SceneRouter.COMBAT).instantiate()
		get_tree().root.add_child.call_deferred(cs_inst)
		get_tree().set_deferred("current_scene", cs_inst)
		await get_tree().create_timer(wait).timeout
		get_viewport().get_texture().get_image().save_png(out)
		print("saved ", out)
		var cm: CombatManager = cs_inst.combat
		var limit := Time.get_ticks_msec() + 240000
		while not cm.is_game_over() and Time.get_ticks_msec() < limit and cm.command_log.size() < rec["commands"].size():
			await get_tree().create_timer(0.5).timeout
		while not cm.is_game_over() and not cm.is_player_turn() and Time.get_ticks_msec() < limit:
			await get_tree().create_timer(0.5).timeout
		print("replay: %d/%d commands, turn %d (recorded %d), dealt %d (recorded %d), result %s (recorded %s)" % [
			cm.command_log.size(), rec["commands"].size(), cm.turn_number, int(rec["turns"]),
			cm.stats.get_stat("damage_dealt"), int(rec["stats"].get("damage_dealt", 0)), FightRecord.result_name(cm.result), rec["result"]])
		get_tree().quit()
		return
	var mission := GameData.mission("assault").duplicate(true)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--enemies="):
			mission["encounter"] = a.trim_prefix("--enemies=").split(",")
	var run := RunData.new(GameData.sector("shipyard"), GameData.player_mech("bastion"), 12345, mission)
	RunState.run = run
	var scene := ""
	match what:
		"shop", "shop_leave":
			run.phase = RunData.PHASE_SHOP
			run._stock_shop()
			run.add_scraps(300)
			run.cargo.add(run.new_part("autocannon"))
			scene = RunState.PHASE_SCENES[RunData.PHASE_SHOP]
		"reward", "reward_parts", "reward_mech": # salvage after a won fight (reward_parts: a category picked; reward_mech: and SHOW MECH)
			run.choose_node(run.available_nodes()[0])
			run.fight_won()
			if what != "reward":
				run.choose_reward_category("hardpoint")
			scene = RunState.PHASE_SCENES[RunData.PHASE_REWARD]
		"refit":
			run.phase = RunData.PHASE_REFIT
			run.cargo.add(run.new_part("autocannon"))
			scene = RunState.PHASE_SCENES[RunData.PHASE_REFIT]
		"event", "event_map":
			run.current_node_id = run.available_nodes()[0]
			run.phase = RunData.PHASE_EVENT
			run.event = {"id": args[3] if args.size() > 3 else "live_relay", "step": "", "resolved": false, "result": ""}
			if args.size() > 4: # a choice already taken (a multi-step event's next step)
				run.resolve_event(int(args[4]))
			scene = RunState.PHASE_SCENES[RunData.PHASE_EVENT]
		"combat", "combat_reveal", "combat_end", "combat_preview", "combat_play", "combat_keys", "combat_record", "combat_pad", "combat_status", "combat_map":
			run.choose_node(run.available_nodes()[0])
			scene = RunState.PHASE_SCENES[RunData.PHASE_FIGHT]
		_:
			scene = RunState.PHASE_SCENES[RunData.PHASE_MAP]
	# Added beside this node (a scene change would free it mid-wait).
	var inst: Node = load(scene).instantiate()
	get_tree().root.add_child.call_deferred(inst)
	get_tree().set_deferred("current_scene", inst)
	await get_tree().create_timer(wait).timeout
	if settings:
		for n in _all_menus(get_tree().root):
			n.open()
			if "--pad-page" in OS.get_cmdline_user_args(): # Keys and controls → Gamepad
				n._show_controls(true)
				for btn in n.find_children("*", "Button", true, false):
					if btn.text == "Gamepad":
						btn.pressed.emit()
		await get_tree().create_timer(0.3).timeout
	if profiling:
		await _profile()
		get_tree().quit()
		return
	if what == "map" and args.size() > 3: # hover a stop (its path preview)
		get_tree().current_scene._on_node_hover(int(args[3]), true)
		await get_tree().create_timer(0.6).timeout
	if what == "shop_leave": # the leave button's first press (its warning)
		get_tree().current_scene._on_leave()
		await get_tree().create_timer(0.5).timeout
	if what == "combat":
		_play_one_card()
		await get_tree().create_timer(2.5).timeout
	if what == "combat_map" or what == "event_map": # the location map over the fight / the stop
		LocationMapScreen.peek(get_tree().current_scene)
		await get_tree().create_timer(2.0).timeout
	if what == "reward_mech":
		get_tree().current_scene._mech_toggle.button_pressed = true
		await get_tree().create_timer(0.5).timeout
	if what == "combat_status": # statuses on every enemy (a part's Shock, the mech's Deflect)
		var cs := get_tree().current_scene
		for e in cs.combat.enemies:
			CardResolver.add_status_to(e, e.non_destroyed_components()[0], "shock", 2, true)
			CardResolver.add_status_to(e, e.non_destroyed_components()[-1], "acid", 1, true)
			e.add_mech_status("deflect", 3)
		cs._refresh_all_panels()
		await get_tree().create_timer(1.0).timeout
	if what == "combat_end": # the win screen over the fight
		var ecs := get_tree().current_scene
		ecs.end_screen.show_result(CombatManager.Result.WIN, "Continue", ecs.combat.stats)
		await get_tree().create_timer(1.2).timeout
	if what == "combat_preview":
		_aim_overheating_card()
		await get_tree().create_timer(1.2).timeout
	elif what == "combat_play":
		await _play_turns(3)
	elif what == "combat_keys":
		await _key_turns(2)
	elif what == "combat_pad":
		await _pad_test()
	elif what == "combat_record":
		GameSettings.speed = 3.0
		await _play_turns(int(args[3]) if args.size() > 3 else 15)
		var rec: Dictionary = get_tree().current_scene._record_so_far()
		var f := FileAccess.open(out + ".json", FileAccess.WRITE)
		f.store_string(JSON.stringify(rec))
		f.close()
		var r := FightRecord.replay(JSON.parse_string(JSON.stringify(rec)))
		var cm: CombatManager = get_tree().current_scene.combat
		print("combat_record: %d commands, turn %d, result %s; headless replay: turn %d, result %s, dealt %d vs %d -> %s" % [
			rec["commands"].size(), cm.turn_number, FightRecord.result_name(cm.result), r["turns"], r["result"],
			r["combat"].stats.get_stat("damage_dealt"), cm.stats.get_stat("damage_dealt"),
			"SAME" if r["turns"] == cm.turn_number and r["result"] == FightRecord.result_name(cm.result) and r["combat"].stats.get_stat("damage_dealt") == cm.stats.get_stat("damage_dealt") else "DIFFERENT"])
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()

## Combat: plays the first affordable attack so the SPENT state shows.
func _play_one_card() -> void:
	var cs := get_tree().current_scene
	if cs == null or not ("combat" in cs) or cs.combat == null:
		return
	var cm: CombatManager = cs.combat
	for card in cm.hand_cards():
		if card.is_attack() and cm.can_play(card):
			var e: MechData = cm.living_enemies()[0]
			cm.play_attack_card(card, e, e.non_destroyed_components()[0])
			return

## combat_preview: heat just under max, an attack hovered and aimed at the
## enemy part with the least HP left.
func _aim_overheating_card() -> void:
	var cs := get_tree().current_scene
	if cs == null or not ("combat" in cs) or cs.combat == null:
		return
	var cm: CombatManager = cs.combat
	for card in cm.hand_cards(): # prime a protocol first (its badge, the glow on the cards it affects)
		if card.protocol() != "" and cm.can_play(card):
			cm.apply(cm.play_command(card, null, null))
			break
	for card in cm.hand_cards():
		if card.is_attack():
			cm.player_mech.current_heat = cm.player_mech.heat_capacity() - cm.effective_cost(card) + 1
			cm.player_mech.add_mech_status("absorb", 5) # status badges, with their stacks
			cm.living_enemies()[0].add_mech_status("deflect", 3)
			cs.player_panel.refresh()
			for ep in cs.enemy_panels:
				ep.refresh()
			var ui: CardUI = cs.hand_tray.card_ui_for(card)
			ui._on_mouse_entered() # lifts it and opens its hint, as a real hover does
			var e: MechData = cm.living_enemies()[0]
			var parts := e.non_destroyed_components()
			parts.sort_custom(func(a, b): return a.current_hp < b.current_hp)
			parts[0].current_hp = mini(parts[0].current_hp, card.damage_min)
			cs.enemy_panels[0].refresh()
			cs._aim_card = card
			cs._set_targeting({"mech": e, "component": parts[0], "panel": cs.enemy_panels[0]})
			return

## combat_play: each turn drops every affordable card through the screen's
## drop handler (attacks on the first living enemy part), waits for the hits
## to play out, then presses End Turn and waits out the enemy turn.
func _play_turns(turns: int) -> void:
	var cs := get_tree().current_scene
	if cs == null or not ("combat" in cs) or cs.combat == null:
		print("combat_play: no combat scene")
		return
	var cm: CombatManager = cs.combat
	for n in range(turns):
		var waited := 0
		while not cm.is_game_over() and (not cm.is_player_turn() or UIState.input_locked): # the passive reveal, the enemy turn
			await get_tree().create_timer(0.2).timeout
			waited += 1
			if waited % 50 == 0:
				print("combat_play: still waiting at turn %d (player turn %s, input locked %s, phase %d)" % [cm.turn_number, cm.is_player_turn(), UIState.input_locked, cm.phase])
		if cm.is_game_over():
			break
		for card in cm.hand_cards():
			if not cm.is_player_turn() or cm.is_game_over():
				break
			if not cm.can_play(card) or cm.player_mech.current_heat + cm.effective_cost(card) > cm.player_mech.heat_capacity() or card.protocol() == "reroute":
				continue
			var point := Vector2.ZERO
			if card.is_attack():
				var e: MechData = cm.living_enemies()[0]
				point = cs._grid_for(e).component_center_global(e.non_destroyed_components()[0])
			cs._handle_card_drop(card, point, 999.0)
			while not cm.is_game_over() and (cm.has_pending_attack() or UIState.input_locked):
				await get_tree().create_timer(0.1).timeout
		if cm.is_player_turn():
			cs._on_end_turn_pressed()
		await get_tree().create_timer(0.5).timeout
	while not cm.is_game_over() and UIState.input_locked:
		await get_tree().create_timer(0.2).timeout
	await get_tree().create_timer(1.0).timeout
	print("combat_play: turn %d, result %d, %d commands: %s" % [cm.turn_number, cm.result, cm.command_log.size(), JSON.stringify(cm.command_log)])

## profile_*: frame time (avg and 95th percentile) and draw
## calls, as is and with each experiment switched on.
func _profile() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var root := get_tree().current_scene
	print("profile: %s" % await _measure())
	print("profile, again (noise): %s" % await _measure())
	var terrains := _all(root, "HoloTerrain")
	for t in terrains:
		t._viewport.msaa_3d = Viewport.MSAA_DISABLED
	if not terrains.is_empty():
		print("profile, HoloTerrain without MSAA: %s" % await _measure())
		for t in terrains:
			t._viewport.msaa_3d = Viewport.MSAA_4X
		for t in terrains:
			t._viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		print("profile, HoloTerrain frozen (not rendered): %s" % await _measure())
		for t in terrains:
			t._viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var rains := _all(root, "Rain")
	for r in rains:
		r.visible = false
		r.set_process(false)
	if not rains.is_empty():
		print("profile, no rain: %s" % await _measure())

func _measure(seconds: float = 6.0) -> String:
	await get_tree().create_timer(1.0).timeout # settle
	var frames: Array[float] = []
	var calls := 0.0
	# GPU time per viewport (the window, and each HoloTerrain's SubViewport):
	# frame time alone is capped by the display on macOS.
	var vps: Array = [get_viewport()]
	for t in _all(get_tree().current_scene, "HoloTerrain"):
		vps.append(t._viewport)
	var gpu := {}
	for vp in vps:
		RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
		gpu[vp] = Vector2.ZERO
	var t0 := Time.get_ticks_usec()
	var last := t0
	while Time.get_ticks_usec() - t0 < int(seconds * 1000000.0):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
		calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		for vp in vps:
			gpu[vp] += Vector2(RenderingServer.viewport_get_measured_render_time_cpu(vp.get_viewport_rid()), RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid()))
	var n := float(frames.size())
	var avg: float = frames.reduce(func(a, b): return a + b, 0.0) / n
	var sorted := frames.duplicate()
	sorted.sort()
	var gpu_text := PackedStringArray()
	for vp in vps:
		gpu_text.append("%s cpu %.2f / gpu %.2f ms" % ["window" if vp == get_viewport() else "terrain", gpu[vp].x / n, gpu[vp].y / n])
	return "%.2f ms/frame avg (%.0f fps), p95 %.2f ms, %.0f draw calls, render: %s (gpu 0 = the driver has no timestamps; Metal)" % [avg, 1000.0 / avg, sorted[int(n * 0.95)], calls / n, ", ".join(gpu_text)]

func _all(node: Node, cls: String) -> Array:
	var out := []
	if node == null:
		return out
	if node.get_script() != null and node.get_script().get_global_name() == cls:
		out.append(node)
	for c in node.get_children():
		out.append_array(_all(c, cls))
	return out

func _all_menus(node: Node) -> Array:
	var out := []
	if node is SettingsMenu:
		out.append(node)
	for c in node.get_children():
		out.append_array(_all_menus(c))
	return out

## combat_keys: each turn presses the number of every affordable card
## (attacks: Tab once, then Enter), then E.
func _key_turns(turns: int) -> void:
	var cs := get_tree().current_scene
	var cm: CombatManager = cs.combat
	for n in range(turns):
		while not cm.is_game_over() and (not cm.is_player_turn() or UIState.input_locked):
			await get_tree().create_timer(0.2).timeout
		if cm.is_game_over():
			break
		var i := 0
		while i < cs.hand_tray.ordered_cards().size() and cm.is_player_turn():
			var card: CardData = cs.hand_tray.ordered_cards()[i].card
			i += 1
			if not cm.can_play(card) or cm.player_mech.current_heat + cm.effective_cost(card) > cm.player_mech.heat_capacity() or card.protocol() == "reroute":
				continue
			await _key(KEY_1 + i - 1)
			if card.is_attack():
				await _key(KEY_TAB)
				await _key(KEY_ENTER)
			while not cm.is_game_over() and (cm.has_pending_attack() or UIState.input_locked):
				await get_tree().create_timer(0.1).timeout
		await _key(KEY_E)
		await get_tree().create_timer(0.5).timeout
	while not cm.is_game_over() and UIState.input_locked:
		await get_tree().create_timer(0.2).timeout
	print("combat_keys: turn %d, result %d, %d commands: %s" % [cm.turn_number, cm.result, cm.command_log.size(), JSON.stringify(cm.command_log)])

func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	var up := InputEventKey.new()
	up.keycode = code
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().create_timer(0.15).timeout

func _pad(button: JoyButton) -> void:
	for down in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.device = 0
		ev.button_index = button
		ev.pressed = down
		Input.parse_input_event(ev)
		await get_tree().create_timer(0.1).timeout

func _stick(x: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.device = 0
	ev.axis = JOY_AXIS_LEFT_X
	ev.axis_value = x
	Input.parse_input_event(ev)

func _pad_test() -> void:
	var cs := get_tree().current_scene
	var cm: CombatManager = cs.combat
	while not cm.is_player_turn() or UIState.input_locked:
		await get_tree().create_timer(0.2).timeout
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	print("combat_pad: RB -> aiming %s" % (cs._aim_card.name if cs._aim_card != null else (("picked " + cs._pad_card.name) if cs._pad_card != null else "nothing")))
	await _pad(JOY_BUTTON_DPAD_RIGHT)
	await _pad(JOY_BUTTON_A)
	await get_tree().create_timer(2.0).timeout
	print("combat_pad: A -> %d commands: %s" % [cm.command_log.size(), JSON.stringify(cm.command_log)])
	var before := get_viewport().get_mouse_position()
	_stick(1.0)
	await get_tree().create_timer(0.4).timeout
	_stick(0.0)
	await get_tree().create_timer(0.1).timeout
	print("combat_pad: stick right moved the cursor %s -> %s" % [before, get_viewport().get_mouse_position()])
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	await get_tree().create_timer(0.5).timeout


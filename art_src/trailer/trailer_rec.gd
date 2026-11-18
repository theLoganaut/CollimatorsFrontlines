extends SceneTree
## Trailer recorder: drives the game for one trailer shot while Movie Maker records it, and
## writes what happened, frame by frame, so the editor can sync cuts to the music and point
## the camera at the action. Runs beside the game's own tools (Godot -s), changing nothing in them.
## Use art_src/trailer/record.sh rather than calling this directly; it sets the resolution,
## records, encodes and cleans up.
##
## Godot --path . --fixed-fps 60 --write-movie <dir>/frame.png -s art_src/trailer/trailer_rec.gd -- \
##     --mode=<mode> --events=<file.json> [--fps=60] [--seconds=N] [--keep-ui] [positional args]
##
## Modes (positional args go to the game's tool the mode wraps):
##   replay  <fight record.json>   a recorded fight (tools/RenderReplay.tscn); --speed=1.0 --clean
##   screen  <Screenshot.tscn args> any tools/Screenshot.tscn preset, held for --seconds
##                                   (e.g. `map x 99`, `event x 99`, `shop x 99`, `hub_hangar x 99`)
##   refit   [Screenshot args]      the refit swap: a chassis part to the Workbench, a Cargo part into
##                                   the chassis, the first part into Cargo; clicks land on --beat (s)
##   heat    [Screenshot args]      a fight where cards push Heat to the edge, then an overheating play
##   hangar  [Screenshot args]      the Hangar (`hub_hangar x 99`), clicking the mech tabs in --mechs order,
##                                   one every --every beats
##   operator                       the Operator's channel on black, typing --line="..." (--scale, --hold)
##   walls                          the War Room: left wall, middle, right wall, a turn every --beat
##   table                          the War Room zooming into the War Table
##
## Events: {"fps", "size", "frames", "events": [{"frame", "t", "type", ...}]}. Positions are
## "x"/"y" in 0..1 of the frame, so they hold at any resolution. Types: scene, hit, destroyed,
## card, overheat, vent, turn, enemy_turn, game_over, heat (value), pick, drop, pan, zoom, end.
## hit / destroyed are when the rules decide (an enemy turn's all land on one frame); impact / boom
## are when the player SEES them (the floating number, DESTROYED), with "who" it landed on:
## sync cuts and the camera to impact / boom.

var args: PackedStringArray = []
var opts := {}
var fps := 60
var frame := 0
var events: Array = []
var events_path := ""
var scene: Node = null
var _combat_hooked := false
var _last_heat := -1
var _stop_at := -1
var _vr := Vector2(1280, 720)
var _win := Vector2i(1920, 1080)

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.trim_prefix("--").split("=", true, 1)
			opts[kv[0]] = kv[1] if kv.size() > 1 else "true"
		else:
			args.append(a)
	fps = int(opts.get("fps", "60"))
	events_path = opts.get("events", "user://trailer_events.json")
	process_frame.connect(_tick)
	node_added.connect(_on_added)
	var mode: String = opts.get("mode", "screen")
	match mode:
		"replay":
			change_scene_to_file.call_deferred("res://tools/RenderReplay.tscn")
		"screen", "refit", "heat", "hangar":
			change_scene_to_file.call_deferred("res://tools/Screenshot.tscn")
		"walls", "table":
			_war_room.call_deferred(mode)
		"operator":
			_operator_scene.call_deferred()
		_:
			printerr("trailer_rec: unknown mode ", mode)
			quit(1)
	if opts.has("seconds"):
		_stop_at = int(float(opts["seconds"]) * fps)
	elif mode != "replay": # a scripted scene that stalls can't record forever
		_stop_at = 120 * fps

# ---------- every frame ----------

func _tick() -> void:
	frame += 1
	if not opts.has("keep-ui"):
		_hide_dev_ui()
	if scene != null and "combat" in scene and scene.combat != null:
		if not _combat_hooked:
			_hook_combat(scene)
		var h: int = scene.combat.player_mech.current_heat
		if h != _last_heat:
			_last_heat = h
			_event("heat", {"value": h, "max": scene.combat.player_mech.heat_capacity()})
	if _stop_at > 0 and frame >= _stop_at:
		_finish()

## What a Steam viewer shouldn't see: the Feedback buttons, the build label, and in a fight the
## speed / settings / map / log buttons.
func _hide_dev_ui() -> void:
	for n in root.find_children("*", "Button", true, false):
		if n.text == "Feedback":
			n.modulate.a = 0.0
	for n in root.find_children("*", "Label", true, false):
		if str(n.text).contains("Dev build"):
			n.visible = false
	if scene != null and "speed_controls" in scene:
		for prop in ["speed_controls", "settings_button", "map_button", "log_button"]:
			var c = scene.get(prop)
			if c != null and c is CanvasItem:
				c.modulate.a = 0.0
	_vr = root.get_visible_rect().size
	_win = root.size
	# the real mouse parks off to the side so it never hovers anything into the shot
	if opts.get("mode", "") in ["replay", "screen", "walls", "table"]:
		var vr := root.get_visible_rect().size
		root.warp_mouse(Vector2(vr.x - 2, vr.y * 0.5))

func _on_added(n: Node) -> void:
	# what the player sees land: HitFx's floating numbers and DESTROYED, the moment they appear
	if n is Label and n.get_parent() != null and n.get_parent().get_script() != null 			and str(n.get_parent().get_script().resource_path).ends_with("HitFx.gd"):
		_on_fx_label.call_deferred(n)
		return
	# only the game's screens (res://scenes/...), not the tools that open them or popups
	if n.get_parent() != root or not n.scene_file_path.begins_with("res://scenes/"):
		return
	scene = n
	_combat_hooked = false
	_event("scene", {"name": n.scene_file_path.get_file()})
	var mode: String = opts.get("mode", "")
	var path := str(n.get_script().resource_path) if n.get_script() else ""
	if mode == "refit" and path.ends_with("RefitScreen.gd"):
		_refit(n)
	elif mode == "heat" and path.ends_with("CombatScene.gd"):
		_heat(n)
	elif mode == "hangar" and path.ends_with("HangarScreen.gd"):
		_hangar(n)

# ---------- events ----------

func _norm(p: Vector2) -> Dictionary:
	var vr := root.get_visible_rect().size
	return {"x": snappedf(p.x / vr.x, 0.0001), "y": snappedf(p.y / vr.y, 0.0001)}

func _event(type: String, data := {}) -> void:
	var e := {"frame": frame, "t": snappedf(float(frame) / fps, 0.001), "type": type}
	e.merge(data)
	events.append(e)

func _on_fx_label(l: Label) -> void:
	if not is_instance_valid(l):
		return
	var p: Vector2 = l.get_global_rect().get_center()
	var text := str(l.text)
	var d := {"who": _who_at(p)}
	d.merge(_norm(p))
	if text == "DESTROYED":
		_event("boom", d)
	elif text.is_valid_int():
		d["damage"] = int(text)
		_event("impact", d)

## Whose panel a screen point is on: "player", an enemy's name, or "".
func _who_at(p: Vector2) -> String:
	if scene == null or not ("enemy_panels" in scene):
		return ""
	for panel in scene.enemy_panels:
		if panel.get_global_rect().grow(40).has_point(p):
			return str(panel.mech.name)
	if scene.player_panel != null and scene.player_panel.get_global_rect().grow(40).has_point(p):
		return "player"
	return ""

func _part_pos(cs: Node, mech, comp) -> Dictionary:
	if cs.has_method("_grid_for"):
		var g = cs._grid_for(mech)
		if g != null and g.has_method("component_center_global"):
			return _norm(g.component_center_global(comp))
	return {}

func _hook_combat(cs: Node) -> void:
	_combat_hooked = true
	var cm = cs.combat
	var who := func(mech) -> String: return "player" if mech == cm.player_mech else str(mech.name)
	cm.hit_landed.connect(func(mech, comp, dmg):
		var d := {"target": who.call(mech), "part": str(comp.name), "damage": dmg}
		d.merge(_part_pos(cs, mech, comp)); _event("hit", d))
	cm.component_destroyed.connect(func(mech, comp):
		var d := {"target": who.call(mech), "part": str(comp.name)}
		d.merge(_part_pos(cs, mech, comp)); _event("destroyed", d))
	cm.card_played.connect(func(mech, card): _event("card", {"by": who.call(mech), "card": str(card.name)}))
	cm.overheated.connect(func(mech, backlash): _event("overheat", {"by": who.call(mech), "backlash": backlash}))
	cm.mech_vented.connect(func(mech, amount): _event("vent", {"by": who.call(mech), "amount": amount}))
	cm.turn_changed.connect(func(phase, n): _event("turn", {"phase": int(phase), "turn": n}))
	cm.enemy_turn_started.connect(func(): _event("enemy_turn"))
	cm.game_over.connect(func(result): _event("game_over", {"result": int(result)}))

func _finish() -> void:
	_event("end")
	var vr := root.get_visible_rect().size
	var out := {"fps": fps, "size": [int(root.size.x), int(root.size.y)], "viewport": [vr.x, vr.y],
		"frames": frame, "mode": opts.get("mode", ""), "args": Array(args), "events": events}
	var f := FileAccess.open(events_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(out, "  "))
		f.close()
	print("trailer_rec: %d frames, %d events -> %s" % [frame, events.size(), events_path])
	quit()

# RenderReplay quits on its own when the fight ends: write the events on the way out.
func _finalize() -> void:
	if not events.is_empty() and events[-1]["type"] != "end":
		_event("end")
		# the viewport is gone by now: use the size cached on the last frame
		var out := {"fps": fps, "size": [_win.x, _win.y], "viewport": [_vr.x, _vr.y],
			"frames": frame, "mode": opts.get("mode", ""), "args": Array(args), "events": events}
		var f := FileAccess.open(events_path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(out, "  "))
			f.close()
		print("trailer_rec: %d frames, %d events -> %s" % [frame, events.size(), events_path])

# ---------- input helpers (scripted scenes) ----------

var mouse := Vector2.ZERO

func _frames(k: int) -> void:
	for i in k:
		await process_frame

func _beats(b: float) -> int:
	return maxi(1, roundi(b * float(opts.get("beat", "0.5")) * fps))

func _send_move(p: Vector2) -> void:
	mouse = p
	var e := InputEventMouseMotion.new()
	var w := root.get_final_transform() * p
	e.position = w; e.global_position = w
	Input.warp_mouse(w)
	Input.parse_input_event(e)

func _send_button(pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	var w := root.get_final_transform() * mouse
	e.position = w; e.global_position = w
	Input.parse_input_event(e)

func _rotate_key() -> void:
	var gs := root.get_node("GameSettings")
	var e := InputEventKey.new(); e.keycode = gs.key("rotate"); e.pressed = true
	Input.parse_input_event(e)
	await process_frame
	var u := InputEventKey.new(); u.keycode = gs.key("rotate"); u.pressed = false
	Input.parse_input_event(u)

## Moves the mouse to `to` over `k` frames (eased); turns the held part `turns` times on the way.
func _glide(to: Vector2, k: int, turns := 0) -> void:
	var from := mouse
	var turn_every := maxi(2, k / (turns + 2)) if turns > 0 else 0
	for i in range(1, k + 1):
		var t := float(i) / k
		t = t * t * (3.0 - 2.0 * t)
		_send_move(from.lerp(to, t))
		if i % 2 == 0:
			_event("mouse", _norm(mouse))
		if turns > 0 and i >= k / 3 and i % turn_every == 0:
			turns -= 1
			await _rotate_key()
		else:
			await process_frame

# ---------- refit ----------

func _cell_at(g, cell: Vector2i) -> Vector2:
	return g.get_screen_transform() * (g.cell_pos(cell) + Vector2.ONE * g.cell_size / 2.0)

func _fit(run, p, where: String) -> Dictionary:
	for k in 4:
		var s: int = (p.rotation_steps + k) % 4
		for y in range(-4, 10):
			for x in range(-4, 10):
				if run.can_move(p, where, s, Vector2i(x, y)):
					return {"steps": s, "off": Vector2i(x, y)}
	return {}

## Picks `p` up on a beat and puts it down two beats later, the way a player would.
func _carry(p, g_from, g_to, steps: int, off: Vector2i) -> void:
	await _glide(_cell_at(g_from, p.placed_cells[0]), _beats(1))
	_send_button(true); await _frames(2); _send_button(false)
	_event("pick", {"part": str(p.name)}.merged(_norm(mouse)))
	await _frames(2)
	var turns: int = (steps - p.rotation_steps + 4) % 4
	var rel: Vector2i = GridUtils.rotate_cells(p.cells, steps)[0]
	await _glide(_cell_at(g_to, off + rel), _beats(2) - 4, turns)
	_send_button(true); await _frames(2); _send_button(false)
	_event("drop", {"part": str(p.name)}.merged(_norm(mouse)))
	await _frames(_beats(1) - 2)

func _refit(ws: Node) -> void:
	await _frames(int(fps * 0.75))
	var g := {}
	for grid in ws._grids.keys():
		g[ws._grids[grid]] = grid
	var run = ws.run
	var plan := {}
	for p in run.player_mech.components.duplicate():
		if not plan.is_empty() or str(p.name).contains("Core"):
			continue
		var home := {"steps": p.rotation_steps, "off": p.offset}
		var bench := _fit(run, p, RunData.BENCH)
		run.move_part(p, RunData.BENCH, bench["steps"], bench["off"])
		for c in run.cargo.items.duplicate():
			if not plan.is_empty():
				continue
			var c_home := {"steps": c.rotation_steps, "off": c.offset}
			var into_mech := _fit(run, c, RunData.MECH)
			if into_mech.is_empty():
				continue
			run.move_part(c, RunData.MECH, into_mech["steps"], into_mech["off"])
			var into_cargo := _fit(run, p, RunData.CARGO)
			run.move_part(c, RunData.CARGO, c_home["steps"], c_home["off"])
			if not into_cargo.is_empty():
				plan = {"p": p, "c": c, "bench": bench, "mech": into_mech, "cargo": into_cargo}
		run.move_part(p, RunData.MECH, home["steps"], home["off"])
	ws._refresh()
	if plan.is_empty():
		printerr("trailer_rec: no refit swap found"); _finish(); return
	_send_move(Vector2(root.get_visible_rect().size.x * 0.5, root.get_visible_rect().size.y * 0.7))
	await _frames(_beats(2))
	_event("start")
	await _carry(plan["p"], g[RunData.MECH], g[RunData.BENCH], plan["bench"]["steps"], plan["bench"]["off"])
	await _carry(plan["c"], g[RunData.CARGO], g[RunData.MECH], plan["mech"]["steps"], plan["mech"]["off"])
	await _carry(plan["p"], g[RunData.BENCH], g[RunData.CARGO], plan["cargo"]["steps"], plan["cargo"]["off"])
	await _frames(_beats(4))
	_finish()

# ---------- heat ----------

func _heat(cs: Node) -> void:
	while cs.combat == null:
		await process_frame
	var cm = cs.combat
	while not cm.is_player_turn() or root.get_node("UIState").input_locked:
		await process_frame
	await _frames(_beats(2))
	_event("start")
	# keep one playable attack back for the overheat: the costliest
	var over = null
	for card in cm.hand_cards():
		if card.is_attack() and cm.can_play(card) and (over == null or cm.effective_cost(card) > cm.effective_cost(over)):
			over = card
	# play the rest of what's affordable, a beat apart, so the Heat counter climbs
	for card in cm.hand_cards():
		if card == over or not cm.is_player_turn() or cm.is_game_over():
			continue
		if not cm.can_play(card) or card.protocol() == "reroute":
			continue
		if cm.player_mech.current_heat + cm.effective_cost(card) > cm.player_mech.heat_capacity():
			continue
		var point := Vector2.ZERO
		if card.is_attack():
			var e = cm.living_enemies()[0]
			point = cs._grid_for(e).component_center_global(e.non_destroyed_components()[0])
		cs._handle_card_drop(card, point, 999.0)
		while not cm.is_game_over() and (cm.has_pending_attack() or root.get_node("UIState").input_locked):
			await process_frame
		await _frames(_beats(1))
	# then the edge: the kept attack costs more than the Heat left; hover it, then play it
	if over != null:
		cm.player_mech.current_heat = maxi(cm.player_mech.current_heat, cm.player_mech.heat_capacity() - cm.effective_cost(over) + 1)
		cs.player_panel.refresh()
		var ui = cs.hand_tray.card_ui_for(over)
		if ui != null:
			ui._on_mouse_entered()
		await _frames(_beats(3))
		var e = cm.living_enemies()[0]
		cs._handle_card_drop(over, cs._grid_for(e).component_center_global(e.non_destroyed_components()[0]), 999.0)
		_event("overheat_play")
		while not cm.is_game_over() and (cm.has_pending_attack() or root.get_node("UIState").input_locked):
			await process_frame
	await _frames(_beats(6))
	_finish()

# ---------- Hangar ----------

## Clicks the mech tabs light to heavy (--mechs=redline,jackal,bastion), one every --every beats
## (default 4, a bar at 120 bpm), the way a player picks a mech. Logs a "pick" per click with "mech".
func _hangar(hs: Node) -> void:
	await _frames(int(fps * 0.75))
	var order: PackedStringArray = str(opts.get("mechs", "redline,jackal,bastion")).split(",")
	var every := float(opts.get("every", "4"))
	var player_mechs: Array = root.get_node("GameData").PLAYER_MECHS
	var tab_at := func(id: String) -> Vector2:
		var b: Control = hs._tabs.get_child(player_mechs.find(id))
		return b.get_global_rect().get_center()
	_send_move(Vector2(root.get_visible_rect().size.x * 0.45, root.get_visible_rect().size.y * 0.55))
	await _frames(_beats(1))
	_event("start")
	for id in order:
		await _glide(tab_at.call(id), _beats(1))
		_send_button(true); await _frames(2); _send_button(false)
		_event("pick", {"mech": id}.merged(_norm(mouse)))
		# drift off the tabs so the hover highlight doesn't sit on the button
		await _glide(mouse + Vector2(40, 90), _beats(1))
		await _frames(maxi(1, _beats(every - 2)))
	await _frames(_beats(2))
	_finish()

# ---------- the Operator ----------

## UIKit.label's look (UIKit itself can't compile from a -s script: it names an autoload).
func _label(text: String, font_size: int, color: Color, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## The Operator's channel as the War Room shows it (WarRoomScreen._build_operator: his portrait,
## "OPERATOR · SECURE CHANNEL", the line coming in a few letters at a time), on black, centred
## and --scale times bigger, with no Continue button. The line is --line="...".
func _operator_scene() -> void:
	var stage := Control.new()
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(stage)
	current_scene = stage
	scene = stage
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.add_child(bg)
	_event("scene", {"name": "Operator"})
	await _frames(int(fps * 0.5))
	var r := Vector2(640, 104)
	var k := float(opts.get("scale", "1.3"))
	var panel := GlassPanel.new()
	panel.size = r
	panel.scale = Vector2(k, k)
	var vr := root.get_visible_rect().size
	panel.position = ((vr - r * k) / 2.0).floor()
	stage.add_child(panel)
	var face := OperatorPortrait.new()
	face.position = Vector2(10, 10)
	face.size = Vector2(76, r.y - 20)
	panel.add_child(face)
	var who := _label("OPERATOR  ·  SECURE CHANNEL", 10, Color("b9d8d4"))
	who.position = Vector2(100, 10)
	panel.add_child(who)
	var line := _label(str(opts.get("line", "...")), 14, Color("eefcfa"), true)
	line.position = Vector2(100, 30)
	line.size = Vector2(r.x - 100 - 16, r.y - 40)
	line.visible_ratio = 0.0
	panel.add_child(line)
	_event("start", _norm(panel.position + r * k / 2.0))
	# the same pace as the War Room: a short pause, then about 45 letters a second
	face.talking = true
	await _frames(int(fps * 0.35))
	var n: int = line.text.length()
	var k_frames := int(fps * clampf(n / 45.0, 0.6, 2.6))
	for i in range(1, k_frames + 1):
		line.visible_ratio = float(i) / k_frames
		await process_frame
	face.talking = false
	_event("line_done")
	await _frames(int(fps * float(opts.get("hold", "2.5"))))
	_finish()

# ---------- War Room ----------

func _war_room(mode: String) -> void:
	var wv: Node = load(root.get_node("SceneRouter").WAR_ROOM).instantiate()
	root.add_child(wv)
	current_scene = wv
	scene = wv
	_event("scene", {"name": "WarRoom"})
	await _frames(int(fps * 1.5))
	var tut := root.get_node("Tutorial")
	if not tut.active:
		tut._root.visible = false
	wv._operator.visible = false
	if mode == "walls": # left wall, then the middle, then the right wall, a turn every two beats
		wv._pan_to(-1, true)
		await _frames(_beats(2))
		_event("start")
		for v in [0, 1]:
			wv._pan_to(v)
			_event("pan", {"view": v})
			await _frames(_beats(4))
	else: # the War Table zoom
		await _frames(_beats(2))
		_event("start")
		wv._zoom_in()
		_event("zoom")
		await _frames(_beats(8))
	_finish()

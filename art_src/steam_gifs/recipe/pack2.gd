extends SceneTree
# Packing GIF: on the refit screen, (1) a mech part goes to the Workbench, (2) a Cargo part
# goes into the mech, (3) the Workbench part goes into Cargo. Logs each frame's mouse in
# window pixels (what the movie frames are) to --log=<file>.
var frame := 0
var mouse := Vector2(640, 500)
var down := false
var log_lines: PackedStringArray = []
var log_path := ""

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--log="):
			log_path = a.get_slice("=", 1)
	process_frame.connect(func():
		frame += 1
		log_lines.append("%d %d %d %d" % [frame, mouse.x, mouse.y, 1 if down else 0]))
	node_added.connect(_on_added)
	change_scene_to_file.call_deferred("res://tools/Screenshot.tscn")

func _on_added(n: Node) -> void:
	if n.get_script() and str(n.get_script().resource_path).ends_with("RefitScreen.gd"):
		_run(n)

func _frames(k: int) -> void:
	for i in k:
		await process_frame

func _send_move(p: Vector2) -> void:
	mouse = p
	var e := InputEventMouseMotion.new()
	var w := root.get_final_transform() * p
	e.position = w; e.global_position = w
	Input.warp_mouse(w)
	Input.parse_input_event(e)

func _send_button(pressed: bool) -> void:
	down = pressed
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	var w := root.get_final_transform() * mouse
	e.position = w; e.global_position = w
	Input.parse_input_event(e)

func _rotate() -> void:
	var gs := root.get_node("GameSettings")
	var e := InputEventKey.new(); e.keycode = gs.key("rotate"); e.pressed = true
	Input.parse_input_event(e)
	await process_frame
	var u := InputEventKey.new(); u.keycode = gs.key("rotate"); u.pressed = false
	Input.parse_input_event(u)

func _glide(to: Vector2, k: int, rotations := 0) -> void:
	var from := mouse
	for i in range(1, k + 1):
		var t := float(i) / k
		t = t * t * (3.0 - 2.0 * t)
		_send_move(from.lerp(to, t))
		if rotations > 0 and i >= k / 2 and i % 6 == 0:
			rotations -= 1
			await _rotate()
		else:
			await process_frame

func _at(g, cell: Vector2i) -> Vector2:
	return g.get_screen_transform() * (g.cell_pos(cell) + Vector2.ONE * g.cell_size / 2.0)

## {steps, off} where `p` fits in `where` now (its own turn first), or {}.
func _fit(run: RunData, p: ComponentData, where: String) -> Dictionary:
	for k in 4:
		var s: int = (p.rotation_steps + k) % 4
		for y in range(-4, 10):
			for x in range(-4, 10):
				if run.can_move(p, where, s, Vector2i(x, y)):
					return {"steps": s, "off": Vector2i(x, y)}
	return {}

## Carries `p` from grid `g_from` to (steps, off) in grid `g_to`, the way a player would.
func _carry(p: ComponentData, g_from, g_to, steps: int, off: Vector2i) -> void:
	await _glide(_at(g_from, p.placed_cells[0]), 26)
	await _frames(8)
	_send_button(true); await _frames(3); _send_button(false); await _frames(6)
	var turns: int = (steps - p.rotation_steps + 4) % 4
	var rel: Vector2i = GridUtils.rotate_cells(p.cells, steps)[0]
	await _glide(_at(g_to, off + rel), 44, turns)
	await _frames(10)
	_send_button(true); await _frames(3); _send_button(false)
	await _frames(22)

func _run(ws: Node) -> void:
	await _frames(45)
	var g := {}
	for grid in ws._grids.keys():
		g[ws._grids[grid]] = grid
	var run: RunData = ws.run
	var plan := {}
	for p in run.player_mech.components.duplicate():
		if not plan.is_empty() or str(p.name).contains("Core"):
			continue
		var p_home := {"steps": p.rotation_steps, "off": p.offset}
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
		run.move_part(p, RunData.MECH, p_home["steps"], p_home["off"])
	ws._refresh()
	if plan.is_empty():
		print("no swap found"); quit(); return
	print("plan: %s -> bench, %s -> mech %s, %s -> cargo %s" % [plan["p"].name, plan["c"].name, plan["mech"], plan["p"].name, plan["cargo"]])
	await _frames(15)
	var film_start := frame
	await _frames(20)
	await _carry(plan["p"], g[RunData.MECH], g[RunData.BENCH], plan["bench"]["steps"], plan["bench"]["off"])
	await _carry(plan["c"], g[RunData.CARGO], g[RunData.MECH], plan["mech"]["steps"], plan["mech"]["off"])
	await _carry(plan["p"], g[RunData.BENCH], g[RunData.CARGO], plan["cargo"]["steps"], plan["cargo"]["off"])
	await _glide(Vector2(640, 520), 24)
	await _frames(40)
	print("in mech: %s, in cargo: %s" % [run.player_mech.components.has(plan["c"]), run.cargo.items.has(plan["p"])])
	print("film %d %d" % [film_start, frame])
	var f := FileAccess.open(log_path, FileAccess.WRITE)
	f.store_string("film %d %d\n" % [film_start, frame] + "\n".join(log_lines))
	f.close()
	quit()

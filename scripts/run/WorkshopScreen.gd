class_name WorkshopScreen
extends RunScreen
## Base for the run's two workshop stops, the Refit and the Autonomous Bay,
## laid out like the Hangar: a pixel-art bay behind (`bay_art()`, 624×390
## drawn ×ART_SCALE), the mech as a hologram on its pad, and holo glass
## screens. Left: the screen's own panel (`_build_left`). Top centre: the
## part preview. Right: Cargo and the 6×6 workbench (RunData.bench), where
## parts can be laid out to mix and match; whatever is left on the bench
## when leaving is scrapped for scraps (RunData.scrap_bench). Bottom centre:
## messages and the leave button.
##
## Grab a part on any grid and drop it on another (R / right-click rotates
## while dragging); RunData.move_part says where it may go (the chassis only
## at a refit). Dropping anywhere else puts it back. Undo (the footer button,
## Ctrl/Cmd+Z) steps moves back one at a time, while the part is still
## where that move left it (buying, selling or scrapping it ends that).

const BASE := Vector2(1152, 720)
const ART_SCALE := 1152.0 / 624.0
const HOLO_H := 250.0
const LEFT := Rect2(12, 57, 330, 651)
const PREVIEW := Rect2(354, 57, 444, 212)
const FOOTER := Rect2(354, 616, 444, 92)
const RIGHT := Rect2(810, 57, 330, 651)
const BENCH_CELL := 42.0
const CARGO_MAX := Vector2(306, 196) # the Cargo grid shrinks its cells to fit
const CARGO_CELL := 40.0

var _stage: Control
var _bay: Texture2D
var _holo: TextureRect
var _left: GlassPanel
var _right: GlassPanel
var _preview: PartPreview
var _cargo_title: Label
var _cargo_grid: PackingGrid
var _bench_title: Label
var _bench_grid: PackingGrid
var _bench_note: Label
var _message: Label
var _leave: Button
var _undo: Button
## Moves that can be undone, newest last: {part, from, steps, offset, to}.
var _undo_stack: Array = []
var _grids: Dictionary = {} # PackingGrid -> RunData.MECH / CARGO / BENCH

## Parts not drawn yet (a swap animation is bringing them in), and whether
## one is playing (no dragging or leaving meanwhile).
var _hidden_parts: Array[ComponentData] = []
var _busy: bool = false

var _drag: ComponentData = null
var _drag_from: PackingGrid = null
var _drag_steps: int = 0
var _drag_rel := Vector2i.ZERO
var _mouse := Vector2.ZERO

## The bay's pixel art (res:// path).
func bay_art() -> String:
	return ""

## The projector pad's centre in the bay art's pixels (the hologram stands on it).
func pad_center() -> Vector2:
	return Vector2(312, 318)

## Whether the right panel holds Cargo and the workbench (else the screen
## fills `_right` itself in `_build_right_panel`).
func has_bench() -> bool:
	return true

func _build_right_panel() -> void:
	pass

## The leave button's text (without the scrap note).
func leave_text() -> String:
	return "Done"

func _build_left() -> void:
	pass

## Called after any change to the run's parts or scraps.
func _refresh_extra() -> void:
	pass

## Whether the leave button is usable (a refit needs a working hardpoint).
func _can_leave() -> bool:
	return true

func _on_leave() -> void:
	pass

## What leaving now would lose, in words (the leave button asks once when
## there's any): parts on the workbench or outside the opening refit's
## Cargo, scrapped. Screens add their own (unspent scraps, unused repairs).
func leave_warnings() -> Array[String]:
	var out: Array[String] = []
	if has_bench():
		var n := run.leave_scrap_count()
		if n > 0:
			out.append("%d part%s left out will be scrapped for %d scraps" % [n, "" if n == 1 else "s", run.leave_scrap_value()])
	return out

var _leave_armed: bool = false
var _leave_modal: Control = null

## The leave button's first press opens a pop-up listing leave_warnings()
## (and each part that would be scrapped, with its scraps) and returns
## false; "Leave anyway" there leaves (calls _on_leave again, armed).
func _confirm_leave() -> bool:
	if _leave_armed:
		return true
	var w := leave_warnings()
	if w.is_empty():
		return true
	_open_leave_modal(w)
	return false

func _open_leave_modal(warnings: Array[String]) -> void:
	_close_leave_modal()
	Audio.play("overheat_warn", 0.0, -8.0)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.z_index = 300
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_leave_modal = dim
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", GlassPanel.panel_style(Palette.WARNING, 18.0))
	box.custom_minimum_size = Vector2(440, 0)
	center.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	box.add_child(v)
	v.add_child(UIKit.label("Leave %s?" % screen_title().to_lower(), 20, Palette.WARNING))
	for w in warnings:
		v.add_child(UIKit.label("• " + w[0].to_upper() + w.substr(1) + ".", 14, Palette.TEXT, true))
	var parts: Array[ComponentData] = RunParts.leave_scrap_parts(run) if has_bench() else []
	if not parts.is_empty():
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 2)
		for i in range(mini(parts.size(), 8)):
			var row := HBoxContainer.new()
			var name_l := UIKit.label(parts[i].name, 13, Palette.category_color(parts[i].category))
			name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name_l)
			row.add_child(UIKit.label("+%d scraps" % Economy.scrap_value(parts[i]), 13, Palette.SCRAPS))
			list.add_child(row)
		if parts.size() > 8:
			list.add_child(UIKit.label("…and %d more" % (parts.size() - 8), 12, Palette.TEXT_MUTED))
		v.add_child(list)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	v.add_child(buttons)
	var stay := GlassPanel.button("Stay", 14)
	stay.custom_minimum_size = Vector2(0, 40)
	stay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stay.pressed.connect(func():
		Audio.play("ui")
		_close_leave_modal())
	buttons.add_child(stay)
	var go := GlassPanel.button("%s anyway" % leave_text(), 14, true, Palette.HARDPOINT)
	go.custom_minimum_size = Vector2(0, 40)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.pressed.connect(func():
		_close_leave_modal()
		_leave_armed = true
		_on_leave()
		_leave_armed = false)
	buttons.add_child(go)

func _close_leave_modal() -> void:
	if _leave_modal != null and is_instance_valid(_leave_modal):
		_leave_modal.queue_free()
	_leave_modal = null

## Esc closes the leave pop-up (Stay); Ctrl/Cmd+Z undoes a move.
func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	if _leave_modal != null and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close_leave_modal()
	elif _leave_modal == null and GameSettings.is_key(event, "undo") and (event.ctrl_pressed or event.meta_pressed):
		get_viewport().set_input_as_handled()
		_undo_move()

## After everything is built and filled in (first message, etc.).
func _after_build() -> void:
	_say("Hover a part to inspect it.")

func _build() -> void:
	_bay = load(bay_art()) if bay_art() != "" and ResourceLoader.exists(bay_art()) else null
	_stage = Control.new()
	_stage.size = BASE
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_stage.draw.connect(_draw_stage)
	add_child(_stage)
	move_child(_stage, 0) # under the top bar
	_holo = TextureRect.new()
	_holo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_holo.stretch_mode = TextureRect.STRETCH_SCALE
	_holo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holo.material = MechArt.hologram_material(0.9, 0.55)
	_stage.add_child(_holo)
	_place_hologram(MechArt.player_front(run.player_mech.id))

	_left = _panel(LEFT)
	_build_left()
	_preview = PartPreview.new()
	_preview.hint_text = "Hover a part on a grid to inspect it."
	_preview.position = PREVIEW.position
	_preview.size = PREVIEW.size
	_stage.add_child(_preview)
	if has_bench():
		_build_right()
	else:
		_right = _panel(RIGHT)
		_build_right_panel()
	var footer := _panel(FOOTER)
	_message = UIKit.label("", 12, Color("b9d8d4"), true)
	_message.position = Vector2(14, 10)
	_message.size = Vector2(FOOTER.size.x - 28, 34)
	footer.add_child(_message)
	_undo = GlassPanel.button("Undo", 13)
	_undo.size = Vector2(80, 36)
	_undo.position = Vector2(14, FOOTER.size.y - 46)
	_undo.tooltip_text = "Put the last part you moved back (Ctrl/Cmd+%s)." % GameSettings.key_label("undo")
	_undo.pressed.connect(_undo_move)
	footer.add_child(_undo)
	_leave = GlassPanel.button(leave_text(), 14, true, Palette.HARDPOINT)
	_leave.size = Vector2(FOOTER.size.x - 28 - 88, 36)
	_leave.position = Vector2(14 + 88, FOOTER.size.y - 46)
	_leave.pressed.connect(_on_leave)
	footer.add_child(_leave)
	_refresh()
	_after_build()

func _panel(r: Rect2) -> GlassPanel:
	var p := GlassPanel.new()
	p.position = r.position
	p.size = r.size
	_stage.add_child(p)
	return p

func _draw_stage() -> void:
	if _bay != null:
		_stage.draw_texture_rect(_bay, Rect2(Vector2.ZERO, BASE), false)
	else:
		_stage.draw_rect(Rect2(Vector2.ZERO, BASE), Palette.BG, true)
	# a soft shade so the glass reads over the art
	_stage.draw_rect(Rect2(Vector2.ZERO, BASE), Color(0, 0.02, 0.03, 0.25), true)

func _place_hologram(tex: Texture2D) -> void:
	_holo.visible = tex != null
	if tex == null:
		return
	var used := tex.get_image().get_used_rect()
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(used)
	_holo.texture = atlas
	var w := HOLO_H * used.size.x / used.size.y
	var feet := pad_center() * ART_SCALE
	_holo.size = Vector2(w, HOLO_H)
	_holo.position = Vector2(feet.x - w / 2.0, feet.y - HOLO_H)

func _build_right() -> void:
	_right = _panel(RIGHT)
	_cargo_title = UIKit.label("", 11, Color("b9d8d4"))
	_cargo_title.position = Vector2(12, 10)
	_right.add_child(_cargo_title)
	_cargo_grid = _add_grid(_right, RunData.CARGO)
	_bench_title = UIKit.label("WORKBENCH  ·  6×6", 11, Color("b9d8d4"))
	_right.add_child(_bench_title)
	_bench_grid = _add_grid(_right, RunData.BENCH)
	var cells := {}
	for r in range(RunData.BENCH_SIZE):
		for c in range(RunData.BENCH_SIZE):
			cells[Vector2i(r, c)] = true
	_bench_grid.setup(cells, Vector2i(RunData.BENCH_SIZE, RunData.BENCH_SIZE), BENCH_CELL)
	_bench_note = UIKit.label("", 11, Color("9fb9b6"), true)
	_bench_note.size = Vector2(RIGHT.size.x - 24, 40)
	_right.add_child(_bench_note)

func _add_grid(parent: Control, where: String) -> PackingGrid:
	var g := PackingGrid.new()
	g.part_pressed.connect(_on_part_pressed)
	g.part_hovered.connect(_on_part_hovered)
	parent.add_child(g)
	_grids[g] = where
	return g

func _layout(screen: Vector2) -> void:
	if _stage == null:
		return
	_stage.position = ((screen - BASE) / 2.0).floor()
	_stage.position.y = maxf(0.0, _stage.position.y)

## Rebuilds every grid from the run.
func _refresh() -> void:
	if not has_bench():
		_refresh_extra()
		_leave_armed = false
		_undo.disabled = _undoable().is_empty()
		_leave.disabled = not _can_leave()
		_leave.text = leave_text()
		refresh_header()
		return
	var cg := run.cargo
	var cell := minf(CARGO_CELL, minf((CARGO_MAX.x + PackingGrid.GAP) / cg.cols, (CARGO_MAX.y + PackingGrid.GAP) / cg.rows) - PackingGrid.GAP)
	_cargo_grid.setup(cg.cells(), Vector2i(cg.rows, cg.cols), floorf(cell))
	_cargo_grid.set_parts(_shown(cg.items))
	var real := run.opening_cargo_size()
	var temp := {}
	if real != Vector2i.ZERO:
		for c in cg.cells():
			if c.x >= real.x or c.y >= real.y:
				temp[c] = true
	_cargo_grid.temp_cells = temp
	_cargo_title.text = "CARGO  ·  %d×%d  ·  carried through the mission" % [cg.rows, cg.cols] if real == Vector2i.ZERO \
		else "CARGO  ·  %d×%d FOR THIS REFIT  ·  amber is scrapped" % [cg.rows, cg.cols]
	_cargo_grid.position = Vector2(floorf((RIGHT.size.x - _cargo_grid.size.x) / 2.0), 32)
	var bench_top := 32.0 + CARGO_MAX.y + 22.0
	_bench_title.position = Vector2(12, bench_top)
	_bench_grid.position = Vector2(floorf((RIGHT.size.x - _bench_grid.size.x) / 2.0), bench_top + 22.0)
	_bench_grid.set_parts(_shown(run.bench.items))
	_bench_note.position = Vector2(12, _bench_grid.position.y + _bench_grid.size.y + 8.0)
	var n := run.bench.items.size()
	_bench_note.text = "Lay parts out here to mix and match. Anything left on it when you leave is scrapped." if n == 0 \
		else "Left here when you leave: %d part%s, scrapped for %d scraps." % [n, "" if n == 1 else "s", run.bench_value()]
	_bench_note.add_theme_color_override("font_color", Color("9fb9b6") if n == 0 else Palette.SCRAPS)
	_refresh_extra()
	_leave.disabled = not _can_leave() or _busy
	_leave_armed = false # something changed: ask again
	_undo.disabled = _undoable().is_empty()
	var leaving := run.leave_scrap_count()
	_leave.text = leave_text() + ("" if leaving == 0 else "  ·  scrap %d for +%d" % [leaving, run.leave_scrap_value()])
	refresh_header()

func _shown(parts: Array[ComponentData]) -> Array[ComponentData]:
	if _hidden_parts.is_empty():
		return parts
	return parts.filter(func(c): return not _hidden_parts.has(c))

func _say(text: String, c: Color = Color("b9d8d4")) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", c)

func _on_part_hovered(_g: PackingGrid, part: ComponentData) -> void:
	if _drag == null and part != null:
		_preview.show_part(part)

# ---------- dragging ----------

func _on_part_pressed(g: PackingGrid, part: ComponentData, cell: Vector2i) -> void:
	if _drag != null or part.destroyed or _busy:
		return
	if not (run.can_rearrange(RunData.CARGO) or run.can_rearrange(RunData.MECH)):
		return
	if _grids[g] == RunData.MECH and not run.can_rearrange(RunData.MECH):
		return
	_drag = part
	_drag_from = g
	_drag_steps = part.rotation_steps
	_drag_rel = cell - part.offset
	g.dim_part = part
	g.queue_redraw()
	_preview.show_part(part)
	_update_hints()

## Lights every square the dragged part could land on, in each grid, as
## it's turned now (RunData.can_move over every offset).
func _update_hints() -> void:
	for g in _grids.keys():
		var cells := {}
		if _drag != null:
			var where: String = _grids[g]
			var span := maxi((g as PackingGrid).bounds.x, (g as PackingGrid).bounds.y) + 4
			for ox in range(-4, span):
				for oy in range(-4, span):
					var off := Vector2i(ox, oy)
					if run.can_move(_drag, where, _drag_steps, off):
						for c in GridUtils.place_cells(_drag.cells, _drag_steps, off):
							cells[c] = true
		(g as PackingGrid).set_hints(cells)

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse = event.position
	if _drag == null:
		return
	if (event is InputEventKey and event.pressed and not event.echo and GameSettings.is_key(event, "rotate")) \
			or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
		get_viewport().set_input_as_handled()
		_drag_steps = (_drag_steps + 1) % 4
		_drag_rel = GridUtils.rotate_cells(_drag.cells, _drag_steps)[0]
		_update_hints()
		_update_ghost()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_end_drag()
	elif event is InputEventMouseMotion:
		_update_ghost()
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		_drop()

## {grid, offset} under the mouse, or {}.
func _target() -> Dictionary:
	for g in _grids.keys():
		if (g as PackingGrid).is_visible_in_tree() and g.contains_global(_mouse):
			return {"grid": g, "offset": g.cell_at_global(_mouse) - _drag_rel}
	return {}

func _update_ghost() -> void:
	for g in _grids.keys():
		g.clear_ghost()
	var t := _target()
	if t.is_empty():
		return
	(t["grid"] as PackingGrid).set_ghost(GridUtils.place_cells(_drag.cells, _drag_steps, t["offset"]),
		run.can_move(_drag, _grids[t["grid"]], _drag_steps, t["offset"]))

func _drop() -> void:
	var t := _target()
	if not t.is_empty():
		var where: String = _grids[t["grid"]]
		var from := {"part": _drag, "from": _grids[_drag_from], "steps": _drag.rotation_steps, "offset": _drag.offset, "to": where}
		if run.move_part(_drag, where, _drag_steps, t["offset"]):
			if from["from"] != where or from["steps"] != _drag_steps or from["offset"] != t["offset"]:
				_undo_stack.append(from)
			match where:
				RunData.MECH: _say("%s installed." % _drag.name)
				RunData.CARGO: _say("%s stowed in Cargo." % _drag.name)
				RunData.BENCH: _say("%s set on the workbench (worth %d scraps if left there)." % [_drag.name, Economy.scrap_value(_drag)])
		elif where == RunData.MECH and not run.can_rearrange(RunData.MECH):
			_say("The chassis can only be changed at a refit.", Palette.WARNING)
		elif where == RunData.MECH and not run.fits_class(_drag):
			var wc := ComponentLibrary.weight_class_of(_drag.library_id).capitalize()
			_say("%s is a %s part: it only fits a %s chassis." % [_drag.name, wc, wc], Palette.WARNING)
		else:
			_say("It doesn't fit there.", Palette.WARNING)
	_end_drag()

## Where a part is now: RunData.MECH / CARGO / BENCH, or "" if it's gone.
func _where(part: ComponentData) -> String:
	if run.player_mech.components.has(part):
		return RunData.MECH
	if run.cargo.items.has(part):
		return RunData.CARGO
	if run.bench.items.has(part):
		return RunData.BENCH
	return ""

## The newest move that can still be undone (its part where it left it),
## dropping any that can't.
func _undoable() -> Dictionary:
	while not _undo_stack.is_empty():
		var m: Dictionary = _undo_stack[-1]
		if _where(m["part"]) == m["to"] and run.can_move(m["part"], m["from"], m["steps"], m["offset"]):
			return m
		_undo_stack.pop_back()
	return {}

func _undo_move() -> void:
	if _drag != null or _busy:
		return
	var m := _undoable()
	if m.is_empty():
		_say("Nothing to undo.", Palette.TEXT_MUTED)
		return
	_undo_stack.pop_back()
	run.move_part(m["part"], m["from"], m["steps"], m["offset"])
	Audio.play("ui")
	_say("Undone: %s is back where it was." % m["part"].name)
	_refresh()

func _end_drag() -> void:
	for g in _grids.keys():
		g.dim_part = null
		g.clear_ghost()
		g.set_hints({})
	_drag = null
	_drag_from = null
	_refresh()

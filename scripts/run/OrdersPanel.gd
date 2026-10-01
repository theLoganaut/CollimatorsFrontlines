class_name OrdersPanel
extends Control
## The Operator's deployment orders (DeploymentOrders), on a glass comm
## panel over the location map right after Launch (Logan, 2026-09-29): three
## offers, one to take, never labelled boost / tradeoff / gamble. Then any
## step the order needs: pick a category and a part, place frame squares on
## the chassis, or choose a component to strip out or transmute. "Hide"
## drops the panel to a tab so the map can be looked over (the map's stops
## wait until the orders are done); the tab or a click on a stop brings it
## back. Once done, the Operator signs off and the run moves on.

signal done()

const W := 760.0
const CARD := Vector2(230, 150)
const GRID_CELL := 32.0

var run: RunData
var _dim: ColorRect
var _box: PanelContainer
var _face: OperatorPortrait
var _line: Label
var _body: VBoxContainer
var _message: Label
var _hide_btn: Button
var _tab: Button
var _talk: Tween
var _notes: Array[String] = []
var _hover_label: Label

func setup(p_run: RunData) -> void:
	run = p_run
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.45)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)
	_box = PanelContainer.new()
	_box.add_theme_stylebox_override("panel", GlassPanel.panel_style(GlassPanel.HOLO, 16.0))
	_box.draw.connect(func(): GlassPanel.draw_frame(_box, Rect2(Vector2.ZERO, _box.size)))
	_box.resized.connect(_place)
	add_child(_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.custom_minimum_size = Vector2(W, 0)
	_box.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	v.add_child(head)
	_face = OperatorPortrait.new()
	_face.custom_minimum_size = Vector2(72, 92)
	_face.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(_face)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 8)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	hv.add_child(UIKit.label("OPERATOR  ·  DEPLOYMENT ORDERS", 10, Color("b9d8d4")))
	_line = UIKit.label("", 15, Color("eefcfa"), true)
	hv.add_child(_line)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	v.add_child(_body)
	_message = UIKit.label("", 12, Palette.WARNING, true)
	v.add_child(_message)
	var foot := HBoxContainer.new()
	v.add_child(foot)
	foot.add_child(UIKit.spacer())
	_hide_btn = GlassPanel.button("Hide  ·  look at the map", 12)
	_hide_btn.custom_minimum_size = Vector2(190, 32)
	_hide_btn.pressed.connect(hide_panel)
	foot.add_child(_hide_btn)
	_tab = GlassPanel.button("Deployment orders  ·  show", 13, true, Palette.LINK)
	_tab.custom_minimum_size = Vector2(240, 36)
	_tab.pressed.connect(show_panel)
	_tab.visible = false
	add_child(_tab)
	get_viewport().size_changed.connect(_place)
	_refresh()

func is_open() -> bool:
	return _box.visible

func hide_panel() -> void:
	_box.visible = false
	_dim.visible = false
	_tab.visible = true
	_place()

func show_panel() -> void:
	_box.visible = true
	_dim.visible = true
	_tab.visible = false
	Audio.play("holo", 0.04, -6.0)
	_place()

func _place() -> void:
	if _tab == null: # still being built
		return
	var screen := get_viewport_rect().size
	_box.reset_size()
	_box.position = ((screen - _box.size) / 2.0 + Vector2(0, 16)).floor()
	_box.position.y = maxf(56.0, _box.position.y)
	_tab.position = Vector2(floorf((screen.x - _tab.custom_minimum_size.x) / 2.0), screen.y - 60.0)

func _say(text: String) -> void:
	if _line.text == text:
		return
	_line.text = text
	_line.visible_ratio = 0.0
	if _talk != null:
		_talk.kill()
	_face.talking = true
	_talk = create_tween()
	_talk.tween_property(_line, "visible_ratio", 1.0, clampf(text.length() / 55.0, 0.4, 2.2))
	_talk.tween_callback(func(): _face.talking = false)

func _warn(text: String) -> void:
	_message.text = text

## Rebuilds the body for where the orders are now.
func _refresh() -> void:
	for c in _body.get_children():
		c.queue_free()
	_hover_label = null
	_message.text = ""
	if run.orders.get("chosen", "") == "":
		_build_offers()
	elif not run.orders_pending():
		_build_done()
	else:
		var step := DeploymentOrders.current_step(run)
		match step.get("type", ""):
			DeploymentOrders.STEP_PICK: _build_pick(step)
			DeploymentOrders.STEP_CELLS: _build_cells(step)
			DeploymentOrders.STEP_REMOVE, DeploymentOrders.STEP_TRANSMUTE: _build_choose_part(step)
	_place.call_deferred()

# ---------- the three offers ----------

func _build_offers() -> void:
	_say("Before you drop: command cleared three packages for this op. You get one. Choose.")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_child(row)
	for id in run.orders.get("offer", []):
		row.add_child(_order_card(id))

func _order_card(id: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = CARD
	GlassPanel.style_button(b, false)
	b.mouse_entered.connect(func(): Audio.play("holo", 0.04, -10.0))
	b.pressed.connect(_take.bind(id))
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_top = 10
	v.offset_right = -12
	v.offset_bottom = -10
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	v.add_child(UIKit.label(DeploymentOrders.title(id).to_upper(), 15, Color("dffcf8"), true))
	var rule := ColorRect.new()
	rule.color = Color(GlassPanel.HOLO, 0.35)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(rule)
	v.add_child(UIKit.label(DeploymentOrders.text(id), 12, Color("b9d8d4"), true))
	return b

func _take(id: String) -> void:
	var note := DeploymentOrders.choose(run, id)
	if run.orders.get("chosen", "") != id:
		return
	Audio.play("prime")
	if note != "":
		_notes.append(note)
	SaveGame.save(run)
	_refresh()

# ---------- steps ----------

func _build_pick(step: Dictionary) -> void:
	var rarity := str(step.get("rarity", "salvaged")).capitalize()
	var left := (run.orders.get("steps", []) as Array).filter(func(s): return s.get("type", "") == DeploymentOrders.STEP_PICK).size()
	if step["category"] == "":
		_say("%s stock's on the pallet. What do you need?%s" % [rarity, "" if left <= 1 else " (%d picks)" % left])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		_body.add_child(row)
		for cat in Economy.CATEGORIES:
			var col := Palette.category_color(cat)
			var b := GlassPanel.button(cat.capitalize(), 17, false, col)
			b.custom_minimum_size = Vector2(220, 72)
			b.add_theme_stylebox_override("normal", GlassPanel.control_style(col, 0.12, 0.85))
			b.pressed.connect(func():
				DeploymentOrders.pick_category(run, cat)
				SaveGame.save(run)
				_refresh())
			row.add_child(b)
		return
	_say("Take one. It goes in your Cargo.")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_child(row)
	for id in step.get("options", []):
		var card := PartCardUI.new()
		row.add_child(card)
		card.setup(id)
		card.pressed.connect(func(_c):
			var note := DeploymentOrders.pick_part(run, id)
			if note != "":
				Audio.play("prime")
				_notes.append(note)
				SaveGame.save(run)
				_refresh())

## A PackingGrid of the chassis and its parts (room around it for new squares).
func _chassis_grid(with_offers: bool) -> PackingGrid:
	var g := PackingGrid.new()
	var mech := run.player_mech
	var b := Vector2i.ZERO
	for c in mech.cells:
		b = Vector2i(maxi(b.x, c.x + 1), maxi(b.y, c.y + 1))
	if with_offers:
		g.origin = Vector2i(1, 1)
		b += Vector2i(2, 2)
	g.setup(run.chassis_cells(), b, GRID_CELL)
	g.set_parts(mech.components)
	if with_offers:
		g.set_offers(run.cell_options(), true)
	var holder := CenterContainer.new()
	holder.add_child(g)
	_body.add_child(holder)
	return g

func _build_cells(step: Dictionary) -> void:
	var left := int(step["left"])
	_say("The frame's modular. Click a + to add a square, %d to place. Fill them at a refit." % left if left > 1 \
		else "Click a + to add a square to your frame. Fill it at a refit.")
	var g := _chassis_grid(true)
	g.cell_pressed.connect(func(_g, cell):
		if DeploymentOrders.add_cell(run, cell):
			Audio.play("frame_square", 0.02)
			SaveGame.save(run)
			_refresh())

func _build_choose_part(step: Dictionary) -> void:
	var strip: bool = step["type"] == DeploymentOrders.STEP_REMOVE
	_say("Click the component to strip out. It's gone for the run." if strip \
		else "Click the component to transmute. What comes back is random.")
	var g := _chassis_grid(false)
	_hover_label = UIKit.label("Hover a component.", 12, Color("9fb9b6"))
	_hover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(_hover_label)
	g.part_hovered.connect(func(_g, part):
		if _hover_label != null:
			_hover_label.text = "Hover a component." if part == null else "%s  ·  %s  ·  %s  ·  %d HP" % [part.name, part.category.capitalize(), part.rarity.capitalize(), part.max_hp])
	g.part_pressed.connect(func(_g, part, _cell):
		if not DeploymentOrders.can_choose_part(run, part):
			_warn("That's your last working hardpoint. Pick something else.")
			return
		var note := DeploymentOrders.choose_part(run, part)
		Audio.play("prime")
		_notes.append(note)
		SaveGame.save(run)
		_refresh())

# ---------- signing off ----------

func _build_done() -> void:
	var chosen: String = run.orders["chosen"]
	_say("%s, confirmed. Good hunting, pilot." % DeploymentOrders.title(chosen))
	var summary := UIKit.label(DeploymentOrders.text(chosen), 13, Color("b9d8d4"), true)
	_body.add_child(summary)
	for n in _notes:
		_body.add_child(UIKit.label(n, 12, Palette.OK, true))
	var row := HBoxContainer.new()
	row.add_child(UIKit.spacer())
	var go := GlassPanel.button("To the refit" if run.phase == RunData.PHASE_REFIT else "To the map", 14, true, Palette.HARDPOINT)
	go.custom_minimum_size = Vector2(180, 40)
	go.pressed.connect(func(): done.emit())
	row.add_child(go)
	_body.add_child(row)
	_hide_btn.visible = false

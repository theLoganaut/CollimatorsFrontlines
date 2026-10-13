extends Control
## The Hangar (Logan, 2026-09-27; overhauled 2026-09-28): the bay behind the
## War Room's Hangar door, seen from inside (assets/warroom/hangar_bay.png,
## 624×390 art drawn ×ART_SCALE like the War Room). The mech you're looking
## at stands on the projector pad as a hologram; the screens around it are
## holo glass (GlassPanel).
##
## Pick the mech you'll launch in and set its starting loadout from any
## Surplus part (all start unlocked). Left: the mech tabs, its chassis and a
## 6×6 workbench to park parts while mixing and matching (it stays in the
## Hangar; only the chassis launches). Right: the armory (ArmoryBrowser:
## search, category chips, sorting). Top: the part preview (PartPreview),
## showing whatever part was hovered last.
##
## Click an armory part to pick it up, or grab one on the chassis or bench,
## then place it on either (R / right-click rotates; Esc cancels). Dropping
## a grabbed part anywhere else removes it. Every change saves to the
## profile; a loadout needs at least one hardpoint to launch.

const BASE := Vector2(1152, 720)
const ART_SCALE := 1152.0 / 624.0
const TOP_BAR_H := TopBar.HEIGHT
const CELL := 34.0
const BENCH_SIZE := 6
## The projector pad in hangar_bay.png pixels, and the hologram's height.
const PAD_CENTER := Vector2(311, 312)
const HOLO_H := 270.0
const LEFT := Rect2(12, 57, 312, 651)
const PREVIEW := Rect2(338, 57, 448, 226)
const ARMORY := Rect2(800, 57, 340, 651)

var _mech_id: String = "bastion"
var _mech: MechData
var _bench_parts: Array[ComponentData] = []
var _stage: Control
var _bay: Texture2D
var _holo: TextureRect
var _tabs: HBoxContainer
var _chassis_title: Label
var _grid: PackingGrid
var _info: Label
var _bench: PackingGrid
var _message: Label
var _select_btn: Button
var _preview: PartPreview
var _armory: ArmoryBrowser

var _drag: ComponentData = null
var _drag_steps: int = 0
var _drag_rel := Vector2i.ZERO
var _drag_from: PackingGrid = null # null = picked from the armory
var _mouse := Vector2.ZERO # last mouse position, from input events

func _ready() -> void:
	UIState.reset()
	get_tree().paused = false
	Audio.music("hub")
	Audio.ambience("hub")
	_mech_id = Profile.mech if GameData.PLAYER_MECHS.has(Profile.mech) else "bastion"
	_bay = load("res://assets/warroom/hangar_bay.png")

	_stage = Control.new()
	_stage.size = BASE
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_stage.draw.connect(func(): _stage.draw_texture_rect(_bay, Rect2(Vector2.ZERO, BASE), false))
	add_child(_stage)

	_holo = TextureRect.new()
	_holo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_holo.stretch_mode = TextureRect.STRETCH_SCALE
	_holo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holo.material = MechArt.hologram_material(0.95, 0.55)
	_stage.add_child(_holo)

	_build_left()
	_preview = PartPreview.new()
	_preview.position = PREVIEW.position
	_preview.size = PREVIEW.size
	_stage.add_child(_preview)
	_armory = ArmoryBrowser.new()
	_armory.position = ARMORY.position
	_armory.size = ARMORY.size
	_armory.part_hovered.connect(_show_detail_id)
	_armory.part_picked.connect(_pick_from_armory)
	_stage.add_child(_armory)

	var row := UIKit.top_bar(self, "Hangar")
	row.add_child(UIKit.spacer())
	var back := UIKit.back_button()
	back.pressed.connect(func(): SceneRouter.go(SceneRouter.WAR_ROOM))
	row.add_child(back)

	get_viewport().size_changed.connect(_layout)
	_show_mech(_mech_id)

func _build_left() -> void:
	var panel := GlassPanel.new()
	panel.position = LEFT.position
	panel.size = LEFT.size
	_stage.add_child(panel)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	_tabs.position = Vector2(12, 12)
	panel.add_child(_tabs)
	for id in GameData.PLAYER_MECHS:
		var b := GlassPanel.button(id.capitalize(), 13)
		b.custom_minimum_size = Vector2(92, 32)
		b.pressed.connect(_show_mech.bind(id))
		_tabs.add_child(b)
	_chassis_title = UIKit.label("", 11, Color("b9d8d4"))
	_chassis_title.position = Vector2(12, 54)
	panel.add_child(_chassis_title)
	_grid = PackingGrid.new()
	_grid.part_pressed.connect(_on_part_pressed)
	_grid.part_hovered.connect(_on_part_hovered)
	panel.add_child(_grid)
	_info = UIKit.label("", 11, Color("9fb9b6"), true)
	_info.size = Vector2(LEFT.size.x - 24, 34)
	panel.add_child(_info)
	var bench_title := UIKit.label("WORKBENCH  ·  6×6  ·  parts stay in the Hangar", 11, Color("b9d8d4"))
	bench_title.position = Vector2(12, 308)
	panel.add_child(bench_title)
	_bench = PackingGrid.new()
	_bench.part_pressed.connect(_on_part_pressed)
	_bench.part_hovered.connect(_on_part_hovered)
	var bench_cells := {}
	for r in range(BENCH_SIZE):
		for c in range(BENCH_SIZE):
			bench_cells[Vector2i(r, c)] = true
	_bench.setup(bench_cells, Vector2i(BENCH_SIZE, BENCH_SIZE), CELL)
	_bench.position = Vector2(((LEFT.size.x - _bench.size.x) / 2.0), 328)
	panel.add_child(_bench)
	_message = UIKit.label("Pick a part from the armory, or grab one on the chassis or workbench.  R / right-click rotates.", 11, Color("9fb9b6"), true)
	_message.position = Vector2(12, 560)
	_message.size = Vector2(LEFT.size.x - 24, 36)
	panel.add_child(_message)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	buttons.position = Vector2(12, 603)
	panel.add_child(buttons)
	_select_btn = GlassPanel.button("Launch in this mech", 13, true, Palette.HARDPOINT)
	_select_btn.custom_minimum_size = Vector2(170, 36)
	_select_btn.pressed.connect(_select_mech)
	buttons.add_child(_select_btn)
	var reset := GlassPanel.button("Reset loadout", 13)
	reset.custom_minimum_size = Vector2(110, 36)
	reset.pressed.connect(_reset)
	buttons.add_child(reset)

func _layout() -> void:
	var screen: Vector2 = get_viewport_rect().size
	size = screen
	_stage.position = ((screen - Vector2(0, 0) - BASE) / 2.0).floor()
	_stage.position.y = maxf(0.0, _stage.position.y)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BG, true)

# ---------- mechs and loadouts ----------

func _show_mech(id: String) -> void:
	_end_drag()
	_mech_id = id
	_mech = GameData.player_mech(id, Profile.loadouts.get(id, []))
	var b := Vector2i.ZERO
	for c in _mech.cells:
		b = Vector2i(maxi(b.x, c.x + 1), maxi(b.y, c.y + 1))
	_grid.setup(GridUtils.cells_to_set(_mech.cells), b, CELL)
	_grid.position = Vector2(((LEFT.size.x - _grid.size.x) / 2.0), 74)
	_info.position = Vector2(12, _grid.position.y + _grid.size.y + 8)
	_chassis_title.text = "CHASSIS  ·  %s  ·  %s" % [_mech.name.to_upper(), _mech.weight_class.to_upper()]
	_load_bench()
	_armory.setup(_mech.weight_class)
	_place_hologram(MechArt.player_front(id))
	for i in range(_tabs.get_child_count()):
		var tab: Button = _tabs.get_child(i)
		var mid: String = GameData.PLAYER_MECHS[i]
		GlassPanel.style_button(tab, mid == id)
		tab.text = mid.capitalize() + ("  ✓" if mid == Profile.mech else "")
	_refresh()
	_layout()

## The mech stands on the projector pad as a hologram.
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
	var feet := PAD_CENTER * ART_SCALE
	_holo.size = Vector2(w, HOLO_H)
	_holo.position = Vector2(feet.x - w / 2.0, feet.y - HOLO_H)

func _load_bench() -> void:
	_bench_parts.clear()
	var taken := {}
	for e in Profile.hangar_bench.get(_mech_id, []):
		var id := str(e.get("id", ""))
		if not ComponentLibrary.has(id):
			continue
		var part := ComponentLibrary.make(id)
		var off: Array = e.get("offset", [0, 0])
		var offset := Vector2i(int(off[0]), int(off[1]))
		var steps := int(e.get("rotation", 0))
		if not GridUtils.can_place(part.cells, steps, offset, _bench.allowed, taken):
			continue
		part.place(steps, offset)
		for c in part.placed_cells:
			taken[c] = true
		_bench_parts.append(part)

func _refresh() -> void:
	_grid.set_parts(_mech.components)
	_bench.set_parts(_bench_parts)
	var hardpoints := _mech.components.filter(func(c): return c.category == ComponentData.CATEGORY_HARDPOINT).size()
	var used := 0
	for c in _mech.components:
		used += c.cells.size()
	_info.text = "%d HP  ·  %d / %d cells  ·  %d hardpoints\nmax heat %d  ·  heat check %s" % [
		_mech.max_hp(), used, _mech.cells.size(), hardpoints, _mech.heat_capacity(),
		"live" if _mech.heat_check_timing == MechData.HEAT_CHECK_LIVE else "at end of turn"]
	_select_btn.disabled = hardpoints == 0 or Profile.mech == _mech_id
	_select_btn.text = "Launching in this mech" if Profile.mech == _mech_id else "Launch in this mech"

static func _entries(parts: Array[ComponentData]) -> Array:
	var list := []
	for c in parts:
		list.append({"id": c.library_id, "offset": [c.offset.x, c.offset.y], "rotation": c.rotation_steps})
	return list

func _save() -> void:
	Profile.loadouts[_mech_id] = _entries(_mech.components)
	Profile.hangar_bench[_mech_id] = _entries(_bench_parts)
	Profile.save()

func _select_mech() -> void:
	if _mech.components.any(func(c): return c.category == ComponentData.CATEGORY_HARDPOINT):
		Profile.mech = _mech_id
		Profile.save()
		_show_mech(_mech_id)

func _reset() -> void:
	Profile.loadouts.erase(_mech_id)
	Profile.save()
	_show_mech(_mech_id)
	_message.text = "Default loadout restored. The workbench is untouched."

func _on_part_hovered(_g: PackingGrid, part: ComponentData) -> void:
	if part != null and _drag == null:
		_preview.show_part(part)

func _show_detail_id(id: String) -> void:
	if _drag == null:
		_preview.show_part(ComponentLibrary.make(id))

# ---------- placing parts ----------

func _pick_from_armory(id: String) -> void:
	_end_drag()
	_drag = ComponentLibrary.make(id)
	_drag_steps = 0
	_drag_rel = GridUtils.rotate_cells(_drag.cells, 0)[0]
	_drag_from = null
	_preview.show_part(_drag)
	_message.text = "Placing %s: click a spot on the chassis or workbench (R rotates, right-click or Esc cancels)." % _drag.name
	_update_hints()
	_update_ghost()

func _on_part_pressed(g: PackingGrid, part: ComponentData, cell: Vector2i) -> void:
	if _drag != null:
		return
	_drag = part
	_drag_steps = part.rotation_steps
	_drag_rel = cell - part.offset
	_drag_from = g
	g.dim_part = part
	g.queue_redraw()
	_update_hints()

func _parts_of(g: PackingGrid) -> Array[ComponentData]:
	return _mech.components if g == _grid else _bench_parts

## The grid under the mouse (null = neither).
func _target() -> PackingGrid:
	var m := _mouse
	for g in [_grid, _bench]:
		if g.contains_global(m):
			return g
	return null

func _fits(g: PackingGrid, offset: Vector2i) -> bool:
	var taken := {}
	for c in _parts_of(g):
		if c != _drag:
			for cell in c.placed_cells:
				taken[cell] = true
	return GridUtils.can_place(_drag.cells, _drag_steps, offset, g.allowed, taken)

## Lights every square the held part could land on, as it's turned now.
func _update_hints() -> void:
	for g in [_grid, _bench]:
		var cells := {}
		if _drag != null:
			var span := maxi(g.bounds.x, g.bounds.y) + 4
			for ox in range(-4, span):
				for oy in range(-4, span):
					if _fits(g, Vector2i(ox, oy)):
						for c in GridUtils.place_cells(_drag.cells, _drag_steps, Vector2i(ox, oy)):
							cells[c] = true
		g.set_hints(cells)

func _update_ghost() -> void:
	_grid.clear_ghost()
	_bench.clear_ghost()
	if _drag == null:
		return
	var g := _target()
	if g == null:
		return
	var off := g.cell_at_global(_mouse) - _drag_rel
	g.set_ghost(GridUtils.place_cells(_drag.cells, _drag_steps, off), _fits(g, off))

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse = event.position
	if _drag == null:
		return
	if event is InputEventKey and event.pressed and not event.echo and GameSettings.is_key(event, "rotate"):
		_rotate()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_end_drag()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		get_viewport().set_input_as_handled()
		if _drag_from != null:
			_rotate()
		else:
			_end_drag()
	elif event is InputEventMouseMotion:
		_update_ghost()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# armory picks drop on click; grabbed parts drop on release
		if (_drag_from == null and event.pressed) or (_drag_from != null and not event.pressed):
			get_viewport().set_input_as_handled()
			_drop()

func _rotate() -> void:
	get_viewport().set_input_as_handled()
	_drag_steps = (_drag_steps + 1) % 4
	_drag_rel = GridUtils.rotate_cells(_drag.cells, _drag_steps)[0]
	_update_hints()
	_update_ghost()

func _drop() -> void:
	var g := _target()
	if g != null:
		var off := g.cell_at_global(_mouse) - _drag_rel
		if not _fits(g, off):
			_message.text = "It doesn't fit there."
			if _drag_from == null:
				return # keep holding the armory part
			_end_drag()
			return
		if _drag_from != null:
			_parts_of(_drag_from).erase(_drag)
		_drag.place(_drag_steps, off)
		if g == _grid:
			_drag.set_instance_id(_free_id(_drag.library_id))
		_parts_of(g).append(_drag)
		_message.text = "%s %s." % [_drag.name, "installed" if g == _grid else "set on the workbench"]
	elif _drag_from != null:
		_parts_of(_drag_from).erase(_drag)
		_message.text = "%s removed." % _drag.name
	_save()
	_end_drag()

## A part id not yet used on the chassis ("voltage_spike", then "voltage_spike_2"…).
func _free_id(library_id: String) -> String:
	var id := library_id
	var n := 2
	while _mech.components.any(func(c): return c != _drag and c.id == id):
		id = "%s_%d" % [library_id, n]
		n += 1
	return id

func _end_drag() -> void:
	if _grid == null:
		return
	_grid.dim_part = null
	_bench.dim_part = null
	_drag = null
	_drag_from = null
	_grid.clear_ghost()
	_bench.clear_ghost()
	_grid.set_hints({})
	_bench.set_hints({})
	if _mech != null:
		_refresh()

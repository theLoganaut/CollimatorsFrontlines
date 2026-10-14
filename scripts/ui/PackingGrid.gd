class_name PackingGrid
extends Control
## A grid parts are packed into: a mech's chassis, Cargo or the Hangar's
## workbench. Draws its allowed cells and the parts placed in it (PartArt
## squares, HP on each part's first cell, a hatch on destroyed ones), and, while a part is dragged over
## it, a ghost of where it would land (green if it fits, red if not).
## RefitScreen drives the dragging; this only draws and hit-tests.
## An autonomous bay also shows `offer_cells`: empty squares next to the
## frame that can be bought (a "+" each; clicking one emits cell_pressed).
## `origin` shifts the drawing so offers above or left of row/col 0 fit.
## `temp_cells` are squares that only last for now (the opening refit's
## 5×5 Cargo): shaded amber, and a part on them is edged amber.
## `hint_cells`, while a part is dragged: every square it could land on
## here (as it's turned now), lightly lit.

signal part_pressed(grid: PackingGrid, part: ComponentData, cell: Vector2i)
signal cell_pressed(grid: PackingGrid, cell: Vector2i)
signal part_hovered(grid: PackingGrid, part: ComponentData)

const GAP := 3.0
## A press and release closer than this (pixels) is a click: it picks the
## part up to carry, and the next click puts it down (Logan, 2026-10-13).
## A release farther away is a drag and drops there.
const CLICK_SLOP := 6.0

var title: String = ""
var cell_size: float = 40.0
var allowed: Dictionary = {}   # Vector2i -> true
var bounds := Vector2i(1, 1)   # rows × cols
var parts: Array[ComponentData] = []
var ghost_cells: Array[Vector2i] = []
var ghost_ok: bool = false
var ghost_color: Color = Palette.OK
var dim_part: ComponentData = null # the part being dragged, drawn faint where it came from
var origin := Vector2i.ZERO # drawn position of cell (0, 0), in cells
var offer_cells: Array[Vector2i] = []
var offer_ok: bool = true # affordable: offers drawn lit, else muted
var temp_cells: Dictionary = {} # Vector2i -> true
var hint_cells: Dictionary = {} # Vector2i -> true

func set_hints(cells: Dictionary) -> void:
	hint_cells = cells
	queue_redraw()

var _hovered: ComponentData = null
var _hovered_offer := Vector2i(-99, -99)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # part art (PartArt)
	gui_input.connect(_on_gui_input)
	mouse_exited.connect(func(): _set_hovered(null))

func setup(p_allowed: Dictionary, p_bounds: Vector2i, p_cell: float, p_title: String = "") -> void:
	allowed = p_allowed
	bounds = p_bounds
	cell_size = p_cell
	title = p_title
	custom_minimum_size = Vector2(bounds.y, bounds.x) * (cell_size + GAP) - Vector2(GAP, GAP)
	size = custom_minimum_size
	queue_redraw()

func set_parts(p: Array[ComponentData]) -> void:
	parts = p
	queue_redraw()

func cell_pos(cell: Vector2i) -> Vector2:
	return Vector2(cell.y + origin.y, cell.x + origin.x) * (cell_size + GAP)

## The cell under a point in this control's coordinates (may be outside the grid).
func cell_at_local(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.y / (cell_size + GAP)), floori(p.x / (cell_size + GAP))) - origin

func set_offers(cells: Array[Vector2i], ok: bool) -> void:
	offer_cells = cells
	offer_ok = ok
	queue_redraw()

func cell_at_global(p: Vector2) -> Vector2i:
	return cell_at_local(p - global_position)

func contains_global(p: Vector2) -> bool:
	return get_global_rect().grow(cell_size * 0.5).has_point(p)

func part_at(cell: Vector2i) -> ComponentData:
	for c in parts:
		if c.placed_cells.has(cell):
			return c
	return null

func set_ghost(cells: Array[Vector2i], ok: bool) -> void:
	ghost_cells = cells
	ghost_ok = ok
	queue_redraw()

func clear_ghost() -> void:
	if not ghost_cells.is_empty():
		ghost_cells = []
		queue_redraw()

func _set_hovered(c: ComponentData) -> void:
	if c != _hovered:
		_hovered = c
		part_hovered.emit(self, c)
		queue_redraw()

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var cell := cell_at_local(event.position)
		_set_hovered(part_at(cell))
		var offer := cell if offer_cells.has(cell) else Vector2i(-99, -99)
		if offer != _hovered_offer:
			_hovered_offer = offer
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := cell_at_local(event.position)
		var p := part_at(cell)
		if p != null:
			accept_event()
			part_pressed.emit(self, p, cell)
		elif offer_cells.has(cell):
			accept_event()
			cell_pressed.emit(self, cell)

func _draw() -> void:
	for cell in allowed.keys():
		PartArt.draw_empty_cell(self, Rect2(cell_pos(cell), Vector2(cell_size, cell_size)))
	for cell in temp_cells.keys():
		var tr := Rect2(cell_pos(cell), Vector2(cell_size, cell_size))
		draw_rect(tr, Color(Palette.WARNING, 0.08), true)
		_dashed_rect(tr.grow(-2.0), Color(Palette.WARNING, 0.45))
	var font := get_theme_default_font()
	for c in parts:
		var faint := c == dim_part
		for cell in c.placed_cells:
			var r := Rect2(cell_pos(cell), Vector2(cell_size, cell_size))
			if c.destroyed:
				draw_rect(r, Color(0, 0, 0, 0.45), true)
				_hatch(r)
				draw_rect(r, Palette.DANGER, false, 2.0)
			else:
				PartArt.draw_part_cell(self, r, c, cell, 0.3 if faint else 1.0)
				if c.current_hp < c.max_hp or temp_cells.has(cell):
					draw_rect(r, Palette.WARNING, false, 2.0)
			if c == _hovered and not faint:
				draw_rect(r.grow(1.0), Palette.LINK, false, 2.0)
		if not c.placed_cells.is_empty() and not faint and not c.destroyed:
			var first := c.placed_cells[0]
			for cell in c.placed_cells:
				if cell.x < first.x or (cell.x == first.x and cell.y < first.y):
					first = cell
			draw_string(font, cell_pos(first) + Vector2(3, 14), str(c.current_hp), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	for cell in hint_cells.keys():
		var hr := Rect2(cell_pos(cell), Vector2(cell_size, cell_size)).grow(-1.0)
		draw_rect(hr, Color(Palette.OK, 0.12), true)
		draw_rect(hr, Color(Palette.OK, 0.45), false, 1.0)
	for cell in offer_cells:
		var r := Rect2(cell_pos(cell), Vector2(cell_size, cell_size)).grow(-2.0)
		var oc := Palette.SCRAPS if offer_ok else Palette.TEXT_MUTED
		var lit := cell == _hovered_offer and offer_ok
		if lit:
			draw_rect(r, Color(oc, 0.3), true)
		_dashed_rect(r, Color(oc, 1.0 if lit else 0.6))
		var c := r.get_center()
		var arm := cell_size * 0.18
		draw_line(c - Vector2(arm, 0), c + Vector2(arm, 0), Color(oc, 0.9), 2.0)
		draw_line(c - Vector2(0, arm), c + Vector2(0, arm), Color(oc, 0.9), 2.0)
	for cell in ghost_cells:
		var r := Rect2(cell_pos(cell), Vector2(cell_size, cell_size))
		var gc := Palette.OK if ghost_ok else Palette.DANGER
		draw_rect(r, Color(gc, 0.45), true)
		draw_rect(r, gc, false, 2.0)
	if title != "":
		draw_string(font, Vector2(0, -8), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Palette.TEXT_MUTED)

func _dashed_rect(r: Rect2, col: Color) -> void:
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in range(4):
		draw_dashed_line(pts[i], pts[(i + 1) % 4], col, 1.5, 4.0)

## A destroyed part's cell: crossed out.
func _hatch(rect: Rect2) -> void:
	var r := rect.grow(-5.0)
	draw_line(r.position, r.end, Palette.DANGER, 2.0)
	draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), Palette.DANGER, 2.0)

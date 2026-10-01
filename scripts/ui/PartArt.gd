class_name PartArt
extends RefCounted
## Component art (PixelLab): `assets/components/<library id>.png`, painted
## inside the part's unrotated shape at 32 px per grid cell. In a grid each
## of the part's cells shows its own tile of the art, turned with the part,
## so the art fits the shape at any rotation and the gaps between cells
## still show where the squares are. Grids have no fill (Logan, 2026-09-28):
## a square is only its edges, a little see-through, in the part's category
## color (a part without art keeps a faint tint so it still reads), and an
## empty square is a dim outline. draw_part_cell / draw_empty_cell are the
## one place every grid draws its squares.

const PATH := "res://assets/components/%s.png"
const EDGE_ALPHA := 0.55     # a part square's edges
const EDGE_WIDTH := 2.0
const PLAIN_FILL_ALPHA := 0.28 # a part without art
const EMPTY_EDGE := Color(0.45, 0.5, 0.6, 0.45)

static var _textures: Dictionary = {} # library id -> Texture2D (or null)

static func texture(component: ComponentData) -> Texture2D:
	var id := component.library_id
	if not _textures.has(id):
		var path := PATH % id
		_textures[id] = load(path) if ResourceLoader.exists(path) else null
	return _textures[id]

## A cell with art: the tint, the art's tile for `cell` (one of the part's
## placed cells) and the edges, into `rect` on `canvas`. `alpha` fades all of it.
static func draw_cell(canvas: CanvasItem, rect: Rect2, component: ComponentData, cell: Vector2i, tex: Texture2D, alpha: float = 1.0) -> void:
	var color := Palette.category_color(component.category)
	var top_left := Vector2i(999999, 999999)
	var bottom_right := Vector2i(-999999, -999999)
	for c in component.placed_cells:
		top_left = Vector2i(mini(top_left.x, c.x), mini(top_left.y, c.y))
		bottom_right = Vector2i(maxi(bottom_right.x, c.x), maxi(bottom_right.y, c.y))
	# The cell within the placed shape (row, col), turned back to the
	# unrotated shape one counterclockwise step at a time (see GridUtils).
	var local := cell - top_left
	var dims := bottom_right - top_left + Vector2i.ONE # rows, cols
	var steps := posmod(component.rotation_steps, 4)
	for i in range(steps):
		local = Vector2i(dims.y - 1 - local.y, local.x)
		dims = Vector2i(dims.y, dims.x)
	var tile := tex.get_width() / float(dims.y)
	var src := Rect2(local.y * tile, local.x * tile, tile, tile)
	canvas.draw_set_transform(rect.get_center(), steps * PI / 2.0)
	canvas.draw_texture_rect_region(tex, Rect2(-rect.size / 2.0, rect.size), src, Color(1, 1, 1, alpha))
	canvas.draw_set_transform(Vector2.ZERO, 0.0)
	canvas.draw_rect(rect, Color(color, EDGE_ALPHA * alpha), false, EDGE_WIDTH)

## A part's square in any grid: its art tile and edges, or, without art, a
## faint tint and edges.
static func draw_part_cell(canvas: CanvasItem, rect: Rect2, component: ComponentData, cell: Vector2i, alpha: float = 1.0) -> void:
	var tex := texture(component)
	if tex != null:
		draw_cell(canvas, rect, component, cell, tex, alpha)
		return
	var color := Palette.category_color(component.category)
	canvas.draw_rect(rect, Color(color, PLAIN_FILL_ALPHA * alpha), true)
	canvas.draw_rect(rect, Color(color, 0.8 * alpha), false, EDGE_WIDTH)

## An empty square: just a dim outline.
static func draw_empty_cell(canvas: CanvasItem, rect: Rect2) -> void:
	canvas.draw_rect(rect, EMPTY_EDGE, false, 1.0)

static var _shapes: Dictionary = {} # library id -> an unrotated copy, for draw_shape

## A part's whole shape, unrotated, as big as fits `box` (up to `max_cell`
## per square) and centered in it, each square with its art.
static func draw_shape(canvas: CanvasItem, box: Rect2, component: ComponentData, alpha: float = 1.0, max_cell: float = 30.0, gap: float = 2.0) -> void:
	if component == null:
		return
	if not _shapes.has(component.library_id):
		var copy := ComponentLibrary.make(component.library_id)
		if copy != null:
			copy.place(0, Vector2i.ZERO)
		_shapes[component.library_id] = copy
	var shape: ComponentData = _shapes[component.library_id]
	if shape == null:
		return
	var dims := Vector2i.ZERO # rows, cols
	for c in shape.cells:
		dims = Vector2i(maxi(dims.x, c.x + 1), maxi(dims.y, c.y + 1))
	var cell := minf(max_cell, minf((box.size.x + gap) / dims.y, (box.size.y + gap) / dims.x) - gap)
	var total := Vector2(dims.y, dims.x) * (cell + gap) - Vector2(gap, gap)
	var origin := (box.position + (box.size - total) / 2.0).floor()
	for c in shape.placed_cells:
		draw_part_cell(canvas, Rect2(origin + Vector2(c.y, c.x) * (cell + gap), Vector2(cell, cell)), shape, c, alpha)

class_name GridUtils
extends RefCounted
## Cell-shape math shared by the loader and the grid UI. Cells are
## Vector2i(row, col). Rotation matches Refit Bay's own `rotateCells90`
## (clockwise): (row, col) -> (col, -row), then re-normalized to a
## non-negative bounding box. Verified by hand against all four of
## Bastion's placements in the Combat Slice audit — see Chassis page.

static func normalize_cells(cells: Array[Vector2i]) -> Array[Vector2i]:
	if cells.is_empty():
		return []
	var min_row := 999999
	var min_col := 999999
	for c in cells:
		min_row = mini(min_row, c.x)
		min_col = mini(min_col, c.y)
	var out: Array[Vector2i] = []
	for c in cells:
		out.append(Vector2i(c.x - min_row, c.y - min_col))
	out.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.y < b.y))
	return out

static func rotate_cells_90(cells: Array[Vector2i]) -> Array[Vector2i]:
	var rotated: Array[Vector2i] = []
	for c in cells:
		rotated.append(Vector2i(c.y, -c.x))
	return normalize_cells(rotated)

static func rotate_cells(cells: Array[Vector2i], steps: int) -> Array[Vector2i]:
	var out := normalize_cells(cells)
	var n: int = ((steps % 4) + 4) % 4
	for i in range(n):
		out = rotate_cells_90(out)
	return out

static func offset_cells(cells: Array[Vector2i], offset: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in cells:
		out.append(c + offset)
	return out

## Rotates a component's local shape by `steps` (90° clockwise each) and
## places it at `offset` in the owning grid's coordinate space.
static func place_cells(local_cells: Array[Vector2i], steps: int, offset: Vector2i) -> Array[Vector2i]:
	return offset_cells(rotate_cells(local_cells, steps), offset)

static func cells_to_set(cells: Array[Vector2i]) -> Dictionary:
	var set := {}
	for c in cells:
		set[c] = true
	return set

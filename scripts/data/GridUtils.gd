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

## Whether `local_cells` rotated by `steps` at `offset` lands only on
## `allowed` cells (a set) that aren't in `occupied` (a set).
## The smallest rectangle holding every cell (x = column, y = row).
static func bounds_of(cells: Array[Vector2i]) -> Rect2i:
	if cells.is_empty():
		return Rect2i()
	var lo := cells[0]
	var hi := cells[0]
	for c in cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	return Rect2i(lo, hi - lo + Vector2i.ONE)

static func can_place(local_cells: Array[Vector2i], steps: int, offset: Vector2i, allowed: Dictionary, occupied: Dictionary) -> bool:
	for c in place_cells(local_cells, steps, offset):
		if not allowed.has(c) or occupied.has(c):
			return false
	return true

## The first placement (rotation, then row, then column) that fits, as
## {"rotation", "offset"}, or {} if none does. `bounds` = rows × cols to scan.
static func find_fit(local_cells: Array[Vector2i], allowed: Dictionary, occupied: Dictionary, bounds: Vector2i) -> Dictionary:
	for rot in range(4):
		for r in range(bounds.x):
			for c in range(bounds.y):
				if can_place(local_cells, rot, Vector2i(r, c), allowed, occupied):
					return {"rotation": rot, "offset": Vector2i(r, c)}
	return {}

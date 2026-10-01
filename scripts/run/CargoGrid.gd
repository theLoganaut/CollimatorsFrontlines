class_name CargoGrid
extends RefCounted
## Parts carried but not installed (Logan, 2026-09-27: "Cargo", a shaped
## grid). A part must fit by its shape, rotated if need be, like packing
## the chassis. Starts 3×3 (Logan: 2×2 couldn't hold most hardpoints);
## autonomous bays sell +1 row or +1 column.
## Parts keep their HP while stored.

const START_SIZE := 3

var rows: int = START_SIZE
var cols: int = START_SIZE
var items: Array[ComponentData] = [] # placed in cargo space (placed_cells)

func _init(p_rows: int = START_SIZE, p_cols: int = START_SIZE) -> void:
	rows = p_rows
	cols = p_cols

func cells() -> Dictionary:
	var set := {}
	for r in range(rows):
		for c in range(cols):
			set[Vector2i(r, c)] = true
	return set

func occupied(except: ComponentData = null) -> Dictionary:
	var set := {}
	for it in items:
		if it == except:
			continue
		for c in it.placed_cells:
			set[c] = true
	return set

func can_place(comp: ComponentData, steps: int, offset: Vector2i) -> bool:
	return GridUtils.can_place(comp.cells, steps, offset, cells(), occupied(comp))

## Where `comp` would fit right now ({} = nowhere).
func find_fit(comp: ComponentData) -> Dictionary:
	return GridUtils.find_fit(comp.cells, cells(), occupied(comp), Vector2i(rows, cols))

func place(comp: ComponentData, steps: int, offset: Vector2i) -> bool:
	if not can_place(comp, steps, offset):
		return false
	comp.place(steps, offset)
	if not items.has(comp):
		items.append(comp)
	return true

## Puts `comp` in the first spot it fits. False if it doesn't fit anywhere.
func add(comp: ComponentData) -> bool:
	var fit := find_fit(comp)
	if fit.is_empty():
		return false
	return place(comp, fit["rotation"], fit["offset"])

func remove(comp: ComponentData) -> void:
	items.erase(comp)

func grow_rows() -> void:
	rows += 1

func grow_cols() -> void:
	cols += 1

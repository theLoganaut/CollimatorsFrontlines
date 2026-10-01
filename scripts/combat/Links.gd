class_name Links
extends RefCounted
## Links and facing arrows (Statuses & Links → Links). A direction is set
## on the unrotated part and turns with it (clockwise, like GridUtils).
## Adjacent reach = the cells touching that side of the shape; vector
## reach = the whole row/column out from that side to the chassis edge.
## A part is reached if any of its cells is.

const ORDER := ["up", "right", "down", "left"]
const VECTORS := {"up": Vector2i(-1, 0), "right": Vector2i(0, 1), "down": Vector2i(1, 0), "left": Vector2i(0, -1)}
const REACH_ADJACENT := "adjacent"
const REACH_VECTOR := "vector"

## `dir` as the part now faces, after `steps` clockwise turns.
static func rotate_dir(dir: String, steps: int) -> String:
	var i := ORDER.find(dir)
	if i < 0:
		return dir
	return ORDER[(i + ((steps % 4) + 4) % 4) % 4]

## Cells reached from `comp` in each of `dirs` (as placed).
static func reached_cells(mech: MechData, comp: ComponentData, dirs: Array, reach: String) -> Array[Vector2i]:
	var own := GridUtils.cells_to_set(comp.placed_cells)
	var chassis := GridUtils.cells_to_set(mech.cells)
	var bounds := Vector2i.ZERO
	for c in mech.cells:
		bounds = Vector2i(maxi(bounds.x, c.x + 1), maxi(bounds.y, c.y + 1))
	var out := {}
	for d in dirs:
		var v: Vector2i = VECTORS.get(rotate_dir(d, comp.rotation_steps), Vector2i.ZERO)
		if v == Vector2i.ZERO:
			continue
		for cell in comp.placed_cells:
			var p: Vector2i = cell + v
			while p.x >= 0 and p.y >= 0 and p.x < bounds.x and p.y < bounds.y:
				if not own.has(p) and chassis.has(p):
					out[p] = true
				if reach != REACH_VECTOR:
					break
				p += v
	var cells: Array[Vector2i] = []
	for k in out.keys():
		cells.append(k)
	return cells

## Living parts of `mech` (other than `comp`) sitting on reached cells.
static func reached_components(mech: MechData, comp: ComponentData, dirs: Array, reach: String) -> Array[ComponentData]:
	var cells := GridUtils.cells_to_set(reached_cells(mech, comp, dirs, reach))
	var out: Array[ComponentData] = []
	for other in mech.components:
		if other == comp or other.destroyed:
			continue
		for c in other.placed_cells:
			if cells.has(c):
				out.append(other)
				break
	return out

## The part's Refit Bay link ({"dirs", "reach"}), or none.
static func link_of(comp: ComponentData) -> Dictionary:
	var d := ComponentLibrary.definition(comp.library_id)
	var link: Dictionary = d.get("link", {})
	var dirs: Array = link.get("dirs", [])
	if dirs.is_empty() and link.get("dir", "none") in ORDER:
		dirs = [link["dir"]]
	return {"dirs": dirs, "reach": link.get("reach", REACH_ADJACENT)}

## What the part's link reaches (Fire Control Relay, Thermal Transfer Bus).
static func linked(mech: MechData, comp: ComponentData) -> Array[ComponentData]:
	var l := link_of(comp)
	return reached_components(mech, comp, l["dirs"], l["reach"])

## What a facing arrow points at (Plated Housing up, Coolant Flush down).
static func facing(mech: MechData, comp: ComponentData) -> Array[ComponentData]:
	var dir: String = comp.passive.get("facing", "")
	if dir == "":
		return []
	return reached_components(mech, comp, [dir], REACH_ADJACENT)

## Living parts of `mech` touching `comp` on any side (for attacks that arc
## to "a component next to the target").
static func adjacent_parts(mech: MechData, comp: ComponentData) -> Array[ComponentData]:
	var near := {}
	for cell in comp.placed_cells:
		for v in VECTORS.values():
			near[cell + v] = true
	var out: Array[ComponentData] = []
	for other in mech.components:
		if other == comp or other.destroyed:
			continue
		for c in other.placed_cells:
			if near.has(c):
				out.append(other)
				break
	return out

class_name ChassisGridUI
extends Control
## Reusable grid: lays out one ComponentCellUI per chassis cell for a given
## MechData, manually positioned (not a GridContainer — chassis shapes are
## sparse and irregular, see Chassis page). Used for both the player and
## every enemy (Combat Slice §6). No assumption that a component's own
## cells are contiguous (Targeting Computer isn't).

var mech: MechData
var cell_size: float = 24.0
var gap: float = 3.0
var accepts_attack_drops: bool = false

var _cells: Dictionary = {} # Vector2i -> ComponentCellUI

signal attack_dropped(card: CardData, mech: MechData, component: ComponentData)
signal self_card_dropped(card: CardData)

func setup(p_mech: MechData, p_accepts_attack_drops: bool, p_cell_size: float = 24.0) -> void:
	mech = p_mech
	accepts_attack_drops = p_accepts_attack_drops
	cell_size = p_cell_size
	_rebuild()

func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_cells.clear()
	if mech == null:
		return

	var occupied: Dictionary = {} # Vector2i -> ComponentData
	for c in mech.components:
		for cell in c.placed_cells:
			occupied[cell] = c

	var max_row := 0
	var max_col := 0
	for cell in mech.cells:
		max_row = maxi(max_row, cell.x)
		max_col = maxi(max_col, cell.y)

	for cell in mech.cells:
		var cell_ui := ComponentCellUI.new()
		add_child(cell_ui)
		var comp: ComponentData = occupied.get(cell, null)
		cell_ui.position = Vector2(cell.y, cell.x) * (cell_size + gap)
		cell_ui.custom_minimum_size = Vector2(cell_size, cell_size)
		cell_ui.size = Vector2(cell_size, cell_size)
		cell_ui.setup(cell, comp, mech, accepts_attack_drops)
		cell_ui.attack_dropped.connect(func(card, m, c2): attack_dropped.emit(card, m, c2))
		cell_ui.self_card_dropped.connect(func(card): self_card_dropped.emit(card))
		_cells[cell] = cell_ui

	custom_minimum_size = Vector2(max_col + 1, max_row + 1) * (cell_size + gap)
	size = custom_minimum_size

## Re-draws every cell (HP numbers, destroyed hatching, damage rings)
## without rebuilding the tree — call after any damage/status change.
func refresh_all() -> void:
	for cell_ui in _cells.values():
		cell_ui.refresh()

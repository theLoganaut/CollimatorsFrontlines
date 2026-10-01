class_name PassiveRow
extends Control
## A mech's passive badges, centered in a row (above the player's health
## bar, below each enemy's). Every icon starts hidden: CombatScene's opening
## reveal flies each passive's card to its slot and pops the icon in.

const GAP := 6.0

var mech: MechData
var _icons: Dictionary = {} # ComponentData -> PassiveIcon

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## `row_width`: the width to center the icons in.
func setup(p_mech: MechData, row_width: float) -> void:
	mech = p_mech
	size = Vector2(row_width, PassiveIcon.ICON_SIZE.y)
	var comps := mech.passive_components()
	var n := comps.size()
	var x0 := (row_width - (n * PassiveIcon.ICON_SIZE.x + (n - 1) * GAP)) / 2.0
	for i in range(n):
		var icon := PassiveIcon.new()
		add_child(icon)
		icon.position = Vector2(x0 + i * (PassiveIcon.ICON_SIZE.x + GAP), 0)
		icon.setup(comps[i], mech)
		icon.visible = false
		_icons[comps[i]] = icon

func icon_for(component: ComponentData) -> PassiveIcon:
	return _icons.get(component, null)

## Shows any icon the reveal didn't get to (it was skipped).
func reveal_all() -> void:
	for icon in _icons.values():
		if not icon.visible:
			icon.pop_in()

func refresh() -> void:
	for icon in _icons.values():
		icon.queue_redraw()

class_name ComponentCellUI
extends Control
## One grid cell (Combat Slice §6). HP number on the component's top-left-
## most placed cell, category color, a warning ring when damaged, a
## diagonal hatch + red border when Destroyed (UI & Screens visual
## language). HP and Destroyed are drawn from the grid's *displayed* HP so
## they follow its countdown animation.
##
## Not a drop target itself: the dragged card asks CombatScene, which
## hit-tests grids via ChassisGridUI.cell_at() (see CardUI.gd for why).
## Hovering a cell sets it as the Description Box's component, which stays
## until a different component is hovered.

var cell_coord: Vector2i
var component: ComponentData = null # null = an unused chassis cell
var mech: MechData = null
var grid: ChassisGridUI = null
var is_first_cell: bool = false

var _hp_label: Label
var _flash: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # part art (PartArt)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(func(): if component != null: UIState.clear_hovered(component))
	_hp_label = Label.new()
	_hp_label.add_theme_color_override("font_color", Color.WHITE)
	_hp_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_hp_label.add_theme_constant_override("outline_size", 3)
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_label.position = Vector2(2, 0)
	add_child(_hp_label)
	set_process(false)
	_refresh_label()

func setup(p_coord: Vector2i, p_component: ComponentData, p_mech: MechData, p_grid: ChassisGridUI) -> void:
	cell_coord = p_coord
	component = p_component
	mech = p_mech
	grid = p_grid
	is_first_cell = component != null and component.placed_cells.size() > 0 and component.placed_cells[0] == p_coord
	if is_inside_tree():
		_refresh_label()
	queue_redraw()

func refresh() -> void:
	_refresh_label()
	queue_redraw()

func flash() -> void:
	_flash = 1.0
	set_process(true)

func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * 4.0)
	queue_redraw()
	if _flash <= 0.0:
		set_process(false)

func _shown_hp() -> int:
	if component == null:
		return 0
	return grid.shown_hp(component) if grid != null else component.current_hp

func _shows_destroyed() -> bool:
	return component != null and component.destroyed and _shown_hp() <= 0

func _refresh_label() -> void:
	if _hp_label == null:
		return
	_hp_label.add_theme_font_size_override("font_size", maxi(10, int(size.x * 0.36)))
	if component != null and is_first_cell and not _shows_destroyed():
		_hp_label.text = str(_shown_hp())
	else:
		_hp_label.text = ""

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if component == null:
		PartArt.draw_empty_cell(self, rect)
		return
	if _shows_destroyed():
		draw_rect(rect, Color(0, 0, 0, 0.45), true)
		_draw_hatch(rect)
		draw_rect(rect, Palette.DANGER, false, 2.0)
	else:
		PartArt.draw_part_cell(self, rect, component, cell_coord)
		if _shown_hp() < component.max_hp:
			draw_rect(rect, Palette.WARNING, false, 2.0)
		if not component.is_usable():
			draw_rect(rect, Color(0, 0, 0, 0.45), true) # Disabled / Offline: can't act
		if is_first_cell and not component.statuses.is_empty():
			_draw_status_dots(rect)
	if grid != null and grid.status_lit(component):
		var sc := Palette.status_color(grid.lit_status())
		draw_rect(rect, Color(sc, 0.28), true)
		draw_rect(rect, sc.lightened(0.2), false, 2.5)
	if grid != null and grid.is_targeted(component):
		draw_rect(rect, Color(1, 1, 1, 0.22), true)
		draw_rect(rect, Color.WHITE, false, 2.0)
	if grid != null and grid.is_covering(component):
		draw_rect(rect, Color(Palette.LINK, 0.3), true)
		draw_rect(rect, Palette.LINK, false, 3.0)
	if _flash > 0.0:
		draw_rect(rect, Color(1, 1, 1, _flash * 0.85), true)

## One marker per status the part holds (bottom-right of its first cell);
## the Description Box names them. Dots, or shapes in colorblind mode
## (Palette.draw_status). Placeholder until the pinned status icons.
func _draw_status_dots(rect: Rect2) -> void:
	var r := maxf(2.5, size.x * 0.09)
	if Palette.colorblind:
		r = maxf(r, 4.0) # shapes need a little more room to read
	var x := rect.end.x - r - 2.0
	for s in component.statuses:
		Palette.draw_status(self, Vector2(x, rect.end.y - r - 2.0), r, s.status)
		x -= r * 2.0 + 1.5

func _draw_hatch(rect: Rect2) -> void:
	var step := 6.0
	var i := -rect.size.y
	while i < rect.size.x:
		draw_line(Vector2(i, 0), Vector2(i + rect.size.y, rect.size.y), Palette.BORDER, 2.0)
		i += step

func _on_mouse_entered() -> void:
	if component != null and UIState.dragging_card == null:
		UIState.set_hovered(component, mech)

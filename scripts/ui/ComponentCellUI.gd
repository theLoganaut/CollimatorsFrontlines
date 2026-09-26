class_name ComponentCellUI
extends Control
## One grid cell (Combat Slice §6). HP number on the component's top-left-
## most placed cell, category color, a warning ring when damaged, a
## diagonal hatch + red border when Destroyed (UI & Screens visual
## language). Also a drop target: attack cards land here only on an
## `accepts_attack_drops` (enemy) cell over a live component; self cards
## resolve on release over *any* cell, enemy or player's (Combat Rules:
## "resolve ... anywhere outside the hand").

signal attack_dropped(card: CardData, mech: MechData, component: ComponentData)
signal self_card_dropped(card: CardData)

var cell_coord: Vector2i
var component: ComponentData = null # null = an unused chassis cell
var mech: MechData = null
var accepts_attack_drops: bool = false
var is_first_cell: bool = false

var _hp_label: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)
	_hp_label = Label.new()
	_hp_label.add_theme_color_override("font_color", Color.WHITE)
	_hp_label.add_theme_font_size_override("font_size", 10)
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_label.position = Vector2(2, 0)
	add_child(_hp_label)
	_refresh_label()

func setup(p_coord: Vector2i, p_component: ComponentData, p_mech: MechData, p_accepts_attack_drops: bool) -> void:
	cell_coord = p_coord
	component = p_component
	mech = p_mech
	accepts_attack_drops = p_accepts_attack_drops
	is_first_cell = component != null and component.placed_cells.size() > 0 and component.placed_cells[0] == p_coord
	if is_inside_tree():
		_refresh_label()
	queue_redraw()

func refresh() -> void:
	_refresh_label()
	queue_redraw()

func _refresh_label() -> void:
	if _hp_label == null:
		return
	if component != null and is_first_cell and not component.destroyed:
		_hp_label.text = str(component.current_hp)
	else:
		_hp_label.text = ""

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if component == null:
		draw_rect(rect, Palette.PANEL_2, true)
		draw_rect(rect, Palette.BORDER, false, 1.0)
		return
	if component.destroyed:
		draw_rect(rect, Palette.PANEL_2, true)
		_draw_hatch(rect)
		draw_rect(rect, Palette.DANGER, false, 2.0)
		return
	draw_rect(rect, Palette.category_color(component.category), true)
	if component.current_hp < component.max_hp:
		draw_rect(rect, Palette.WARNING, false, 2.0)

func _draw_hatch(rect: Rect2) -> void:
	var step := 6.0
	var i := -rect.size.y
	while i < rect.size.x:
		draw_line(Vector2(i, 0), Vector2(i + rect.size.y, rect.size.y), Palette.BORDER, 2.0)
		i += step

func _on_mouse_entered() -> void:
	if component != null:
		UIState.set_hovered(component, mech)

func _on_mouse_exited() -> void:
	if component != null:
		UIState.clear_hovered(component)

func _on_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed):
		return
	if UIState.dragging_card == null:
		return
	var card := UIState.dragging_card
	if card.is_attack():
		if accepts_attack_drops and component != null and not component.destroyed:
			attack_dropped.emit(card, mech, component)
			get_viewport().set_input_as_handled()
		# otherwise: an attack card released somewhere invalid — snap back, no-op.
	else:
		self_card_dropped.emit(card)
		get_viewport().set_input_as_handled()

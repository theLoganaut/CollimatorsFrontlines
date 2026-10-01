class_name PartCardUI
extends Control
## One component shown as a card, for picking or inspecting (reward picks,
## autonomous bays, refits): category and rarity, name, HP and shape, then
## what it does — each card it grants (heat, damage, statuses, effect text)
## or, for a reactor, its passive. Everything comes from Refit Bay.
## Clickable when `selectable`; hover lifts the border to yellow. Drawn as
## holo glass tinted by the part's category.

signal pressed(card: PartCardUI)

const SIZE := Vector2(210, 300)
const SHAPE_CELL := 11.0

var component_id: String = ""
var component: ComponentData = null # an existing part (keeps its HP), else a fresh one
var selectable: bool = true
var footer_text: String = ""
var footer_color: Color = Palette.TEXT

var _hover: bool = false
var _box: VBoxContainer
var _footer: Label

func _ready() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): _set_hover(true))
	mouse_exited.connect(func(): _set_hover(false))
	gui_input.connect(_on_gui_input)

## Show a library part (`id`) or an existing part (`comp`, with its HP).
func setup(id: String, comp: ComponentData = null) -> void:
	component_id = id
	component = comp if comp != null else ComponentLibrary.make(id)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if selectable else Control.CURSOR_ARROW
	_build()

func set_footer(text: String, color: Color = Palette.TEXT) -> void:
	footer_text = text
	footer_color = color
	if _footer != null:
		_footer.text = text
		_footer.add_theme_color_override("font_color", color)

func _build() -> void:
	for c in get_children():
		c.queue_free()
	var d := ComponentLibrary.definition(component.library_id)
	var cat_color := Palette.category_color(component.category)
	_box = VBoxContainer.new()
	_box.position = Vector2(12, 10)
	_box.size = Vector2(SIZE.x - 24, SIZE.y - 20)
	_box.add_theme_constant_override("separation", 3)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(UIKit.label(component.category.to_upper(), 10, cat_color))
	head.add_child(UIKit.spacer())
	head.add_child(UIKit.label(str(d.get("rarity", "")).capitalize(), 10, Palette.rarity_color(d.get("rarity", ""))))
	_box.add_child(head)
	_box.add_child(UIKit.label(component.name, 17, Palette.TEXT, true))
	var hp := "%d HP" % component.max_hp if component.current_hp == component.max_hp else "%d / %d HP" % [component.current_hp, component.max_hp]
	var hp_label := UIKit.label(hp, 12, Palette.TEXT_MUTED if component.current_hp == component.max_hp else Palette.WARNING)
	_box.add_child(hp_label)
	var shape := Control.new()
	shape.custom_minimum_size.y = _shape_height() + 6.0
	shape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shape.draw.connect(_draw_shape.bind(shape))
	_box.add_child(shape)

	if component.category == ComponentData.CATEGORY_REACTOR:
		_box.add_child(UIKit.label("PASSIVE · always in play", 10, cat_color))
		_box.add_child(UIKit.label(component.passive_text(), 11, Palette.TEXT, true))
	else:
		for card in component.cards:
			var line := card.name
			var bits: Array[String] = ["%d heat" % card.heat_cost]
			if card.damage_label() != "":
				bits.append(card.damage_label())
			_box.add_child(UIKit.label("%s  ·  %s" % [line, "  ·  ".join(bits)], 12, Palette.TEXT, true))
			var sub: Array[String] = []
			sub.append_array(card.status_lines())
			if card.effect_text != "":
				sub.append(card.effect_text)
			if not sub.is_empty():
				_box.add_child(UIKit.label("\n".join(sub), 10, Palette.TEXT_MUTED, true))
	_box.add_child(UIKit.spacer(false))
	_footer = UIKit.label(footer_text, 12, footer_color)
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(_footer)
	queue_redraw()

func _shape_height() -> float:
	var rows := 0
	for c in component.cells:
		rows = maxi(rows, c.x + 1)
	return rows * (SHAPE_CELL + 2.0)

func _set_hover(h: bool) -> void:
	_hover = h and selectable
	queue_redraw()

func _on_gui_input(event: InputEvent) -> void:
	if selectable and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		pressed.emit(self)

func _draw() -> void:
	if component == null:
		return
	var cat_color := Palette.category_color(component.category)
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.015, 0.03, 0.04, 0.8), true)
	GlassPanel.draw_glass(self, r, 1.0, Palette.LINK if _hover else cat_color, 10.0, 0.9 if _hover else 0.7)

## The part's cells, drawn in the spacer under the HP line, with its art.
func _draw_shape(canvas: Control) -> void:
	var shape := ComponentLibrary.make(component.library_id)
	if shape == null:
		return
	shape.place(0, Vector2i.ZERO)
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for c in shape.placed_cells:
		PartArt.draw_part_cell(canvas, Rect2(c.y * (SHAPE_CELL + 2.0), 2.0 + c.x * (SHAPE_CELL + 2.0), SHAPE_CELL, SHAPE_CELL), shape, c)

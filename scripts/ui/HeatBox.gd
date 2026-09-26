class_name HeatBox
extends Control
## Small "current/max" heat readout (the sketch's "2/9" boxes).

var current: int = 0
var max_value: int = 1
var _label: Label

func _ready() -> void:
	custom_minimum_size = Vector2(44, 32)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Palette.TEXT)
	_label.add_theme_font_size_override("font_size", 13)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_refresh_label()

func set_heat(p_current: int, p_max: int) -> void:
	current = p_current
	max_value = p_max
	if is_inside_tree():
		_refresh_label()
	queue_redraw()

func _refresh_label() -> void:
	_label.text = "%d/%d" % [current, max_value]
	_label.add_theme_color_override("font_color", Palette.DANGER if current > max_value else Palette.TEXT)

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Palette.PANEL_2, true)
	draw_rect(rect, Palette.BORDER, false, 1.0)

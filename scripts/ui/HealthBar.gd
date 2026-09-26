class_name HealthBar
extends Control
## A labeled HP bar (`current / max`), Refit Bay style.

var current: int = 0
var max_value: int = 1
var _label: Label

func _ready() -> void:
	custom_minimum_size = Vector2(80, 16)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Palette.TEXT)
	_label.add_theme_font_size_override("font_size", 11)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_refresh_label()

func set_hp(p_current: int, p_max: int) -> void:
	current = maxi(p_current, 0)
	max_value = maxi(p_max, 1)
	if is_inside_tree():
		_refresh_label()
	queue_redraw()

func _refresh_label() -> void:
	_label.text = "%d / %d HP" % [current, max_value]

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Palette.PANEL_2, true)
	var frac: float = clampf(float(current) / float(max_value), 0.0, 1.0)
	if frac > 0.0:
		draw_rect(Rect2(rect.position, Vector2(rect.size.x * frac, rect.size.y)), Palette.DANGER, true)
	draw_rect(rect, Palette.BORDER, false, 1.0)

class_name TopBar
extends Control
## The strip across the top of the run, hub and Hangar screens, on holo
## glass (Logan, 2026-10-02: in place of the flat grey bar): smoked glass
## with scanlines, a teal edge along the bottom that brightens under the
## title, and corner ticks. The title sits on the left in capitals; what
## follows goes in `row`, read-outs as glass chips (chip()), buttons as
## GlassPanel buttons or tiles.

const HEIGHT := 50.0
const CHIP_H := 32.0

var row: HBoxContainer
var _title: Label

static func make(parent: Control, title: String) -> TopBar:
	var bar := TopBar.new()
	parent.add_child(bar)
	bar.set_title(title)
	return bar

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	offset_bottom = HEIGHT
	row = HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 22
	row.offset_right = -12
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	_title = UIKit.label("", 16, Color("dffcf8"))
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_title.resized.connect(queue_redraw)
	row.add_child(_title)
	resized.connect(queue_redraw)

func set_title(text: String) -> void:
	_title.text = text.to_upper()

## Makes the title a button (the War Room's: click its name to rename it):
## it lights on hover and calls `on_click`.
func clickable_title(on_click: Callable, tooltip: String) -> void:
	_title.mouse_filter = Control.MOUSE_FILTER_STOP
	_title.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_title.tooltip_text = tooltip
	_title.mouse_entered.connect(func(): _title.add_theme_color_override("font_color", Palette.LINK))
	_title.mouse_exited.connect(func(): _title.add_theme_color_override("font_color", Color("dffcf8")))
	_title.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			on_click.call())

## A read-out on glass (scraps, HP, chips): `label` inside a small framed
## chip edged in `accent`. Returns the chip; keep the label to update it.
static func chip(label: Label, accent: Color = GlassPanel.HOLO) -> PanelContainer:
	var c := PanelContainer.new()
	var st := GlassPanel.control_style(accent, 0.0, 0.55)
	st.content_margin_left = 12
	st.content_margin_right = 12
	st.content_margin_top = 2
	st.content_margin_bottom = 2
	c.add_theme_stylebox_override("panel", st)
	c.custom_minimum_size = Vector2(0, CHIP_H)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	c.add_child(label)
	return c

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var a := GlassPanel.HOLO
	draw_rect(r, Color(0.01, 0.035, 0.045, 0.86), true)
	var top := Color(a, 0.10)
	var bottom := Color(a, 0.02)
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, 0), r.end, Vector2(0, r.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))
	var y := 2.0
	while y < r.end.y:
		draw_line(Vector2(0, y), Vector2(r.end.x, y), Color(a, 0.035), 1.0)
		y += 3.0
	# The bottom edge, brighter (with a glow) under the title.
	var base := r.end.y - 1.0
	draw_line(Vector2(0, base), Vector2(r.end.x, base), Color(a, 0.45), 1.0)
	var t_end := row.offset_left + _title.position.x + _title.size.x + 18.0
	draw_rect(Rect2(0, base - 3.0, t_end, 3.0), Color(a, 0.12), true)
	draw_line(Vector2(0, base), Vector2(t_end, base), Color(a, 0.95), 2.0)
	draw_line(Vector2(t_end, base), Vector2(t_end + 10.0, base - 6.0), Color(a, 0.6), 1.0)
	# A tick before the title, and brackets at the bar's lower corners.
	var mid := r.size.y / 2.0
	draw_rect(Rect2(10, mid - 7.0, 3, 14), Color(a, 0.9), true)
	draw_line(Vector2(r.end.x - 1.0, base), Vector2(r.end.x - 1.0, base - 8.0), Color(a, 0.9), 2.0)
	draw_line(Vector2(1.0, base), Vector2(1.0, base - 8.0), Color(a, 0.9), 2.0)

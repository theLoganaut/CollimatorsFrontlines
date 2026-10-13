class_name HeatBox
extends Control
## Small "current/max" heat readout (the sketch's "2/9" boxes). Can show a
## preview of the heat a card would bring you to (amber), or red when that
## would overheat. The player's also forecasts the end of the turn under it
## ("vents to 3"), and its glass warms as the heat nears max (from
## NEAR_SHARE), with a slow glow unless motion is reduced.

var current: int = 0
var max_value: int = 1
var font_size: int = 13
var preview: int = -1 # -1 = no preview
## Show "vents to N" under the box (the player's); vent_at_max is the mech's own (< 0 = balance.json).
var show_forecast: bool = false
var vent_at_max: float = -1.0
const NEAR_SHARE := 0.75
var _label: Label
var _t: float = 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(44, 32)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Palette.TEXT)
	_label.add_theme_font_size_override("font_size", font_size)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_refresh_label()

func set_heat(p_current: int, p_max: int) -> void:
	if is_inside_tree() and p_current > current:
		# a little punch when heat goes up
		pivot_offset = size / 2.0
		scale = Vector2(1.14, 1.14)
		create_tween().tween_property(self, "scale", Vector2.ONE, 0.18).set_ease(Tween.EASE_OUT)
	current = p_current
	max_value = p_max
	if is_inside_tree():
		_refresh_label()
	queue_redraw()

func set_preview(p_preview: int) -> void:
	if preview == p_preview:
		return
	preview = p_preview
	_refresh_label()
	queue_redraw()

func _state_color() -> Color:
	var shown := preview if preview >= 0 else current
	if shown > max_value:
		return Palette.DANGER
	if preview >= 0:
		return Palette.WARNING
	return Color("eefcfa")

func _refresh_label() -> void:
	if _label == null:
		return
	_label.text = "%d/%d" % [preview if preview >= 0 else current, max_value]
	_label.add_theme_color_override("font_color", _state_color())

## The heat shown is at or past NEAR_SHARE of max (but not over).
func _near_max() -> bool:
	var shown := preview if preview >= 0 else current
	return shown >= ceili(max_value * NEAR_SHARE) and shown <= max_value

func _process(delta: float) -> void:
	if _near_max() and not GameSettings.reduce_motion:
		_t += delta
		queue_redraw()

func _draw() -> void: # holo glass, lit by the preview / overheat colour
	var rect := Rect2(Vector2.ZERO, size)
	var has_state := preview >= 0 or current > max_value
	draw_rect(rect, Color(0.015, 0.03, 0.04, 0.8), true)
	GlassPanel.draw_glass(self, rect, 1.0, _state_color() if has_state else Palette.HARDPOINT, 5.0, 0.8)
	if has_state:
		draw_rect(rect, _state_color(), false, 2.0)
	if _near_max() and not has_state:
		var k := 0.55 + 0.25 * sin(_t * 3.0) if not GameSettings.reduce_motion else 0.7
		draw_rect(rect, Color(Palette.WARNING, k), false, 2.0)
		draw_rect(rect.grow(2.0), Color(Palette.WARNING, k * 0.3), false, 2.0)
	if show_forecast:
		var shown := preview if preview >= 0 else current
		var after := shown - HeatRules.amount_vented(shown, max_value, vent_at_max)
		var text := "vents to %d" % after if after < shown else ("too cool to vent" if shown > 0 else "cool")
		# wider than the box, centered on it, so "too cool to vent" isn't clipped
		draw_string(get_theme_default_font(), Vector2(-40, size.y + 15), text, HORIZONTAL_ALIGNMENT_CENTER, size.x + 80, 12,
			Palette.DANGER if after > max_value else Color("9fb9b6"))

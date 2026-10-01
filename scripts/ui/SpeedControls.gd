class_name SpeedControls
extends Control
## Three right-facing "play" buttons, top-right next to Settings: normal,
## 1.5× and 2× speed (one, two and three arrows). The active speed is lit.

const BUTTON_SIZE := Vector2(40, 40)
const GAP := 6.0
const LABELS := ["Normal speed", "1.5× speed", "2× speed"]

var _buttons: Array[Button] = []

func _ready() -> void:
	size = Vector2(BUTTON_SIZE.x * 3 + GAP * 2, BUTTON_SIZE.y)
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in range(3):
		var b := Button.new()
		b.position = Vector2(i * (BUTTON_SIZE.x + GAP), 0)
		b.size = BUTTON_SIZE
		b.tooltip_text = LABELS[i]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_pressed.bind(i))
		b.draw.connect(_draw_arrows.bind(b, i + 1))
		add_child(b)
		_buttons.append(b)
	GameSettings.changed.connect(_refresh)
	_refresh()

func _on_pressed(i: int) -> void:
	GameSettings.set_value("speed", GameSettings.SPEEDS[i])

func _refresh() -> void:
	for i in range(_buttons.size()):
		var active: bool = is_equal_approx(GameSettings.speed, GameSettings.SPEEDS[i])
		var style := GlassPanel.control_style(Palette.HARDPOINT if active else GlassPanel.HOLO, 0.35 if active else 0.0, 0.9 if active else 0.45)
		style.bg_color = Color(Palette.HARDPOINT, 0.35) if active else Color(0.02, 0.05, 0.06, 0.8)
		var hover := style.duplicate()
		hover.border_color = Palette.LINK
		for state in ["normal", "pressed", "focus"]:
			_buttons[i].add_theme_stylebox_override(state, style)
		_buttons[i].add_theme_stylebox_override("hover", hover)
		_buttons[i].set_meta("active", active)
		_buttons[i].queue_redraw()

## `count` small right-facing triangles, centered on the button.
func _draw_arrows(b: Button, count: int) -> void:
	var active: bool = b.get_meta("active", false)
	var color: Color = Color("fff1e8") if active else Color("b9d8d4")
	var tri_w := 9.0
	var tri_h := 12.0
	var overlap := 2.0
	var total_w := count * tri_w - (count - 1) * overlap
	var x0 := (BUTTON_SIZE.x - total_w) / 2.0
	var cy := BUTTON_SIZE.y / 2.0
	for k in range(count):
		var x := x0 + k * (tri_w - overlap)
		b.draw_colored_polygon(PackedVector2Array([
			Vector2(x, cy - tri_h / 2.0), Vector2(x + tri_w, cy), Vector2(x, cy + tri_h / 2.0)]), color)

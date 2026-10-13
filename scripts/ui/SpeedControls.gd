class_name SpeedControls
extends Control
## Three right-facing "play" buttons, top-right next to Settings: normal,
## 1.5× and 2× speed (one, two and three arrows), as glass tiles
## (GlassPanel.draw_tile). The active speed is lit teal.

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
		b.flat = true
		b.mouse_entered.connect(b.queue_redraw)
		b.mouse_exited.connect(b.queue_redraw)
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
		_buttons[i].set_meta("active", is_equal_approx(GameSettings.speed, GameSettings.SPEEDS[i]))
		_buttons[i].queue_redraw()

## `count` small right-facing triangles, centered on the button.
func _draw_arrows(b: Button, count: int) -> void:
	var active: bool = b.get_meta("active", false)
	GlassPanel.draw_tile(b, active)
	var color: Color = Color("eefcfa") if active else Color("8fb8b3")
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

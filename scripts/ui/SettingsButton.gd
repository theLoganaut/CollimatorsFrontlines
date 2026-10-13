class_name SettingsButton
extends Control
## Settings button, top-right corner: a glass tile (GlassPanel.draw_tile)
## with a gear drawn on it. Opens the settings menu.

signal pressed()

const BUTTON_SIZE := Vector2(40, 40)

func _ready() -> void:
	custom_minimum_size = BUTTON_SIZE
	size = BUTTON_SIZE
	var btn := Button.new()
	btn.flat = true
	btn.size = BUTTON_SIZE
	btn.tooltip_text = "Settings (Esc)"
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(func(): pressed.emit())
	btn.mouse_entered.connect(btn.queue_redraw)
	btn.mouse_exited.connect(btn.queue_redraw)
	btn.draw.connect(func(): _draw_gear(btn))
	add_child(btn)

## A gear: a ring with eight square teeth and a hole.
static func _draw_gear(b: Button) -> void:
	GlassPanel.draw_tile(b, false)
	var c := b.size / 2.0
	var col := Color("cfeeea") if b.is_hovered() else Color("8fb8b3")
	for i in range(8):
		var a := TAU * i / 8.0
		var dir := Vector2(cos(a), sin(a))
		var p := c + dir * 9.5
		var side := Vector2(-dir.y, dir.x)
		b.draw_colored_polygon(PackedVector2Array([p + side * 2.6 - dir * 2.5, p + side * 2.6 + dir * 2.5, p - side * 2.6 + dir * 2.5, p - side * 2.6 - dir * 2.5]), col)
	b.draw_circle(c, 8.0, col)
	b.draw_circle(c, 3.5, Color(0.02, 0.05, 0.06, 1.0))

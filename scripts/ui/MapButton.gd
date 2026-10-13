class_name MapButton
extends Control
## Opens the location map over a fight or a stop's screen (Logan,
## 2026-10-02), to look ahead without leaving: a glass tile like the
## settings button, with a folded map drawn on it. In combat it sits left of
## the speed buttons; on a stop's screen, left of the settings button.

signal pressed()

const BUTTON_SIZE := Vector2(40, 40)

func _ready() -> void:
	custom_minimum_size = BUTTON_SIZE
	size = BUTTON_SIZE
	var btn := Button.new()
	btn.flat = true
	btn.size = BUTTON_SIZE
	btn.tooltip_text = "Map (%s)" % GameSettings.key_label("map")
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(func():
		Audio.play("ui", 0.03)
		pressed.emit())
	btn.mouse_entered.connect(btn.queue_redraw)
	btn.mouse_exited.connect(btn.queue_redraw)
	btn.draw.connect(func(): _draw_map(btn))
	add_child(btn)

## A map folded in three panels, with a route and its end marked.
static func _draw_map(b: Button) -> void:
	GlassPanel.draw_tile(b, false)
	var col := Color("cfeeea") if b.is_hovered() else Color("8fb8b3")
	var o := b.size / 2.0 - Vector2(11, 9)
	var pts := PackedVector2Array([Vector2(0, 2), Vector2(7, 0), Vector2(15, 2), Vector2(22, 0),
		Vector2(22, 16), Vector2(15, 18), Vector2(7, 16), Vector2(0, 18), Vector2(0, 2)])
	for i in range(pts.size()):
		pts[i] += o
	b.draw_polyline(pts, col, 1.5, true)
	b.draw_line(o + Vector2(7, 0), o + Vector2(7, 16), col, 1.0, true)
	b.draw_line(o + Vector2(15, 2), o + Vector2(15, 18), col, 1.0, true)
	b.draw_polyline(PackedVector2Array([o + Vector2(3, 13), o + Vector2(9, 9), o + Vector2(13, 11), o + Vector2(18, 6)]), Color(Palette.LINK, 0.9), 1.5, true)
	b.draw_circle(o + Vector2(18, 6), 2.2, Palette.LINK)

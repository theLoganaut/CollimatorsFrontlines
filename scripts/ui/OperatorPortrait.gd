class_name OperatorPortrait
extends Control
## The Operator on a comm feed (assets/operator/operator.png, a handler
## in shadow): the portrait behind holo glass with scanlines, a slow
## flicker, a rolling interference band now and then, and signal bars
## that move while he's talking. Used by the War Room's Operator panel and
## the training coach.

const ART := "res://assets/operator/operator.png"

## True while his line is still coming in: the signal bars move.
var talking: bool = false
var _tex: Texture2D
var _t: float = 0.0
var _band: float = -1.0 # interference band position (0..1), <0 = none

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	_tex = load(ART) if ResourceLoader.exists(ART) else null

func _process(delta: float) -> void:
	_t += delta
	if _band >= 0.0:
		_band += delta * 1.6
		if _band > 1.2:
			_band = -1.0
	elif randf() < delta * 0.25:
		_band = 0.0
	queue_redraw()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.0, 0.02, 0.03, 0.9), true)
	if _tex != null:
		# cover the frame, keeping the head in view
		var ts := _tex.get_size()
		var s := maxf(r.size.x / ts.x, r.size.y / ts.y)
		var src := Rect2(Vector2.ZERO, r.size / s)
		src.position = Vector2((ts.x - src.size.x) / 2.0, (ts.y - src.size.y) * 0.3)
		var flicker := 0.9 + 0.06 * sin(_t * 23.0) * sin(_t * 3.1)
		draw_texture_rect_region(_tex, r, src, Color(0.86 * flicker, 1.0 * flicker, 1.0 * flicker))
	# holo wash and scanlines
	draw_rect(r, Color(GlassPanel.HOLO, 0.07), true)
	var y := 1.0
	while y < r.size.y:
		draw_line(Vector2(0, y), Vector2(r.size.x, y), Color(0, 0, 0, 0.22), 1.0)
		y += 3.0
	if _band >= 0.0:
		var by := (_band - 0.1) * r.size.y
		draw_rect(Rect2(0, by, r.size.x, 5.0), Color(GlassPanel.HOLO, 0.14), true)
		draw_rect(Rect2(0, by + 7.0, r.size.x, 1.0), Color(GlassPanel.HOLO, 0.22), true)
	# signal bars, bottom right
	for i in range(4):
		var h := 3.0 + i * 2.0
		var lit := 1.0
		if talking:
			lit = 1.0 if (sin(_t * 9.0 + i * 1.7) + sin(_t * 5.3 + i)) > -0.6 + i * 0.35 else 0.25
		draw_rect(Rect2(r.size.x - 22.0 + i * 4.0, r.size.y - 6.0 - h, 3.0, h), Color(GlassPanel.HOLO, 0.85 * lit), true)
	GlassPanel.draw_frame(self, r, 1.0, GlassPanel.HOLO, 6.0)

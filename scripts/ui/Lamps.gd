class_name Lamps
extends Control
## The light a background's lamps cast (backgrounds.json `lamps`, drawn by
## PlayField over the image): each lamp has a bright halo and a pool of
## light on the ground below it, sized by how near it is. Until a boss's
## phase 2 they glow faintly; as `alarm` rises (0..1) they pulse like warning
## lights, the pulse running down the line from the far end (Logan,
## 2026-11-20: the lights carry the pulse, not the whole screen). Held
## steady with Reduce motion.
##
## `style` "bulbs" (backgrounds.json `lamp_style`): strung bulbs, like the
## Mining Grounds tunnel's. Each sways on its wire and glows round, with no
## pool; as `alarm` rises they stutter, drop out and surge, swinging harder.
## "work": the same, bolted down (floodlights on scaffolds don't sway).

const PULSE_RATE := 1.6  # pulses a second at full alarm
const RIPPLE := 0.09     # seconds between one lamp's pulse and the next nearer one
const IDLE := 0.22       # how bright they are before phase 2

var points: Array[Vector2] = [] # on screen
var depth: Array[float] = []    # 0 far .. 1 near, per lamp
var color: Color = Color(1.0, 0.63, 0.2)
var alarm: float = 0.0
var style: String = "alarm"

var _t: float = 0.0
static var _glow: Texture2D = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = add

## Lamps at `fractions` of `image` (the background's rect on screen).
func setup(fractions: Array, image: Rect2) -> void:
	points.clear()
	depth.clear()
	var ys := fractions.map(func(p): return float(p[1]))
	var top: float = ys.min() if not ys.is_empty() else 0.0
	var bottom: float = ys.max() if not ys.is_empty() else 1.0
	for p in fractions:
		points.append(image.position + Vector2(p[0], p[1]) * image.size)
		depth.append(clampf((float(p[1]) - top) / maxf(bottom - top, 0.001), 0.0, 1.0))
	queue_redraw()

func _process(delta: float) -> void:
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null and settings.reduce_motion:
		return
	if Engine.time_scale > 0.0:
		delta /= Engine.time_scale
	_t += delta
	queue_redraw()

static func _glow_texture() -> Texture2D:
	if _glow == null:
		var g := GradientTexture2D.new()
		g.width = 64
		g.height = 64
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		g.fill_to = Vector2(1.0, 0.5)
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 1))
		grad.set_color(1, Color(1, 1, 1, 0))
		grad.add_point(0.35, Color(1, 1, 1, 0.45))
		g.gradient = grad
		_glow = g
	return _glow

## A steady 0..1 noise per lamp and time step.
static func _noise(i: int, step: float) -> float:
	return fmod(absf(sin(float(i) * 12.9898 + step * 78.233) * 43758.5453), 1.0)

func _draw() -> void:
	var tex := _glow_texture()
	if style in ["bulbs", "work"]:
		_draw_bulbs(tex)
		return
	for i in range(points.size()):
		var near: float = depth[i]
		var r := lerpf(14.0, 70.0, near * near) * (size.x / 1920.0 if size.x > 0.0 else 1.0)
		# far lamps pulse first: the alarm runs down the line toward you
		# (each side is listed far to near, 10 a side on the Shipyard pier)
		var phase := _t * PULSE_RATE - float(i % 10) * RIPPLE * PULSE_RATE
		var pulse := pow(0.5 + 0.5 * sin(phase * TAU), 3.0)
		var level := IDLE * (0.9 + 0.1 * sin(_t * 7.0 + i)) + alarm * (0.15 + 0.85 * pulse)
		var c := Color(color, level)
		var at := points[i]
		# the pool on the ground: wide and flat, just below the lamp
		var pool := Vector2(r * 2.4, r * 0.9)
		draw_texture_rect(tex, Rect2(at + Vector2(-pool.x / 2.0, -pool.y * 0.25), pool), false, c)
		# the halo round the lamp itself
		var halo := Vector2(r, r)
		draw_texture_rect(tex, Rect2(at - halo / 2.0, halo), false, Color(c, minf(1.0, level * 1.3)))

func _draw_bulbs(tex: Texture2D) -> void:
	var scale := size.x / 1920.0 if size.x > 0.0 else 1.0
	for i in range(points.size()):
		var sway := 0.0 if style == "work" else sin(_t * (1.1 + 0.15 * float(i % 3)) + float(i) * 0.7) * (1.5 + 4.0 * alarm) * scale
		var at := points[i] + Vector2(sway, absf(sway) * 0.25)
		var level := IDLE + 0.12 + 0.04 * sin(_t * 9.0 + float(i) * 2.1)
		if alarm > 0.0:
			# stutter: every ~0.08 s a bulb may drop out or surge
			var n := _noise(i, floor(_t * 12.0))
			var flick := 0.05 if n < 0.18 else (1.0 if n > 0.82 else 0.55)
			level = lerpf(level, flick, alarm)
		var glow := Vector2(46.0, 46.0) * scale
		draw_texture_rect(tex, Rect2(at - glow / 2.0, glow), false, Color(color, level * 0.8))
		var core := Vector2(14.0, 14.0) * scale
		draw_texture_rect(tex, Rect2(at - core / 2.0, core), false, Color(color.lightened(0.4), minf(1.0, level * 1.4)))


class_name Rain
extends Control
## Rain over a combat background (PlayField adds it for a background with
## `weather` "rain"). Streaks fall across the whole scene; each drop lands
## somewhere on the ground (from `ground_y` down) and splashes there: a
## little crown and two flecks that fade out. Drops landing lower on the
## screen are nearer the camera, so they're longer, faster and splash wider.
## Everything snaps to the background's pixel size to match the pixel art.

const DROPS := 200
const FAR_SPEED := 420.0  # px/s for a drop landing at the far edge of the ground
const NEAR_SPEED := 980.0 # ...and at the bottom of the screen
const FAR_LENGTH := 5.0   # streak length in art pixels
const NEAR_LENGTH := 11.0
const WIND := 0.14        # sideways drift per pixel fallen
const SPLASH_TIME := 0.32
const STREAK_COLOR := Color(0.74, 0.82, 0.94, 0.42)
const SPLASH_COLOR := Color(0.84, 0.9, 1.0, 0.9)

## Where the ground starts, in this control's coordinates.
var ground_y: float = 0.0
## One art pixel on screen.
var pixel: float = 2.0

var _drops: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	resized.connect(_reset)
	_reset()

func setup(p_ground_y: float, p_pixel: float) -> void:
	ground_y = p_ground_y
	pixel = maxf(1.0, p_pixel)
	_reset()

## Fresh drops, already spread through the fall so it's raining from the first frame.
func _reset() -> void:
	_drops.clear()
	if size.y <= 0.0:
		return
	for i in range(DROPS):
		var d := _new_drop()
		d["y"] = _rng.randf_range(-size.y * 0.3, d["land_y"])
		_drops.append(d)

func _new_drop() -> Dictionary:
	var land_y := _rng.randf_range(ground_y, size.y)
	var depth := clampf((land_y - ground_y) / maxf(size.y - ground_y, 1.0), 0.0, 1.0) # 0 far, 1 near
	var start_y := -_rng.randf_range(0.0, size.y * 0.25)
	# Start upwind so the drop drifts onto the screen as it falls.
	var x := _rng.randf_range(0.0, size.x) - (land_y - start_y) * WIND
	return {"x": x, "y": start_y, "land_y": land_y, "depth": depth,
		"speed": lerpf(FAR_SPEED, NEAR_SPEED, depth), "len": lerpf(FAR_LENGTH, NEAR_LENGTH, depth), "splash": -1.0}

func _process(delta: float) -> void:
	visible = not GameSettings.reduce_motion
	if not visible:
		return
	for i in range(_drops.size()):
		var d := _drops[i]
		if d["splash"] >= 0.0:
			d["splash"] += delta
			if d["splash"] >= SPLASH_TIME:
				_drops[i] = _new_drop()
			continue
		var fall: float = d["speed"] * delta
		d["y"] += fall
		d["x"] += fall * WIND
		if d["y"] >= d["land_y"]:
			d["x"] -= (d["y"] - d["land_y"]) * WIND
			d["y"] = d["land_y"]
			d["splash"] = 0.0
	queue_redraw()

func _draw() -> void:
	for d in _drops:
		var depth: float = d["depth"]
		var w := pixel * (1.0 if depth < 0.5 else 2.0)
		if d["splash"] < 0.0:
			var tail: float = d["len"] * pixel
			var head := _snap(Vector2(d["x"], d["y"]))
			var top := _snap(Vector2(d["x"] - tail * WIND, d["y"] - tail))
			draw_line(top, head, STREAK_COLOR, w)
			continue
		var t: float = d["splash"] / SPLASH_TIME
		var color := Color(SPLASH_COLOR, SPLASH_COLOR.a * (1.0 - t * t))
		var spread := pixel * lerpf(2.0, 5.0, depth) * (0.5 + t)
		var base := _snap(Vector2(d["x"], d["y"]))
		# The hit: a short flat flash on the ground...
		if t < 0.35:
			draw_rect(Rect2(_snap(base + Vector2(-spread * 0.6, 0)), Vector2(spread * 1.2 + w, pixel)), color)
		# ...a crown spreading out along the ground...
		draw_rect(Rect2(_snap(base + Vector2(-spread - w * 2.0, 0)), Vector2(w * 2.0, pixel)), color)
		draw_rect(Rect2(_snap(base + Vector2(spread, 0)), Vector2(w * 2.0, pixel)), color)
		# ...and flecks thrown up and falling back.
		var rise := sin(t * PI) * pixel * lerpf(3.0, 7.0, depth)
		var fleck := Vector2(w, w)
		draw_rect(Rect2(_snap(base + Vector2(-spread * 0.7, -rise * 0.8)), fleck), color)
		draw_rect(Rect2(_snap(base + Vector2(spread * 0.7, -rise * 0.8)), fleck), color)
		draw_rect(Rect2(_snap(base + Vector2(0, -rise * 1.2)), fleck), color)

func _snap(p: Vector2) -> Vector2:
	return (p / pixel).floor() * pixel

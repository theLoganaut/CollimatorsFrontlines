class_name Snow
extends Control
## Snow over a combat background (PlayField adds it for a background with
## `weather` "snow"). Flakes float slowly down across the whole scene,
## swaying side to side on a light breeze; each one settles somewhere on the
## ground (from `ground_y` down), lies there a moment and melts away. Flakes
## settling lower on the screen are nearer the camera, so they're bigger,
## brighter and fall a little faster. Everything snaps to the background's
## pixel size to match the pixel art.

const FLAKES := 170
const FAR_SPEED := 14.0   # art px/s for a flake settling at the far edge of the ground
const NEAR_SPEED := 30.0  # ...and at the bottom of the screen
const SWAY := 3.5         # art px each way a flake sways
const SWAY_RATE := Vector2(0.6, 1.4) # its sway cycles per second, from..to
const BREEZE := 4.0       # art px/s every flake drifts sideways
const SETTLE_TIME := 1.6  # how long a settled flake takes to melt
const FAR_COLOR := Color(0.78, 0.84, 0.94, 0.5)
const NEAR_COLOR := Color(0.94, 0.97, 1.0, 0.9)

## Where the ground starts, in this control's coordinates.
var ground_y: float = 0.0
## One art pixel on screen.
var pixel: float = 2.0

var _flakes: Array[Dictionary] = []
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

## Fresh flakes, already spread through the fall so it's snowing from the first frame.
func _reset() -> void:
	_flakes.clear()
	if size.y <= 0.0:
		return
	for i in range(FLAKES):
		var f := _new_flake()
		f["y"] = _rng.randf_range(-size.y * 0.1, f["land_y"])
		_flakes.append(f)

func _new_flake() -> Dictionary:
	var land_y := _rng.randf_range(ground_y, size.y)
	var depth := clampf((land_y - ground_y) / maxf(size.y - ground_y, 1.0), 0.0, 1.0) # 0 far, 1 near
	return {"x": _rng.randf_range(-SWAY * pixel, size.x + SWAY * pixel), "y": -_rng.randf_range(0.0, size.y * 0.1),
		"land_y": land_y, "depth": depth, "speed": lerpf(FAR_SPEED, NEAR_SPEED, depth) * _rng.randf_range(0.8, 1.2),
		"phase": _rng.randf() * TAU, "rate": _rng.randf_range(SWAY_RATE.x, SWAY_RATE.y) * TAU,
		"big": depth > 0.55 and _rng.randf() < 0.6, "settled": -1.0}

func _process(delta: float) -> void:
	visible = not GameSettings.reduce_motion
	if not visible:
		return
	# Real time: the game's speed setting (and hit-stop) leaves the weather alone.
	if Engine.time_scale > 0.0:
		delta /= Engine.time_scale
	for i in range(_flakes.size()):
		var f := _flakes[i]
		if f["settled"] >= 0.0:
			f["settled"] += delta
			if f["settled"] >= SETTLE_TIME:
				_flakes[i] = _new_flake()
			continue
		f["y"] += f["speed"] * pixel * delta
		f["x"] += BREEZE * pixel * delta
		f["phase"] += f["rate"] * delta
		if f["y"] >= f["land_y"]:
			f["y"] = f["land_y"]
			f["x"] += sin(f["phase"]) * SWAY * pixel # lie where it touched down
			f["settled"] = 0.0
		elif f["x"] > size.x + SWAY * 2.0 * pixel: # blown off the side: back in on the other
			f["x"] -= size.x + SWAY * 4.0 * pixel
	queue_redraw()

func _draw() -> void:
	for f in _flakes:
		var depth: float = f["depth"]
		var color := FAR_COLOR.lerp(NEAR_COLOR, depth)
		var x: float = f["x"]
		if f["settled"] >= 0.0:
			var t: float = f["settled"] / SETTLE_TIME
			color.a *= 1.0 - t * t
		else:
			x += sin(f["phase"]) * SWAY * pixel
		var p := _snap(Vector2(x, f["y"]))
		if f["big"]:
			# A near flake: a little plus of pixels, its arms fainter.
			draw_rect(Rect2(p, Vector2(pixel, pixel)), color)
			var faint := Color(color, color.a * 0.45)
			for o in [Vector2(-pixel, 0), Vector2(pixel, 0), Vector2(0, -pixel), Vector2(0, pixel)]:
				draw_rect(Rect2(p + o, Vector2(pixel, pixel)), faint)
		else:
			draw_rect(Rect2(p, Vector2(pixel, pixel)), color)

func _snap(p: Vector2) -> Vector2:
	return (p / pixel).floor() * pixel

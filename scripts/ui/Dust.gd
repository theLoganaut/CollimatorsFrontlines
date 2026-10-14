class_name Dust
extends Control
## Blowing dust over a combat background (PlayField adds it for a background
## with `weather` "dust"). The wind comes in gusts: calm spells with a faint
## drift of motes, then a gust builds, blows a while (fluttering, never
## steady) and dies down, sometimes straight into another. Each gust has its
## own strength and length, and all blow the same way (picked per fight).
## Under a gust the motes race across and stretch into streaks, the air
## thickens with a haze, and puffs of dust lift off the ground (from
## `ground_y` down) and roll away downwind. Motes lower on the screen are
## nearer the camera, so they're bigger and faster. Everything snaps to the
## background's pixel size to match the pixel art.

const MOTES := 240
const CALM_WIND := 0.06            # wind between gusts (a gust at full strength = 1)
const MOTE_SPEED := Vector2(70.0, 190.0) # art px/s at full wind, far..near
const CALM_TIME := Vector2(1.5, 5.0)  # seconds between gusts, from..to
const RISE_TIME := Vector2(0.3, 1.0)  # a gust building up
const HOLD_TIME := Vector2(0.6, 2.8)  # blowing
const FALL_TIME := Vector2(0.9, 2.4)  # dying down
const STRENGTH := Vector2(0.45, 1.0)  # how hard a gust blows
const RE_GUST := 0.3               # chance a dying gust whips straight up into another
const PUFF_RATE := 24.0            # puffs lifted per second by a full gust
const PUFF_LIFE := Vector2(1.2, 2.4)
const PUFF_SIZE := Vector2(6.0, 16.0) # art px radius when grown, far..near
const HAZE_ALPHA := 0.24
const MOTE_COLOR := Color(0.98, 0.91, 0.78)
const PUFF_COLOR := Color(0.9, 0.78, 0.62)

enum Phase { CALM, RISE, HOLD, FALL }

## Where the ground starts, in this control's coordinates.
var ground_y: float = 0.0
## One art pixel on screen.
var pixel: float = 2.0

var _motes: Array[Dictionary] = []
var _puffs: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _dir := 1.0         # +1 blows left to right, -1 right to left
var _phase := Phase.CALM
var _phase_left := 0.0  # seconds left in this phase
var _phase_len := 1.0
var _strength := 1.0    # this gust's
var _env := 0.0         # the gust's build-up and die-down, 0..1
var _time := 0.0
var _wind := CALM_WIND  # what blows right now (calm + gust + flutter)
var _puff_due := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	_dir = 1.0 if _rng.randf() < 0.5 else -1.0
	_set_phase(Phase.CALM, _rng.randf_range(0.3, 2.0)) # the first gust comes soon
	resized.connect(_reset)
	_reset()

func setup(p_ground_y: float, p_pixel: float) -> void:
	ground_y = p_ground_y
	pixel = maxf(1.0, p_pixel)
	_reset()

## Fresh motes spread over the scene; no puffs yet.
func _reset() -> void:
	_motes.clear()
	_puffs.clear()
	if size.y <= 0.0:
		return
	for i in range(MOTES):
		_motes.append(_new_mote(_rng.randf_range(0.0, size.x)))

func _new_mote(x: float) -> Dictionary:
	var y := _rng.randf_range(ground_y * 0.35, size.y)
	var depth := clampf((y - ground_y) / maxf(size.y - ground_y, 1.0), 0.0, 1.0) # 0 far (or in the air), 1 near
	return {"x": x, "y": y, "depth": depth, "speed": lerpf(MOTE_SPEED.x, MOTE_SPEED.y, depth) * _rng.randf_range(0.7, 1.3),
		"bob": _rng.randf() * TAU, "bob_rate": _rng.randf_range(1.0, 2.5), "big": depth > 0.6 and _rng.randf() < 0.4,
		"stretch": _rng.randf_range(0.3, 1.3), "shade": _rng.randf_range(0.0, 1.0)}

func _set_phase(p: Phase, length: float) -> void:
	_phase = p
	_phase_len = maxf(length, 0.01)
	_phase_left = _phase_len

func _rand(r: Vector2) -> float:
	return _rng.randf_range(r.x, r.y)

## The gust cycle: calm → rise → hold → fall → calm (or straight into a new rise).
func _step_wind(delta: float) -> void:
	_time += delta
	_phase_left -= delta
	var t := 1.0 - _phase_left / _phase_len
	match _phase:
		Phase.CALM:
			_env = 0.0
		Phase.RISE:
			_env = maxf(_env, smoothstep(0.0, 1.0, t))
		Phase.HOLD:
			_env = 1.0
		Phase.FALL:
			_env = 1.0 - smoothstep(0.0, 1.0, t)
	if _phase_left <= 0.0:
		match _phase:
			Phase.CALM:
				_strength = _rand(STRENGTH)
				_set_phase(Phase.RISE, _rand(RISE_TIME))
			Phase.RISE:
				_set_phase(Phase.HOLD, _rand(HOLD_TIME))
			Phase.HOLD:
				_set_phase(Phase.FALL, _rand(FALL_TIME))
			Phase.FALL:
				if _rng.randf() < RE_GUST:
					_strength = _rand(STRENGTH)
					_set_phase(Phase.RISE, _rand(RISE_TIME))
				else:
					_set_phase(Phase.CALM, _rand(CALM_TIME))
	# Inside a gust the wind flutters: two slow waves beating against each other.
	var flutter := 1.0 + 0.3 * sin(_time * 5.3) * sin(_time * 2.1 + 1.0)
	_wind = CALM_WIND + (1.0 - CALM_WIND) * _env * _strength * flutter

func _process(delta: float) -> void:
	visible = not GameSettings.reduce_motion
	if not visible:
		return
	# Real time: the game's speed setting (and hit-stop) leaves the weather alone.
	if Engine.time_scale > 0.0:
		delta /= Engine.time_scale
	_step_wind(delta)
	var margin := pixel * 20.0
	for i in range(_motes.size()):
		var m := _motes[i]
		m["x"] += _dir * _wind * m["speed"] * pixel * delta
		m["bob"] += m["bob_rate"] * delta
		m["y"] -= _wind * _wind * 6.0 * pixel * delta # a gust lifts the motes a little
		if m["x"] > size.x + margin or m["x"] < -margin or m["y"] < ground_y * 0.3:
			_motes[i] = _new_mote(-margin * 0.5 if _dir > 0.0 else size.x + margin * 0.5)
	# Puffs: lifted off the ground by the gust, rolling downwind, spreading and thinning.
	_puff_due += PUFF_RATE * maxf(_wind - CALM_WIND * 2.0, 0.0) * delta
	while _puff_due >= 1.0:
		_puff_due -= 1.0
		_puffs.append(_new_puff())
	for p in _puffs:
		p["age"] += delta
		p["x"] += _dir * (_wind * p["speed"] + 6.0) * pixel * delta
		p["y"] -= 3.0 * pixel * delta
	_puffs = _puffs.filter(func(p): return p["age"] < p["life"])
	queue_redraw()

func _new_puff() -> Dictionary:
	var y := _rng.randf_range(ground_y, size.y)
	var depth := clampf((y - ground_y) / maxf(size.y - ground_y, 1.0), 0.0, 1.0)
	# Mostly from the upwind side, so the dust rolls across the scene.
	var upwind := _rng.randf_range(-0.1, 0.75) * size.x
	return {"x": upwind if _dir > 0.0 else size.x - upwind, "y": y, "age": 0.0, "life": _rand(PUFF_LIFE),
		"size": lerpf(PUFF_SIZE.x, PUFF_SIZE.y, depth) * _rng.randf_range(0.7, 1.3),
		"speed": lerpf(MOTE_SPEED.x, MOTE_SPEED.y, depth) * 0.6,
		# a few lumps, so a puff rolls as a ragged cloud rather than a ball
		"lumps": [Vector2.ZERO, Vector2(_rng.randf_range(-1.6, -0.6), _rng.randf_range(-0.6, 0.1)),
			Vector2(_rng.randf_range(0.5, 1.5), _rng.randf_range(-0.4, 0.3))],
		"lump_size": [1.0, _rng.randf_range(0.5, 0.8), _rng.randf_range(0.4, 0.75)]}

func _draw() -> void:
	# The haze: the air thickens under a gust, most of all near the ground.
	var gust := clampf((_wind - CALM_WIND) / (1.0 - CALM_WIND), 0.0, 1.0)
	if gust > 0.01:
		# Thickest at the far edge of the ground, where the most air is between
		# it and the camera: fading out toward the sky and thinning toward the
		# bottom, in steps too fine to see.
		var steps := 24
		var band := size.y / float(steps)
		var g := maxf(ground_y, 1.0)
		for i in range(steps):
			var mid := (float(i) + 0.5) * band
			var thick := mid / g if mid < g else 1.0 - 0.6 * (mid - g) / maxf(size.y - g, 1.0)
			var y0 := floorf(band * i / pixel) * pixel
			var y1 := size.y if i == steps - 1 else floorf(band * (i + 1) / pixel) * pixel
			draw_rect(Rect2(0, y0, size.x, y1 - y0), Color(PUFF_COLOR, HAZE_ALPHA * gust * thick))
	for p in _puffs:
		var t: float = p["age"] / p["life"]
		var alpha := 0.4 * sin(t * PI) * (1.0 - t * 0.5)
		var r: float = p["size"] * pixel * (0.4 + 0.6 * t)
		for k in range(p["lumps"].size()):
			_draw_blob(Vector2(p["x"], p["y"]) + p["lumps"][k] * r, r * p["lump_size"][k], Color(PUFF_COLOR, alpha * 0.6))
	for m in _motes:
		var depth: float = m["depth"]
		var w := pixel * (2.0 if m["big"] else 1.0)
		var color := Color(MOTE_COLOR.lerp(PUFF_COLOR, m["shade"]), lerpf(0.3, 0.75, depth) * (0.35 + 0.65 * gust))
		var p := _snap(Vector2(m["x"], m["y"] + sin(m["bob"]) * pixel * 1.5))
		# Faster wind, longer streak (drawn trailing upwind).
		var tail := floorf(_wind * lerpf(5.0, 16.0, depth) * m["stretch"]) * pixel
		var x0 := p.x - tail if _dir > 0.0 else p.x
		draw_rect(Rect2(x0, p.y, tail + w, w), color)

## A rough pixel disc, wider than tall like rolling dust: one snapped rect per art-pixel row.
func _draw_blob(center: Vector2, r: float, color: Color) -> void:
	var ry := r * 0.7
	var rows := int(ry / pixel)
	var c := _snap(center)
	for i in range(-rows, rows + 1):
		var dy := float(i) * pixel
		var half := floorf(r * 1.4 * sqrt(maxf(1.0 - (dy * dy) / (ry * ry), 0.0)) / pixel) * pixel
		draw_rect(Rect2(c + Vector2(-half, dy), Vector2(half * 2.0 + pixel, pixel)), color)

func _snap(p: Vector2) -> Vector2:
	return (p / pixel).floor() * pixel

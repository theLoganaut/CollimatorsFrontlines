class_name Omen
extends Control
## A boss's phase 2 over its background (PlayField.set_phase2), one per
## location, in the background's pixel size like the weather:
##   "storm"  (Shipyard): lightning forks down the sky now and then, and
##            the screen flashes with it (PlayField reads `flash`); where the
##            background has `spray` edges, waves burst up over them.
##   "glitch" (Data Archives): blocks of corrupted pixels and torn scanlines
##            flicker in and out.
##   "embers" (Mining Grounds): sparks rise off the ground and drift up;
##            with `rockfall`, rocks drop from the ceiling (a cave) or off
##            `rock_edges` (a pit's cliff tops) and burst into dust where
##            they land.
## Hidden with Reduce motion (and `flash` stays 0: no flashing lights).

const STORM_GAP := Vector2(3.5, 8.0)   # seconds between strikes, from..to
const STRIKE_TIME := 0.35
const BOLT_COLOR := Color(0.85, 0.9, 1.0, 0.95)
const GLITCH_RATE := 7.0               # corrupted blocks a second
const GLITCH_COLORS := [Color(1.0, 0.2, 0.45, 0.55), Color(0.35, 0.95, 1.0, 0.45), Color(0.9, 0.9, 1.0, 0.35)]
const SPRAY_GAP := Vector2(0.12, 0.4)  # seconds between bursts, from..to
const SPRAY_GRAVITY := 260.0           # art px/s²
const SPRAY_COLORS := [Color(0.92, 0.96, 1.0, 0.9), Color(0.7, 0.8, 0.95, 0.8), Color(0.5, 0.62, 0.85, 0.7)]
const ROCK_GAP := Vector2(0.5, 1.6)    # seconds between rocks, from..to
const ROCK_COLORS := [Color(0.32, 0.24, 0.2), Color(0.42, 0.32, 0.25), Color(0.25, 0.19, 0.16)]
const DUST_COLOR := Color(0.62, 0.5, 0.4, 0.7)
const EMBERS := 80
const EMBER_SPEED := Vector2(14.0, 42.0) # art px/s, from..to
const EMBER_COLORS := [Color(1.0, 0.75, 0.3), Color(1.0, 0.5, 0.15), Color(1.0, 0.3, 0.1)]

var mode: String = "storm"
## Where the ground starts, in this control's coordinates.
var ground_y: float = 0.0
## One art pixel on screen.
var pixel: float = 2.0
## How bright the screen flashes right now (lightning), 0..1.
var flash: float = 0.0

var _rng := RandomNumberGenerator.new()
var _next_strike: float = 1.2
var _strike_t: float = -1.0
var _bolt: PackedVector2Array = PackedVector2Array()
var _blocks: Array[Dictionary] = []
var _glitch_acc: float = 0.0
var _embers: Array[Dictionary] = []
## Edges the sea breaks over, on screen: [[from, to], ...], the sea on the
## outer side (left of a left-hand edge, right of a right-hand one).
var spray_edges: Array = []
var _spray: Array[Dictionary] = []
var _next_spray: float = 0.3
## Rocks fall from the ceiling (embers mode).
var rockfall: bool = false
## Where rocks break off, on screen: [[x0, x1, y], ...] ([] = the ceiling).
var rock_edges: Array = []
var _rocks: Array[Dictionary] = []
var _dust: Array[Dictionary] = []
var _next_rock: float = 0.6

func _init(p_mode: String = "storm") -> void:
	mode = p_mode

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	resized.connect(_reset)
	_reset()

func setup(p_ground_y: float, p_pixel: float) -> void:
	ground_y = p_ground_y
	pixel = maxf(1.0, p_pixel)
	_reset()

func _reset() -> void:
	_embers.clear()
	if mode == "embers" and size.y > 0.0:
		for i in range(EMBERS):
			var e := _new_ember()
			e["y"] = _rng.randf_range(size.y * 0.3, size.y)
			_embers.append(e)

func _new_ember() -> Dictionary:
	return {"x": _rng.randf_range(0.0, size.x), "y": size.y + _rng.randf_range(0.0, size.y * 0.2),
		"speed": _rng.randf_range(EMBER_SPEED.x, EMBER_SPEED.y) * pixel, "phase": _rng.randf() * TAU,
		"size": 1.0 if _rng.randf() < 0.7 else 2.0, "color": EMBER_COLORS[_rng.randi() % EMBER_COLORS.size()]}

func _process(delta: float) -> void:
	var settings := get_node_or_null("/root/GameSettings")
	visible = not (settings != null and settings.reduce_motion)
	if not visible:
		flash = 0.0
		return
	if Engine.time_scale > 0.0:
		delta /= Engine.time_scale # real time, like the weather
	match mode:
		"storm": _storm(delta)
		"glitch": _glitch(delta)
		"embers":
			_rise(delta)
			if rockfall:
				_fall(delta)
	queue_redraw()

func _storm(delta: float) -> void:
	_waves(delta)
	if _strike_t >= 0.0:
		_strike_t += delta
		# a double flicker: bright, dark, bright again, fading
		var t := _strike_t
		flash = 0.5 if t < 0.06 else (0.05 if t < 0.11 else maxf(0.0, 0.35 * (1.0 - (t - 0.11) / (STRIKE_TIME - 0.11))))
		if _strike_t >= STRIKE_TIME:
			_strike_t = -1.0
			flash = 0.0
		return
	_next_strike -= delta
	if _next_strike <= 0.0:
		_next_strike = _rng.randf_range(STORM_GAP.x, STORM_GAP.y)
		_strike_t = 0.0
		_bolt = _make_bolt()

## Waves breaking over the spray edges: a burst of droplets thrown up and
## outward, falling back; bigger and higher nearer the camera.
func _waves(delta: float) -> void:
	for d in _spray:
		d["v"].y += SPRAY_GRAVITY * pixel * delta
		d["p"] += d["v"] * delta
		d["age"] += delta
	_spray = _spray.filter(func(d): return d["age"] < d["life"])
	if spray_edges.is_empty():
		return
	_next_spray -= delta
	if _next_spray > 0.0:
		return
	_next_spray = _rng.randf_range(SPRAY_GAP.x, SPRAY_GAP.y)
	var edge: Array = spray_edges[_rng.randi() % spray_edges.size()]
	var a: Vector2 = edge[0]
	var b: Vector2 = edge[1]
	var k := sqrt(_rng.randf()) # more of them nearer the camera, where the edge is longer
	var at := a.lerp(b, k)
	var outward := -1.0 if b.x < a.x else 1.0
	var power := lerpf(0.4, 1.3, k)
	for i in range(_rng.randi_range(14, 26)):
		_spray.append({"p": at + Vector2(_rng.randf_range(-6.0, 6.0) * pixel * power, 0.0),
			"v": Vector2(outward * _rng.randf_range(-10.0, 45.0), -_rng.randf_range(60.0, 150.0)) * pixel * power,
			"age": 0.0, "life": _rng.randf_range(0.55, 1.0), "size": 1.0 if _rng.randf() < 0.6 else 2.0,
			"color": SPRAY_COLORS[_rng.randi() % SPRAY_COLORS.size()]})

## A jagged fork from the top of the sky down toward the horizon.
func _make_bolt() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var x := _rng.randf_range(size.x * 0.1, size.x * 0.9)
	var y := 0.0
	var bottom := maxf(ground_y * _rng.randf_range(0.6, 0.95), size.y * 0.2)
	pts.append(Vector2(x, y))
	while y < bottom:
		y += pixel * _rng.randf_range(4.0, 10.0)
		x += pixel * _rng.randf_range(-6.0, 6.0)
		pts.append(Vector2(x, minf(y, bottom)))
	return pts

func _glitch(delta: float) -> void:
	_glitch_acc += delta * GLITCH_RATE
	while _glitch_acc >= 1.0:
		_glitch_acc -= 1.0
		var band := _rng.randf() < 0.18 # now and then a whole torn scanline
		var w := size.x if band else pixel * _rng.randf_range(6.0, 40.0)
		var h := pixel * (_rng.randf_range(1.0, 2.0) if band else _rng.randf_range(1.0, 5.0))
		_blocks.append({"rect": Rect2(0.0 if band else _rng.randf_range(0.0, size.x - w), _rng.randf_range(0.0, size.y), w, h),
			"color": GLITCH_COLORS[_rng.randi() % GLITCH_COLORS.size()], "life": _rng.randf_range(0.06, 0.22), "age": 0.0, "band": band})
	for b in _blocks:
		b["age"] += delta
	_blocks = _blocks.filter(func(b): return b["age"] < b["life"])

func _rise(delta: float) -> void:
	for i in range(_embers.size()):
		var e := _embers[i]
		e["y"] -= e["speed"] * delta
		e["phase"] += delta * 2.0
		e["x"] += sin(e["phase"]) * pixel * 6.0 * delta
		if e["y"] < size.y * 0.15:
			_embers[i] = _new_ember()

func _fall(delta: float) -> void:
	for r in _rocks:
		r["v"] += SPRAY_GRAVITY * pixel * delta
		r["y"] += r["v"] * delta
		r["x"] += float(r.get("drift", 0.0)) * delta # off a cliff, it tumbles out toward the middle
	for r in _rocks.filter(func(r): return r["y"] >= r["land"]):
		for i in range(_rng.randi_range(8, 14)): # it bursts into dust
			_dust.append({"p": Vector2(r["x"], r["land"]), "v": Vector2(_rng.randf_range(-40.0, 40.0), -_rng.randf_range(5.0, 30.0)) * pixel,
				"age": 0.0, "life": _rng.randf_range(0.4, 0.9), "size": 1.0 if _rng.randf() < 0.5 else 2.0})
	_rocks = _rocks.filter(func(r): return r["y"] < r["land"])
	for d in _dust:
		d["p"] += d["v"] * delta
		d["v"] *= 0.92
		d["age"] += delta
	_dust = _dust.filter(func(d): return d["age"] < d["life"])
	_next_rock -= delta
	if _next_rock <= 0.0:
		_next_rock = _rng.randf_range(ROCK_GAP.x, ROCK_GAP.y)
		var x := _rng.randf_range(size.x * 0.1, size.x * 0.9)
		var y := -pixel * 4.0
		if not rock_edges.is_empty():
			var e: Array = rock_edges[_rng.randi() % rock_edges.size()]
			x = _rng.randf_range(float(e[0]), float(e[1]))
			y = float(e[2])
		var land := _rng.randf_range(maxf(ground_y, y + pixel * 20.0), size.y * 0.9)
		_rocks.append({"x": x, "y": y, "v": 0.0, "land": land, "drift": (size.x * 0.5 - x) * 0.25,
			"size": float(_rng.randi_range(2, 4)), "color": ROCK_COLORS[_rng.randi() % ROCK_COLORS.size()]})

func _draw() -> void:
	match mode:
		"storm":
			for d in _spray:
				var fade := 1.0 - float(d["age"]) / float(d["life"])
				var c: Color = d["color"]
				var s: float = float(d["size"]) * pixel
				draw_rect(Rect2(_snap(d["p"]), Vector2(s, s)), Color(c, c.a * fade))
			if _strike_t >= 0.0 and _bolt.size() > 1:
				var a := clampf(1.0 - _strike_t / STRIKE_TIME, 0.0, 1.0)
				var snapped := PackedVector2Array()
				for p in _bolt:
					snapped.append(_snap(p))
				draw_polyline(snapped, Color(BOLT_COLOR, BOLT_COLOR.a * a), pixel * 2.0)
				draw_polyline(snapped, Color(0.5, 0.6, 1.0, 0.35 * a), pixel * 5.0)
		"glitch":
			for b in _blocks:
				var c: Color = b["color"]
				var fade := 1.0 - float(b["age"]) / float(b["life"])
				var r: Rect2 = b["rect"]
				draw_rect(Rect2(_snap(r.position), r.size), Color(c, c.a * fade * (0.5 if b["band"] else 1.0)))
		"embers":
			for r in _rocks:
				var sz: float = float(r["size"]) * pixel
				var c: Color = r["color"]
				draw_rect(Rect2(_snap(Vector2(r["x"], r["y"])), Vector2(sz, sz)), c)
				draw_rect(Rect2(_snap(Vector2(r["x"], r["y"])), Vector2(sz, pixel)), c.lightened(0.25)) # its lit top
			for d in _dust:
				var fade := 1.0 - float(d["age"]) / float(d["life"])
				var ds: float = float(d["size"]) * pixel
				draw_rect(Rect2(_snap(d["p"]), Vector2(ds, ds)), Color(DUST_COLOR, DUST_COLOR.a * fade))
			for e in _embers:
				var top := size.y * 0.15
				var fade := clampf((float(e["y"]) - top) / maxf(size.y * 0.4, 1.0), 0.0, 1.0)
				var flicker := 0.7 + 0.3 * sin(float(e["phase"]) * 5.0)
				var c: Color = e["color"]
				var s: float = float(e["size"]) * pixel
				draw_rect(Rect2(_snap(Vector2(e["x"], e["y"])), Vector2(s, s)), Color(c, fade * flicker))

func _snap(p: Vector2) -> Vector2:
	return (p / pixel).floor() * pixel

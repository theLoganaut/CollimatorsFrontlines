class_name LavaFlow
extends Control
## Lava for a boss's phase 2 (backgrounds.json `lava`, drawn by PlayField over
## the image, under the weather; Logan, 2026-11-20). Each flow follows its
## `path` ([x, y] fractions of the image, from the crack it bursts out of
## down to where it drains): when phase 2 hits it erupts in a fountain, a
## molten stream runs down the path, and it pools where it ends and sinks
## into the ground there, crusting dark round the edge and steaming. Then it
## keeps flowing, its bright core rippling downhill, sputtering now and then.
## Everything snaps to the background's pixel size. Reduce motion: it's
## there, fully formed and still, with no fountains or steam.

const FLOW_SPEED := 38.0      # art px/s the stream's front runs downhill
const RIPPLE_SPEED := 9.0     # art px/s the bright core ripples down it
const POOL_TIME := 1.6        # seconds a pool takes to spread
const GRAVITY := 240.0        # art px/s² for the fountain's blobs
const SPUTTER_GAP := Vector2(1.8, 4.0)
const CORE := Color(1.0, 0.92, 0.55)
const HOT := Color(1.0, 0.58, 0.16)
const RED := Color(0.85, 0.24, 0.08)
const CRUST := Color(0.3, 0.1, 0.06)
const STEAM := Color(0.75, 0.68, 0.62, 0.45)

## One art pixel on screen.
var pixel: float = 2.0
var _flows: Array[Dictionary] = []
var _t: float = -1.0 # seconds since it erupted (-1: not yet)
var _still: bool = false
var _blobs: Array[Dictionary] = []
var _steam: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _glow: Control = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	_glow = Control.new()
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = add
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	_glow.show_behind_parent = true

## The flows from backgrounds.json `lava`, placed on `image` (the
## background's rect on screen).
func setup(flows: Array, image: Rect2, p_pixel: float) -> void:
	pixel = maxf(1.0, p_pixel)
	_glow.size = size
	var keep_t := _t
	_flows.clear()
	for f in flows:
		var pts: Array[Vector2] = []
		for p in f.get("path", []):
			pts.append(image.position + Vector2(p[0], p[1]) * image.size)
		if pts.size() < 2:
			continue
		# a point every art pixel along the path, with how far down it is
		var samples: Array[Dictionary] = []
		var dist := 0.0
		for i in range(pts.size() - 1):
			var a := pts[i]
			var b := pts[i + 1]
			var steps := maxi(1, int(a.distance_to(b) / pixel))
			var across := (b - a).normalized().orthogonal().abs() # the stream's width lies across its run
			across = Vector2(1, 0) if across.x >= across.y else Vector2(0, 1)
			for k in range(steps):
				samples.append({"p": a.lerp(b, float(k) / steps), "d": dist + a.distance_to(b) * float(k) / steps, "n": across})
			dist += a.distance_to(b)
		samples.append({"p": pts[-1], "d": dist, "n": Vector2(1, 0)})
		_flows.append({"samples": samples, "length": dist, "width": float(f.get("width", 4.0)),
			"pool": float(f.get("pool", 10.0)), "delay": float(f.get("delay", 0.0)), "next_sputter": 2.0})
	_t = keep_t

## Phase 2: it erupts now (animated), or is simply there.
func erupt(animate: bool) -> void:
	if _t >= 0.0:
		return
	_t = 0.0
	if not animate:
		_t = 60.0 # long since spread
		return
	for f in _flows:
		f["burst"] = true

func _process(delta: float) -> void:
	if _t < 0.0:
		return
	var settings := get_node_or_null("/root/GameSettings")
	_still = settings != null and settings.reduce_motion
	if Engine.time_scale > 0.0:
		delta /= Engine.time_scale
	if _still:
		_t = maxf(_t, 60.0)
		_blobs.clear()
		_steam.clear()
	else:
		_t += delta
		for f in _flows:
			var since: float = _t - float(f["delay"])
			if since < 0.0:
				continue
			if f.get("burst", false):
				f["burst"] = false
				_fountain(f, _rng.randi_range(36, 50), 1.0)
			f["next_sputter"] = float(f["next_sputter"]) - delta
			if float(f["next_sputter"]) <= 0.0 and since > 2.0:
				f["next_sputter"] = _rng.randf_range(SPUTTER_GAP.x, SPUTTER_GAP.y)
				_fountain(f, _rng.randi_range(5, 10), 0.5)
			if _pool_size(f) > 0.3 and _rng.randf() < delta * 3.0:
				var end: Vector2 = (f["samples"] as Array)[-1]["p"]
				_steam.append({"p": end + Vector2(_rng.randf_range(-1.0, 1.0) * _pool_size(f) * float(f["pool"]) * pixel, 0.0),
					"age": 0.0, "life": _rng.randf_range(1.2, 2.2), "size": 2.0 if _rng.randf() < 0.5 else 3.0})
		for b in _blobs:
			b["v"].y += GRAVITY * pixel * delta
			b["p"] += b["v"] * delta
			b["age"] += delta
		_blobs = _blobs.filter(func(b): return b["age"] < b["life"])
		for s in _steam:
			s["p"] += Vector2(sin(float(s["age"]) * 2.0) * 3.0, -10.0) * pixel * delta
			s["age"] += delta
		_steam = _steam.filter(func(s): return s["age"] < s["life"])
	queue_redraw()
	_glow.queue_redraw()

## Blobs of lava thrown up out of the crack.
func _fountain(f: Dictionary, n: int, power: float) -> void:
	var at: Vector2 = (f["samples"] as Array)[0]["p"]
	for i in range(n):
		_blobs.append({"p": at, "v": Vector2(_rng.randf_range(-40.0, 40.0), -_rng.randf_range(50.0, 130.0) * power) * pixel,
			"age": 0.0, "life": _rng.randf_range(0.7, 1.4), "size": float(_rng.randi_range(1, 3))})

## How far down the stream's front has run (art distance on screen).
func _front(f: Dictionary) -> float:
	var since: float = _t - float(f["delay"]) - 0.25 # the fountain first
	return clampf(since * FLOW_SPEED * pixel, 0.0, float(f["length"]))

## How spread its pool is, 0..1 (it starts once the front reaches the end).
func _pool_size(f: Dictionary) -> float:
	var reach := float(f["length"]) / (FLOW_SPEED * pixel) + 0.25 + float(f["delay"])
	return clampf((_t - reach) / POOL_TIME, 0.0, 1.0)

## The lava's colour at a point: crust at the edge, then red, orange and the
## bright core, which ripples downhill.
func _heat(d: float, across: float) -> Color:
	var ripple := 0.5 + 0.5 * sin((d / pixel - _t * RIPPLE_SPEED) * 0.45) * sin((d / pixel - _t * RIPPLE_SPEED * 0.6) * 0.17 + 1.3)
	if across >= 0.99:
		return CRUST if ripple < 0.6 else RED # the cooling edge
	var h := (1.0 - across * 0.7) * (0.55 + 0.5 * ripple)
	if h > 0.78:
		return CORE
	if h > 0.5:
		return HOT
	return RED

func _draw() -> void:
	if _t < 0.0:
		return
	for f in _flows:
		var front := _front(f)
		var length: float = f["length"]
		for s in f["samples"]:
			var d: float = s["d"]
			if d > front:
				break
			var down := d / maxf(length, 1.0)
			var w := float(f["width"]) * (0.75 + 0.5 * down)
			var half := floorf(w / 2.0)
			var at := _snap(s["p"])
			var n: Vector2 = s["n"]
			for k in range(-int(half), int(half) + 1):
				var across := absf(float(k)) / maxf(half, 1.0)
				draw_rect(Rect2(at + n * float(k) * pixel, Vector2(pixel, pixel)), _heat(d, across))
		# the leading edge glows brightest while it runs
		if front < length and front > 0.0:
			var tip := _snap(_sample_at(f, front))
			draw_rect(Rect2(tip - Vector2(pixel, pixel), Vector2(pixel * 3.0, pixel * 2.0)), CORE)
		_draw_pool(f)
		_draw_fissure(f)
	for b in _blobs:
		var k := float(b["age"]) / float(b["life"])
		var c := CORE.lerp(HOT, clampf(k * 2.0, 0.0, 1.0)).lerp(RED, clampf(k * 2.0 - 1.0, 0.0, 1.0))
		var sz := float(b["size"]) * pixel
		draw_rect(Rect2(_snap(b["p"]), Vector2(sz, sz)), c)
	for s in _steam:
		var fade := 1.0 - float(s["age"]) / float(s["life"])
		var sz := float(s["size"]) * pixel
		draw_rect(Rect2(_snap(s["p"]), Vector2(sz, sz)), Color(STEAM, STEAM.a * fade))

## The pool it drains into: a flat ellipse, crusting dark at its rim (sinking
## into the ground), molten in the middle with bright patches drifting.
func _draw_pool(f: Dictionary) -> void:
	var grow := _pool_size(f)
	if grow <= 0.0:
		return
	var end: Vector2 = _snap((f["samples"] as Array)[-1]["p"])
	var rx := maxf(1.0, float(f["pool"]) * grow)
	var ry := maxf(1.0, rx * 0.35)
	for row in range(-int(ry), int(ry) + 1):
		var span := int(rx * sqrt(maxf(0.0, 1.0 - pow(float(row) / ry, 2.0))))
		for col in range(-span, span + 1):
			var r := sqrt(pow(float(col) / rx, 2.0) + pow(float(row) / ry, 2.0))
			var swirl := 0.5 + 0.5 * sin(float(col) * 0.6 + _t * 2.2) * sin(float(row) * 1.3 - _t * 1.4)
			var c := CRUST if r > 0.85 else (RED if r > 0.65 else (CORE if swirl > 0.75 and r < 0.5 else HOT))
			draw_rect(Rect2(end + Vector2(col, row) * pixel, Vector2(pixel, pixel)), c)

## The crack it bursts out of: a jagged split in the rock, glowing.
func _draw_fissure(f: Dictionary) -> void:
	var since: float = _t - float(f["delay"])
	if since < 0.0:
		return
	var open := clampf(since / 0.3, 0.0, 1.0)
	var at := _snap((f["samples"] as Array)[0]["p"])
	var half := int(float(f["width"]) * 1.2 * open)
	for k in range(-half, half + 1):
		var jag := float(int(absf(sin(float(k) * 1.7)) * 2.0)) # a ragged edge
		var c := CORE if absf(float(k)) < half * 0.4 else (HOT if absf(float(k)) < half * 0.75 else CRUST)
		draw_rect(Rect2(at + Vector2(float(k), -jag) * pixel, Vector2(pixel, pixel * (1.0 + jag))), c)

func _draw_glow() -> void:
	if _t < 0.0:
		return
	var tex := Lamps._glow_texture()
	for f in _flows:
		var front := _front(f)
		var pulse := 0.85 + 0.15 * sin(_t * 2.3 + float(f["delay"]) * 3.0)
		var step := 6
		var samples: Array = f["samples"]
		for i in range(0, samples.size(), step):
			if float(samples[i]["d"]) > front:
				break
			var r := float(f["width"]) * pixel * 7.0
			_glow.draw_texture_rect_region(tex, Rect2(samples[i]["p"] - Vector2(r, r) / 2.0, Vector2(r, r)), Rect2(0, 0, 64, 64), Color(1.0, 0.4, 0.1, 0.14 * pulse))
		var grow := _pool_size(f)
		if grow > 0.0:
			var end: Vector2 = samples[-1]["p"]
			var pr := float(f["pool"]) * pixel * 6.0 * grow
			_glow.draw_texture_rect_region(tex, Rect2(end - Vector2(pr, pr * 0.6) / 2.0, Vector2(pr, pr * 0.6)), Rect2(0, 0, 64, 64), Color(1.0, 0.45, 0.12, 0.35 * pulse))

func _sample_at(f: Dictionary, d: float) -> Vector2:
	for s in f["samples"]:
		if float(s["d"]) >= d:
			return s["p"]
	return (f["samples"] as Array)[-1]["p"]

func _snap(p: Vector2) -> Vector2:
	return (p / pixel).floor() * pixel

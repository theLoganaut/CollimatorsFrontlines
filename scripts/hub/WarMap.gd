class_name WarMap
extends RefCounted
## The theater of war on the War Table, generated from a seed
## (Profile.sector_seed, so it changes whenever the sectors reroll). A
## heightmap of hills, a coast on one side, mountains on the other flank and
## a river behind our lines, then the war drawn on it: the front line, our
## HQ, both sides' units, and each location placed by its `map_zone` in
## data/sectors.json ("coast": on the shore, "flank": in the mountain
## foothills, cut into an open-pit mine; "backline": on a mesa far behind the
## enemy's front). Everything is in map UV: u 0..1 left to right, v 0..1 from
## the far (enemy) edge to the near (our) edge. SectorMapView renders it.

const GRID := Vector2i(132, 77)   # heightmap vertices (x, z)
const SIZE := Vector2(12.0, 7.0)  # world units; one grid square per unit
const RELIEF := 1.5               # world height of the tallest ground
const SEA_DEPTH := 0.12
const CONTOUR := RELIEF / 20.0    # height between the hologram's contour lines

var seed_value: int = 0
var grid := GRID                      # this map's heightmap vertices
var dims := SIZE                      # and its size in world units
var coast_base: float = 0.15          # how far the sea reaches in (a _side() value)
var heights := PackedFloat32Array()   # per vertex, world units; below 0 is water
var territory := PackedFloat32Array() # per vertex, 0 hostile .. 1 ours
var sea_left: bool = true
var front := PackedVector2Array()     # the front line, sea to far flank
var river := PackedVector2Array()
var sites: Dictionary = {}            # location id -> uv
var hq: Vector2 = Vector2(0.5, 0.9)
var routes: Dictionary = {}           # location id -> PackedVector2Array (HQ to site)
var units: Array = []                 # {uv, hostile, kind}

var rugged: float = 1.0               # how mountainous this theater is
var has_river: bool = true
var _river_v := Vector2.ZERO # the v band the river's valley can reach
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _ridge := FastNoiseLite.new()
var _coast_noise := FastNoiseLite.new()

static func generate(p_seed: int, locations: Array) -> WarMap:
	var m := WarMap.new()
	m._build(p_seed, locations)
	return m

## Just the ground of one location, for its route map (LocationMapScreen):
## `p_dims` in size, with the look of its `map_zone` ("coast": a strip of
## sea on one side; "flank": rugged, with open-pit mines; "backline":
## mesas). No front, units or sites; it all reads as one colour.
static func location_terrain(p_seed: int, zone: String, p_dims: Vector2) -> WarMap:
	var m := WarMap.new()
	m.dims = p_dims
	m.grid = Vector2i(int(p_dims.x * 11.0) + 1, int(p_dims.y * 11.0) + 1)
	m._seed_noise(p_seed)
	m.sea_left = m._rng.randf() < 0.5
	m.coast_base = 0.05 if zone == "coast" else -1.0
	m.rugged = {"flank": 1.4, "backline": 1.0}.get(zone, 0.8)
	m.has_river = m._rng.randf() < 0.5
	m.front = PackedVector2Array([Vector2(0, -1), Vector2(1, -1)])
	m._make_river()
	m._make_heights([])
	match zone:
		"flank":
			for i in 3:
				m._open_pit(Vector2(m._rng.randf_range(0.15, 0.85), m._rng.randf_range(0.1, 0.9)))
		"backline":
			for i in 3:
				var uv := Vector2(m._rng.randf_range(0.15, 0.85), m._rng.randf_range(0.1, 0.9))
				m._flatten(uv, 0.7, _between_contours(maxf(m.height_at(uv), 0.4 * RELIEF)))
	m.territory.resize(m.grid.x * m.grid.y)
	m.territory.fill(1.0)
	return m

func _seed_noise(p_seed: int) -> void:
	seed_value = p_seed
	_rng.seed = p_seed
	for n in [_noise, _ridge, _coast_noise]:
		n.seed = _rng.randi()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 5
	_noise.frequency = 0.23
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge.fractal_octaves = 4
	_ridge.frequency = 0.2
	_coast_noise.frequency = 0.5

func _build(p_seed: int, locations: Array) -> void:
	_seed_noise(p_seed)
	sea_left = _rng.randf() < 0.5
	rugged = _rng.randf_range(0.65, 1.3)
	has_river = _rng.randf() < 0.75
	_place_sites(locations)
	_make_front()
	_make_river()
	_make_heights(locations)
	_make_territory()
	_make_routes()
	_make_units()

# ---------- helpers ----------

## Distance from the sea's map edge, in u (0 at that edge, 1 at the far flank).
func _side(u: float) -> float:
	return u if sea_left else 1.0 - u

func _from_side(s: float) -> float:
	return s if sea_left else 1.0 - s

## Where the shore is at depth v, as a _side() value.
func coast_at(v: float) -> float:
	return coast_base + 0.045 * _coast_noise.get_noise_1d(v * 9.0) + 0.03 * sin(v * 5.0 + float(seed_value % 7))

## The front line's v at u.
func front_at(u: float) -> float:
	for i in range(front.size() - 1):
		var a := front[i]
		var b := front[i + 1]
		if (u >= a.x and u <= b.x) or (u <= a.x and u >= b.x):
			return lerpf(a.y, b.y, 0.0 if a.x == b.x else (u - a.x) / (b.x - a.x))
	return front[0].y if front.size() > 0 else 0.6

## A UV (and height) as a point in the hologram's world.
func world(uv: Vector2, h: float = 0.0) -> Vector3:
	return Vector3((uv.x - 0.5) * dims.x, h, (uv.y - 0.5) * dims.y)

## Ground height (world units, water clamped to 0) at a UV, bilinear.
func height_at(uv: Vector2) -> float:
	var g := Vector2(clampf(uv.x, 0.0, 1.0) * (grid.x - 1), clampf(uv.y, 0.0, 1.0) * (grid.y - 1))
	var x0 := mini(int(g.x), grid.x - 2)
	var y0 := mini(int(g.y), grid.y - 2)
	var f := g - Vector2(x0, y0)
	var h00 := heights[y0 * grid.x + x0]
	var h10 := heights[y0 * grid.x + x0 + 1]
	var h01 := heights[(y0 + 1) * grid.x + x0]
	var h11 := heights[(y0 + 1) * grid.x + x0 + 1]
	return maxf(0.0, lerpf(lerpf(h00, h10, f.x), lerpf(h01, h11, f.x), f.y))

## True when the UV is on water (sea or river).
func is_water(uv: Vector2) -> bool:
	var g := Vector2i(roundi(clampf(uv.x, 0.0, 1.0) * (grid.x - 1)), roundi(clampf(uv.y, 0.0, 1.0) * (grid.y - 1)))
	return heights[g.y * grid.x + g.x] < 0.0

## A military grid reference for a UV: column letter A-L, row number 1-7.
static func grid_ref(uv: Vector2) -> String:
	var col := clampi(int(uv.x * SIZE.x), 0, int(SIZE.x) - 1)
	var row := clampi(int(uv.y * SIZE.y), 0, int(SIZE.y) - 1)
	return "%s%d" % [char(65 + col), row + 1]

## Distance between UVs in world units (the map is wider than deep).
func _dist(a: Vector2, b: Vector2) -> float:
	return ((a - b) * dims).length()

# ---------- generation ----------

func _place_sites(locations: Array) -> void:
	hq = Vector2(_from_side(0.5 + _rng.randf_range(-0.04, 0.12)), 0.9)
	var taken: Array[Vector2] = []
	for loc in locations:
		var uv: Vector2
		match str(loc.get("map_zone", "")):
			"coast":
				var v := _rng.randf_range(0.36, 0.5)
				uv = Vector2(_from_side(coast_at(v) + 0.045), v)
			"flank":
				uv = Vector2(_from_side(_rng.randf_range(0.8, 0.86)), _rng.randf_range(0.34, 0.5))
			"backline":
				uv = Vector2(_from_side(_rng.randf_range(0.42, 0.6)), _rng.randf_range(0.1, 0.15))
			_:
				uv = _free_spot(taken)
		taken.append(uv)
		sites[loc["id"]] = uv

func _free_spot(taken: Array[Vector2]) -> Vector2:
	var best := Vector2(0.5, 0.3)
	var best_d := -1.0
	for i in 24:
		var uv := Vector2(_from_side(_rng.randf_range(0.35, 0.9)), _rng.randf_range(0.12, 0.5))
		var d := 99.0
		for t in taken:
			d = minf(d, _dist(uv, t))
		if d > best_d:
			best = uv
			best_d = d
	return best

## The front: a wandering line across the map with every site behind it
## (hostile side) and our HQ in front of it.
func _make_front() -> void:
	var deepest := 0.0
	for uv in sites.values():
		deepest = maxf(deepest, (uv as Vector2).y)
	var base := clampf(deepest + 0.1, 0.56, 0.66)
	var phase := _rng.randf() * TAU
	var steps := 24
	var start := coast_at(base) - 0.02
	for i in range(steps + 1):
		var s := lerpf(start, 1.0, float(i) / steps)
		var v := base + 0.035 * sin(s * 9.0 + phase) + 0.02 * _coast_noise.get_noise_1d(s * 30.0 + 100.0)
		front.append(Vector2(_from_side(s), clampf(v, deepest + 0.05, 0.74)))
	if not sea_left:
		front.reverse()

## A river out of the mountain flank, behind our side of the front, to the sea.
func _make_river() -> void:
	if not has_river:
		return
	var fu := front_at(_from_side(0.6))
	var src := Vector2(_from_side(1.02), clampf(fu + _rng.randf_range(0.08, 0.13), 0.66, 0.8))
	var mouth_v := clampf(src.y + _rng.randf_range(-0.02, 0.07), 0.7, 0.84)
	var mouth := Vector2(_from_side(coast_at(mouth_v) - 0.04), mouth_v)
	var steps := 40
	var phase := _rng.randf() * TAU
	for i in range(steps + 1):
		var t := float(i) / steps
		var p := src.lerp(mouth, t)
		p.y += 0.035 * sin(t * 11.0 + phase) * sin(t * PI) + 0.012 * _coast_noise.get_noise_1d(t * 40.0 + 300.0)
		river.append(p)
	_river_v = Vector2(99.0, -99.0)
	for p in river:
		_river_v = Vector2(minf(_river_v.x, p.y - 0.08), maxf(_river_v.y, p.y + 0.08))

func _poly_dist(p: Vector2, line: PackedVector2Array) -> float:
	var best := 99.0
	for i in range(line.size() - 1):
		var a := line[i] * dims
		var b := line[i + 1] * dims
		best = minf(best, (p * dims).distance_to(Geometry2D.get_closest_point_to_segment(p * dims, a, b)))
	return best

func _make_heights(locations: Array) -> void:
	heights.resize(grid.x * grid.y)
	var zone := {}
	for loc in locations:
		zone[loc["id"]] = str(loc.get("map_zone", ""))
	for gy in range(grid.y):
		for gx in range(grid.x):
			var uv := Vector2(float(gx) / (grid.x - 1), float(gy) / (grid.y - 1))
			var w := uv * dims
			var s := _side(uv.x)
			var fbm := 0.5 + 0.5 * _noise.get_noise_2d(w.x, w.y)
			var ridge := 0.5 + 0.5 * _ridge.get_noise_2d(w.x + 40.0, w.y)
			var mountains := smoothstep(0.5, 0.95, s) * (1.0 - smoothstep(0.55, 0.9, uv.y) * 0.7)
			var backline := 1.0 - smoothstep(0.0, 0.35, uv.y)
			var h := 0.1 + 0.32 * fbm + (mountains * 0.62 * ridge * ridge + backline * 0.15 * ridge) * rugged
			h *= RELIEF
			# the coast: land sinks into the sea past the shore, with a few islands
			var shore := s - coast_at(uv.y)
			if shore < 0.06:
				var t := smoothstep(-0.05, 0.06, shore)
				h = lerpf(-SEA_DEPTH, h * t + 0.02, t)
				var isle := _coast_noise.get_noise_2d(w.x * 2.2 + 70.0, w.y * 2.2) - 0.35
				if isle > 0.0 and shore < -0.06:
					h = maxf(h, -SEA_DEPTH + isle * 2.2 * RELIEF * 0.35)
			# the river's channel
			if has_river and shore > -0.02 and uv.y > _river_v.x and uv.y < _river_v.y:
				h = lerpf(-0.025, h, smoothstep(0.04, 0.65, _poly_dist(uv, river)))
			heights[gy * grid.x + gx] = h
	# ground works at each site and HQ
	_flatten(hq, 0.45, _between_contours(height_at(hq)))
	for id in sites.keys():
		var uv: Vector2 = sites[id]
		match zone.get(id, ""):
			"coast":
				_flatten(uv, 0.5, 0.035)
			"flank":
				_open_pit(uv)
			"backline":
				_flatten(uv, 0.55, _between_contours(maxf(height_at(uv), 0.42 * RELIEF)))
			_:
				_flatten(uv, 0.4, height_at(uv))

## A flat level halfway between two contour lines (a flat top on a line
## would light up whole).
static func _between_contours(h: float) -> float:
	return floorf(h / CONTOUR) * CONTOUR + CONTOUR * 0.5

## Levels the ground to `level` within `radius` world units, easing out.
func _flatten(center: Vector2, radius: float, level: float) -> void:
	for gy in range(grid.y):
		for gx in range(grid.x):
			var uv := Vector2(float(gx) / (grid.x - 1), float(gy) / (grid.y - 1))
			var d := _dist(uv, center)
			if d < radius * 1.8:
				var i := gy * grid.x + gx
				if heights[i] < 0.0 and d > radius:
					continue # leave the water beside a shore site
				heights[i] = lerpf(level, heights[i], smoothstep(radius, radius * 1.8, d))

## An open-pit mine: terraces stepping down into a bowl.
func _open_pit(center: Vector2) -> void:
	const R := 0.62
	const STEPS := 4
	var rim := _between_contours(clampf(height_at(center), 0.3 * RELIEF, 0.55 * RELIEF))
	var step_h := CONTOUR # 4 benches from a rim at least 0.3 RELIEF stay above water
	for gy in range(grid.y):
		for gx in range(grid.x):
			var uv := Vector2(float(gx) / (grid.x - 1), float(gy) / (grid.y - 1))
			var d := _dist(uv, center) / R
			if d >= 1.5:
				continue
			var i := gy * grid.x + gx
			if d >= 1.0:
				heights[i] = lerpf(rim, heights[i], smoothstep(1.0, 1.5, d))
				continue
			var k := d * STEPS
			var level := floorf(k)
			var ramp := smoothstep(0.75, 1.0, k - level) # a short ramp up each bench
			heights[i] = rim - (STEPS - level - ramp) * step_h

func _make_territory() -> void:
	territory.resize(grid.x * grid.y)
	for gy in range(grid.y):
		for gx in range(grid.x):
			var uv := Vector2(float(gx) / (grid.x - 1), float(gy) / (grid.y - 1))
			territory[gy * grid.x + gx] = smoothstep(-0.015, 0.015, uv.y - front_at(uv.x))

## A route from HQ to each site: a gentle curve.
func _make_routes() -> void:
	for id in sites.keys():
		var to: Vector2 = sites[id]
		var mid := (hq + to) / 2.0
		var n := Vector2(-(to - hq).y, (to - hq).x).normalized()
		var ctrl := mid + n * _rng.randf_range(-0.08, 0.08)
		var pts := PackedVector2Array()
		for i in range(33):
			var t := float(i) / 32.0
			pts.append(hq.lerp(ctrl, t).lerp(ctrl.lerp(to, t), t))
		routes[id] = pts

## Units along the front: theirs just behind it, ours just in front of it.
func _make_units() -> void:
	var kinds := ["mech", "armor", "artillery"]
	for hostile in [true, false]:
		var n := 7 if hostile else 6
		for i in range(n):
			for attempt in 8:
				var s := lerpf(coast_at(0.6) + 0.06, 0.96, (float(i) + _rng.randf_range(0.2, 0.8)) / n)
				var u := _from_side(s)
				var f := front_at(u)
				var v := f - _rng.randf_range(0.05, 0.13) if hostile else f + _rng.randf_range(0.04, 0.09)
				var uv := Vector2(u, v)
				if _wet(uv) or _near_site(uv, 0.7):
					continue
				units.append({"uv": uv, "hostile": hostile, "kind": kinds[_rng.randi() % kinds.size()]})
				break

## Water at or right beside a UV.
func _wet(uv: Vector2) -> bool:
	for d in [Vector2.ZERO, Vector2(0.012, 0), Vector2(-0.012, 0), Vector2(0, 0.02), Vector2(0, -0.02)]:
		if is_water(uv + d):
			return true
	return false

func _near_site(uv: Vector2, r: float) -> bool:
	if _dist(uv, hq) < r:
		return true
	for s in sites.values():
		if _dist(uv, s) < r:
			return true
	return false

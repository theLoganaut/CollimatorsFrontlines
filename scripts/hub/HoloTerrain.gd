class_name HoloTerrain
extends Control
## A WarMap's ground as a live 3D hologram (the War Table's theater, a
## location's route map). The heightmap is a mesh in its own SubViewport
## (contour lines, grid squares, teal or red ground by `territory`, water,
## a cut-away plate edge) composited additively over whatever is behind, so
## it reads as projected light. The camera fits the plate into this control
## minus the insets and turns a little with the mouse. proj() turns map UVs
## into this control's coordinates, so callers draw their markers on top.
## project_in() sweeps the terrain in and raises it.

const HOLO := Palette.REACTOR
const WATER := Color("2f7fd0")
const FOV := 30.0
const PLATE_DEPTH := 0.32      # the cut-away edge below sea level

const TERRAIN_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float rise = 1.0;
uniform float reveal = 1.0;
uniform float t = 0.0;
uniform vec3 ours : source_color;
uniform vec3 theirs : source_color;
uniform float contour = 0.07;
uniform float relief = 0.95;
varying float h;
varying vec3 w;
varying float terr;
varying vec2 muv;
float grid_line(float x, float width) {
	float fw = max(fwidth(x), 1e-4);
	float d = abs(fract(x - 0.5) - 0.5);
	return 1.0 - smoothstep(fw * width * 0.5, fw * (width * 0.5 + 1.0), d);
}
void vertex() {
	h = VERTEX.y;
	VERTEX.y *= rise;
	w = VERTEX;
	terr = COLOR.r;
	muv = UV;
}
void fragment() {
	vec3 base = mix(theirs, ours, terr);
	float hn = clamp(h / relief, 0.0, 1.0);
	vec3 n = normalize(cross(dFdx(w), dFdy(w)));
	float light = abs(dot(n, normalize(vec3(-0.72, 0.6, 0.42))));
	float minor = grid_line(h / contour, 1.0);
	float major = grid_line(h / (contour * 5.0), 1.8);
	float shore = 1.0 - smoothstep(0.0, 0.035, h);
	float grid = max(grid_line(w.x, 0.8), grid_line(w.z, 0.8));
	float sweep = exp(-pow((muv.x - fract(t * 0.06) * 1.3 + 0.15) * 12.0, 2.0));
	vec3 col = base * (0.012 + 0.09 * hn) * (0.2 + 1.3 * light * light);
	col += base * (minor * (0.22 + 0.25 * hn) + major * 0.5);
	col += vec3(0.55, 0.85, 1.0) * shore * 0.4;
	col += ours * grid * 0.09;
	col += base * sweep * 0.14;
	float edge = (1.0 - muv.y) - reveal * 1.15 + 0.1;
	col *= 1.0 - smoothstep(-0.06, 0.0, edge);
	col += base * exp(-pow(edge * 40.0, 2.0)) * 0.8 * step(reveal, 0.99);
	ALBEDO = col;
}
"""

const WATER_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float reveal = 1.0;
uniform float t = 0.0;
uniform vec3 water : source_color;
varying vec3 w;
varying vec2 muv;
void vertex() {
	w = VERTEX;
	muv = UV;
}
void fragment() {
	float x = (w.z + 0.07 * sin(w.x * 2.3 + t * 0.9) + 0.04 * sin(w.x * 5.1 - t * 1.3)) / 0.16;
	float fw = max(fwidth(x), 1e-4);
	float ripple = 1.0 - smoothstep(fw * 0.4, fw * 1.4, abs(fract(x - 0.5) - 0.5));
	float shimmer = 0.5 + 0.5 * sin(w.x * 1.7 + w.z * 2.9 + t * 1.6);
	vec3 col = water * (0.07 + ripple * (0.08 + 0.1 * shimmer));
	float edge = (1.0 - muv.y) - reveal * 1.15 + 0.1;
	ALBEDO = col * (1.0 - smoothstep(-0.06, 0.0, edge));
}
"""

const PLATE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float rise = 1.0;
uniform float reveal = 1.0;
uniform vec3 ours : source_color;
uniform float contour = 0.07;
varying vec3 w;
varying float along;
float band(float x, float width) {
	float fw = max(fwidth(x), 1e-4);
	float d = abs(fract(x - 0.5) - 0.5);
	return 1.0 - smoothstep(fw * width * 0.5, fw * (width * 0.5 + 1.0), d);
}
void vertex() {
	if (UV.y < 0.5) {
		VERTEX.y *= rise;
	}
	w = VERTEX;
	along = UV.x;
}
void fragment() {
	float fw = max(fwidth(UV.y), 1e-4);
	float top = 1.0 - smoothstep(fw, fw * 2.5, UV.y);
	float bottom = 1.0 - smoothstep(fw, fw * 2.5, 1.0 - UV.y);
	vec3 col = ours * (0.03 + 0.07 * (1.0 - UV.y));
	col += ours * band(w.y / contour, 0.8) * 0.12;
	col += ours * (top * 0.7 + bottom * 0.5);
	ALBEDO = col * clamp(reveal * 1.6, 0.0, 1.0);
}
"""

const COMPOSITE_SHADER := """
shader_type canvas_item;
render_mode blend_add;
uniform float t = 0.0;
uniform float fade = 1.0;
void fragment() {
	vec3 c = texture(TEXTURE, UV).rgb;
	float scan = 0.84 + 0.16 * sin(FRAGCOORD.y * 2.1 - t * 8.0);
	float flicker = 0.96 + 0.04 * sin(t * 43.0) * sin(t * 7.3);
	COLOR = vec4(c * scan * flicker * fade, 1.0);
}
"""

var map: WarMap
var pitch: float = 47.0        # camera elevation, degrees
var yaw_sway: float = 3.0      # degrees the view turns with the mouse
var inset_top: float = 70.0
var inset_bottom: float = 64.0
var inset_side: float = 24.0
var ours: Color = HOLO         # the terrain's colour where territory is 1
var hold_still: bool = false   # stop turning with the mouse (a pop-up is anchored)
var rise: float = 0.0
var reveal: float = 0.0
var inner: Rect2               # where the plate is fitted
var _time: float = 0.0
var _yaw: float = 0.0
var _render_k: float = 1.0
## The 3D pass renders at most RENDERS_PER_SECOND (profiled 2026-09-30: its
## SubViewport is ~3 ms of GPU a frame at retina scale, most of a 144 Hz
## frame; a slow hologram doesn't need more than 60). A 60 Hz display still
## renders it every frame.
const RENDERS_PER_SECOND := 60.0
var _since_render: float = 0.0

var _viewport: SubViewport
var _camera: Camera3D
var _pivot: Node3D
var _screen: TextureRect
var _terrain_mat: ShaderMaterial
var _water_mat: ShaderMaterial
var _plate_mat: ShaderMaterial
var _composite: ShaderMaterial

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_pivot = Node3D.new()
	_viewport.add_child(_pivot)
	_camera = Camera3D.new()
	_camera.fov = FOV
	_camera.environment = env
	_camera.current = true
	_pivot.add_child(_camera)
	_screen = TextureRect.new()
	_screen.texture = _viewport.get_texture()
	_screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_screen.stretch_mode = TextureRect.STRETCH_SCALE
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_composite = ShaderMaterial.new()
	_composite.shader = _shader(COMPOSITE_SHADER)
	_screen.material = _composite
	add_child(_screen)
	resized.connect(_layout)
	visibility_changed.connect(func():
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if is_visible_in_tree() else SubViewport.UPDATE_DISABLED)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if is_visible_in_tree() else SubViewport.UPDATE_DISABLED

static func _shader(code: String) -> Shader:
	var s := Shader.new()
	s.code = code
	return s

func setup(p_map: WarMap) -> void:
	map = p_map
	_build_meshes()
	_layout()

func _build_meshes() -> void:
	for c in _pivot.get_children():
		if c != _camera:
			c.queue_free()
	var g := map.grid
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	verts.resize(g.x * g.y)
	cols.resize(g.x * g.y)
	uvs.resize(g.x * g.y)
	for y in range(g.y):
		for x in range(g.x):
			var i := y * g.x + x
			var uv := Vector2(float(x) / (g.x - 1), float(y) / (g.y - 1))
			verts[i] = map.world(uv, map.heights[i])
			cols[i] = Color(map.territory[i], 0, 0)
			uvs[i] = uv
	var idx := PackedInt32Array()
	for y in range(g.y - 1):
		for x in range(g.x - 1):
			var i := y * g.x + x
			idx.append_array([i, i + 1, i + g.x, i + 1, i + g.x + 1, i + g.x])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var terrain := ArrayMesh.new()
	terrain.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_terrain_mat = ShaderMaterial.new()
	_terrain_mat.shader = _shader(TERRAIN_SHADER)
	_terrain_mat.set_shader_parameter("ours", ours)
	_terrain_mat.set_shader_parameter("theirs", Palette.HARDPOINT)
	_terrain_mat.set_shader_parameter("relief", WarMap.RELIEF)
	_terrain_mat.set_shader_parameter("contour", WarMap.CONTOUR)
	_add_mesh(terrain, _terrain_mat)

	var water := PlaneMesh.new()
	water.size = map.dims
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = _shader(WATER_SHADER)
	_water_mat.set_shader_parameter("water", WATER)
	_add_mesh(water, _water_mat).position.y = -0.006

	# the cut-away edge: a wall down from the ground's profile all round
	var ring := PackedVector2Array() # uv around the edge
	for x in range(g.x):
		ring.append(Vector2(float(x) / (g.x - 1), 1.0))
	for y in range(g.y - 1, -1, -1):
		ring.append(Vector2(1.0, float(y) / (g.y - 1)))
	for x in range(g.x - 1, -1, -1):
		ring.append(Vector2(float(x) / (g.x - 1), 0.0))
	for y in range(g.y):
		ring.append(Vector2(0.0, float(y) / (g.y - 1)))
	var pv := PackedVector3Array()
	var puv := PackedVector2Array()
	var pidx := PackedInt32Array()
	for k in range(ring.size()):
		var uv := ring[k]
		pv.append(map.world(uv, map.height_at(uv)))
		pv.append(map.world(uv, -PLATE_DEPTH))
		puv.append(Vector2(float(k) / ring.size(), 0.0))
		puv.append(Vector2(float(k) / ring.size(), 1.0))
		if k > 0:
			var a := (k - 1) * 2
			pidx.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	var parr := []
	parr.resize(Mesh.ARRAY_MAX)
	parr[Mesh.ARRAY_VERTEX] = pv
	parr[Mesh.ARRAY_TEX_UV] = puv
	parr[Mesh.ARRAY_INDEX] = pidx
	var plate := ArrayMesh.new()
	plate.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, parr)
	_plate_mat = ShaderMaterial.new()
	_plate_mat.shader = _shader(PLATE_SHADER)
	_plate_mat.set_shader_parameter("ours", ours)
	_plate_mat.set_shader_parameter("contour", WarMap.CONTOUR)
	_add_mesh(plate, _plate_mat)
	_apply_rise()

func _add_mesh(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pivot.add_child(mi)
	return mi


## Sweeps the terrain in from the near edge and grows it to full height.
func project_in(time: float = 0.9) -> Tween:
	rise = 0.0
	reveal = 0.0
	_apply_rise()
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(v: float): reveal = v; _apply_rise(), 0.0, 1.0, time * 0.75).set_trans(Tween.TRANS_SINE)
	tw.tween_method(func(v: float): rise = v; _apply_rise(), 0.0, 1.0, time).set_delay(time * 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tw

func show_now() -> void:
	rise = 1.0
	reveal = 1.0
	_apply_rise()

func _apply_rise() -> void:
	for m in [_terrain_mat, _water_mat, _plate_mat]:
		if m != null:
			m.set_shader_parameter("reveal", reveal)
			m.set_shader_parameter("rise", rise)

func _layout() -> void:
	if map == null or _camera == null:
		return
	inner = Rect2(Vector2(inset_side, inset_top), size - Vector2(inset_side * 2.0, inset_top + inset_bottom))
	if inner.size.x < 10.0 or inner.size.y < 10.0:
		return
	_render_k = clampf(get_viewport().get_final_transform().get_scale().x if get_viewport() else 1.0, 1.0, 2.0)
	_viewport.size = Vector2i((inner.size * _render_k).ceil())
	_screen.position = inner.position
	_screen.size = inner.size
	_fit_camera()

## Moves the camera back until the whole plate fits the inner rect, and
## centers it.
func _fit_camera() -> void:
	_camera.v_offset = 0.0
	var lo := 4.0
	var hi := 60.0
	for i in 18:
		var d := (lo + hi) / 2.0
		_place_camera(d)
		var b := _plate_bounds()
		if b.size.x <= _viewport.size.x * 0.97 and b.size.y <= _viewport.size.y * 0.97:
			hi = d
		else:
			lo = d
	_place_camera(hi)
	for i in 3:
		var b := _plate_bounds()
		var off := b.get_center().y - _viewport.size.y / 2.0
		var world_per_px := 2.0 * hi * tan(deg_to_rad(FOV) / 2.0) / _viewport.size.y
		_camera.v_offset -= off * world_per_px

func _place_camera(dist: float) -> void:
	var p := deg_to_rad(pitch)
	var target := Vector3(0, WarMap.RELIEF * 0.2, 0)
	_camera.position = target + Vector3(0, sin(p), cos(p)) * dist
	_camera.look_at(target)
	_pivot.rotation.y = deg_to_rad(_yaw)

func _plate_bounds() -> Rect2:
	var b := Rect2()
	var first := true
	for x in [0.0, 1.0]:
		for z in [0.0, 1.0]:
			for y in [-PLATE_DEPTH, WarMap.RELIEF * 0.8]:
				var p := _camera.unproject_position(_pivot.transform * map.world(Vector2(x, z), y))
				if first:
					b = Rect2(p, Vector2.ZERO)
					first = false
				else:
					b = b.expand(p)
	return b

## A map point (uv, height above the ground) in this control's coordinates.
func proj(uv: Vector2, above: float = 0.0, ground: bool = true) -> Vector2:
	var h := (map.height_at(uv) if ground else 0.0) * rise + above
	var p := _camera.unproject_position(_pivot.transform * map.world(uv, h))
	return inner.position + p / _render_k

func proj_line(pts: PackedVector2Array, above: float = 0.015) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(proj(p, above))
	return out

## A world circle on the ground around a UV, projected.
func ground_ring(uv: Vector2, radius: float, above: float = 0.02) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var h := map.height_at(uv) * rise + above
	var c := map.world(uv, h)
	for k in range(33):
		var ang := TAU * k / 32.0
		var p := c + Vector3(cos(ang), 0, sin(ang)) * radius
		pts.append(inner.position + _camera.unproject_position(_pivot.transform * p) / _render_k)
	return pts

static func draw_dashed(ci: CanvasItem, pts: PackedVector2Array, dash: float, gap: float, offset: float, c: Color, width: float) -> void:
	var period := dash + gap
	var s := fposmod(offset, period)
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		var pos := 0.0
		while pos < seg:
			var phase := fposmod(s + pos, period)
			var run := minf(seg - pos, (dash - phase) if phase < dash else (period - phase))
			if phase < dash:
				ci.draw_line(a.lerp(b, pos / seg), a.lerp(b, (pos + run) / seg), c, width, true)
			pos += maxf(run, 0.01)
		s += seg

func _process(delta: float) -> void:
	if not is_visible_in_tree() or map == null:
		return
	var still: bool = GameSettings.reduce_motion # no flicker, scanline roll or sway
	if not still:
		_time += delta
	var want := clampf((get_local_mouse_position().x / maxf(size.x, 1.0) - 0.5) * 2.0, -1.0, 1.0) * yaw_sway
	if hold_still or still:
		want = _yaw
	if absf(want - _yaw) > 0.01:
		_yaw = lerpf(_yaw, want, minf(1.0, delta * 2.0))
		_pivot.rotation.y = deg_to_rad(_yaw)
	for m in [_terrain_mat, _water_mat]:
		if m != null:
			m.set_shader_parameter("t", _time)
	_composite.set_shader_parameter("t", _time)
	# a frame early rather than late, so 60 Hz displays don't skip any
	var interval := 0.9 / RENDERS_PER_SECOND
	_since_render += delta / maxf(Engine.time_scale, 0.001)
	if _since_render >= interval:
		_since_render = minf(_since_render - interval, interval)
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

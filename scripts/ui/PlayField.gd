class_name PlayField
extends Control
## The combat screen's background, added first so everything else sits on
## top of it. Card drops no longer route through here — see CardUI.gd.
##
## With a background from data/backgrounds.json it draws that image
## (covering the screen, enlarged by its zoom from the bottom edge) and knows
## where enemies' feet stand on its floor; without one it's the plain field.
## A background with `weather` ("rain", "snow" or "dust") gets that layer
## (Rain, Snow, Dust) over the image (under everything else on the screen).
##
## A boss's phase 2 (set_phase2) turns the scene ominous for its location:
## the image darkens into a vignette and the location's colour pulses
## through it (GRADE_SHADER), the weather doubles, and an Omen layer adds
## lightning (Shipyard), corrupted pixels and torn scanlines (Data Archives)
## or rising embers and heat shimmer (Mining Grounds).
##
## A background can also have a `sea` mask (its water rolls in waves all
## fight, raging in phase 2), `lamps` (Lamps: pools of light, which carry the
## phase-2 pulse instead of the whole screen) and `spray` edges (the Omen
## throws spray over them in phase 2).
## With `frames` (a strip of whole-background frames side by side, frame 0 =
## the image; `fps`) the background itself is animated; `frames_phase2`
## (at `fps_phase2`) takes over in a boss's phase 2, else `frames` speeds up.
## Built by tools/sea_frames.py. `lava` flows (LavaFlow) erupt in phase 2.

var background: Dictionary = {}
var _texture: Texture2D = null
var _weather: Control = null # Rain, Snow or Dust
var _storm: Control = null   # phase 2: a second weather layer
var _omen: Omen = null
var _lamps: Lamps = null
var _lava: LavaFlow = null
var _dread: float = 0.0
var _phase2: bool = false
var _frames: Array[Texture2D] = [] # the animated background's frames ([] = a still)
var _frames_p2: Array[Texture2D] = [] # ...and its phase-2 ones ([] = `_frames`, faster)
var _frame_t: float = 0.0

## Per location: its phase-2 Omen and the colour that washes through it.
const PHASE2 := {
	"shipyard": {"omen": "storm", "tint": Color(1.0, 0.28, 0.2), "mode": 0},
	"data_archives": {"omen": "glitch", "tint": Color(0.8, 0.25, 0.95), "mode": 1},
	"mining_grounds": {"omen": "embers", "tint": Color(1.0, 0.45, 0.12), "mode": 2, "lamp_grade": Color(0.85, 0.3, 0.15)},
}
const PHASE2_TIME := 1.8 # how long the scene takes to turn
## The grade's colour on a background whose lamps carry the warm light.
const STORM_COLD := Color(0.55, 0.62, 0.85)

## The background's grade in phase 2: `dread` 0..1 darkens it toward a
## vignette and the location's `tint`, which pulses through it (an alarm).
## mode 0 storm: `flash` lights it (Omen's lightning); 1 glitch: bands of
## the image slip sideways with a colour split now and then; 2 embers: the
## ground glows and shimmers with heat. `still` (Reduce motion) holds it.
const GRADE_SHADER := """
shader_type canvas_item;
uniform float dread = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 0.3, 0.2, 1.0);
uniform int mode = 0;
uniform float flash = 0.0;
uniform bool still = false;
uniform sampler2D sea_mask : filter_nearest;
uniform bool has_sea = false;
uniform float tint_pulse = 1.0; // 0: the lamps carry the pulse instead
uniform float sea_calm = 0.8; // the shader's own waves before phase 2 (0 when the frames are animated)
uniform float darken = 0.7;   // what the phase-2 grade leaves of the image's brightness
uniform float vignette = 0.6; // how dark its corners go
uniform float sea_rage = 3.2; // ...and at full phase 2 (less when phase-2 frames do the crashing)
float hash(float n) { return fract(sin(n) * 43758.5453); }
void fragment() {
	float t = still ? 0.0 : TIME;
	vec2 uv = UV;
	float split = 0.0;
	float swell = 0.0;
	// the sea rolls all fight, in art pixels, bigger nearer the camera; in
	// phase 2 (dread) the waves grow and quicken
	if (has_sea && texture(sea_mask, UV).r > 0.5) {
		vec2 px = UV / TEXTURE_PIXEL_SIZE;
		float near = clamp((UV.y - 0.3) / 0.7, 0.0, 1.0);
		float amp = mix(sea_calm, sea_rage, dread) * (0.4 + near * 1.6);
		float spd = mix(1.0, 2.4, dread);
		float wy = sin(px.x * 0.08 - t * spd * 2.0 + sin(px.y * 0.06 + t * spd) * 1.5) * amp;
		float wx = sin(px.y * 0.11 + t * spd * 1.4) * amp * 0.5;
		vec2 moved = UV + floor(vec2(wx, wy) + 0.5) * TEXTURE_PIXEL_SIZE;
		if (texture(sea_mask, moved).r > 0.5) {
			uv = moved;
		}
		swell = sin(px.x * 0.05 + px.y * 0.09 - t * spd * 1.6) * (0.03 + 0.07 * dread);
	}
	if (!still && dread > 0.0) {
		if (mode == 1) {
			float tick = floor(t * 10.0);
			float burst = step(0.85, hash(tick * 1.7));
			float band = floor(SCREEN_UV.y * 36.0);
			float on = step(0.55, hash(band * 3.1 + tick));
			uv.x += (hash(band + tick * 7.3) - 0.5) * 0.04 * burst * on * dread;
			split = 0.004 * burst * dread;
		} else if (mode == 2) {
			float w = smoothstep(0.55, 1.0, SCREEN_UV.y);
			uv.x += sin(SCREEN_UV.y * 140.0 + t * 7.0) * 0.0012 * w * dread;
		}
	}
	vec4 c = texture(TEXTURE, uv) * COLOR;
	c.rgb += vec3(swell);
	if (split > 0.0) {
		c.r = (texture(TEXTURE, uv + vec2(split, 0.0)) * COLOR).r;
		c.b = (texture(TEXTURE, uv - vec2(split, 0.0)) * COLOR).b;
	}
	float lum = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	vec3 graded = mix(c.rgb, lum * tint.rgb * 1.5, 0.4) * darken;
	c.rgb = mix(c.rgb, graded, dread);
	float v = smoothstep(0.3, 0.9, length((SCREEN_UV - vec2(0.5, 0.5)) * vec2(1.2, 1.0)));
	c.rgb *= 1.0 - v * vignette * dread;
	float pulse = still ? 0.35 : pow(0.5 + 0.5 * sin(t * (mode == 1 ? 4.5 : 2.0)), 4.0);
	float where = mode == 2 ? smoothstep(0.35, 1.0, SCREEN_UV.y) * 1.6 : 1.0;
	c.rgb += tint.rgb * pulse * 0.13 * dread * where * tint_pulse;
	c.rgb += vec3(0.75, 0.82, 1.0) * flash;
	COLOR = c;
}
"""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(_fit_weather)

func set_background(bg: Dictionary) -> void:
	background = bg
	var path: String = bg.get("image", "")
	_texture = load(path) if path != "" and ResourceLoader.exists(path) else null
	_frames = _load_frames(bg, "frames")
	_frames_p2 = _load_frames(bg, "frames_phase2")
	_frame_t = 0.0
	if not _frames.is_empty():
		_texture = _frames[0]
	for layer in [_weather, _storm, _omen, _lamps, _lava]:
		if layer != null:
			layer.queue_free()
	_weather = null
	_storm = null
	_omen = null
	_lamps = null
	_lava = null
	_dread = 0.0
	_phase2 = false
	material = null
	if _texture != null:
		if not bg.get("lamps", []).is_empty():
			_lamps = Lamps.new()
			_lamps.color = Color(str(bg.get("lamp_color", "#ffa035")))
			_lamps.style = str(bg.get("lamp_style", "alarm"))
			add_child(_lamps) # under the weather
		if not bg.get("lava", []).is_empty():
			_lava = LavaFlow.new() # bursts out in phase 2
			add_child(_lava)
		_weather = _make_weather(bg.get("weather", ""))
		if bg.has("sea") or _lamps != null or not _frames.is_empty():
			_make_grade() # the sea rolls from the start
	if _weather != null:
		add_child(_weather)
	_fit_weather()
	queue_redraw()

## A background's `frames` strip cut into its frames ([] without one).
static func _load_frames(bg: Dictionary, key: String) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	var path: String = bg.get(key, "")
	if path == "" or not ResourceLoader.exists(path):
		return out
	var strip: Image = (load(path) as Texture2D).get_image()
	var h := strip.get_height()
	var w := int(bg.get("frame_width", h))
	for i in range(strip.get_width() / w):
		out.append(ImageTexture.create_from_image(strip.get_region(Rect2i(i * w, 0, w, h))))
	return out

## The grade material, with this background's sea mask and lamps (phase 2
## sets its look; until then `dread` is 0 and only the sea moves).
func _make_grade() -> ShaderMaterial:
	if material != null:
		return material
	var grade := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = GRADE_SHADER
	grade.shader = shader
	var sea_path: String = background.get("sea", "")
	if sea_path != "" and ResourceLoader.exists(sea_path):
		grade.set_shader_parameter("sea_mask", load(sea_path))
		grade.set_shader_parameter("has_sea", true)
	grade.set_shader_parameter("tint_pulse", 0.0 if _lamps != null else 1.0)
	grade.set_shader_parameter("sea_calm", 0.0 if not _frames.is_empty() else 0.8)
	grade.set_shader_parameter("sea_rage", 1.0 if not _frames_p2.is_empty() else 3.2)
	material = grade
	return grade

static func _make_weather(kind: String) -> Control:
	match kind:
		"rain": return Rain.new()
		"snow": return Snow.new()
		"dust": return Dust.new()
	return null

## Whether the scene has turned for a boss's phase 2.
func in_phase2() -> bool:
	return _phase2

## The colour of this location's phase 2 (also the boss's aura).
func phase2_tint() -> Color:
	return PHASE2.get(str(background.get("location", "")), {}).get("tint", Color(1.0, 0.3, 0.2))

## A boss's phase 2: the scene turns ominous for its location, over
## PHASE2_TIME (at once if not `animate`).
func set_phase2(animate: bool) -> void:
	if in_phase2():
		return
	_phase2 = true
	if _lava != null:
		_lava.erupt(animate)
	if not _frames_p2.is_empty():
		_frames = _frames_p2 # the sea starts crashing
		_frame_t = 0.0
	var look: Dictionary = PHASE2.get(str(background.get("location", "")), {"omen": "", "tint": phase2_tint(), "mode": 0})
	var grade := _make_grade()
	# with lamps the warm light is theirs: the scene itself goes storm-cold
	grade.set_shader_parameter("tint", look.get("lamp_grade", STORM_COLD) if _lamps != null else look["tint"])
	grade.set_shader_parameter("darken", float(background.get("grade_darken", 0.7)))
	grade.set_shader_parameter("vignette", float(background.get("grade_vignette", 0.6)))
	grade.set_shader_parameter("mode", int(look["mode"]))
	if _texture != null:
		_storm = _make_weather(background.get("weather", ""))
		if _storm != null:
			add_child(_storm)
		if str(look["omen"]) != "":
			_omen = Omen.new(str(look["omen"]))
			add_child(_omen)
		_fit_weather()
	if animate:
		create_tween().tween_method(_set_dread, 0.0, 1.0, PHASE2_TIME).set_trans(Tween.TRANS_SINE)
	else:
		_set_dread(1.0)

func _set_dread(v: float) -> void:
	_dread = v
	if _storm != null:
		_storm.modulate.a = v
	if _omen != null:
		_omen.modulate.a = v
	if _lamps != null:
		_lamps.alarm = v
	if material != null:
		(material as ShaderMaterial).set_shader_parameter("dread", v)

func _process(delta: float) -> void:
	var settings := get_node_or_null("/root/GameSettings")
	if _frames.size() > 1 and not (settings != null and settings.reduce_motion):
		if Engine.time_scale > 0.0:
			delta /= Engine.time_scale # real time, like the weather
		if _phase2 and (not _frames_p2.is_empty() or background.has("fps_phase2")):
			_frame_t += delta * float(background.get("fps_phase2", background.get("fps", 6.0)))
		else: # without phase-2 frames, phase 2 plays them up to 1.6× as fast
			_frame_t += delta * float(background.get("fps", 6.0)) * (1.0 + 0.6 * _dread)
		var tex := _frames[int(_frame_t) % _frames.size()]
		if tex != _texture:
			_texture = tex
			queue_redraw()
	if material == null:
		return
	(material as ShaderMaterial).set_shader_parameter("still", settings != null and settings.reduce_motion)
	(material as ShaderMaterial).set_shader_parameter("flash", _omen.flash * _dread if _omen != null else 0.0)

## The weather covers the field, lands on the background's ground and moves
## in its pixel size.
func _fit_weather() -> void:
	if _texture == null:
		return
	var rect := image_rect()
	for layer in [_weather, _storm, _omen]:
		if layer != null:
			layer.size = size
			layer.call("setup", rect.position.y + float(background.get("ground", 0.5)) * rect.size.y, rect.size.x / _texture.get_width())
	if _lamps != null:
		_lamps.size = size
		_lamps.setup(background.get("lamps", []), rect)
	if _lava != null:
		_lava.size = size
		_lava.setup(background.get("lava", []), rect, rect.size.x / _texture.get_width())
	if _omen != null:
		var rf = background.get("rockfall", false)
		_omen.rockfall = rf is Dictionary or bool(rf)
		_omen.rock_edges.clear()
		if rf is Dictionary:
			for e in rf.get("from", []): # [x0, x1, y] fractions
				_omen.rock_edges.append([rect.position.x + float(e[0]) * rect.size.x, rect.position.x + float(e[1]) * rect.size.x, rect.position.y + float(e[2]) * rect.size.y])
		_omen.spray_edges.clear()
		for e in background.get("spray", []):
			_omen.spray_edges.append([rect.position + Vector2(e[0], e[1]) * rect.size, rect.position + Vector2(e[2], e[3]) * rect.size])

## Where the background image sits on the screen.
func image_rect() -> Rect2:
	var tex_size := _texture.get_size()
	var s := maxf(size.x / tex_size.x, size.y / tex_size.y) * float(background.get("zoom", 1.0))
	var rect_size := tex_size * s
	return Rect2(Vector2((size.x - rect_size.x) / 2.0, size.y - rect_size.y), rect_size)

## How far an enemy may stand from its slot's x, as a fraction of the image.
const FLOOR_NUDGE_X := 0.025

## Where n enemies' feet stand, left to right ([] = no background, or no
## slots for n enemies). With a `floor`, each stands near its slot's x and
## anywhere in the floor's y band, off its `avoid` spots, picked from `seed`
## (the fight's: the same fight, replayed, stands them the same).
func feet_points(n: int, seed: int = 0) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if _texture == null:
		return out
	var rect := image_rect()
	var slots: Array = background.get("slots", {}).get(str(n), [])
	var floor: Dictionary = background.get("floor", {})
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, n, background.get("id", "")])
	for p in slots:
		var at := Vector2(p[0], p[1])
		if not floor.is_empty():
			at = _floor_spot(floor, float(p[0]), rng)
		out.append(rect.position + at * rect.size)
	return out

## A spot on the floor near x: a few tries to miss its `avoid` spots, else
## the first one that does along the band, else x on the band's middle.
func _floor_spot(floor: Dictionary, x: float, rng: RandomNumberGenerator) -> Vector2:
	var fx: Array = floor.get("x", [0.0, 1.0])
	var fy: Array = floor.get("y", [0.5, 0.5])
	for i in range(16):
		var spot := Vector2(clampf(x + rng.randf_range(-FLOOR_NUDGE_X, FLOOR_NUDGE_X), fx[0], fx[1]), rng.randf_range(fy[0], fy[1]))
		if not _avoided(floor, spot):
			return spot
	for k in range(11):
		var spot := Vector2(clampf(x, fx[0], fx[1]), lerpf(fy[0], fy[1], k / 10.0))
		if not _avoided(floor, spot):
			return spot
	return Vector2(clampf(x, fx[0], fx[1]), (fy[0] + fy[1]) / 2.0)

func _avoided(floor: Dictionary, spot: Vector2) -> bool:
	for r in floor.get("avoid", []):
		if spot.x >= r[0] and spot.x <= r[2] and spot.y >= r[1] and spot.y <= r[3]:
			return true
	return false

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BG, true)
	if _texture != null:
		draw_texture_rect(_texture, image_rect(), false)

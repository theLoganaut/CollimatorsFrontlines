class_name MechArt
extends RefCounted
## Mech sprites (PixelLab, 128×128, straight-on so the part grid can sit on
## top). Enemies face the player, so they have one sprite; player mechs have
## a front (Hangar) and a back (combat, seen from behind). A mech without art
## returns null and its screen keeps the plain placeholder.

const ENEMY_PATH := "res://assets/enemies/%s.png"
const PLAYER_FRONT_PATH := "res://assets/mechs/%s_front.png"
const PLAYER_BACK_PATH := "res://assets/mechs/%s_back.png"

static func enemy(mech_id: String) -> Texture2D:
	return _load(ENEMY_PATH % mech_id)

## An enemy's sprite as a TextureRect (`sprite`), or null without art. An
## enemy with `assets/enemies/<id>_anim.png` (a strip of square frames, side
## by side, frame 0 = its still sprite) plays it in a loop at ANIM_FPS; with
## Reduce motion on it holds frame 0.
const ENEMY_ANIM_PATH := "res://assets/enemies/%s_anim.png"
const ANIM_FPS := 8.0

## A boss's phase-2 form (`assets/enemies/<id>_p2.png`, with an optional
## `<id>_p2_anim.png` strip), or null: it keeps its phase-1 sprite.
const ENEMY_P2_SUFFIX := "_p2"

static func enemy_phase2(mech_id: String) -> Texture2D:
	return enemy(mech_id + ENEMY_P2_SUFFIX)

static func enemy_sprite(mech_id: String, rect_size: Vector2, phase2: bool = false) -> TextureRect:
	if phase2 and enemy_phase2(mech_id) != null:
		mech_id += ENEMY_P2_SUFFIX
	var tex := enemy(mech_id)
	if tex == null:
		return null
	var r := sprite(tex, rect_size)
	var strip := _load(ENEMY_ANIM_PATH % mech_id)
	if strip == null or strip.get_height() <= 0:
		return r
	var side := strip.get_height()
	var frames := strip.get_width() / side
	if frames < 2:
		return r
	var atlas := AtlasTexture.new()
	atlas.atlas = strip
	atlas.region = Rect2(0, 0, side, side)
	r.texture = atlas
	r.ready.connect(func() -> void:
		var frame := [0]
		var tw := r.create_tween().set_loops()
		tw.tween_interval(1.0 / ANIM_FPS)
		tw.tween_callback(func() -> void:
			var settings := r.get_node_or_null("/root/GameSettings")
			var still: bool = settings != null and settings.reduce_motion
			frame[0] = 0 if still else (frame[0] + 1) % frames
			atlas.region = Rect2(frame[0] * side, 0, side, side)))
	return r

static func player_front(mech_id: String) -> Texture2D:
	return _load(PLAYER_FRONT_PATH % mech_id)

static func player_back(mech_id: String) -> Texture2D:
	return _load(PLAYER_BACK_PATH % mech_id)

## A sprite filling `rect_size` (kept square, centered), drawn with hard
## pixel edges.
static func sprite(tex: Texture2D, rect_size: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.size = rect_size
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

static var _bottom_insets: Dictionary = {} # texture path -> float

## The share of a sprite's height left empty below its lowest pixel (under
## its feet), so it can be stood on a floor line.
static func bottom_inset(tex: Texture2D) -> float:
	if not _bottom_insets.has(tex.resource_path):
		var img := tex.get_image()
		var inset := 0.0
		if img != null:
			var used := img.get_used_rect()
			if used.size.y > 0:
				inset = 1.0 - float(used.end.y) / float(img.get_height())
		_bottom_insets[tex.resource_path] = inset
	return _bottom_insets[tex.resource_path]

static func _load(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null

## The hologram look of the War Room's Hangar pads and the Hangar: the
## sprite recoloured teal (keeping a little of its shading), scanlines, a
## slow sweep and a flicker. `strength` is its opacity.
const HOLOGRAM_SHADER := """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.35, 0.9, 0.84, 1.0);
uniform float strength = 0.75;
uniform float detail = 0.35;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 col = min(vec3(1.0), lum * detail + tint.rgb * 0.75);
	float scan = step(1.0, mod(FRAGCOORD.y, 3.0));
	float sweep = smoothstep(0.08, 0.0, abs(fract(TIME * 0.35) - UV.y)) * 0.35;
	float flicker = 0.92 + 0.08 * sin(TIME * 21.0 + UV.y * 30.0);
	COLOR = vec4(col + sweep, c.a * strength * scan * flicker);
}
"""

static var _hologram_shader: Shader

static func hologram_material(strength: float = 0.75, detail: float = 0.35) -> ShaderMaterial:
	if _hologram_shader == null:
		_hologram_shader = Shader.new()
		_hologram_shader.code = HOLOGRAM_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _hologram_shader
	mat.set_shader_parameter("strength", strength)
	mat.set_shader_parameter("detail", detail)
	return mat


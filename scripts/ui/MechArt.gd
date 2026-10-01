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


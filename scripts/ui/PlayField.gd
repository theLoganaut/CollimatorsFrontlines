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

var background: Dictionary = {}
var _texture: Texture2D = null
var _weather: Control = null # Rain, Snow or Dust

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(_fit_weather)

func set_background(bg: Dictionary) -> void:
	background = bg
	var path: String = bg.get("image", "")
	_texture = load(path) if path != "" and ResourceLoader.exists(path) else null
	if _weather != null:
		_weather.queue_free()
		_weather = null
	if _texture != null:
		match bg.get("weather", ""):
			"rain": _weather = Rain.new()
			"snow": _weather = Snow.new()
			"dust": _weather = Dust.new()
	if _weather != null:
		add_child(_weather)
		_fit_weather()
	queue_redraw()

## The weather covers the field, lands on the background's ground and moves
## in its pixel size.
func _fit_weather() -> void:
	if _weather == null:
		return
	var rect := image_rect()
	_weather.size = size
	_weather.call("setup", rect.position.y + float(background.get("ground", 0.5)) * rect.size.y, rect.size.x / _texture.get_width())

## Where the background image sits on the screen.
func image_rect() -> Rect2:
	var tex_size := _texture.get_size()
	var s := maxf(size.x / tex_size.x, size.y / tex_size.y) * float(background.get("zoom", 1.0))
	var rect_size := tex_size * s
	return Rect2(Vector2((size.x - rect_size.x) / 2.0, size.y - rect_size.y), rect_size)

## Where n enemies' feet stand, left to right ([] = no background, or no
## slots for n enemies).
func feet_points(n: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if _texture == null:
		return out
	var rect := image_rect()
	for p in background.get("slots", {}).get(str(n), []):
		out.append(rect.position + Vector2(p[0], p[1]) * rect.size)
	return out

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BG, true)
	if _texture != null:
		draw_texture_rect(_texture, image_rect(), false)

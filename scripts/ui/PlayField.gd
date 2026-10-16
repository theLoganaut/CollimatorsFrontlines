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

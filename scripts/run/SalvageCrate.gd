class_name SalvageCrate
extends Control
## One salvage crate on the reward screen (Logan, 2026-11-11): pixel art per
## category (assets/run/crates/<category>.png, PixelLab), lit in the
## category's color. Hovering lifts it and lights the floor under it. Once
## picked, RewardScreen flies it to the bottom of the screen, shakes it
## (`shake`) and calls open(): the lid blows off, a flash and sparks burst
## out and a beam of the category's light rises from the open crate.
## It never says what's inside: no rarity shows until the parts land.

signal pressed()

const DIR := "res://assets/run/crates/"
const LID_FLIGHT := 0.9 # seconds the lid tumbles away
const SAME_AREA := 88.0 * 68.0 # art pixels: each crate is scaled so its body covers this much (the hardpoint crate's)

var category: String = ""
var art_scale: float = 2.0
var enabled: bool = true
var interactive: bool = true:
	set(v):
		interactive = v
		if not v:
			_hover = false
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if v and enabled else Control.CURSOR_ARROW
## How hard it's rattling, in art pixels (RewardScreen tweens it).
var shake: float = 0.0
## The beam is drawn by another layer (RewardScreen puts it behind the cards), not over everything with the crate.
var beam_elsewhere: bool = false
var opened: bool = false
## Lit as if hovered (the Surprise me roll passing over it).
var spotlight: bool = false

var _tex: Texture2D
var _open_tex: Texture2D
var _lid_rows: int = 0 # rows of the closed art that are its lid
var _used: Rect2 # the art's opaque pixels (where it stands, how wide it is)
var _hover: bool = false
var _lift: float = 0.0
var _time: float = 0.0
var _jolt := Vector2.ZERO
var _tilt: float = 0.0
var _lid_t: float = 1.0
var _flash: float = 0.0
var _beam: float = 0.0
var _sparks: Array = [] # [pos, vel, life, max life]

## Where the lid ends on each crate's art (rows from the top), set by art_src/crates/build.py.
const LID_ROWS := {"hardpoint": 38, "reactor": 41, "protocol": 36}

func setup(cat: String, scale_by: float = 2.0) -> void:
	category = cat
	_tex = load(DIR + cat + ".png")
	# every crate the same size on screen (the area its body covers), whatever its art's size:
	# the protocol one came out bigger, and the reactor one is boxier, so matching widths wasn't enough
	var body := Vector2(_tex.get_image().get_used_rect().size)
	art_scale = scale_by * sqrt(SAME_AREA / maxf(1.0, body.x * body.y))
	_open_tex = load(DIR + cat + "_open.png") if ResourceLoader.exists(DIR + cat + "_open.png") else null
	_lid_rows = int(LID_ROWS.get(cat, 0))
	_used = Rect2(_tex.get_image().get_used_rect())
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = art_size()
	size = art_size()
	mouse_filter = Control.MOUSE_FILTER_STOP
	interactive = true

## Where the crate stands (bottom center of its body), in its own coordinates.
func foot() -> Vector2:
	return Vector2(_used.get_center().x, _used.end.y) * art_scale

func art_size() -> Vector2:
	return (_tex.get_size() if _tex != null else Vector2(112, 96)) * art_scale

func color() -> Color:
	return Palette.category_color(category)

func _ready() -> void:
	mouse_entered.connect(func():
		if interactive and enabled:
			_hover = true
			Audio.play("hover"))
	mouse_exited.connect(func(): _hover = false)
	gui_input.connect(func(e: InputEvent):
		if interactive and enabled and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			pressed.emit())

## The lid blows off: flash, sparks, and the light inside comes up.
func open() -> void:
	opened = true
	_lid_t = 0.0
	_flash = 1.0
	shake = 0.0
	var c := Vector2(size.x / 2.0, _lid_rows * art_scale)
	for i in range(34):
		var a := randf_range(PI * 1.05, PI * 1.95)
		var v := Vector2(cos(a), sin(a)) * randf_range(140.0, 420.0)
		var life := randf_range(0.35, 0.8)
		_sparks.append([c + Vector2(randf_range(-size.x * 0.3, size.x * 0.3), 0), v, life, life])
	create_tween().tween_property(self, "_beam", 1.0, 0.25)

## The beam of light out of the open crate, fanning wide (Logan, 2026-11-11: under all three
## slots, not just the middle one), drawn on `ci` in this crate's local space (set its transform first).
## `aim` (this crate's local space): the row of cards it lights. The beam's edges run from the
## crate mouth's sides to the outer cards' outer edges where the row's bottom is (so they touch
## them where they're seen), then carry on behind the cards, fading out by the row's top.
## Without an aim it fans a fixed amount.
func draw_beam(ci: CanvasItem, aim: Rect2 = Rect2()) -> void:
	if _beam <= 0.0 or _tex == null:
		return
	var c := color()
	var sz := art_size()
	var top := _lid_rows * art_scale + 2.0
	var mid := _used.get_center().x * art_scale
	var bw := _used.size.x * art_scale * 0.38 # half-width at the crate's mouth
	var hit_mid := mid
	var hit_half := bw * 6.0
	var hit_y := top - sz.y * 2.2 # where the edges reach the cards
	var end_y := hit_y - sz.y * 1.2 # where the light has faded out
	if aim.has_area():
		hit_mid = aim.get_center().x
		hit_half = aim.size.x / 2.0
		hit_y = aim.end.y
		end_y = aim.position.y
	# grow out of the crate as it opens
	hit_y = lerpf(top, hit_y, _beam)
	end_y = lerpf(top, end_y, _beam)
	var t_end := (top - end_y) / maxf(1.0, top - hit_y) # how far past the hit line the edges run on
	var pulse := 0.85 + 0.15 * sin(_time * 5.0)
	for i in range(3): # the outer layer reaches the edges; the inner ones are narrower, so the core is brighter
		var k := 1.0 - i * 0.26
		var l0 := Vector2(mid - bw * k, top)
		var r0 := Vector2(mid + bw * k, top)
		var l1 := Vector2(hit_mid - hit_half * k, hit_y)
		var r1 := Vector2(hit_mid + hit_half * k, hit_y)
		var l2 := l0.lerp(l1, t_end)
		var r2 := r0.lerp(r1, t_end)
		var a := 0.15 * _beam * pulse
		ci.draw_polygon(PackedVector2Array([l0, r0, r1, l1]), PackedColorArray([Color(c, a), Color(c, a), Color(c, a * 0.75), Color(c, a * 0.75)]))
		ci.draw_polygon(PackedVector2Array([l1, r1, r2, l2]), PackedColorArray([Color(c, a * 0.75), Color(c, a * 0.75), Color(c, 0.0), Color(c, 0.0)]))

## Already open (back on the screen after the opening): no burst.
func show_open() -> void:
	opened = true
	_lid_t = 1.0
	_beam = 1.0

func _process(delta: float) -> void:
	_time += delta
	_lift = move_toward(_lift, 1.0 if _hover or spotlight else 0.0, delta * (14.0 if spotlight else 6.0))
	if shake > 0.0:
		_jolt = Vector2(randf_range(-shake, shake), randf_range(-shake, shake) * 0.4) * art_scale
		_tilt = randf_range(-shake, shake) * 0.012
	else:
		_jolt = Vector2.ZERO
		_tilt = 0.0
	if _lid_t < 1.0:
		_lid_t = minf(1.0, _lid_t + delta / LID_FLIGHT)
	_flash = maxf(0.0, _flash - delta * 2.6)
	for s in _sparks:
		s[0] += s[1] * delta
		s[1] += Vector2(0, 620.0) * delta
		s[2] -= delta
	_sparks = _sparks.filter(func(s): return s[2] > 0.0)
	queue_redraw()

func _draw() -> void:
	if _tex == null:
		return
	var c := color()
	var sz := art_size()
	var foot := Vector2(_used.get_center().x, _used.end.y - 3.0) * art_scale # where it stands
	# the floor under it: a shadow, lit in its color on hover or once open
	var lit := maxf(_lift * 0.8, _beam)
	draw_set_transform(foot, 0.0, Vector2(1.0, 0.28))
	var w := _used.size.x * art_scale
	draw_circle(Vector2.ZERO, w * 0.44, Color(0, 0, 0, 0.4))
	if lit > 0.0:
		for i in range(4):
			draw_circle(Vector2.ZERO, w * (0.58 - i * 0.1), Color(c, 0.08 * lit))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if not beam_elsewhere:
		draw_beam(self)
	# the crate (lifted on hover, rattled while it shakes)
	var lift := Vector2(0, -6.0 * _lift)
	draw_set_transform(foot + _jolt + lift, _tilt, Vector2.ONE)
	var body := Rect2(-foot, sz)
	var tint := Color(1.18, 1.18, 1.18) if _hover or spotlight else (Color(0.45, 0.45, 0.5) if not enabled else Color.WHITE)
	if opened and _open_tex != null:
		draw_texture_rect(_open_tex, body, false, tint)
	elif opened:
		# no open art: the body without its lid rows
		var src := Rect2(0, _lid_rows, _tex.get_width(), _tex.get_height() - _lid_rows)
		draw_texture_rect_region(_tex, Rect2(body.position + Vector2(0, _lid_rows * art_scale), Vector2(sz.x, sz.y - _lid_rows * art_scale)), src, tint)
	else:
		draw_texture_rect(_tex, body, false, tint)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	# the lid, tumbling up and away
	if opened and _lid_t < 1.0:
		var t := _lid_t
		var lid_src := Rect2(0, 0, _tex.get_width(), _lid_rows)
		var lid_sz := Vector2(sz.x, _lid_rows * art_scale)
		var at := Vector2(sz.x / 2.0 + 120.0 * t, lid_sz.y / 2.0 - 340.0 * t + 520.0 * t * t)
		draw_set_transform(at, 2.6 * t, Vector2.ONE)
		draw_texture_rect_region(_tex, Rect2(-lid_sz / 2.0, lid_sz), lid_src, Color(1, 1, 1, 1.0 - t * t))
		draw_set_transform_matrix(Transform2D.IDENTITY)
	for s in _sparks:
		var k: float = s[2] / s[3]
		var p := 2.0 + 2.0 * k
		draw_rect(Rect2(s[0] - Vector2(p, p) / 2.0, Vector2(p, p)), Color(c.lightened(0.5), k), true)
	if _flash > 0.0:
		var fc := Vector2(sz.x / 2.0, _lid_rows * art_scale)
		for i in range(6):
			draw_circle(fc, w * (0.08 + i * 0.07) * (1.6 - _flash * 0.6), Color(c.lightened(0.6), 0.1 * _flash * _flash))

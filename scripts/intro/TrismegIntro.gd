extends Control
## The Trismeg Studios intro: a hooded figure whose drop-shaped opening gives up
## its area to a new drop swelling at its bottom point. The drop lets go and
## falls through the hood onto the stone, which bursts into smoke and comes out
## the title. Built in _ready() from
## `<pieces_dir>/layout.json` (every piece's pivot, and every timing under
## "timeline"), drawn on a 1920×1080 stage scaled to fit the window. Any key,
## click or pad button skips. Nothing here is game-specific: only `next_scene`
## changes per game.

signal finished

@export_file("*.tscn") var next_scene: String = "res://scenes/WarRoom.tscn"
@export_dir var pieces_dir: String = "res://assets/intro/trismeg"
## Replays forever instead of moving on (also `-- --loop-intro` on the
## command line). Space restarts, Esc quits.
@export var loop: bool = false

const SKIP_FADE := 0.25

var _layout: Dictionary
var _tl: Dictionary
var _stage: Node2D         # the 1920×1080 canvas, scaled and centred
var _scene: Node2D         # everything that shakes
var _sprites: Dictionary = {}
var _opening: Sprite2D     # the hood's drop-shaped opening, painted in the background colour
var _drop: Sprite2D        # the drop that grows at the opening's tip and falls
var _sparks: CPUParticles2D
var _smoke: Array[CPUParticles2D] = []
var _smoke_at: Array[float] = []  # seconds after impact
var _black: ColorRect
var _t: float = 0.0
var _impacted: bool = false
var _smoke_fired: int = 0
var _done: bool = false
var _skipping: bool = false

func _ready() -> void:
	loop = loop or "--loop-intro" in OS.get_cmdline_user_args()
	_layout = JSON.parse_string(FileAccess.get_file_as_string(pieces_dir.path_join("layout.json")))
	_tl = _layout.timeline
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(_tl.background_color)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_stage = Node2D.new()
	add_child(_stage)
	_scene = Node2D.new()
	_scene.name = "Scene"
	_stage.add_child(_scene)
	# the hood is solid; the opening is a second sprite on top of it
	_scene.add_child(_piece("hood"))
	_opening = _piece("hood_opening")
	_scene.add_child(_opening)
	_scene.add_child(_piece("stone"))
	# the drop is drawn after the stone, so it falls in front of the hood and lands on the stone
	_drop = _piece("drop")
	_drop.visible = false
	_scene.add_child(_drop)
	# the title is drawn under the smoke, so it comes out of it as it clears
	for piece in ["title_trismeg", "title_line", "title_studios"]:
		var s := _piece(piece)
		s.modulate.a = 0.0
		_scene.add_child(s)
	_build_particles()
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)
	get_viewport().size_changed.connect(_fit)
	_fit()
	_pose(0.0)

## A piece as a Sprite2D whose position is its pivot, given in its parent's
## space (`origin` is the parent's position on the 1920×1080 canvas).
func _piece(id: String, origin: Vector2 = Vector2.ZERO) -> Sprite2D:
	var info: Dictionary = _layout.pieces[id]
	var s := Sprite2D.new()
	s.name = id
	s.texture = load(pieces_dir.path_join(info.file))
	s.centered = false
	s.offset = -_vec(info.pivot_in_image)
	s.position = _vec(info.pivot_screen) - origin
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_sprites[id] = s
	return s

func _fit() -> void:
	var canvas := _vec(_layout.canvas)
	var view := get_viewport_rect().size
	var k: float = min(view.x / canvas.x, view.y / canvas.y)
	_stage.scale = Vector2(k, k)
	_stage.position = (view - canvas * k) / 2.0

func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	_pose(_t)
	if _t >= float(_tl.total_seconds):
		_finish()

# --- the timeline ---------------------------------------------------------

## Sets every animated piece for time t. Particles are the only part that
## isn't a pure function of t: they're fired as t passes their moment.
func _pose(t: float) -> void:
	var growth := _drop_growth(t)
	_pose_opening(t, growth)
	_pose_drop(t, growth)
	var impact := float(_tl.impact)
	if t >= impact and not _impacted:
		_impacted = true
		_sparks.restart()
	while _smoke_fired < _smoke.size() and t >= impact + _smoke_at[_smoke_fired]:
		_smoke[_smoke_fired].restart()
		_smoke_fired += 1
	var shake: Dictionary = _tl.screen_shake
	var since := t - float(shake.start)
	if since >= 0.0 and since < 0.6:
		var amp := float(shake.amplitude_px) * exp(-float(shake.decay_per_second) * since)
		_scene.position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * amp
	else:
		_scene.position = Vector2.ZERO
	_sprites.stone.visible = t < float(_tl.stone_vanishes)
	var fade := _ease(t, _tl.title_trismeg_fade, Tween.TRANS_SINE, Tween.EASE_OUT)
	_sprites.title_trismeg.modulate.a = fade
	_sprites.title_trismeg.scale = Vector2.ONE * lerpf(1.05, 1.0, fade)
	var grow := _ease(t, _tl.title_line_grow, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	_sprites.title_line.scale.x = grow
	_sprites.title_line.modulate.a = 1.0 if grow > 0.0 else 0.0
	_sprites.title_studios.modulate.a = 0.85 * _ease(t, _tl.title_studios_fade, Tween.TRANS_SINE, Tween.EASE_OUT)
	if not _skipping:
		_black.modulate.a = 1.0 - _ease(t, _tl.fade_in, Tween.TRANS_SINE, Tween.EASE_IN_OUT) \
				+ _ease(t, _tl.fade_out, Tween.TRANS_SINE, Tween.EASE_IN_OUT)

## How grown the drop is, as a scale from drop.start_scale to 1 (0 before it
## forms). One smoothstep curve drives both the drop and the opening.
func _drop_growth(t: float) -> float:
	var d: Dictionary = _tl.drop
	var forms := float(d.forms_at)
	var full := float(d.full_at)
	if t <= forms:
		return 0.0
	if t >= full:
		return 1.0
	var u := (t - forms) / (full - forms)
	return lerpf(float(d.start_scale), 1.0, u * u * (3.0 - 2.0 * u))

## The opening gives up area in step with the drop: its scale is
## sqrt(1 - (1 - end²) * growth²), so it ends at `end_scale`. It stays small
## through the fall and grows back once the drop has landed.
func _pose_opening(t: float, growth: float) -> void:
	var o: Dictionary = _tl.opening
	var end := float(o.end_scale)
	var s := sqrt(1.0 - (1.0 - end * end) * growth * growth)
	var regrow: Array = o.regrow
	if t >= float(regrow[0]):
		s = lerpf(end, 1.0, _ease(t, regrow, Tween.TRANS_BACK, Tween.EASE_OUT))
	_opening.scale = Vector2.ONE * s

## The drop swells at the opening's tip (its pivot is its top point, so it
## grows downward), stretches a little, lets go, and falls straight down.
func _pose_drop(t: float, growth: float) -> void:
	var d: Dictionary = _tl.drop
	var full := float(d.full_at)
	var detach := float(d.detaches_at)
	var lands := detach + float(d.fall_seconds)
	_drop.visible = t > float(d.forms_at) and t < lands
	if not _drop.visible:
		return
	var start := _vec(d.start_screen)
	if t < detach:
		_drop.position = start
		if t < full:
			_drop.scale = Vector2.ONE * growth
		else:
			# the stretch just before it lets go: (1, 1) -> (.97, 1.08) -> (1, 1.1)
			var u := (t - full) / (detach - full)
			if u < 0.5:
				_drop.scale = Vector2(lerpf(1.0, 0.97, u * 2.0), lerpf(1.0, 1.08, u * 2.0))
			else:
				_drop.scale = Vector2(lerpf(0.97, 1.0, (u - 0.5) * 2.0), lerpf(1.08, 1.1, (u - 0.5) * 2.0))
	else:
		var u := _ease(t, [detach, lands], Tween.TRANS_QUAD, Tween.EASE_IN)
		_drop.position = start + Vector2(0.0, float(d.fall_px) * u)
		_drop.scale = Vector2(lerpf(1.0, 0.97, u), lerpf(1.1, 1.12, u))

## 0 → 1 across the window [from, to], eased.
func _ease(t: float, window: Array, trans: Tween.TransitionType, easing: Tween.EaseType) -> float:
	var from := float(window[0])
	var to := float(window[1])
	if t <= from:
		return 0.0
	if t >= to:
		return 1.0
	return Tween.interpolate_value(0.0, 1.0, t - from, to - from, trans, easing)

# --- particles ------------------------------------------------------------

func _build_particles() -> void:
	var origin := _vec(_tl.smoke_origin_screen)
	var puff: Texture2D = load(pieces_dir.path_join("smoke_puff.png"))
	# three violent waves, then a dense core spread across the stone
	for wave in 3:
		var p := _smoke_burst(origin, puff)
		p.amount = 16 - wave * 4
		p.initial_velocity_min = 700.0 - wave * 150.0
		p.initial_velocity_max = 1700.0 - wave * 350.0
		_smoke.append(p)
		_smoke_at.append([0.0, 0.08, 0.17][wave])
	var core := _smoke_burst(origin + Vector2(0, 20), puff)
	core.amount = 24
	core.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	core.emission_rect_extents = Vector2(200, 60)
	core.initial_velocity_min = 40.0
	core.initial_velocity_max = 220.0
	core.spread = 180.0
	# big at once so the stone vanishes under it within ~0.1 s
	core.scale_amount_min = 0.8
	core.scale_amount_max = 1.1
	core.scale_amount_curve = _curve([Vector2(0, 0.6), Vector2(0.03, 1.3), Vector2(1, 2.0)])
	core.color_ramp = _fade_ramp(1.0, 0.3)
	_smoke.insert(1, core)  # fires with the first wave
	_smoke_at.insert(1, 0.0)
	_sparks = CPUParticles2D.new()
	_sparks.name = "Sparks"
	_sparks.texture = load(pieces_dir.path_join("spark.png"))
	_sparks.position = origin
	_sparks.local_coords = true
	_sparks.emitting = false
	_sparks.one_shot = true
	_sparks.explosiveness = 1.0
	_sparks.amount = 60
	_sparks.lifetime = 0.7
	_sparks.lifetime_randomness = 0.5
	_sparks.direction = Vector2.UP
	_sparks.spread = 72.5
	_sparks.initial_velocity_min = 500.0
	_sparks.initial_velocity_max = 1400.0
	_sparks.damping_min = 1400.0
	_sparks.damping_max = 2200.0
	_sparks.gravity = Vector2(0, 500)
	_sparks.particle_flag_align_y = true
	_sparks.scale_amount_min = 0.6
	_sparks.scale_amount_max = 1.1
	_sparks.color_ramp = _fade_ramp(1.0, 0.55)
	_scene.add_child(_sparks)

func _smoke_burst(at: Vector2, tex: Texture2D) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "Smoke"
	p.texture = tex
	p.position = at
	p.local_coords = true
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 2.6
	p.lifetime_randomness = 0.35
	p.direction = Vector2.UP
	p.spread = 100.0
	# stop dead after the burst, then rise and drift
	p.damping_min = 7000.0
	p.damping_max = 9000.0
	p.damping_curve = _curve([Vector2(0, 1), Vector2(0.07, 1), Vector2(0.12, 0), Vector2(1, 0)])
	p.gravity = Vector2(0, -230)
	p.tangential_accel_min = -35.0
	p.tangential_accel_max = 35.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -40.0
	p.angular_velocity_max = 40.0
	p.scale_amount_min = 0.45
	p.scale_amount_max = 0.7
	# 0.15 → 1.2 in the first 0.15 s, then keeps swelling
	p.scale_amount_curve = _curve([Vector2(0, 0.15), Vector2(0.06, 1.2), Vector2(1, 1.9)])
	p.color_ramp = _fade_ramp(0.9, 0.25)
	_scene.add_child(p)
	return p

func _curve(points: Array) -> Curve:
	var c := Curve.new()
	c.max_value = 3.0
	for pt in points:
		c.add_point(pt, 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	return c

## White, holding `alpha` until `hold` of the lifetime, then fading out.
func _fade_ramp(alpha: float, hold: float) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, alpha))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(hold, Color(1, 1, 1, alpha))
	return g

# --- skipping and leaving ---------------------------------------------------

func _input(event: InputEvent) -> void:
	if _done or _skipping or not event.is_pressed() or event.is_echo():
		return
	if loop:
		if event is InputEventKey and event.keycode == KEY_ESCAPE:
			get_tree().quit()
		elif event is InputEventKey and event.keycode == KEY_SPACE:
			_finish()
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		get_viewport().set_input_as_handled()
		_skipping = true
		var tw := create_tween()
		tw.tween_property(_black, "modulate:a", 1.0, SKIP_FADE)
		tw.tween_callback(_finish)

func _finish() -> void:
	if _done:
		return
	_done = true
	if loop:
		get_tree().reload_current_scene()
		return
	finished.emit()
	get_tree().change_scene_to_file(next_scene)

func _vec(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))

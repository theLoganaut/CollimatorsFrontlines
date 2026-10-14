extends Control
## The Trismeg Studios intro: the hooded alchemist tips his vial and flask,
## the drops hit the stone, it bursts into smoke and comes out a keyboard and
## mouse, then the title. Built in _ready() from `<pieces_dir>/layout.json`
## (every piece's pivot, and every timing under "timeline"), drawn on a
## 1920×1080 stage scaled to fit the window. Any key, click or pad button
## skips. Nothing here is game-specific: only `next_scene` changes per game.

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
var _bodies: Array[Node2D] = []  # the figure (behind and in front of the stone), moving as one
var _sprites: Dictionary = {}
var _pivots: Dictionary = {}   # side -> HandPivot
var _vessels: Dictionary = {}  # side -> vial/flask sprite
var _overlays: Dictionary = {} # side -> [layer, vessel copy, hand copy] drawn over the cuff
var _drops: Dictionary = {}    # side -> drop sprite
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
	var back := _body()
	for piece in ["robe", "beard"]:
		back.add_child(_piece(piece))
	for piece in ["stone", "keyboard_mouse"]:
		_scene.add_child(_piece(piece))
	_sprites.keyboard_mouse.visible = false
	var front := _body()
	for side in ["left", "right"]:
		var vessel: String = "vial_left" if side == "left" else "flask_right"
		var pivot := Node2D.new()
		pivot.name = "HandPivot_" + side
		pivot.position = _vec(_layout.pieces["hand_%s_thumb" % side].pivot_screen)
		front.add_child(pivot)
		pivot.add_child(_piece("hand_%s_thumb" % side, pivot.position))
		pivot.add_child(_piece(vessel, pivot.position))
		pivot.add_child(_piece("hand_%s_front" % side, pivot.position))
		front.add_child(_piece("cuff_" + side))
		# The cuff hides the back of the hand in the sleeve, but the vessel
		# swings in front of the sleeve: draw the vessel again over the cuff,
		# and the hand again over that, clipped to the vessel's shape so only
		# the fingers on the vessel show.
		var real_vessel: Sprite2D = _sprites[vessel]
		var real_front: Sprite2D = _sprites["hand_%s_front" % side]
		var layer := Node2D.new()
		layer.name = "OverCuff_" + side
		layer.position = pivot.position
		front.add_child(layer)
		var vessel_copy := _piece(vessel, pivot.position)
		vessel_copy.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		layer.add_child(vessel_copy)
		var hand_copy := _piece("hand_%s_front" % side, pivot.position)
		vessel_copy.add_child(hand_copy)
		_overlays[side] = [layer, vessel_copy, hand_copy]
		_sprites[vessel] = real_vessel  # _piece() filed the copies under these names
		_sprites["hand_%s_front" % side] = real_front
		_pivots[side] = pivot
		_vessels[side] = _sprites[vessel]
	for side in ["left", "right"]:
		var drop := _piece("drop")
		drop.name = "Drop_" + side
		drop.visible = false
		_scene.add_child(drop)
		_drops[side] = drop
	_build_particles()
	for piece in ["title_trismeg", "title_line", "title_studios"]:
		var s := _piece(piece)
		s.modulate.a = 0.0
		_scene.add_child(s)
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)
	get_viewport().size_changed.connect(_fit)
	_fit()
	_pose(0.0)

## A layer of the figure: everything in it moves with the body (see
## _body_xform). Pieces go in at their canvas positions.
func _body() -> Node2D:
	var body := Node2D.new()
	body.name = "Body"
	_scene.add_child(body)
	_bodies.append(body)
	return body

## Where the body is at time t: timeline.body_motion keys of
## [seconds, rise (px, negative is up), stretch y, stretch x], eased between,
## about body_motion.pivot (the foot of the robe). Identity without them.
func _body_xform(t: float) -> Transform2D:
	if not _tl.has("body_motion"):
		return Transform2D.IDENTITY
	var keys: Array = _tl.body_motion.keys
	var k: Array = keys[-1]
	if t < float(keys[0][0]):
		k = keys[0]
	else:
		for i in range(keys.size() - 1):
			var a: Array = keys[i]
			var b: Array = keys[i + 1]
			if t >= float(a[0]) and t < float(b[0]):
				var u := (1.0 - cos(PI * (t - float(a[0])) / (float(b[0]) - float(a[0])))) / 2.0
				k = [t, lerpf(a[1], b[1], u), lerpf(a[2], b[2], u), lerpf(a[3], b[3], u)]
				break
	var pivot := _vec(_tl.body_motion.pivot)
	return Transform2D(0.0, Vector2(float(k[3]), float(k[2])), 0.0, pivot + Vector2(0, float(k[1]))) \
			* Transform2D(0.0, -pivot)

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
	var split: Dictionary = _tl.tilt_split
	var body := _body_xform(t)
	for b in _bodies:
		b.transform = body
	for side in ["left", "right"]:
		var dir := 1.0 if side == "left" else -1.0  # toward the centre
		var theta := deg_to_rad(_tilt(t, side)) * dir
		_pivots[side].rotation = theta * float(split.hand_pivot_share)
		_vessels[side].rotation = theta * float(split.flask_extra_share)
		if _overlays.has(side):
			var o: Array = _overlays[side]
			o[0].rotation = _pivots[side].rotation
			o[1].rotation = _vessels[side].rotation
			# the hand copy sits where the real hand is: undo the vessel's own turn
			var front: Sprite2D = _sprites["hand_%s_front" % side]
			o[2].transform = o[1].transform.affine_inverse() * front.transform
		_pose_drop(t, side)
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
	var swapped := t >= float(_tl.swap_stone_for_keyboard)
	_sprites.stone.visible = not swapped
	_sprites.keyboard_mouse.visible = swapped
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

## The tilt toward the centre, in degrees, for one side at time t.
func _tilt(t: float, side: String) -> float:
	var a: Dictionary = _tl.anticipation_tilt
	var m: Dictionary = _tl.main_tilt
	var r: Dictionary = _tl.return_upright
	var theta := 0.0
	# a small lean away, rising to its peak and falling back
	if t > float(a.start) and t < float(a.end):
		var u: float
		if t < float(a.peak):
			u = sin(PI / 2.0 * (t - float(a.start)) / (float(a.peak) - float(a.start)))
		else:
			u = cos(PI / 2.0 * (t - float(a.peak)) / (float(a.end) - float(a.peak)))
		theta -= float(a.degrees) * u
	# the pour, held, then back upright
	var deg := float(m.degrees)
	if t >= float(m.end) and t < float(r.start):
		theta += deg
	elif t >= float(r.start):
		theta += deg - _ease(t, [r.start, r.end], Tween.TRANS_BACK, Tween.EASE_OUT) * deg
	else:
		theta += _ease(t, [m.start, m.end], Tween.TRANS_BACK, Tween.EASE_IN_OUT) * deg
	# a flick as the drop lets go
	var d := float(_tl.drops[side].drop_detaches_at)
	if absf(t - d) < 0.14:
		theta += float(_tl.release_flick.degrees) * sin(PI * (t - d + 0.14) / 0.28)
	return theta

func _pose_drop(t: float, side: String) -> void:
	var info: Dictionary = _tl.drops[side]
	var forms := float(info.drop_forms_at)
	var detach := float(info.drop_detaches_at)
	var lands := detach + float(info.fall_seconds)
	var drop: Sprite2D = _drops[side]
	drop.visible = t >= forms and t < lands
	if not drop.visible:
		return
	# the lip moves with the body: the drop swells where the lip is, then
	# falls straight down from where it let go to the stone's height
	var start := _vec(info.drop_start_screen)
	if t < detach:
		drop.position = _body_xform(t) * start
		drop.scale = Vector2.ONE * _ease(t, [forms, detach], Tween.TRANS_SINE, Tween.EASE_OUT)
	else:
		var u := _ease(t, [detach, lands], Tween.TRANS_QUAD, Tween.EASE_IN)
		var from := _body_xform(detach) * start
		drop.position = from.lerp(Vector2(from.x, _vec(info.drop_lands_screen).y), u)
		drop.scale = Vector2(lerpf(1.0, 0.85, u), lerpf(1.0, 1.3, u))

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

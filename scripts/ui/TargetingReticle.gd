class_name TargetingReticle
extends Control
## The targeting crosshair, shared by the player and the enemies so both
## read the same way.
##
## Player: CombatScene moves it to the mouse while an attack card is being
## dragged (`locked` = it's over a valid target).
## Enemy: `trace_to()` flies it around the player's mech like a wandering
## boid (a random wander heading plus a pull back into the mech's area),
## blending it more and more strongly toward the chosen part until it sits
## on it at the end of the trace. It then locks on, and the caller fires.
##
## The control's position is the crosshair's center; drawing is around (0, 0).

signal trace_finished()

const RADIUS := 22.0
const TRACE_DURATION := 2.0
const LOCK_DURATION := 0.3

const MAX_SPEED := 460.0
const WANDER_FORCE := 1100.0
const WANDER_JITTER := 9.0 # rad/s the wander heading can swing
const CONTAIN_FORCE := 1800.0
const SEEK_FORCE := 500.0

enum State { IDLE, TRACE, LOCKING, FADING }

var locked: bool = false

var _state: State = State.IDLE
var _t: float = 0.0
var _target: Vector2
var _area: Rect2
var _boid_pos: Vector2
var _boid_vel: Vector2
var _wander: float = 0.0
var _lock_t: float = 0.0
var _spin: float = 0.0
var _flash: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_level = true
	z_index = 200
	visible = false

## Enemy targeting: wander over `area` for TRACE_DURATION, home in on
## `target`, lock on. Returns (awaitable) once locked.
func trace_to(target: Vector2, area: Rect2) -> void:
	_target = target
	_area = area
	# Continue from wherever the reticle already is (the previous attack's
	# target), otherwise enter from a random spot in the area.
	if visible and _state != State.FADING:
		_boid_pos = position
	else:
		_boid_pos = area.position + Vector2(randf() * area.size.x, randf() * area.size.y)
	_wander = randf() * TAU
	_boid_vel = Vector2.from_angle(_wander) * MAX_SPEED * 0.6
	_t = 0.0
	locked = false
	modulate.a = 1.0
	position = _boid_pos
	visible = true
	_state = State.TRACE
	await trace_finished

## Player targeting: follow a point (the mouse).
func follow(p: Vector2, alpha: float, is_locked: bool) -> void:
	_state = State.IDLE
	position = p
	modulate.a = alpha
	locked = is_locked
	visible = alpha > 0.01

## A shot goes off at the current position: a flash + expanding ring, then fades away.
func fire_and_fade() -> void:
	_flash = 1.0
	locked = true
	visible = true
	modulate.a = 1.0
	_state = State.FADING

func fire() -> void:
	_flash = 1.0

func fade_out() -> void:
	if visible:
		_state = State.FADING

func hide_now() -> void:
	_state = State.IDLE
	visible = false
	locked = false

func _process(delta: float) -> void:
	if not visible:
		return
	if not GameSettings.reduce_motion:
		_spin += delta * (5.0 if locked else 1.6)
	_flash = maxf(0.0, _flash - delta * 3.0)
	match _state:
		State.TRACE:
			_step_trace(delta)
		State.LOCKING:
			_lock_t += delta
			if _lock_t >= LOCK_DURATION:
				_state = State.IDLE
				trace_finished.emit()
		State.FADING:
			if _flash <= 0.0:
				modulate.a = maxf(0.0, modulate.a - delta * 5.0)
				if modulate.a <= 0.0:
					hide_now()
	queue_redraw()

func _step_trace(delta: float) -> void:
	_t += delta
	var u := clampf(_t / TRACE_DURATION, 0.0, 1.0)

	_wander += randf_range(-1.0, 1.0) * WANDER_JITTER * delta
	var steer := Vector2.from_angle(_wander) * WANDER_FORCE
	if not _area.has_point(_boid_pos):
		steer += (_area.get_center() - _boid_pos).normalized() * CONTAIN_FORCE
	steer += (_target - _boid_pos).normalized() * SEEK_FORCE * u
	_boid_vel = (_boid_vel + steer * delta).limit_length(MAX_SPEED)
	_boid_pos += _boid_vel * delta

	# Homing: the drawn reticle is pulled from the free-flying boid onto the
	# target, gently at first and fully by the end of the trace.
	var homing := smoothstep(0.25, 1.0, u)
	position = _boid_pos.lerp(_target, homing)

	if u >= 1.0:
		position = _target
		locked = true
		_lock_t = 0.0
		_state = State.LOCKING

func _draw() -> void:
	var color: Color = Palette.DANGER if locked else Palette.WARNING
	var r := RADIUS
	if _state == State.LOCKING:
		r = lerpf(RADIUS, RADIUS * 0.72, clampf(_lock_t / LOCK_DURATION, 0.0, 1.0))
	elif locked:
		r = RADIUS * 0.72

	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, color, 2.0, true)
	for k in range(4):
		var dir := Vector2.from_angle(_spin + k * PI / 2.0)
		draw_line(dir * (r - 7.0), dir * (r + 9.0), color, 2.0, true)
	draw_circle(Vector2.ZERO, 2.5, color)

	if _flash > 0.0:
		draw_circle(Vector2.ZERO, r * 0.8, Color(1, 1, 1, _flash * 0.8))
		draw_arc(Vector2.ZERO, r + (1.0 - _flash) * 34.0, 0.0, TAU, 40, Color(color, _flash), 3.0, true)

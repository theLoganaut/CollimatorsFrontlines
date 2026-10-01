class_name HealthBar
extends Control
## A labeled HP bar (`current / max`), glass like the rest of combat's UI.
## HP changes slide the bar (and count the number) down to the new value
## instead of jumping.
##
## Two reds (Logan, 2026-09-30): HP above the mech's defeat line is the
## usual red; the stretch below it, the HP it blows up at, is a deeper red,
## so the lighter part is what's left to take off. Kept quiet on purpose
## (clearly a health bar, never a distraction): lost HP lingers as a pale
## chunk that drains away, a hit gives a soft flash, faint ticks mark every
## `tick_step()` HP.

const ANIM_SECONDS := 0.5
const GHOST_DELAY := 0.35
const GHOST_DRAIN := 0.45
const FLASH_SECONDS := 0.2

const RED_TOP := Palette.DANGER
const RED_BOTTOM := Color("c23a26")
const DEEP_TOP := Color("7c1d14")
const DEEP_BOTTOM := Color("631710")
const GHOST := Color(0.95, 0.82, 0.72, 0.6)
const HEAL := Color("7fe0a0")
const TRACK := Color(0.03, 0.04, 0.06, 0.85)

var current: int = 0
var max_value: int = 1
var font_size: int = 11
## HP at or below which the mech is destroyed (0 = none): the deep red zone.
var threshold: int = 0
var _shown: float = -1.0 # -1 = not set yet, the first set_hp() doesn't animate
var _label: Label
var _tween: Tween
var _ghost: float = -1.0
var _ghost_tween: Tween
var _flash: float = 0.0
var _flash_color: Color = Color.WHITE

func _ready() -> void:
	custom_minimum_size = Vector2(80, 16)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Palette.TEXT)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 3)
	_label.add_theme_font_size_override("font_size", font_size)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_refresh_label()

func set_hp(p_current: int, p_max: int) -> void:
	current = maxi(p_current, 0)
	max_value = maxi(p_max, 1)
	if _shown < 0.0:
		_ghost = float(current)
		_set_shown(float(current))
		return
	if is_equal_approx(_shown, float(current)):
		return
	if float(current) < _shown:
		_ghost = maxf(_ghost, _shown)
		if _ghost_tween != null:
			_ghost_tween.kill()
		_ghost_tween = create_tween()
		_ghost_tween.tween_interval(GHOST_DELAY)
		_ghost_tween.tween_method(_set_ghost, _ghost, float(current), GHOST_DRAIN)
		_start_flash(Color.WHITE)
	else:
		_ghost = float(current)
		_start_flash(HEAL)
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_shown, _shown, float(current), ANIM_SECONDS).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

func _start_flash(color: Color) -> void:
	_flash_color = color
	_flash = 1.0
	create_tween().tween_method(func(v: float): _flash = v; queue_redraw(), 1.0, 0.0, FLASH_SECONDS)

func _set_shown(v: float) -> void:
	_shown = v
	_refresh_label()
	queue_redraw()

func _set_ghost(v: float) -> void:
	_ghost = v
	queue_redraw()

func _refresh_label() -> void:
	if _label == null:
		return
	_label.text = "%d / %d HP" % [roundi(maxf(_shown, 0.0)), max_value]

## HP between ticks: at most about 10 ticks whatever the max.
func tick_step() -> int:
	for step in [10, 25, 50, 100, 250]:
		if max_value / step <= 10:
			return step
	return 500

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var w := rect.size.x
	var h := rect.size.y
	draw_rect(rect, TRACK, true)
	var frac: float = clampf(_shown / float(max_value), 0.0, 1.0)
	var ghost_frac: float = clampf(_ghost / float(max_value), 0.0, 1.0)
	var line_frac: float = clampf(float(threshold) / float(max_value), 0.0, 1.0) if threshold > 0 else 0.0
	# The deep zone's track shows even once the HP has left it.
	if line_frac > 0.0:
		draw_rect(Rect2(0, 0, w * line_frac, h), Color(DEEP_BOTTOM, 0.35), true)
	if ghost_frac > frac:
		draw_rect(Rect2(w * frac, 0, w * (ghost_frac - frac), h), GHOST, true)
	if frac > 0.0:
		var deep_w: float = w * minf(frac, line_frac)
		if deep_w > 0.0:
			_gradient(Rect2(0, 0, deep_w, h), DEEP_TOP, DEEP_BOTTOM)
		if frac > line_frac:
			_gradient(Rect2(w * line_frac, 0, w * (frac - line_frac), h), RED_TOP, RED_BOTTOM)
		# a faint sheen along the top edge
		draw_rect(Rect2(0, 1, w * frac, maxf(1.0, h * 0.2)), Color(1, 1, 1, 0.06), true)
	# ticks
	var step := tick_step()
	var hp := step
	while hp < max_value:
		var x: float = w * float(hp) / float(max_value)
		var tall := hp % (step * 5) == 0
		draw_line(Vector2(x, h - (h * 0.45 if tall else h * 0.25)), Vector2(x, h), Color(0, 0, 0, 0.3), 1.0)
		hp += step
	if _flash > 0.0:
		draw_rect(Rect2(0, 0, w * maxf(frac, ghost_frac), h), Color(_flash_color, 0.18 * _flash), true)
	draw_rect(rect, Palette.BORDER, false, 1.0)
	if threshold > 0:
		var x: float = w * line_frac
		# The defeat line: notches on the top and bottom edges, clear of the text.
		draw_line(Vector2(x, -3), Vector2(x, 3), Color(Palette.TEXT, 0.8), 1.5)
		draw_line(Vector2(x, h - 3), Vector2(x, h + 3), Color(Palette.TEXT, 0.8), 1.5)

## A vertical two-color gradient (a few bands, cheap to draw).
func _gradient(r: Rect2, top: Color, bottom: Color) -> void:
	var bands := 3
	for i in range(bands):
		var y0 := r.position.y + r.size.y * float(i) / bands
		var y1 := r.position.y + r.size.y * float(i + 1) / bands
		draw_rect(Rect2(r.position.x, y0, r.size.x, y1 - y0), top.lerp(bottom, float(i) / (bands - 1)), true)

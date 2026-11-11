class_name SlotReel
extends Control
## A slot-machine reel the size of a part card (Logan, 2026-11-11): after a
## salvage crate pops, each slot spins through parts of its category and
## lands on the part really inside, one slot after another. The strip is a
## column of PartCardUIs (random parts of the category, then the real one,
## then one more for the overshoot to show), scrolled down a clipped window
## that eases out with a small bounce; a tick plays as each card passes and
## a thunk and a flash in the category's color when it lands.

signal landed(reel: SlotReel)

const GAP := 14.0
const FILLERS := 9

var real_id: String = ""
var category: String = ""
var _strip: Control
var _step: float = PartCardUI.SIZE.y + GAP
var _last_tick: int = 0
var _flash: float = 0.0
var _speed: float = 0.0
var _prev_y: float = 0.0
var _spinning: bool = false # until the crate pops, the slot is an empty, sealed window
var _time: float = 0.0

func setup(id: String, cat: String) -> void:
	real_id = id
	category = cat
	custom_minimum_size = PartCardUI.SIZE
	size = PartCardUI.SIZE
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip = Control.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_strip)
	var pool := ComponentLibrary.all_ids().filter(func(p): return ComponentLibrary.definition(p).get("category", "") == cat and p != id and ComponentLibrary.is_implemented(p))
	pool.shuffle()
	var ids: Array = []
	for i in range(FILLERS):
		ids.append(pool[i % pool.size()] if not pool.is_empty() else id)
	ids.append(id) # the one it lands on
	ids.append(pool[FILLERS % pool.size()] if not pool.is_empty() else id) # past it, for the bounce
	# top to bottom: the strip scrolls down, so the first card shown is the last in the list
	ids.reverse()
	for i in range(ids.size()):
		var card := PartCardUI.new()
		card.selectable = false
		_strip.add_child(card)
		card.setup(ids[i])
		card.position = Vector2(0, i * _step)
	# start with the top card in the window; the real one sits at index 1
	_strip.position.y = -(ids.size() - 1) * _step
	_prev_y = _strip.position.y
	_strip.visible = false

## Spins for `seconds`, then lands on the real part.
func spin(seconds: float) -> void:
	_spinning = true
	_strip.visible = true
	var end := -_step # index 1 in the window
	var tw := create_tween()
	tw.tween_property(_strip, "position:y", end, seconds).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_land)

func _land() -> void:
	_flash = 1.0
	Audio.play("reel_land", 0.03)
	landed.emit(self)

func _process(delta: float) -> void:
	if _strip == null:
		return
	var y := _strip.position.y
	_speed = absf(y - _prev_y) / maxf(delta, 0.0001)
	_prev_y = y
	var passed := int(floor(y / _step))
	if passed != _last_tick:
		_last_tick = passed
		if _speed > 200.0:
			Audio.play("reel_tick", 0.08, -6.0)
	_flash = maxf(0.0, _flash - delta * 2.2)
	_time += delta
	queue_redraw()

func _draw() -> void:
	# the window's glass edges: dark falloff top and bottom while it spins, and the landing flash
	var c := Palette.category_color(category)
	if not _spinning:
		# the empty slot: dark glass in the crate's color, a scan line sweeping it, a lock mark
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.015, 0.03, 0.04, 0.85), true)
		GlassPanel.draw_glass(self, r, 1.0, c, 10.0, 0.45)
		var sy := fmod(_time * 160.0, size.y)
		draw_rect(Rect2(0, sy, size.x, 2.0), Color(c, 0.25), true)
		var font := get_theme_default_font()
		var q := "?"
		var qw := font.get_string_size(q, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
		draw_string(font, Vector2((size.x - qw) / 2.0, size.y / 2.0 + 14.0), q, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(c, 0.35 + 0.15 * sin(_time * 4.0)))
		return
	var blur := clampf(_speed / 2600.0, 0.0, 1.0)
	if blur > 0.02:
		for i in range(8):
			var a := blur * 0.9 * (1.0 - i / 8.0)
			draw_rect(Rect2(0, i * 9.0, size.x, 9.0), Color(0.01, 0.02, 0.03, a), true)
			draw_rect(Rect2(0, size.y - (i + 1) * 9.0, size.x, 9.0), Color(0.01, 0.02, 0.03, a), true)
		# speed streaks
		for i in range(6):
			var x := fmod(i * 37.0 + 11.0, size.x)
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(c, 0.08 * blur), 2.0)
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(c.lightened(0.4), 0.35 * _flash * _flash), true)
		draw_rect(Rect2(Vector2.ZERO, size).grow(-1.0), Color(c.lightened(0.5), _flash), false, 3.0)

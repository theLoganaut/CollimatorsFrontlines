class_name CombatLog
extends Control
## A small scrolling log of what just happened. Not in the Combat Slice
## plan's UI regions — added because CombatManager resolves an entire
## enemy turn instantly/synchronously (no pacing/animation system is in
## scope for this slice), so without *some* feedback the player has no way
## to tell why their HP just changed. Docked in the otherwise-empty
## top-left corner.
##
## It keeps the fight's last HISTORY lines, each with a category, and shows
## the newest that fit; the mouse wheel scrolls back. Filter chips on top:
## All, You (your cards and vents), Enemy (their actions and lines),
## Damage (hits, parts lost, overheats). Turn markers always show.

const LOG_SIZE := Vector2(300, 120)
const MAX_LINES := 5
const HISTORY := 200
const CHIPS_H := 18.0

const CAT_YOU := "you"
const CAT_ENEMY := "enemy"
const CAT_DAMAGE := "damage"
const CAT_TURN := "turn"
const FILTERS := [["", "All"], [CAT_YOU, "You"], [CAT_ENEMY, "Enemy"], [CAT_DAMAGE, "Damage"]]

var _label: Label
var _entries: Array = [] # {"text", "cat"}
var _filter: String = ""
var _scroll: int = 0 # lines scrolled back from the newest
var _chips: Array[Button] = []

func _ready() -> void:
	custom_minimum_size = LOG_SIZE
	size = LOG_SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS

	var row := HBoxContainer.new()
	row.position = Vector2(8, 4)
	row.add_theme_constant_override("separation", 4)
	add_child(row)
	for f in FILTERS:
		var b := Button.new()
		b.text = f[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, CHIPS_H)
		b.add_theme_font_size_override("font_size", 10)
		b.add_theme_stylebox_override("normal", GlassPanel.control_style())
		b.add_theme_stylebox_override("hover", GlassPanel.control_style(GlassPanel.HOLO, 0.0, 0.5))
		b.add_theme_stylebox_override("pressed", GlassPanel.control_style(Palette.LINK, 0.0, 0.8))
		b.add_theme_color_override("font_color", Color("9fb9b6"))
		b.add_theme_color_override("font_pressed_color", Palette.TEXT)
		b.pressed.connect(func():
			_filter = f[0]
			_scroll = 0
			_refresh())
		row.add_child(b)
		_chips.append(b)

	_label = Label.new()
	_label.position = Vector2(10, 8 + CHIPS_H)
	_label.size = LOG_SIZE - Vector2(20, 16 + CHIPS_H)
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_color", Color("9fb9b6"))
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_label.clip_text = true
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_refresh()

func _draw() -> void: # holo glass, like the description box
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.015, 0.03, 0.04, 0.45), true)
	GlassPanel.draw_glass(self, r, 1.0, GlassPanel.HOLO, 8.0, 0.7)

## Adds a line. `category`: CAT_YOU, CAT_ENEMY, CAT_DAMAGE or CAT_TURN.
func log_line(text: String, category: String = CAT_TURN) -> void:
	_entries.append({"text": text, "cat": category})
	if _entries.size() > HISTORY:
		_entries = _entries.slice(_entries.size() - HISTORY)
	_scroll = 0 # a new line jumps back to the newest
	_refresh()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_scroll = mini(_scroll + 1, maxi(0, _shown().size() - MAX_LINES))
			MOUSE_BUTTON_WHEEL_DOWN:
				_scroll = maxi(0, _scroll - 1)
			_:
				return
		accept_event()
		_refresh()

func _shown() -> Array:
	return _entries.filter(func(e): return _filter == "" or e["cat"] == _filter or e["cat"] == CAT_TURN)

func _refresh() -> void:
	for i in range(_chips.size()):
		_chips[i].set_pressed_no_signal(FILTERS[i][0] == _filter)
	var shown := _shown()
	var end := shown.size() - _scroll
	var lines: Array[String] = []
	for e in shown.slice(maxi(0, end - MAX_LINES), end):
		lines.append(e["text"])
	if _scroll > 0:
		lines.append("↓ %d newer (scroll down)" % _scroll)
	_label.text = "\n".join(lines)

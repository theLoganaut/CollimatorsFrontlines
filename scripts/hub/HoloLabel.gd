class_name HoloLabel
extends Control
## The War Room's hover label: a see-through holo glass panel projected
## from a fixed emitter on the hovered station (Hotspot.anchor). A beam runs
## out from the emitter, then the panel unfolds from the beam's end, so the
## label always comes from the same spot whatever part of the station the
## mouse is on. Covers the whole room; draws nothing and takes no clicks.

const HOLO := GlassPanel.HOLO
const PAD := Vector2(12, 9)
const GAP := 22.0         # beam length from the emitter to the panel
const MIN_W := 170.0
const TITLE_SIZE := 15
const LINE_SIZE := 11
const TAG_SIZE := 10
const BEAM_TIME := 0.10
const OPEN_TIME := 0.16
const CLOSE_TIME := 0.08

var _anchor: Vector2
var _panel: Rect2
var _attach: Vector2      # where the beam meets the panel
var _dir: String = "up"
var _title: String = ""
var _lines: Array = []
var _tag: String = ""
var _tag_color: Color = HOLO
var _t: float = 0.0       # 0 = hidden, 1 = fully open
var _open: bool = false
var _time: float = 0.0
## The room area the panel must stay inside (under the top bar).
var bounds: Rect2 = Rect2(0, 0, 1152, 720)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Opens the label for a station: anchor in this node's coordinates, the
## direction its panel grows, a title, detail lines and an optional tag.
func show_for(anchor: Vector2, dir: String, title: String, lines: Array, tag: String = "", tag_color: Color = HOLO) -> void:
	# the same label again only follows its anchor (a War Table pin moves as
	# the terrain turns with the mouse); a new one unfolds from scratch
	var same := _open and title == _title
	_anchor = anchor
	_dir = dir
	_title = title
	_lines = lines
	_tag = tag
	_tag_color = tag_color
	_layout()
	_open = true
	if not same:
		_t = 0.0
	queue_redraw()

func hide_label() -> void:
	_open = false

func _layout() -> void:
	var font := get_theme_default_font()
	var w := font.get_string_size(_title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE).x
	for l in _lines:
		w = maxf(w, font.get_string_size(str(l), HORIZONTAL_ALIGNMENT_LEFT, -1, LINE_SIZE).x)
	if _tag != "":
		w = maxf(w, font.get_string_size(_tag, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_SIZE).x + 10.0)
	var h := PAD.y * 2.0 + TITLE_SIZE + 4.0 + _lines.size() * (LINE_SIZE + 4.0) + (TAG_SIZE + 10.0 if _tag != "" else 0.0)
	var sz := Vector2(maxf(MIN_W, w + PAD.x * 2.0), h)
	var diag := GAP * 0.7
	match _dir:
		"up_right":
			_attach = _anchor + Vector2(diag, -diag)
			_panel = Rect2(_attach - Vector2(0, sz.y), sz)
		"up_left":
			_attach = _anchor + Vector2(-diag, -diag)
			_panel = Rect2(_attach - sz, sz)
		"right":
			_attach = _anchor + Vector2(GAP, 0)
			_panel = Rect2(_attach - Vector2(0, sz.y / 2.0), sz)
		_:
			_attach = _anchor + Vector2(0, -GAP)
			_panel = Rect2(_attach - Vector2(sz.x / 2.0, sz.y), sz)
	# keep it on screen; the beam then bends to wherever the panel landed
	_panel.position = _panel.position.clamp(bounds.position, bounds.end - _panel.size)
	_attach = _attach.clamp(_panel.position, _panel.end)

func _process(delta: float) -> void:
	_time += delta
	var target := 1.0 if _open else 0.0
	if _t == target and not _open:
		return
	var speed := 1.0 / (BEAM_TIME + OPEN_TIME) if _open else 1.0 / CLOSE_TIME
	_t = move_toward(_t, target, speed * delta)
	queue_redraw()

func _draw() -> void:
	if _t <= 0.0:
		return
	var beam_share := BEAM_TIME / (BEAM_TIME + OPEN_TIME)
	var beam := clampf(_t / beam_share, 0.0, 1.0)
	var unfold := clampf((_t - beam_share) / (1.0 - beam_share), 0.0, 1.0)
	var flicker := 1.0 if GameSettings.reduce_motion else 0.93 + 0.07 * sin(_time * 31.0) * sin(_time * 7.0)
	var a := flicker * (1.0 if _open else _t)

	# emitter and beam
	draw_circle(_anchor, 5.0, Color(HOLO, 0.18 * a))
	draw_circle(_anchor, 2.5, Color(HOLO, 0.95 * a))
	var tip := _anchor.lerp(_attach, beam)
	draw_line(_anchor, tip, Color(HOLO, 0.25 * a), 5.0, true)
	draw_line(_anchor, tip, Color(HOLO, 0.9 * a), 1.5, true)
	if unfold <= 0.0:
		return

	# the glass unfolds out of the beam's end
	var p := _panel
	var grown := Rect2(p.position.lerp(_attach, 1.0 - unfold), p.size * unfold)
	if grown.size.x < 1.0 or grown.size.y < 1.0:
		return
	GlassPanel.draw_glass(self, grown, a, HOLO, 8.0 * unfold)
	if unfold < 0.7:
		return

	# text
	var ta := a * (unfold - 0.7) / 0.3
	var font := get_theme_default_font()
	var pos := p.position + PAD
	draw_string(font, pos + Vector2(0, TITLE_SIZE), _title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE, Color(Color("dffcf8"), ta))
	pos.y += TITLE_SIZE + 4.0
	for l in _lines:
		draw_string(font, pos + Vector2(0, LINE_SIZE), str(l), HORIZONTAL_ALIGNMENT_LEFT, -1, LINE_SIZE, Color(Color("b9d8d4"), ta))
		pos.y += LINE_SIZE + 4.0
	if _tag != "":
		var tw := font.get_string_size(_tag, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_SIZE).x
		var chip := Rect2(pos + Vector2(0, 4), Vector2(tw + 10.0, TAG_SIZE + 5.0))
		draw_rect(chip, Color(_tag_color, 0.22 * ta), true)
		draw_rect(chip, Color(_tag_color, 0.8 * ta), false, 1.0)
		draw_string(font, chip.position + Vector2(5, TAG_SIZE + 1.0), _tag, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_SIZE, Color(_tag_color, ta))

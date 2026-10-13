class_name HoloHint
extends CanvasLayer
## A small holo window explaining statuses and keywords, open the moment
## something is hovered (Logan, 2026-10-02: in place of Godot's delayed,
## placeholder-looking tooltips). One shared window: a keyword in part text
## (UIKit.rich_label) opens it just below the word; a hovered card in the
## hand opens it just above the card. It follows its owner and closes when
## the owner leaves the screen.

const WIDTH := 300.0
const GAP := 10.0
const MARGIN := 12.0 # from the screen's edges

static var _inst: HoloHint = null
## Screen areas a window above its owner slides sideways to keep clear of
## (combat: the heat box and its caption), as Callables returning a global
## Rect2; ones whose object is gone are skipped.
static var keep_clear: Array[Callable] = []

var _panel: PanelContainer
var _vbox: VBoxContainer
var _owner: Control = null
var _above: bool = false
var _point: Vector2 = Vector2.ZERO

## Shows `lines` (plain text, each [text, color]) then `entries` ({label,
## rule, color}) for `owner`: above it when `above`, else just below
## `point` (a global position, say the mouse on a word). Nothing to say
## closes it.
static func open(owner: Control, entries: Array, lines: Array = [], above: bool = false, point: Vector2 = Vector2.ZERO) -> void:
	if entries.is_empty() and lines.is_empty():
		close(owner)
		return
	var h := _window()
	h._owner = owner
	h._above = above
	h._point = point
	h._fill(entries, lines)

## Closes it if `owner` opened it (null: whoever did).
static func close(owner: Control = null) -> void:
	if _inst == null or not is_instance_valid(_inst):
		return
	if owner == null or owner == _inst._owner:
		_inst._owner = null
		_inst._panel.visible = false

static func _window() -> HoloHint:
	if _inst == null or not is_instance_valid(_inst):
		_inst = HoloHint.new()
		(Engine.get_main_loop() as SceneTree).root.add_child(_inst)
	return _inst

func _init() -> void:
	layer = 140
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", GlassPanel.panel_style(GlassPanel.HOLO, 10.0))
	_panel.draw.connect(func(): GlassPanel.draw_frame(_panel, Rect2(Vector2.ZERO, _panel.size), 0.9, GlassPanel.HOLO, 8.0))
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	add_child(_panel)
	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 6)
	_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_vbox)

func _fill(entries: Array, lines: Array) -> void:
	for c in _vbox.get_children():
		_vbox.remove_child(c)
		c.queue_free()
	for line in lines:
		var l := _text("[color=#%s]%s[/color]" % [(line[1] as Color).to_html(false), str(line[0]).replace("[", "[lb]")])
		_vbox.add_child(l)
	for e in entries:
		var col: Color = e["color"]
		_vbox.add_child(_text("[color=#%s][b]%s[/b][/color]  %s" % [col.lightened(0.15).to_html(false), e["label"], str(e["rule"]).replace("[", "[lb]")]))
	_panel.visible = true
	_panel.reset_size()
	_place()

func _text(bbcode: String) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(WIDTH - 20.0, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("normal_font_size", 13)
	l.add_theme_font_size_override("bold_font_size", 13)
	l.add_theme_color_override("default_color", Color("d6ecea"))
	l.text = bbcode
	return l

func _process(_delta: float) -> void:
	if not _panel.visible:
		return
	if _owner == null or not is_instance_valid(_owner) or not _owner.is_visible_in_tree():
		close()
		return
	_place()

## Above the owner (centered on it), or below the point; kept on screen.
func _place() -> void:
	var screen: Vector2 = _panel.get_viewport_rect().size
	var s := _panel.size
	var pos: Vector2
	if _above and _owner != null and is_instance_valid(_owner):
		var r := _owner.get_global_rect()
		pos = Vector2(r.get_center().x - s.x / 2.0, r.position.y - s.y - GAP)
		pos.x = _slide_clear(pos, s)
	else:
		pos = _point + Vector2(-24.0, 18.0)
		if pos.y + s.y > screen.y - MARGIN: # no room below: above the point instead
			pos.y = _point.y - s.y - GAP
	pos.x = clampf(pos.x, MARGIN, maxf(MARGIN, screen.x - s.x - MARGIN))
	pos.y = clampf(pos.y, MARGIN, maxf(MARGIN, screen.y - s.y - MARGIN))
	_panel.position = pos

## The x nearest `pos.x` at which the window misses every keep_clear area.
func _slide_clear(pos: Vector2, s: Vector2) -> float:
	var x := pos.x
	for f in keep_clear:
		if not f.is_valid():
			continue
		var avoid: Rect2 = f.call()
		var box := Rect2(Vector2(x, pos.y), s)
		if not box.intersects(avoid):
			continue
		var left := avoid.position.x - s.x - GAP
		var right := avoid.end.x + GAP
		x = left if absf(left - x) <= absf(right - x) else right
	return x

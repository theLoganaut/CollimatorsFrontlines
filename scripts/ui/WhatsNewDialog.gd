class_name WhatsNewDialog
extends CanvasLayer
## The War Room's What's New?! board: a bulletin on holo glass of what each
## update changed (data/changelog.json, newest first), and a What's Next?!
## button at the top that swaps to the roadmap (the planned minor and major
## updates, in order). It pops up on the first War Room visit after an
## update (a brand-new pilot skips it); opening it marks this version as read
## (Profile.seen_hints). The War Room's version stamp (bottom right) reopens it.

const PATH := "res://data/changelog.json"
const PANEL_SIZE := Vector2(620, 540)
const BULLET := Color("7fe0d4")
const LEAD := Color("eefcfa")
const BODY := Color("b9d8d4")

static var _open: WhatsNewDialog = null

var _panel: GlassPanel
var _title: Label
var _swap: Button
var _list: VBoxContainer
var _scroll: ScrollContainer
var _showing_next: bool = false

static func data() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

## This build's version, as the changelog names it ("0.2.0").
static func current_version() -> String:
	return str(data().get("current", ""))

static func _seen_key() -> String:
	return "whats_new:" + current_version()

## True until the pilot has opened the board for this version.
static func unread() -> bool:
	return current_version() != "" and not Profile.seen_hints.has(_seen_key())

## Marks this version's notes as read, so the board stops popping up.
static func mark_read() -> void:
	if unread():
		Profile.seen_hints.append(_seen_key())
		Profile.save()

## Opens the board over the current screen (once at a time).
static func open(tree: SceneTree) -> void:
	if _open != null and is_instance_valid(_open):
		return
	var d := WhatsNewDialog.new()
	_open = d
	tree.root.add_child(d)
	mark_read()

func _ready() -> void:
	layer = 240
	process_mode = Node.PROCESS_MODE_ALWAYS
	CrashLog.crumb("what's new opened")
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close())
	add_child(dim)
	_panel = GlassPanel.new()
	_panel.tint = 0.9
	_panel.size = PANEL_SIZE
	add_child(_panel)
	var v := VBoxContainer.new()
	v.position = Vector2(24, 18)
	v.size = PANEL_SIZE - Vector2(48, 36)
	v.add_theme_constant_override("separation", 12)
	_panel.add_child(v)
	# the swap button sits at the top of the board
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	v.add_child(top)
	_title = UIKit.label("", 20, LEAD)
	top.add_child(_title)
	top.add_child(UIKit.spacer())
	_swap = GlassPanel.button("", 13, true, Palette.LINK)
	_swap.custom_minimum_size = Vector2(150, 34)
	_swap.pressed.connect(func():
		_showing_next = not _showing_next
		_fill())
	top.add_child(_swap)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)
	var bottom := HBoxContainer.new()
	v.add_child(bottom)
	bottom.add_child(UIKit.spacer())
	var close_btn := GlassPanel.button("Close", 13)
	close_btn.custom_minimum_size = Vector2(110, 34)
	close_btn.pressed.connect(close)
	bottom.add_child(close_btn)
	_fill()
	get_viewport().size_changed.connect(_center)
	_center()

func _center() -> void:
	_panel.position = ((get_viewport().get_visible_rect().size - PANEL_SIZE) / 2.0).floor()

## The changelog (newest first), or the What's Next?! roadmap.
func _fill() -> void:
	for c in _list.get_children():
		c.queue_free()
	var d := data()
	_title.text = "WHAT'S NEXT?!" if _showing_next else "WHAT'S NEW?!"
	_swap.text = "What's New?!" if _showing_next else "What's Next?!"
	if _showing_next:
		var next: Dictionary = d.get("next", {})
		_list.add_child(UIKit.label("The roadmap: planned, and it may shift", 13, Palette.TEXT_MUTED))
		for u in next.get("updates", []):
			_list.add_child(_gap(6))
			_add_update_head(u)
			for item in u.get("items", []):
				_add_item(item, 0)
		if not (next.get("items", []) as Array).is_empty():
			_list.add_child(_gap(10))
		for item in next.get("items", []):
			_add_item(item, 0)
	else:
		var first := true
		for r in d.get("releases", []):
			if not first:
				_list.add_child(_gap(10))
			first = false
			_add_release_head(r)
			if r.has("note"):
				_add_note(r["note"])
			for item in r.get("items", []):
				_add_item(item, 0)
	_scroll.scroll_vertical = 0

func _add_release_head(r: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var version := UIKit.label(str(r.get("version", "")), 17, Palette.SCRAPS)
	row.add_child(version)
	if str(r.get("title", "")) != "":
		row.add_child(UIKit.label("—  " + str(r["title"]), 15, BODY))
	_list.add_child(row)
	var line := ColorRect.new()
	line.color = Color(GlassPanel.HOLO, 0.35)
	line.custom_minimum_size = Vector2(0, 1)
	_list.add_child(line)

## A release's special note (0.2.2: the Discord is open), on its own lit
## glass under the version: a title, a line, and a button that opens `link`.
const NOTE_COLOR := Color("5865f2") # Discord's blurple

func _add_note(n: Dictionary) -> void:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", GlassPanel.panel_style(NOTE_COLOR, 10.0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(UIKit.label(str(n.get("title", "")), 16, NOTE_COLOR.lightened(0.45)))
	col.add_child(UIKit.label(str(n.get("text", "")), 13, BODY, true))
	var link := str(n.get("link", ""))
	if link != "":
		var b := GlassPanel.button(str(n.get("button", "Open")), 13, true, NOTE_COLOR)
		b.custom_minimum_size = Vector2(150, 36)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(func():
			Audio.play("ui")
			OS.shell_open(link))
		row.add_child(b)
	_list.add_child(_gap(4))
	_list.add_child(box)
	_list.add_child(_gap(4))

## A planned update on the roadmap: its version, minor or major, and when.
func _add_update_head(u: Dictionary) -> void:
	var major := str(u.get("kind", "")) == "major"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(UIKit.label(str(u.get("version", "")), 17, Palette.SCRAPS))
	row.add_child(UIKit.label("MAJOR UPDATE" if major else "Minor update", 13, LEAD if major else BULLET))
	row.add_child(UIKit.spacer())
	row.add_child(UIKit.label(str(u.get("when", "")), 13, Palette.TEXT_MUTED))
	_list.add_child(row)
	var line := ColorRect.new()
	line.color = Color(GlassPanel.HOLO, 0.35)
	line.custom_minimum_size = Vector2(0, 1)
	_list.add_child(line)

## One bullet: a line of text, or {label, text} with a lit lead-in, and
## any sub-items indented under it.
func _add_item(item, depth: int) -> void:
	var lead := ""
	var text := ""
	var subs: Array = []
	if item is Dictionary:
		lead = str(item.get("label", ""))
		text = str(item.get("text", ""))
		subs = item.get("items", [])
	else:
		text = str(item)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var indent := Control.new()
	indent.custom_minimum_size = Vector2(4 + 22 * depth, 0)
	row.add_child(indent)
	var dot := UIKit.label("•" if depth == 0 else "–", 14, BULLET)
	dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(dot)
	var body := UIKit.rich_label("", 14 if depth == 0 else 13, BODY)
	var parts: Array = []
	if lead != "":
		parts.append("[color=#%s]%s[/color]" % [LEAD.to_html(false), lead])
	if text != "":
		parts.append(text)
	body.text = " ".join(parts)
	row.add_child(body)
	_list.add_child(row)
	for s in subs:
		_add_item(s, depth + 1)

func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()

func close() -> void:
	_open = null
	queue_free()

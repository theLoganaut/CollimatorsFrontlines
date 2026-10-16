class_name PassiveRow
extends Control
## A mech's badge row (above the player's health bar, above each enemy's
## image): its passives, each status waiting on it (and, with
## part_statuses, on its parts, summed per status) and a primed protocol.
## Every passive icon starts hidden: CombatScene's opening reveal flies each
## passive's card to its slot and pops the icon in. Hovering a badge
## explains it in the Description Box.
##
## Logan, 2026-10-16: badges sit left to right in the order they were
## applied (passives first, as the fight opens), the group centered in the
## row: when one comes or goes, they all slide to stay centered. When they'd run past the row's width, the last
## slot becomes "…": hovering it opens the rest in rows under this one (the
## player's health bar steps aside, expanded_changed), and a right-click
## keeps them open so each can be hovered; another right-click anywhere
## closes them (CombatScene, unpin_any).

const GAP := 6.0
const NUMBER_ROOM := 14.0 # a stack number above (or below) a badge
const SLIDE := 0.15

## The overflow opened or closed (the player's panel hides its health bar).
signal expanded_changed(on: bool)

var mech: MechData
## Stack numbers under the badges or over them.
var numbers_below: bool = true
## What the row holds: passive icons; status and protocol badges; and (with
## statuses) the statuses on the mech's parts, summed per status.
var show_passives: bool = true
var show_statuses: bool = true
var part_statuses: bool = false
var _width: float = 0.0
var _icons: Dictionary = {} # ComponentData -> PassiveIcon
var _order: Array[ComponentData] = []
var _status_badges: Dictionary = {} # status -> StatusBadge
var _protocol_badge: StatusBadge = null
var _protocol_info: Array = [] # [title, text]; [] = none
## Every badge in the order it appeared.
var _seq: Array[Control] = []
## The overflow: badges past the row's room live here, shown while open.
var _more: Control
var _slides: Dictionary = {} # badge -> its slide tween from the last _layout
var _more_badge: MoreBadge
var _expanded: bool = false
var _laid_out: bool = false
## The row whose overflow a right-click pinned open (one at a time).
static var _pinned: PassiveRow = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## `row_width`: the room the badges get.
func setup(p_mech: MechData, row_width: float) -> void:
	mech = p_mech
	_width = row_width
	size = Vector2(row_width, PassiveIcon.ICON_SIZE.y)
	_more = Control.new()
	_more.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_more.visible = false
	_more.draw.connect(_draw_more)
	add_child(_more)
	_more_badge = MoreBadge.new()
	_more_badge.row = self
	_more_badge.visible = false
	add_child(_more_badge)
	for comp in (mech.passive_components() if show_passives else []):
		var icon := PassiveIcon.new()
		icon.numbers_below = numbers_below
		add_child(icon)
		icon.setup(comp, mech)
		icon.visible = false
		_icons[comp] = icon
		_order.append(comp)
		_seq.append(icon)
	_protocol_badge = StatusBadge.new()
	_protocol_badge.kind = "protocol"
	_protocol_badge.visible = false
	add_child(_protocol_badge)
	UIState.describe_on_hover(_protocol_badge, func(): return _protocol_info)
	_layout()

func icon_for(component: ComponentData) -> PassiveIcon:
	return _icons.get(component, null)

## Where a passive's badge shows on screen: its own slot, or the "…" when
## it's in the closed overflow (the reveal flies its card there).
func slot_center_global(component: ComponentData) -> Vector2:
	var icon := icon_for(component)
	if icon == null:
		return get_global_rect().get_center()
	if icon.get_parent() == _more and not _expanded:
		return _more_badge.get_global_rect().get_center()
	return icon.get_global_rect().get_center()

## Shows any icon the reveal didn't get to (it was skipped).
func reveal_all() -> void:
	for icon in _icons.values():
		if not icon.visible:
			icon.pop_in()

## Whether anything shows in the row.
func has_any() -> bool:
	return not _order.is_empty() or not _status_badges.is_empty() or _protocol_badge.visible

## Whether any badge shows a stack number (it needs room under or over the row).
func has_numbers() -> bool:
	return not _status_badges.is_empty()

## The primed protocol, [title, text] for its hover; [] hides it.
func set_protocol(info: Array) -> void:
	if info == _protocol_info:
		return
	_protocol_info = info
	var on := not info.is_empty()
	if on != _protocol_badge.visible:
		_protocol_badge.visible = on
		if on: # primed now: it goes to the end of the row
			_seq.append(_protocol_badge)
			_protocol_badge.pop_in()
		else:
			_seq.erase(_protocol_badge)
	_layout()

func refresh() -> void:
	for icon in _icons.values():
		icon.queue_redraw()
	var now := {}
	if show_statuses:
		for s in mech.mech_statuses:
			if s.stacks > 0:
				now[s.status] = s.stacks
		if part_statuses:
			for comp in mech.non_destroyed_components():
				for s in comp.statuses:
					if s.stacks > 0:
						now[s.status] = int(now.get(s.status, 0)) + s.stacks
	var changed := false
	for st in _status_badges.keys():
		if not now.has(st):
			_seq.erase(_status_badges[st])
			_slides.erase(_status_badges[st])
			_status_badges[st].queue_free()
			_status_badges.erase(st)
			changed = true
	for st in now:
		var b: StatusBadge = _status_badges.get(st, null)
		if b == null:
			b = StatusBadge.new()
			b.kind = "status"
			b.status = st
			b.numbers_below = numbers_below
			add_child(b)
			UIState.describe_on_hover(b, func(): return _describe(st))
			# ...and lights every part of this mech that holds it.
			b.mouse_entered.connect(func(): UIState.set_hovered_status(b, st, mech))
			b.mouse_exited.connect(func(): UIState.clear_hovered_status(b))
			b.tree_exiting.connect(func(): UIState.clear_hovered_status(b))
			_status_badges[st] = b
			_seq.append(b) # newest last
			b.pop_in()
			changed = true
		if b.stacks != now[st]:
			b.stacks = now[st]
			b.queue_redraw()
	if changed:
		_layout()

## A status badge's hover: its rule, and which parts hold it.
func _describe(st: String) -> Array:
	var e := StatusGlossary.get_entry(st)
	var total := mech.mech_status_stacks(st)
	var on: Array[String] = []
	if part_statuses:
		for comp in mech.non_destroyed_components():
			var n := comp.status_stacks(st)
			if n > 0:
				total += n
				on.append("%s %d" % [comp.name, n])
	var text: String = e["rule"] # says how long it lasts
	if not on.is_empty():
		text = "On %s.\n%s" % [", ".join(on), text]
	return ["%s %d" % [e["label"], total], text.strip_edges()]

## How many badge slots fit across the row.
func _capacity() -> int:
	return maxi(1, int((_width + GAP) / (PassiveIcon.ICON_SIZE.x + GAP)))

## Slot `i` of the row (`count` badges in it), or (in_more) of the
## overflow's rows under it; each row's badges centered in the width.
func _slot(i: int, in_more: bool, count: int) -> Vector2:
	var cap := _capacity()
	var step := PassiveIcon.ICON_SIZE.x + GAP
	var in_row := count if not in_more else mini(cap, count - (i / cap) * cap)
	var x0 := (_width - (in_row * step - GAP)) / 2.0
	if not in_more:
		return Vector2(x0 + i * step, 0)
	return Vector2(x0 + (i % cap) * step, (PassiveIcon.ICON_SIZE.y + NUMBER_ROOM) * (1 + i / cap))

## Left to right in the order applied; past the row's room, the last slot
## is "…" and the rest wait in the overflow, in rows under this one.
func _layout() -> void:
	var cap := _capacity()
	var overflow := _seq.size() > cap
	var shown := cap - 1 if overflow else _seq.size()
	for i in range(_seq.size()):
		var item := _seq[i]
		var in_more := i >= shown
		var to := _slot(i - shown if in_more else i, in_more, _seq.size() - shown if in_more else (cap if overflow else shown))
		var parent := _more if in_more else self
		# a slide from the last layout would carry on toward its old slot
		var slide: Tween = _slides.get(item)
		if slide != null and slide.is_valid():
			slide.kill()
		_slides.erase(item)
		if item.get_parent() != parent:
			item.reparent(parent, false)
			item.position = to
		elif _laid_out and item.position != to and item.visible:
			slide = item.create_tween()
			slide.tween_property(item, "position", to, SLIDE).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			_slides[item] = slide
		else:
			item.position = to
	_more_badge.visible = overflow
	_more_badge.position = _slot(cap - 1, false, cap)
	_more_badge.hidden_count = _seq.size() - shown
	_more_badge.queue_redraw()
	var rows := ceili(float(_seq.size() - shown) / float(cap)) if overflow else 0
	_more.size = Vector2(_width, (PassiveIcon.ICON_SIZE.y + NUMBER_ROOM) * (rows + 1))
	_more.queue_redraw()
	if not overflow:
		_set_expanded(false)
	_laid_out = true

## Opens / closes the overflow under the row.
func _set_expanded(on: bool) -> void:
	if not on and _pinned == self:
		_pinned = null
	if on == _expanded:
		return
	_expanded = on
	_more.visible = on
	z_index = 20 if on else 0 # over the health bar and the mech image
	_more_badge.queue_redraw()
	expanded_changed.emit(on)

## A right-click on the "…" keeps the overflow open (or closes it).
func _toggle_pin() -> void:
	if _pinned == self:
		_set_expanded(false)
		return
	if _pinned != null and is_instance_valid(_pinned):
		_pinned._set_expanded(false)
	_set_expanded(true)
	_pinned = self

## A right-click anywhere closes a pinned overflow. True if one was open.
static func unpin_any() -> bool:
	if _pinned == null or not is_instance_valid(_pinned):
		_pinned = null
		return false
	_pinned._set_expanded(false)
	return true

## Glass behind the overflow's rows (they sit over the health bar / image).
func _draw_more() -> void:
	var top := PassiveIcon.ICON_SIZE.y + 4.0
	var r := Rect2(Vector2(-6, top), Vector2(_width + 12, _more.size.y - top + 6))
	_more.draw_rect(r, Color(0.015, 0.03, 0.04, 0.92), true)
	GlassPanel.draw_glass(_more, r, 1.0, GlassPanel.HOLO, 6.0, 0.85)
	_more.draw_rect(r, Color(GlassPanel.HOLO, 0.7), false, 1.0)

## The last slot when the badges overflow: "…". Hovering opens the rest; a
## right-click keeps them open.
class MoreBadge extends Control:
	var row: PassiveRow
	var hidden_count: int = 0

	func _ready() -> void:
		size = PassiveIcon.ICON_SIZE
		custom_minimum_size = PassiveIcon.ICON_SIZE
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func(): row._set_expanded(true))
		mouse_exited.connect(func(): if PassiveRow._pinned != row: row._set_expanded(false))
		UIState.describe_on_hover(self, func(): return ["%d more" % hidden_count, "Right-click to keep them open and hover each one. Right-click again to close."])

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			row._toggle_pin()
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2(2, 2), size - Vector2(4, 4))
		var col := GlassPanel.HOLO
		var open := row != null and row._expanded
		draw_rect(r, Color(0.03, 0.04, 0.06, 0.95), true)
		draw_rect(r, col if open else Color(col, 0.7), false, 1.5)
		for k in range(3):
			draw_circle(Vector2(size.x / 2.0 + (k - 1) * 5.0, size.y / 2.0 + 1.0), 1.6, col.lightened(0.3))

## A square badge on the row: a mech-wide status (its marker, edged in its
## colour, the stacks as a number) or a primed protocol (a purple chip).
class StatusBadge extends Control:
	var kind: String = "status"
	var status: String = ""
	var stacks: int = 0
	var numbers_below: bool = true

	func _ready() -> void:
		size = PassiveIcon.ICON_SIZE
		custom_minimum_size = PassiveIcon.ICON_SIZE
		pivot_offset = PassiveIcon.ICON_SIZE / 2.0
		mouse_filter = Control.MOUSE_FILTER_STOP

	func pop_in() -> void:
		scale = Vector2(1.6, 1.6)
		create_tween().tween_property(self, "scale", Vector2.ONE, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	func _draw() -> void:
		var s := size
		var m := s / 2.0
		var col: Color = Palette.PROTOCOL if kind == "protocol" else Palette.status_color(status)
		var r := Rect2(Vector2(2, 2), s - Vector2(4, 4))
		draw_circle(m, s.x * 0.6, Color(col, 0.16))
		draw_rect(r, Color(0.03, 0.04, 0.06, 0.95), true)
		draw_rect(r, col, false, 1.5)
		if kind == "protocol":
			var c := col.lightened(0.25)
			draw_rect(Rect2(m - Vector2(4, 4), Vector2(8, 8)), c, false, 1.5)
			for d in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
				draw_line(m + d * 4.0, m + d * 8.0, c, 1.5)
			return
		Palette.draw_status(self, m, 7.5, status)
		var font := get_theme_default_font()
		var y := s.y + 12.0 if numbers_below else -3.0
		var text := str(stacks)
		for o in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			draw_string(font, Vector2(0, y) + o, text, HORIZONTAL_ALIGNMENT_CENTER, s.x, 12, Color(0, 0, 0, 0.85))
		draw_string(font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, s.x, 12, col.lightened(0.2))

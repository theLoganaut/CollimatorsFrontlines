class_name PassiveRow
extends Control
## A mech's passive badges, centered in a row (above the player's health
## bar, below each enemy's). Every passive icon starts hidden: CombatScene's
## opening reveal flies each passive's card to its slot and pops the icon in.
##
## After the passives come badges for what's waiting on the mech (Logan,
## 2026-10-02): each mech-wide status (Absorb, Deflect, Smoke) with its
## stacks as a small number (below the badge for enemies, above for the
## player), and a primed protocol (one purple chip for every protocol).
## Hovering a badge explains it in the Description Box.
##
## Enemies use two rows (Logan, 2026-10-02): statuses above the name plate
## (show_passives off, part_statuses on: a status on any of its parts, such
## as Shock, gets a badge too, since the grid is faint at rest) and passives
## under the intents (show_statuses off).

const GAP := 6.0

var mech: MechData
## Stack numbers under the badges (enemies) or over them (the player).
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

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## `row_width`: the width to center the icons in.
func setup(p_mech: MechData, row_width: float) -> void:
	mech = p_mech
	_width = row_width
	size = Vector2(row_width, PassiveIcon.ICON_SIZE.y)
	for comp in (mech.passive_components() if show_passives else []):
		var icon := PassiveIcon.new()
		add_child(icon)
		icon.setup(comp, mech)
		icon.visible = false
		_icons[comp] = icon
		_order.append(comp)
	_protocol_badge = StatusBadge.new()
	_protocol_badge.kind = "protocol"
	_protocol_badge.visible = false
	add_child(_protocol_badge)
	UIState.describe_on_hover(_protocol_badge, func(): return _protocol_info)
	_layout()

func icon_for(component: ComponentData) -> PassiveIcon:
	return _icons.get(component, null)

## Shows any icon the reveal didn't get to (it was skipped).
func reveal_all() -> void:
	for icon in _icons.values():
		if not icon.visible:
			icon.pop_in()

## Whether anything shows in the row (an enemy's intents sit lower if so).
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
	_protocol_badge.visible = not info.is_empty()
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
	var text := "%s\n%s" % [e["rule"], e.get("decay", "")]
	if not on.is_empty():
		text = "On %s.\n%s" % [", ".join(on), text]
	return ["%s %d" % [e["label"], total], text.strip_edges()]

## Passives, then statuses, then the protocol, centered in the row.
func _layout() -> void:
	var items: Array[Control] = []
	for comp in _order:
		items.append(_icons[comp])
	var statuses := _status_badges.keys()
	statuses.sort()
	for st in statuses:
		items.append(_status_badges[st])
	if _protocol_badge.visible:
		items.append(_protocol_badge)
	var n := items.size()
	var x0 := (_width - (n * PassiveIcon.ICON_SIZE.x + maxi(n - 1, 0) * GAP)) / 2.0
	for i in range(n):
		items[i].position = Vector2(x0 + i * (PassiveIcon.ICON_SIZE.x + GAP), 0)

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

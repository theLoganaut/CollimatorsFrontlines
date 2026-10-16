class_name DescriptionBox
extends Control
## Details for the hovered component (yours or an enemy's), plus a status
## glossary for the statuses on that component AND whatever's being
## hovered/dragged in the hand (UI & Screens). It shows only while there's
## something to say (Logan, 2026-09-30: not always on screen), fading in and
## out; with the "Details only with Shift held" setting, only while Shift is
## held as well. Hovering a passive icon shows just that passive:
## what it does and whether its component still stands. It's a holo glass
## screen tinted by what it shows (the part's category; red for an enemy's
## intent), with the part's shape and art in its top corner.
##
## Logan, 2026-10-02: a hovered card no longer opens it (it sat over the
## hand; the card's own HoloHint explains it now). The combat screen's
## buttons and bars explain themselves here (UIState.describe_on_hover)
## instead of in tooltips. While a part is hovered, the mouse wheel scrolls
## the box, wherever the mouse is.
##
## Logan, 2026-10-16: no scrolling if it can be helped, at the same font
## sizes. It's wide, grows upward from its bottom edge to fit what it says
## (up to the area CombatScene gives it, set_area), and opens on the side of
## the screen away from the mouse, so it never covers what's hovered. It
## ignores the mouse (the wheel still scrolls it when it overflows).

const PADDING := 12.0
const THUMB := Vector2(150, 150) # the part's shape, top right (Logan, 2026-10-16: big, it fills the empty right side)

## Set before adding to the tree (CombatScene sizes it to the space it has).
var box_size := Vector2(380, 290)
## Where it may open (set_area): its x on either side, its bottom edge and
## its tallest height.
var _left_x := 0.0
var _right_x := 0.0
var _bottom := 0.0
var _max_h := 0.0
const MIN_H := 60.0

var _title_label: Label
var _hp_label: Label
var _statuses_label: Label
var _cards_label: Label
var _glossary_label: Label
var _empty_label: Label
var _effect_label: Label
var _statuses_header: Label
var _cards_header: Label
var _glossary_header: Label
var _vbox: VBoxContainer
var _scroll: ScrollContainer
var _shown_component: ComponentData = null
var _accent: Color = GlassPanel.HOLO
var _thumb_part: ComponentData = null
## Something hovered to describe (set by _refresh; _process fades to it).
var _has_content: bool = false
const FADE_SPEED := 8.0 # alpha per second

func _ready() -> void:
	custom_minimum_size = box_size
	size = box_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_children()
	UIState.hover_changed.connect(_refresh.unbind(2))
	UIState.hovered_card_changed.connect(_refresh.unbind(1))
	UIState.intent_hover_changed.connect(_refresh.unbind(1))
	UIState.hint = {} # left over from a screen that closed under the mouse
	UIState.hint_changed.connect(_refresh.unbind(1))
	UIState.drag_started.connect(_refresh.unbind(1))
	UIState.drag_ended.connect(_refresh)
	_refresh()
	modulate.a = 0.0
	visible = false

func _process(delta: float) -> void:
	var want := _has_content and (not GameSettings.describe_on_shift or Input.is_key_pressed(KEY_SHIFT))
	var a := move_toward(modulate.a, 1.0 if want else 0.0, delta * FADE_SPEED * (1.0 if want else 0.6))
	if a != modulate.a:
		modulate.a = a
	visible = a > 0.0
	if visible:
		_fit()

## The wheel scrolls the box while a part is hovered, if it overflows.
func _input(event: InputEvent) -> void:
	if not visible or _shown_component == null or not (event is InputEventMouseButton) or not event.pressed:
		return
	if _scroll.get_v_scroll_bar().max_value <= _scroll.size.y:
		return
	var step := 0
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		step = 40
	elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
		step = -40
	if step != 0:
		_scroll.scroll_vertical += step
		get_viewport().set_input_as_handled()

## Where it may open: x on the left or right side (away from the mouse),
## `width`, and between `top` and `bottom` (it sits on the bottom and grows up).
func set_area(left_x: float, right_x: float, width: float, top: float, bottom: float) -> void:
	_left_x = left_x
	_right_x = right_x
	_bottom = bottom
	_max_h = maxf(bottom - top, MIN_H)
	set_box_size(Vector2(width, size.y))
	_fit()
	_pick_side()

## Opposite the mouse: on the right unless the mouse is on the right half.
func _pick_side() -> void:
	if _bottom <= 0.0:
		return
	var right_half := get_global_mouse_position().x > get_viewport_rect().size.x / 2.0
	position.x = _left_x if right_half else _right_x

## As tall as its text (between MIN_H and the area's height), bottom fixed.
func _fit() -> void:
	if _bottom <= 0.0:
		return
	var least := THUMB.y + PADDING * 2.0 if _thumb_part != null else MIN_H
	var h := clampf(maxf(_vbox.get_combined_minimum_size().y + PADDING * 2.0, least), MIN_H, _max_h)
	if h != size.y:
		custom_minimum_size.y = h
		size.y = h
		_scroll.size.y = h - PADDING * 2.0
		queue_redraw()
	position.y = _bottom - h

## Where it is or is about to be on screen while it has something to say
## (Rect2() if not), even before it has faded in (the training coach keeps clear of it).
func shown_rect() -> Rect2:
	if not _has_content:
		return Rect2()
	_fit()
	return get_global_rect()

## Resize after it's already built (the screen changed shape).
func set_box_size(v: Vector2) -> void:
	if v == box_size:
		return
	box_size = v
	custom_minimum_size = box_size
	size = box_size
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_build_children()
	_refresh()

func _build_children() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # part art

	# Sections stack by their content's height, so a part with many cards or
	# statuses pushes the glossary down instead of running into it. If it all
	# doesn't fit, the box scrolls (mouse wheel).
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(PADDING, PADDING)
	_scroll.size = Vector2(box_size.x - PADDING * 2.0, box_size.y - PADDING * 2.0)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scroll)
	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_theme_constant_override("separation", 2)
	_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_vbox)

	_empty_label = _make_label(13, Palette.TEXT_MUTED)
	_empty_label.text = "Hover a component to see its details."

	_title_label = _make_label(16, Color("eefcfa"))
	_hp_label = _make_label(13, Color("9fb9b6"))
	_effect_label = _make_label(12, Palette.LINK)

	_statuses_header = _make_header("STATUSES")
	_statuses_label = _make_label(12, Palette.TEXT)

	_cards_header = _make_header("CARDS")
	_cards_label = _make_label(12, Palette.TEXT)

	_glossary_header = _make_header("GLOSSARY")
	_glossary_label = _make_label(11, Color("9fb9b6"))

func _make_header(text: String) -> Label:
	var l := _make_label(11, Color("7f9d9a"))
	l.text = text
	l.custom_minimum_size.y = 22.0 # a little space above each section
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return l

func _make_label(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.add_child(l)
	return l

## Re-reads the shown component (its HP/statuses may have changed).
func refresh() -> void:
	_refresh()

func _refresh() -> void:
	if modulate.a <= 0.0:
		_pick_side() # not while it's showing: hovering across the middle shouldn't flip it
	if not UIState.hovered_intent.is_empty():
		_show_intent(UIState.hovered_intent)
		_set_look(Palette.DANGER, null)
		_has_content = true
		return
	if UIState.hovered_component == null and not UIState.hint.is_empty():
		_show_hint(UIState.hint)
		_set_look(GlassPanel.HOLO, null)
		_shown_component = null
		_has_content = true
		return
	var component := UIState.hovered_component
	if component == null:
		# nothing to say: fade out still showing what it said (Logan,
		# 2026-10-16: an intent's box flicked to a blank one as it went)
		_has_content = false
		return
	_set_look(Palette.category_color(component.category) if component != null else GlassPanel.HOLO, component)
	var has_component := component != null
	var passive_view := has_component and UIState.hovered_passive
	if component != _shown_component:
		_shown_component = component
		_scroll.scroll_vertical = 0

	_empty_label.visible = not has_component
	_title_label.visible = has_component
	_hp_label.visible = has_component
	if not has_component:
		_effect_label.visible = false
	# no statuses: no section (it only said "None")
	_statuses_header.visible = has_component and not passive_view and not component.statuses.is_empty()
	_statuses_label.visible = _statuses_header.visible
	_cards_header.visible = has_component and not passive_view
	_cards_label.visible = has_component and not passive_view

	if passive_view:
		_title_label.text = "%s (Passive)" % component.name
		if component.destroyed:
			_hp_label.text = "Offline: its %s is destroyed." % component.category
		else:
			_hp_label.text = "Always active · %s · %d / %d HP" % [component.category.capitalize(), component.current_hp, component.max_hp]
		_effect_label.text = component.passive_text()
		_effect_label.visible = component.passive_text() != ""
	elif has_component:
		_title_label.text = "%s (%s)" % [component.name, component.category.capitalize()]
		_hp_label.text = "%d / %d HP" % [component.current_hp, component.max_hp]
		var effect_lines: Array[String] = []
		if component.passive_text() != "" and not component.destroyed:
			effect_lines.append(component.passive_text())
		var mech := UIState.hovered_mech
		var cover := mech.cover_for(component) if mech != null else null
		if cover != null:
			effect_lines.append("Redirected to %s: damage aimed here goes to it while it stands." % cover.name)
		_effect_label.text = "\n".join(effect_lines)
		_effect_label.visible = effect_lines.size() > 0
		var status_lines: Array[String] = []
		for s in component.statuses:
			status_lines.append("%s %d" % [s.status.capitalize(), s.stacks])
		_statuses_label.text = "\n".join(status_lines) if status_lines.size() > 0 else "None"
		var card_lines: Array[String] = []
		for c in component.cards:
			card_lines.append("• %s (%d heat)" % [c.name, c.heat_cost])
		_cards_label.text = "\n".join(card_lines) if card_lines.size() > 0 else "(none)"

	# Glossary: statuses on the hovered component, plus whatever a hovered or
	# dragged card would apply.
	var status_names: Array[String] = []
	if has_component:
		for s in component.statuses:
			if not status_names.has(s.status):
				status_names.append(s.status)
		if component.destroyed and not status_names.has("destroyed"):
			status_names.append("destroyed")
		if passive_view:
			var passive_statuses: Array = component.passive.get("statuses", []).duplicate()
			if component.passive.has("status"):
				passive_statuses.append(component.passive["status"])
			for s in passive_statuses:
				if not status_names.has(s):
					status_names.append(s)
	# (a hovered card explains itself above the card; a dragged one, aimed
	# at a part, adds what it would apply here)
	var relevant_card: CardData = UIState.dragging_card if has_component else null
	if relevant_card != null:
		for s in relevant_card.statuses:
			if not status_names.has(s.status):
				status_names.append(s.status)

	var glossary_lines: Array[String] = []
	for status_name in status_names:
		var entry := StatusGlossary.get_entry(status_name)
		glossary_lines.append("%s — %s" % [entry["label"], entry["rule"]])
	# and any keyword the text uses (Vent, Pierce, Reclaim)
	var text := ""
	if has_component:
		text += component.passive_text()
	if relevant_card != null:
		text += " " + relevant_card.effect_text
	for entry in StatusGlossary.keywords_in(text):
		glossary_lines.append("%s — %s" % [entry["label"], entry["rule"]])
	_glossary_label.text = "\n".join(glossary_lines)
	_glossary_header.visible = glossary_lines.size() > 0
	_glossary_label.visible = glossary_lines.size() > 0
	_empty_label.visible = false
	_has_content = has_component or glossary_lines.size() > 0

## The glass's tint and the part in the corner; the title keeps clear of it.
func _set_look(accent: Color, part: ComponentData) -> void:
	_accent = accent
	_thumb_part = part
	for header in [_statuses_header, _cards_header, _glossary_header]:
		header.add_theme_color_override("font_color", Color(accent.lerp(Color.WHITE, 0.35), 0.85))
	_title_pad(THUMB.x + 6.0 if part != null else 0.0)
	queue_redraw()

## Right margin on the lines beside the corner art (all but the glossary,
## which runs under it) so they wrap before it.
func _title_pad(px: float) -> void:
	for l in [_title_label, _hp_label, _effect_label, _statuses_header, _statuses_label, _cards_header, _cards_label]:
		var st := StyleBoxEmpty.new()
		st.content_margin_right = px
		l.add_theme_stylebox_override("normal", st)

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.015, 0.03, 0.04, 0.9), true) # opaque enough to hide what it covers
	GlassPanel.draw_glass(self, r, 1.0, _accent, 9.0, 0.9)
	if _thumb_part != null:
		var box := Rect2(Vector2(size.x - THUMB.x - PADDING, PADDING), THUMB)
		draw_circle(box.get_center(), THUMB.x * 0.45, Color(_accent, 0.08))
		PartArt.draw_shape(self, box, _thumb_part, 1.0, 48.0)

## A button or bar on the combat screen explaining itself.
func _show_hint(hint: Dictionary) -> void:
	for l in [_statuses_header, _statuses_label, _cards_header, _cards_label, _hp_label, _empty_label, _glossary_header, _glossary_label]:
		l.visible = false
	_title_label.visible = true
	_title_label.text = str(hint.get("title", ""))
	_effect_label.text = str(hint.get("text", ""))
	_effect_label.visible = _effect_label.text != ""
	_scroll.scroll_vertical = 0

## An enemy's planned action: the card, its numbers, and what it's aimed at.
func _show_intent(intent: Dictionary) -> void:
	var mech: MechData = intent["mech"]
	var card: CardData = intent["card"]
	var target: ComponentData = intent.get("target", null)
	for l in [_statuses_header, _statuses_label, _cards_header, _cards_label, _hp_label, _empty_label]:
		l.visible = false
	_title_label.visible = true
	_title_label.text = "%s: %s" % [mech.name, card.name]
	var lines: Array[String] = []
	if card.protocol() != "":
		lines.append("Primes a protocol: %s" % card.effect_text)
	else:
		if card.hits > 0:
			lines.append("%d heat · %s" % [card.heat_cost, card.damage_label()])
		elif card.heat_cost != 0:
			lines.append("%d heat" % card.heat_cost)
		lines.append_array(card.status_lines())
		if card.effect_text != "":
			lines.append(card.effect_text)
		if target != null:
			lines.append("Aimed at your %s (if that part is gone by then, it picks another)." % target.name)
	_hp_label.text = "Enemy intent"
	_hp_label.visible = true
	_effect_label.text = "\n".join(lines)
	_effect_label.visible = true
	var glossary_lines: Array[String] = []
	for st in card.statuses:
		var entry := StatusGlossary.get_entry(st.status)
		glossary_lines.append("%s — %s" % [entry["label"], entry["rule"]])
	_glossary_label.text = "\n".join(glossary_lines)
	_glossary_header.visible = glossary_lines.size() > 0
	_glossary_label.visible = glossary_lines.size() > 0

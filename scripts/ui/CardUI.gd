class_name CardUI
extends Control
## One card: hover lift + scale, and the drag source (Combat Slice §4.4,
## UI & Screens card face: Cost | Dmg, Name, Effect text, Image). The face
## is holo glass tinted by its part's category, with the heat cost on a
## chip and the granting part's art glowing behind the text (PartArt).
##
## Dragging is manual (top_level + z_index), not Godot's built-in drag-and-
## drop. On press the card becomes top_level and follows the mouse. An
## attack card fades out as it's pulled away from where it was picked up,
## and CombatScene draws the targeting crosshair in its place.
##
## The release is caught here in _input(), not by the drop target: Godot
## sends a button release to the control that got the press (this card),
## so a cell under the cursor never sees it. On release the card hands the
## cursor position to UIState.drop_handler (CombatScene), which hit-tests
## the enemy grids and plays the card if it can. Either way the card then
## returns to its slot in the fan. A per-frame check of the button state
## covers a release that never arrives (e.g. focus lost mid-drag).

const BASE_SIZE := Vector2(128, 168)
const HOVER_SCALE := 1.3
const HOVER_LIFT := 34.0
## Attack cards: fully visible up to FADE_START px from the pick-up point,
## fully replaced by the crosshair at FADE_END px.
const FADE_START := 40.0
const FADE_END := 170.0
const DRAG_MIN_SCALE := 0.5

var card: CardData
var hand_tray: Control # HandTray — relayout() is called after every drag ends

## Slot in the fan, set by HandTray.relayout().
var rest_position: Vector2 = Vector2.ZERO
var rest_rotation: float = 0.0
var rest_z: int = 0

var _hovering: bool = false
## The card raised by hover. While the mouse is anywhere on it (its grown,
## raised rect), it keeps the hover and the cards under it ignore the mouse,
## so its keywords can be hovered right to its edges (Logan, 2026-10-13: the
## card behind kept taking over). Godot routes the mouse by node order, not
## z_index, so without this a neighbor underneath wins.
static var _lifted: CardUI = null
## Ignoring the mouse because the raised card covers this one.
var _blocked: bool = false
## 1–9: the number key that plays it (HandTray numbers the fan); 0 = none.
var hotkey: int = 0
## Played this turn: out of the fan (hidden) until the next turn.
var gone: bool = false
var _gone_tween: Tween
var _rest_alpha: float = 1.0
## Picked with its number key and waiting for a target (CombatScene).
var selected: bool = false
## Its part is hovered on your mech: it rises a little and is outlined.
var linked: bool = false
const LINK_LIFT := 14.0
var _dragging: bool = false
var _grab_offset: Vector2 = Vector2.ZERO
var _press_global: Vector2 = Vector2.ZERO
var _ready_to_play: bool = false # self cards: dragged far enough to play on release
var _unavailable: bool = false # its part is Disabled / Offline, or it's spent: greyed out, can't be picked up
var _spent: bool = false # played this fight (single-use)
var _shown_cost: int = -9999
var _category: String = ComponentData.CATEGORY_HARDPOINT
var _component: ComponentData = null # the part that grants it (for its art)
var _hover_tween: Tween

var _cost_label: Label
var _name_label: Label
var _effect_label: RichTextLabel
## Where a hovered keyword's rule opens (global; INF: above the card). A
## right-clicked enemy part's cards put it under the whole row.
var hint_below: Vector2 = Vector2.INF
## A primed protocol will be used up by this card: a soft purple glow.
var protocol_glow: bool = false

func _ready() -> void:
	custom_minimum_size = BASE_SIZE
	size = BASE_SIZE
	pivot_offset = Vector2(BASE_SIZE.x / 2.0, BASE_SIZE.y) # bottom-center: hover grows upward
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)
	set_process(false)
	set_process_input(false)
	_build_children()
	_refresh()

func setup(p_card: CardData, p_category: String, p_hand_tray: Control, p_component: ComponentData = null) -> void:
	card = p_card
	_category = p_category
	_component = p_component
	hand_tray = p_hand_tray
	if is_inside_tree():
		_refresh()

func _build_children() -> void:
	_cost_label = Label.new()
	_cost_label.position = Vector2(4, 8) # in the flame's body (FLAME_AT)
	_cost_label.size = Vector2(24, 22)
	_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cost_label.add_theme_font_size_override("font_size", 15)
	_cost_label.add_theme_color_override("font_color", Palette.TEXT)
	_cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cost_label)

	_name_label = Label.new()
	_name_label.position = Vector2(8, 30)
	_name_label.size = Vector2(BASE_SIZE.x - 14, 36)
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.add_theme_color_override("font_color", Color("eefcfa"))
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)

	# Rich text: statuses and keywords are tinted links, and hovering one
	# (only the word itself, Logan 2026-10-02) opens its rule above the card.
	_effect_label = RichTextLabel.new()
	_effect_label.bbcode_enabled = true
	_effect_label.scroll_active = false
	_effect_label.meta_underlined = false
	_effect_label.position = Vector2(8, 66)
	_effect_label.size = Vector2(BASE_SIZE.x - 16, BASE_SIZE.y - 72)
	_effect_label.add_theme_font_size_override("normal_font_size", 11)
	_effect_label.add_theme_color_override("default_color", Color("b9d0cc"))
	_effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_effect_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_effect_label.meta_hover_started.connect(func(meta):
		var e := StatusGlossary.lookup(str(meta))
		if not e.is_empty() and UIState.dragging_card == null:
			if hint_below != Vector2.INF:
				HoloHint.open(self, [e], [], false, hint_below)
			else:
				HoloHint.open(self, [e], [], true))
	_effect_label.meta_hover_ended.connect(func(_meta): HoloHint.close(self))
	add_child(_effect_label)

func _refresh() -> void:
	if card == null:
		return
	_cost_label.text = str(card.heat_cost if _shown_cost == -9999 else _shown_cost)
	_name_label.text = card.name
	var lines: Array[String] = []
	lines.append_array(card.status_lines())
	if card.effect_text != "":
		lines.append(card.effect_text)
	if card.one_use:
		lines.push_front("One use (intercepted)")
	_effect_label.text = StatusGlossary.annotate("\n".join(lines))
	queue_redraw()

## Display-only: shown, never hovered, dragged or part of the hand (an
## enemy part's cards, CombatScene._show_enemy_cards).
## `keywords`: its statuses and keywords still open their rules on hover.
func make_display(keywords: bool = false) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _effect_label != null:
		_effect_label.mouse_filter = Control.MOUSE_FILTER_PASS if keywords else Control.MOUSE_FILTER_IGNORE

## Display-only face for a component's passive (the opening reveal): no
## cost or damage, "PASSIVE" in the cost corner, the passive's text as the
## effect. Not draggable, not hoverable, never part of the hand.
func show_passive(component: ComponentData) -> void:
	card = null
	_category = component.category
	_component = component
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = BASE_SIZE / 2.0
	_cost_label.text = "PASSIVE"
	_cost_label.size = Vector2(70, 22)
	_cost_label.position = Vector2(8, 4)
	_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_cost_label.add_theme_font_size_override("font_size", 11)
	_cost_label.add_theme_color_override("font_color", Palette.category_color(_category))
	_name_label.text = component.name
	_effect_label.text = StatusGlossary.annotate(component.passive_text())
	_effect_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_effect_label.add_theme_color_override("default_color", Palette.TEXT)
	# No image on a passive card, so its (often long) text gets more room.
	_effect_label.add_theme_font_size_override("normal_font_size", 10)
	_effect_label.position.y = 60
	_effect_label.size.y = BASE_SIZE.y - 66
	queue_redraw()

## Red cost when playing this card now would overheat the mech.
func set_would_overheat(would: bool) -> void:
	if _cost_label != null:
		_cost_label.add_theme_color_override("font_color", Palette.DANGER if would else Palette.TEXT)

## The cost it takes right now (amber when changed from printed), red if it
## would overheat, greyed out when its part can't act, and dimmer still
## with SPENT across it once it's been played this fight.
func set_protocol_glow(on: bool) -> void:
	if on != protocol_glow:
		protocol_glow = on
		queue_redraw()

func set_state(cost: int, would_overheat: bool, unavailable: bool, spent: bool = false) -> void:
	_shown_cost = cost
	_unavailable = unavailable or spent
	if spent != _spent:
		_spent = spent
		queue_redraw()
	if _cost_label == null or card == null:
		return
	_cost_label.text = str(cost)
	var col := Palette.TEXT
	if cost != card.heat_cost:
		col = Palette.WARNING
	if would_overheat:
		col = Palette.DANGER
	_cost_label.add_theme_color_override("font_color", col)
	_rest_alpha = 0.28 if spent else (0.4 if unavailable else 1.0)
	if not gone and (_gone_tween == null or not _gone_tween.is_running()):
		modulate = Color(1, 1, 1, _rest_alpha)

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var accent := Palette.category_color(_category)
	draw_rect(rect, Color(0.015, 0.03, 0.04, 0.9), true) # darker than a panel, so text reads over the fight
	GlassPanel.draw_glass(self, rect, 1.0, accent, 10.0, 0.85)
	# the granting part's art, glowing faintly behind the effect text
	if _component != null:
		var art := Rect2(10, 72, size.x - 20, size.y - 82)
		draw_circle(art.get_center(), art.size.x * 0.42, Color(accent, 0.07))
		PartArt.draw_shape(self, art, _component, 0.3, 30.0)
	if _ready_to_play:
		draw_rect(rect, Color("eefcfa"), false, 3.0)
	else:
		draw_rect(rect, Color(accent, 0.9), false, 1.5)
	if card != null: # the heat cost, in a flame (Logan, 2026-10-16: it's heat)
		draw_glyph(self, flame_shape(FLAME_AT, 1.0), 0.22, 1.5)
		draw_colored_polygon(flame_shape(FLAME_AT + Vector2(0, 2), 0.6), Color(Palette.HARDPOINT, 0.16)) # a smaller flame inside
		_draw_damage()
	draw_line(Vector2(32 if card != null else 8, 28), Vector2(size.x - 8, 28), Color(accent, 0.35), 1.0) # (clear of the flame)
	if hotkey > 0 and not _spent: # its number key, bottom right
		var kc := Vector2(size.x - 13, size.y - 13)
		draw_circle(kc, 9.0, Color(0.02, 0.05, 0.06, 0.9))
		draw_arc(kc, 9.0, 0.0, TAU, 20, Color(accent, 0.8), 1.0, true)
		draw_string(get_theme_default_font(), kc + Vector2(-9, 4.5), str(hotkey), HORIZONTAL_ALIGNMENT_CENTER, 18, 12, Palette.TEXT)
	if protocol_glow and not _spent:
		for i in range(4):
			draw_rect(rect.grow(1.5 + i * 2.5), Color(Palette.PROTOCOL, 0.5 - i * 0.11), false, 2.5)
	if selected or linked:
		draw_rect(rect.grow(2.0), Palette.LINK, false, 3.0)
	if _spent:
		var font := get_theme_default_font()
		var band := Rect2(0, size.y * 0.42, size.x, 24)
		draw_rect(band, Color(0, 0, 0, 0.75), true)
		draw_string(font, Vector2(0, band.position.y + 17), "SPENT", HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, Palette.TEXT)

## The damage, top right (Logan, 2026-10-16: "2×5–6" confused players): a
## reticle holding the hit count, "×", then an impact burst holding the
## damage per hit. One hit: just the burst.
const BURST_AT := Vector2(BASE_SIZE.x - 30.0, 14.0)
const BURST_R := Vector2(24.0, 13.0) # the spikes' reach, across and up
const RETICLE_R := 9.5

func _draw_damage() -> void:
	if card == null or card.hits <= 0:
		return
	var font := get_theme_default_font()
	var col := Palette.HARDPOINT
	draw_glyph(self, burst_shape(BURST_AT, BURST_R), 0.2, 1.5)
	_centered(font, card.per_hit_label(), BURST_AT, 11, Palette.TEXT)
	if card.hits == 1:
		return
	var times_x := BURST_AT.x - BURST_R.x - 6.0
	_centered(font, "×", Vector2(times_x, BURST_AT.y), 12, col)
	var c := Vector2(times_x - 6.0 - RETICLE_R - 3.0, BURST_AT.y)
	draw_reticle(self, c, 1.5)
	_centered(font, str(card.hits), c, 11, Palette.TEXT)

## The card face's glyphs (heat flame, damage burst), also drawn by the
## training coach's inline icons: a dark fill, a `fill_alpha` tint and a
## closed outline `width` wide.
static func draw_glyph(canvas: CanvasItem, outline: PackedVector2Array, fill_alpha: float, width: float) -> void:
	canvas.draw_colored_polygon(outline, GLYPH_DARK)
	canvas.draw_colored_polygon(outline, Color(Palette.HARDPOINT, fill_alpha))
	outline.append(outline[0])
	canvas.draw_polyline(outline, Palette.HARDPOINT, width, true)

## The hit-count reticle: a ring with crosshair ticks through it.
static func draw_reticle(canvas: CanvasItem, at: Vector2, width: float) -> void:
	canvas.draw_circle(at, RETICLE_R, GLYPH_DARK)
	canvas.draw_arc(at, RETICLE_R, 0.0, TAU, 28, Palette.HARDPOINT, width, true)
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]: # the crosshair's ticks, through the ring
		canvas.draw_line(at + d * (RETICLE_R - 3.0), at + d * (RETICLE_R + 3.5), Palette.HARDPOINT, width, true)

const GLYPH_DARK := Color(0.02, 0.05, 0.06, 0.95)

## `text` centered on `at` (a dark outline so it reads over the shapes).
func _centered(font: Font, text: String, at: Vector2, font_size: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var base := at + Vector2(-w / 2.0, font.get_ascent(font_size) / 2.0 - 1.0)
	draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(0, 0, 0, 0.8))
	draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

## An impact burst around `at`: spikes reaching `r` (across, up), a fixed
## uneven pattern so every card's burst looks the same.
static func burst_shape(at: Vector2, r: Vector2) -> PackedVector2Array:
	const SPIKES := [1.0, 0.85, 1.0, 0.9, 0.8, 1.0, 0.92, 1.0, 0.82, 0.95, 1.0, 0.88]
	var pts := PackedVector2Array()
	var n := SPIKES.size()
	for i in range(n * 2):
		var a := TAU * float(i) / float(n * 2) - PI / 2.0
		var k: float = SPIKES[i / 2] if i % 2 == 0 else 0.72
		pts.append(at + Vector2(cos(a) * r.x, sin(a) * r.y) * k)
	return pts

## Where the heat cost's flame stands: the middle of its round body.
const FLAME_AT := Vector2(16, 19)

## A flame's outline around `at` (its round body's middle), `k` its size
## (Logan, 2026-10-16, from his sketch): a round body with three tongues on
## top, a tall one in the middle leaning right and a short one either side.
## In units of the body's radius (9 px at k = 1), y down.
const FLAME_PATH := [
	# [to, control]: quadratic curves from the body's right shoulder round
	[Vector2(-0.6, -1.25), Vector2(-1.0, -0.8)],    # up the left side to the left tongue's tip
	[Vector2(-0.4, -0.78), Vector2(-0.46, -1.02)],  # down into the left notch
	[Vector2(0.14, -1.85), Vector2(-0.38, -1.55)],  # up the middle tongue to its tip
	[Vector2(0.36, -0.82), Vector2(-0.04, -1.22)],  # down its right edge to the right notch
	[Vector2(0.7, -1.12), Vector2(0.58, -0.86)],    # up to the right tongue's tip
	[Vector2(0.98, -0.2), Vector2(1.06, -0.72)],    # down to the body's right shoulder
]

static func flame_shape(at: Vector2, k: float) -> PackedVector2Array:
	var r := 9.0 * k
	var pts := PackedVector2Array()
	var a0 := -0.2
	var a1 := PI + 0.2
	for i in range(17): # the round body, right shoulder down and round to the left
		var a := lerpf(a0, a1, float(i) / 16.0)
		pts.append(at + Vector2(cos(a), sin(a)) * r)
	var from := Vector2(cos(a1), sin(a1))
	for seg in FLAME_PATH:
		var to: Vector2 = seg[0]
		var ctrl: Vector2 = seg[1]
		for i in range(1, 7):
			var s := float(i) / 6.0
			pts.append(at + from.lerp(ctrl, s).lerp(ctrl.lerp(to, s), s) * r)
		from = to
	pts.remove_at(pts.size() - 1) # the last point is the first one again
	return pts

# ---------- hover ----------

func _on_mouse_entered() -> void:
	var other := _lifted if _lifted != null and is_instance_valid(_lifted) and _lifted != self and _lifted._hovering else null
	if other != null:
		if other._holds_mouse():
			return # under the raised card: it keeps the hover
		other._unhover()
	_hovering = true
	_lifted = self
	_apply_hover_visual()
	if card != null:
		UIState.set_hovered_card(card)
	set_process(true)

func _on_mouse_exited() -> void:
	if self == _lifted and _hovering and not _dragging and _holds_mouse():
		return # still on the raised card; _process lets go once the mouse really leaves
	var was_lifted := self == _lifted
	_unhover()
	if was_lifted:
		_hand_off()

func _unhover() -> void:
	_hovering = false
	_apply_hover_visual()
	if card != null:
		UIState.clear_hovered_card(card)
	HoloHint.close(self)
	if _lifted == self:
		_lifted = null
		_block_siblings(false)

func _exit_tree() -> void:
	if _lifted == self: # removed while raised (its part destroyed): free the others
		_block_siblings(false)
		_lifted = null

## The mouse is on this card as it's drawn now (raised and grown).
func _holds_mouse() -> bool:
	return visible and get_global_rect().grow(2.0).has_point(get_global_mouse_position())

func _block_siblings(on: bool) -> void:
	if get_parent() == null:
		return
	for c in get_parent().get_children():
		if c is CardUI and c != self and c._blocked != on:
			c._blocked = on
			c._sync_filter()

func _sync_filter() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE if (_dragging or _blocked) else Control.MOUSE_FILTER_STOP

## While raised: keep the cards under it out of the way, and once the mouse
## leaves it, hand the hover to whichever card it's on now.
func _hold_hover() -> void:
	if self != _lifted or not _hovering:
		set_process(false)
		return
	var inside := _holds_mouse()
	_block_siblings(inside)
	if inside:
		return
	_unhover()
	set_process(false)
	_hand_off()

## The cards under it were ignoring the mouse, so Godot never told the one
## the mouse is on now: give it the hover.
func _hand_off() -> void:
	var mouse := get_global_mouse_position()
	var siblings := get_parent().get_children() if get_parent() != null else []
	for i in range(siblings.size() - 1, -1, -1): # last child first: Godot's own input order
		var c = siblings[i]
		if c is CardUI and c != self and c.visible and not c.gone and c.get_global_rect().has_point(mouse):
			c._on_mouse_entered()
			break

func _apply_hover_visual() -> void:
	if _dragging:
		return
	var up := (_hovering or selected or spotlit) and UIState.dragging_card == null
	if _hover_tween != null:
		_hover_tween.kill()
	_hover_tween = create_tween().set_parallel(true)
	var s: float = HOVER_SCALE if up else 1.0
	var lift := HOVER_LIFT if up else (LINK_LIFT if linked else 0.0)
	_hover_tween.tween_property(self, "scale", Vector2(s, s), 0.1)
	_hover_tween.tween_property(self, "position", rest_position + Vector2(0, -lift), 0.1)
	_hover_tween.tween_property(self, "rotation_degrees", 0.0 if up else rest_rotation, 0.1)
	z_index = 50 if up else rest_z

func set_linked(on: bool) -> void:
	if linked == on:
		return
	linked = on
	_apply_hover_visual()
	queue_redraw()

## Training shows this card as if hovered (Tutorial "hover" steps): raised,
## with its text in the description box.
var spotlit: bool = false

func set_spotlit(on: bool) -> void:
	if spotlit == on:
		return
	spotlit = on
	if card != null:
		if on:
			UIState.set_hovered_card(card)
		else:
			UIState.clear_hovered_card(card)
	_apply_hover_visual()

## The card the mouse has raised, or null.
static func raised() -> CardUI:
	return _lifted if _lifted != null and is_instance_valid(_lifted) and _lifted._hovering else null

func category() -> String:
	return _category

## Whether its text names a status or keyword (tinted, with its rule on hover).
func has_keyword() -> bool:
	return _effect_label != null and _effect_label.text.contains("[url=")

## Where its text's first status or keyword is, on screen (Rect2() if none).
## Card text is plain words plus the tinted links, so the shown text is the
## same string with the tags stripped.
func keyword_rect() -> Rect2:
	if not has_keyword():
		return Rect2()
	var m := RegEx.create_from_string("\\[url=[^\\]]*\\]([^\\[]+)\\[/url\\]").search(_effect_label.text)
	var shown := _effect_label.get_parsed_text()
	var before := RegEx.create_from_string("\\[[^\\]]*\\]").sub(_effect_label.text.substr(0, m.get_start()).replace("[lb]", "<"), "", true)
	var at := before.length()
	var word := m.get_string(1)
	var line := _effect_label.get_character_line(at)
	var start := _effect_label.get_line_range(line).x
	var font := _effect_label.get_theme_font("normal_font")
	var fs := _effect_label.get_theme_font_size("normal_font_size")
	var x := font.get_string_size(shown.substr(start, at - start), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var w := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var local := Rect2(x, _effect_label.get_line_offset(line), w, _effect_label.get_line_height(line))
	var xf := _effect_label.get_global_transform()
	return Rect2(xf * local.position, local.size * xf.get_scale())

func set_selected(on: bool) -> void:
	if selected == on:
		return
	selected = on
	_apply_hover_visual()
	queue_redraw()

## Leaves the fan (played: lifts and fades out, then hides) or comes back
## into it (the next turn: fades in at its slot).
func set_gone(on: bool) -> void:
	if gone == on:
		return
	gone = on
	if _gone_tween != null:
		_gone_tween.kill()
	if on:
		if _hovering:
			_unhover()
		if _dragging or not visible:
			return # _finish_drag_visual hides it where it was dropped
		_gone_tween = create_tween().set_parallel(true)
		_gone_tween.tween_property(self, "modulate:a", 0.0, 0.18)
		_gone_tween.tween_property(self, "position:y", position.y - 40.0, 0.18).set_ease(Tween.EASE_OUT)
		_gone_tween.chain().tween_callback(func(): visible = false)
	else:
		visible = true
		modulate.a = 0.0
		_gone_tween = create_tween()
		_gone_tween.tween_property(self, "modulate:a", _rest_alpha, 0.2)

## Hidden at once (a flying copy takes its place: CombatScene._fly_card).
func hide_now() -> void:
	if _gone_tween != null:
		_gone_tween.kill()
	visible = false

## Snap to the fan slot (no tween) — used by HandTray.relayout().
func apply_rest() -> void:
	if _hover_tween != null:
		_hover_tween.kill()
	position = rest_position
	rotation_degrees = rest_rotation
	scale = Vector2.ONE
	z_index = rest_z
	if _hovering or selected or spotlit:
		_apply_hover_visual()

# ---------- drag ----------

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not _dragging and UIState.dragging_card == null and not UIState.input_locked and not _unavailable:
			_start_drag()
			accept_event()

func _start_drag() -> void:
	if _hover_tween != null:
		_hover_tween.kill()
	_dragging = true
	_press_global = get_global_mouse_position()
	scale = Vector2.ONE
	rotation_degrees = 0.0
	top_level = true
	z_index = 100
	_sync_filter()
	_block_siblings(false)
	# Hold the card by its center so it shrinks toward the cursor.
	pivot_offset = BASE_SIZE / 2.0
	_grab_offset = BASE_SIZE / 2.0
	global_position = _press_global - _grab_offset
	HoloHint.close(self)
	UIState.begin_drag(self, card)
	set_process(true)
	set_process_input(true)

func _process(_delta: float) -> void:
	if not _dragging:
		_hold_hover()
		return
	var mouse := get_global_mouse_position()
	global_position = mouse - _grab_offset
	var dist := mouse.distance_to(_press_global)
	if card.is_attack():
		var f := clampf((dist - FADE_START) / (FADE_END - FADE_START), 0.0, 1.0)
		UIState.drag_fade = f
		modulate.a = 1.0 - f
		var s := lerpf(1.0, DRAG_MIN_SCALE, f)
		scale = Vector2(s, s)
	else:
		var can_play := dist >= FADE_END
		if can_play != _ready_to_play:
			_ready_to_play = can_play
			queue_redraw()
	if not Gamepad.left_held(): # the mouse button, or A on a gamepad
		_release(mouse)

func _input(event: InputEvent) -> void:
	if not _dragging or not (event is InputEventMouseButton):
		return
	if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		get_viewport().set_input_as_handled()
		_release(get_global_mouse_position())
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		get_viewport().set_input_as_handled()
		_cancel()

func _release(pos: Vector2) -> void:
	if not _dragging:
		return
	_dragging = false
	var dist := pos.distance_to(_press_global)
	if UIState.drop_handler.is_valid():
		UIState.drop_handler.call(card, pos, dist)
	UIState.end_drag()
	_finish_drag_visual()

func _cancel() -> void:
	if not _dragging:
		return
	_dragging = false
	if UIState.drop_handler.is_valid():
		UIState.drop_handler.call(card, _press_global, 0.0) # a zero-distance drop never plays
	UIState.end_drag()
	_finish_drag_visual()

func _finish_drag_visual() -> void:
	_dragging = false
	_ready_to_play = false
	top_level = false
	modulate.a = 1.0
	pivot_offset = Vector2(BASE_SIZE.x / 2.0, BASE_SIZE.y)
	_sync_filter()
	set_process(false)
	if _lifted == self:
		_lifted = null
	set_process_input(false)
	queue_redraw()
	if gone: # played: gone from where it was dropped
		visible = false
	if hand_tray != null and hand_tray.has_method("relayout"):
		hand_tray.relayout()

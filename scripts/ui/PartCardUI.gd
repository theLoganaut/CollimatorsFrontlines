class_name PartCardUI
extends Control
## One component shown as a card, for picking or inspecting (reward picks,
## the salvage reels, autonomous bays, the Info Bay, deployment orders).
## Everything on it comes from Refit Bay.
##
## A fixed anatomy (Logan, 2026-11-11: less prototype, more final product),
## the same for every category so how much text a part has never moves
## anything else:
##   header     rarity gem and word on the left, the HP badge on the right
##   art window the part's shape, big, on a grid in the category's color
##   name       a banner across the card, one line (the font shrinks to fit)
##   text box   a fixed box: each card it grants as a row (heat flame with
##              its cost, name, damage burst with its hits and damage) and
##              its statuses and effect under it; a reactor's passive under
##              a PASSIVE ribbon. The text is centered in the box and steps
##              down a size when there's too much (hardpoints are wordy).
##   footer     a strip on the frame (what it sells for, whether it fits)
## Clickable when `selectable`; hover lifts the border to yellow. Drawn as
## holo glass tinted by the part's category.

signal pressed(card: PartCardUI)

const SIZE := Vector2(216, 316)
const PAD := 9.0
const HEADER_H := 22.0
const ART_H := 96.0
const BANNER_H := 24.0
const FOOTER_H := 22.0
const ART_CELL_MAX := 24.0 # the shape's cells in the art window, at most
const SHAPE_GAP := 2.0 # between the shape's cells (and the grid's lines sit in it)
## Text sizes, largest first: [move name, stats, effect lines, passive]. The
## first that fits the text box is used.
const TEXT_STEPS := [[13, 12, 11, 13], [12, 11, 10, 12], [12, 11, 9, 11], [11, 10, 8, 10]]

var component_id: String = ""
var component: ComponentData = null # an existing part (keeps its HP), else a fresh one
var selectable: bool = true
var footer_text: String = ""
var footer_color: Color = Palette.TEXT

var _hover: bool = false
var _footer: Label
var _rarity: String = ""

func _ready() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): _set_hover(true))
	mouse_exited.connect(func(): _set_hover(false))
	gui_input.connect(_on_gui_input)

## Show a library part (`id`) or an existing part (`comp`, with its HP).
func setup(id: String, comp: ComponentData = null) -> void:
	component_id = id
	component = comp if comp != null else ComponentLibrary.make(id)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if selectable else Control.CURSOR_ARROW
	_build()

func set_footer(text: String, color: Color = Palette.TEXT) -> void:
	footer_text = text
	footer_color = color
	if _footer != null:
		_footer.text = text
		_footer.add_theme_color_override("font_color", color)

# ---------- layout ----------

func _art_rect() -> Rect2:
	return Rect2(PAD, HEADER_H + 4.0, SIZE.x - PAD * 2.0, ART_H)

func _banner_rect() -> Rect2:
	var a := _art_rect()
	return Rect2(0, a.end.y + 4.0, SIZE.x, BANNER_H)

func _text_rect() -> Rect2:
	var top := _banner_rect().end.y + 5.0
	return Rect2(PAD, top, SIZE.x - PAD * 2.0, SIZE.y - FOOTER_H - 4.0 - top)

func _footer_rect() -> Rect2:
	return Rect2(0, SIZE.y - FOOTER_H, SIZE.x, FOOTER_H)

func _build() -> void:
	for c in get_children():
		c.queue_free()
	_rarity = str(ComponentLibrary.definition(component.library_id).get("rarity", ""))
	var cat_color := Palette.category_color(component.category)

	# header: the rarity word beside its gem (the gem is drawn); HP on its badge (drawn)
	var rarity := UIKit.label(_rarity.capitalize(), 11, Palette.rarity_color(_rarity))
	rarity.position = Vector2(PAD + 16.0, 3.0)
	add_child(rarity)

	# the name on its banner
	var b := _banner_rect()
	var name_l := _fitted_label(component.name, 17, 11, b.size.x - 20.0, Color("eefcfa"))
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_l.position = b.position
	name_l.size = b.size
	add_child(name_l)

	# the text box: the biggest text steps that fit
	var tr := _text_rect()
	var steps: Array = TEXT_STEPS[TEXT_STEPS.size() - 1]
	for s in TEXT_STEPS:
		if _text_height(s, tr.size.x) <= tr.size.y:
			steps = s
			break
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	box.position = tr.position + Vector2(4, 3)
	box.size = tr.size - Vector2(8, 6)
	add_child(box)
	if component.category == ComponentData.CATEGORY_REACTOR:
		var ribbon := UIKit.label("PASSIVE  ·  ALWAYS IN PLAY", 10, cat_color)
		ribbon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(ribbon)
		var gap := Control.new()
		gap.custom_minimum_size.y = 3.0
		box.add_child(gap)
		var passive := UIKit.rich_label(component.passive_text(), steps[3], Palette.TEXT)
		passive.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(passive)
	else:
		var first := true
		for card in component.cards:
			if not first:
				var sep := Control.new()
				sep.custom_minimum_size.y = 3.0
				box.add_child(sep)
			first = false
			box.add_child(_move_row(card, steps, tr.size.x - 8.0))
			var sub := _move_sub(card)
			if sub != "":
				var l := UIKit.rich_label(sub, steps[2], Color("a9c4c0"))
				box.add_child(l)

	# the footer strip
	var f := _footer_rect()
	_footer = UIKit.label(footer_text, 11, footer_color)
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_footer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_footer.position = f.position
	_footer.size = f.size
	add_child(_footer)
	queue_redraw()

## One card it grants: [heat flame with its cost] name ........ [burst] hits×damage.
func _move_row(card: CardData, steps: Array, width: float) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 5)
	var gem := Control.new() # the heat flame with its cost, or FREE for a 0-heat card (drawn)
	gem.custom_minimum_size = Vector2(22, 22)
	gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cost := card.heat_cost
	var cat_c := Palette.category_color(component.category)
	gem.draw.connect(func():
		if cost <= 0:
			var chip := Rect2(0, 5, 22, 13)
			gem.draw_rect(chip, Color(cat_c, 0.22), true)
			gem.draw_rect(chip, Color(cat_c, 0.8), false, 1.0)
			_draw_number(gem, "FREE", chip.get_center(), 8, cat_c.lightened(0.45))
		else:
			CardUI.draw_flame(gem, Vector2(12, 13), 26.0) # 1 px right of its digit, centered on it (Logan)
			_draw_number(gem, str(cost), Vector2(11, 13), 12, Color("fff3e0")))
	row.add_child(gem)
	var dmg := card.damage_label().replace("×", " × ") # spaced out on the card: "3 × 2-4" (Logan)
	var dmg_w := 0.0
	if dmg != "":
		dmg_w = _font().get_string_size(dmg, HORIZONTAL_ALIGNMENT_LEFT, -1, steps[1]).x + 12.0
	var name_l := _fitted_label(card.name, steps[0], 9, width - 27.0 - dmg_w - 5.0, Palette.TEXT)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_l)
	if dmg != "":
		var badge := Control.new() # the damage: hits x per hit on a badge (drawn)
		badge.custom_minimum_size = Vector2(dmg_w, 20)
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fs: int = steps[1]
		badge.draw.connect(func():
			var r := Rect2(0, 2, dmg_w, 16)
			badge.draw_rect(r, Color(0.35, 0.08, 0.02, 0.55), true)
			badge.draw_rect(r, Color(Palette.HARDPOINT, 0.85), false, 1.0)
			badge.draw_line(r.position + Vector2(1, 1), Vector2(r.end.x - 1, r.position.y + 1), Color(1, 0.8, 0.6, 0.35), 1.0)
			_draw_number(badge, dmg, r.get_center(), fs, Color("ffe2c8")))
		row.add_child(badge)
	return row

## A card's statuses and effect, one line each, under its row.
func _move_sub(card: CardData) -> String:
	var sub: Array[String] = []
	sub.append_array(card.status_lines())
	if card.effect_text != "":
		sub.append(card.effect_text)
	return "\n".join(sub)

## How tall the text box's content is at these text sizes, `width` wide (measured, so the
## card is laid out once, at the size it'll stay).
func _text_height(steps: Array, width: float) -> float:
	var f := _font()
	var w := width - 14.0 # measured a little narrow: the labels wrap a touch earlier than the font's own measure
	if component.category == ComponentData.CATEGORY_REACTOR:
		return 14.0 + 3.0 + _wrapped_h(f, component.passive_text(), steps[3], w) + 6.0
	var h := 6.0
	var first := true
	for card in component.cards:
		if not first:
			h += 3.0 + 2.0
		first = false
		h += 22.0
		var sub := _move_sub(card)
		if sub != "":
			h += 2.0 + _wrapped_h(f, sub, steps[2], w)
	return h

static func _wrapped_h(f: Font, text: String, fs: int, width: float) -> float:
	var plain := text
	var re := RegEx.create_from_string("\\[[^\\]]*\\]")
	plain = re.sub(plain, "", true)
	return f.get_multiline_string_size(plain, HORIZONTAL_ALIGNMENT_LEFT, width, fs, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND).y * 1.08 + 3.0

func _font() -> Font:
	return get_theme_default_font()

## A name on one line: its font shrinks from `font_size` to fit `width`, down to `min_size`
## (Logan, 2026-11-11: long names broke awkwardly over two lines). Past that it wraps.
func _fitted_label(text: String, font_size: int, min_size: int, width: float, color: Color) -> Label:
	var f := _font()
	var fs := font_size
	while fs > min_size and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
		fs -= 1
	return UIKit.label(text, fs, color, f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width)

func _draw_number(canvas: CanvasItem, text: String, at: Vector2, fs: int, color: Color) -> void:
	var f := _font()
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := at + Vector2(-w / 2.0, fs * 0.36)
	canvas.draw_string_outline(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.85))
	canvas.draw_string(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)

## The shape's footprint in cells: (columns, rows).
func _shape_cells() -> Vector2i:
	var rows := 0
	var cols := 0
	for c in component.cells:
		rows = maxi(rows, c.x + 1)
		cols = maxi(cols, c.y + 1)
	return Vector2i(cols, rows)

# ---------- input ----------

func _set_hover(h: bool) -> void:
	_hover = h and selectable
	queue_redraw()

func _on_gui_input(event: InputEvent) -> void:
	if selectable and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		pressed.emit(self)

# ---------- drawing ----------

func _draw() -> void:
	if component == null:
		return
	var c := Palette.category_color(component.category)
	var edge := Palette.LINK if _hover else c
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.015, 0.03, 0.04, 0.88), true)
	GlassPanel.draw_glass(self, r, 1.0, edge, 10.0, 0.9 if _hover else 0.7)

	# header: the rarity gem, and the HP badge
	var rc := Palette.rarity_color(_rarity)
	var g := Vector2(PAD + 6.0, 12.0)
	var gem := PackedVector2Array([g + Vector2(0, -6), g + Vector2(6, 0), g + Vector2(0, 6), g + Vector2(-6, 0)])
	draw_colored_polygon(gem, Color(rc, 0.85))
	draw_polyline(gem + PackedVector2Array([gem[0]]), rc.lightened(0.4), 1.0)
	draw_line(g + Vector2(-3, -1), g + Vector2(0, -4), Color(1, 1, 1, 0.6), 1.0)
	var hp := "%d" % component.max_hp if component.current_hp == component.max_hp else "%d/%d" % [component.current_hp, component.max_hp]
	var f := _font()
	var hw := f.get_string_size(hp, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + f.get_string_size("HP", HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 16.0
	var hb := Rect2(size.x - PAD - hw, 3.0, hw, 17.0)
	var hurt := component.current_hp < component.max_hp
	var hc := Palette.WARNING if hurt else Color("cfe9e5")
	draw_rect(hb, Color(0.0, 0.0, 0.0, 0.45), true)
	draw_rect(hb, Color(hc, 0.55), false, 1.0)
	draw_string(f, hb.position + Vector2(6, 13), "HP", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(hc, 0.7))
	draw_string(f, hb.position + Vector2(10 + f.get_string_size("HP", HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x, 13), hp, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, hc)

	# the art window: a dark well with a grid in the category's color, the shape centered on it
	var a := _art_rect()
	draw_rect(a, Color(0.0, 0.01, 0.015, 0.75), true)
	# the grid: squares the size of the part's own cells, lined up with them, as if it sits in a frame
	var fit := _shape_fit(a.grow(-12.0))
	var pitch: float = fit[0] + SHAPE_GAP
	var x: float = fit[1].x - SHAPE_GAP / 2.0
	while x > a.position.x:
		x -= pitch
	x += pitch
	while x < a.end.x:
		draw_line(Vector2(x, a.position.y), Vector2(x, a.end.y), Color(c, 0.14), 1.0)
		x += pitch
	var y: float = fit[1].y - SHAPE_GAP / 2.0
	while y > a.position.y:
		y -= pitch
	y += pitch
	while y < a.end.y:
		draw_line(Vector2(a.position.x, y), Vector2(a.end.x, y), Color(c, 0.14), 1.0)
		y += pitch
	draw_rect(a, Color(c, 0.45), false, 1.0)
	# its corner brackets
	for corner in [a.position, Vector2(a.end.x, a.position.y), Vector2(a.position.x, a.end.y), a.end]:
		var sx := 1.0 if corner.x == a.position.x else -1.0
		var sy := 1.0 if corner.y == a.position.y else -1.0
		draw_line(corner, corner + Vector2(10 * sx, 0), Color(c, 0.95), 2.0)
		draw_line(corner, corner + Vector2(0, 10 * sy), Color(c, 0.95), 2.0)
	draw_string(f, a.position + Vector2(6, 13), component.category.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(c, 0.75))
	_draw_shape_in(a.grow(-12.0))

	# the name banner
	var b := _banner_rect()
	draw_rect(b, Color(c, 0.16), true)
	draw_line(b.position, Vector2(b.end.x, b.position.y), Color(c, 0.6), 1.0)
	draw_line(Vector2(b.position.x, b.end.y), b.end, Color(c, 0.6), 1.0)

	# the text box
	var t := _text_rect()
	draw_rect(t, Color(0.0, 0.01, 0.015, 0.5), true)
	draw_rect(t, Color(c, 0.22), false, 1.0)

	# the footer strip
	var fr := _footer_rect()
	draw_rect(fr, Color(c, 0.1), true)
	draw_line(fr.position, Vector2(fr.end.x, fr.position.y), Color(c, 0.35), 1.0)

## The part's cells, as big as fits `area` (up to ART_CELL_MAX), centered in it, with its art.
func _draw_shape_in(area: Rect2) -> void:
	var shape := ComponentLibrary.make(component.library_id)
	if shape == null:
		return
	shape.place(0, Vector2i.ZERO)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var fit := _shape_fit(area)
	var cell: float = fit[0]
	var origin: Vector2 = fit[1]
	for p in shape.placed_cells:
		PartArt.draw_part_cell(self, Rect2(origin + Vector2(p.y, p.x) * (cell + SHAPE_GAP), Vector2(cell, cell)), shape, p)

## [cell size, top-left of the first cell] for the shape centered in `area`, as big as fits (up to ART_CELL_MAX).
func _shape_fit(area: Rect2) -> Array:
	var cells := _shape_cells()
	var cell := floorf(minf(ART_CELL_MAX, minf((area.size.x + SHAPE_GAP) / cells.x, (area.size.y + SHAPE_GAP) / cells.y) - SHAPE_GAP))
	var dims := Vector2(cells.x * (cell + SHAPE_GAP) - SHAPE_GAP, cells.y * (cell + SHAPE_GAP) - SHAPE_GAP)
	return [cell, (area.position + (area.size - dims) / 2.0).floor()]

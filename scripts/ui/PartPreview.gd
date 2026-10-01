class_name PartPreview
extends GlassPanel
## A part inspected on a holo glass screen (the Hangar): its shape drawn big
## with its art in the squares (PartArt) and a soft glow under it, then its
## category, rarity and weight class, name, HP and size, and what it does:
## each card (heat, damage, statuses, effect text) or a reactor's passive.
## Everything is Refit Bay data. Shows a hint until something is inspected.

const PAD := 14.0
const SHAPE_BOX := Vector2(150, 150)
const MAX_CELL := 34.0
const GAP := 3.0

var component: ComponentData = null
var _shape_part: ComponentData = null # an unrotated copy, for drawing the shape
var _shape: Control
var _scroll: ScrollContainer
var _info: VBoxContainer
var _hint: Label
## What the empty screen says.
var hint_text: String = "Hover a part in the armory or on a grid to inspect it."

func _ready() -> void:
	super()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shape = Control.new()
	_shape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shape.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_shape.draw.connect(_draw_shape)
	add_child(_shape)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_scroll)
	_info = VBoxContainer.new()
	_info.add_theme_constant_override("separation", 3)
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_info)
	_hint = UIKit.label(hint_text, 13, Color("b9d8d4")) # one line: a wrapping label mis-sizes before layout
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_hint)
	resized.connect(_layout)
	_layout()
	show_part(null)

func _layout() -> void:
	_shape.position = Vector2(PAD, PAD)
	_shape.size = SHAPE_BOX
	_scroll.position = Vector2(PAD * 2.0 + SHAPE_BOX.x, PAD)
	_scroll.size = Vector2(maxf(0.0, size.x - SHAPE_BOX.x - PAD * 3.0), maxf(0.0, size.y - PAD * 2.0))
	_hint.position = Vector2(PAD, PAD)
	_hint.size = size - Vector2(PAD, PAD) * 2.0

## Shows a part (an installed one keeps its HP); null shows the hint.
func show_part(part: ComponentData) -> void:
	component = part
	_hint.visible = part == null
	_scroll.visible = part != null
	for c in _info.get_children():
		c.queue_free()
	if part == null:
		_shape_part = null
		_shape.queue_redraw()
		return
	accent = Palette.category_color(part.category)
	_shape_part = ComponentLibrary.make(part.library_id)
	if _shape_part != null:
		_shape_part.place(0, Vector2i.ZERO)
	var d := ComponentLibrary.definition(part.library_id)
	var cat_color := Palette.category_color(part.category)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(UIKit.label(part.category.to_upper(), 10, cat_color))
	head.add_child(UIKit.label("·  %s" % str(d.get("rarity", "")).capitalize(), 10, Palette.rarity_color(d.get("rarity", ""))))
	head.add_child(UIKit.label("·  %s" % ComponentLibrary.weight_class_of(part.library_id).capitalize(), 10, Color("b9d8d4")))
	_info.add_child(head)
	_info.add_child(UIKit.label(part.name, 18, Color("dffcf8"), true))
	var hp := "%d HP" % part.max_hp if part.current_hp == part.max_hp else "%d / %d HP" % [part.current_hp, part.max_hp]
	_info.add_child(UIKit.label("%s  ·  %d cells" % [hp, part.cells.size()], 12, Palette.WARNING if part.current_hp < part.max_hp else Color("b9d8d4")))
	_info.add_child(_rule())
	if part.category == ComponentData.CATEGORY_REACTOR:
		_info.add_child(UIKit.label("PASSIVE  ·  always in play", 10, cat_color))
		_info.add_child(UIKit.label(part.passive_text(), 12, Palette.TEXT, true))
	else:
		for card in part.cards:
			_info.add_child(_card_line(card, cat_color))
			var sub := _card_details(card)
			if sub != "":
				_info.add_child(UIKit.label(sub, 11, Color("9fb9b6"), true))
	_shape.queue_redraw()
	queue_redraw()

func _rule() -> Control:
	var r := ColorRect.new()
	r.color = Color(accent, 0.35)
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

## "Rapid Fire   [4 heat]   5×5–7": the card's name, a heat chip, its damage.
func _card_line(card: CardData, cat_color: Color) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	row.add_child(UIKit.label(card.name, 13, Palette.TEXT))
	var heat := UIKit.label("%d heat" % card.heat_cost, 10, Palette.HARDPOINT)
	heat.add_theme_stylebox_override("normal", GlassPanel.control_style(Palette.HARDPOINT, 0.18, 0.7))
	heat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(heat)
	if card.damage_label() != "":
		row.add_child(UIKit.label(card.damage_label(), 12, cat_color))
	return row

static func _card_details(card: CardData) -> String:
	var sub: Array[String] = []
	sub.append_array(card.status_lines())
	if card.effect_text != "":
		sub.append(card.effect_text)
	return "\n".join(sub)

## The part's shape, as big as fits, with its art in the squares.
func _draw_shape() -> void:
	if _shape_part == null:
		return
	var dims := Vector2i.ZERO # rows, cols
	for c in _shape_part.cells:
		dims = Vector2i(maxi(dims.x, c.x + 1), maxi(dims.y, c.y + 1))
	var cell := minf(MAX_CELL, minf((SHAPE_BOX.x + GAP) / dims.y, (SHAPE_BOX.y + GAP) / dims.x) - GAP)
	var total := Vector2(dims.y, dims.x) * (cell + GAP) - Vector2(GAP, GAP)
	var origin := ((SHAPE_BOX - total) / 2.0).floor()
	var glow := Palette.category_color(_shape_part.category)
	_shape.draw_circle(SHAPE_BOX / 2.0, maxf(total.x, total.y) * 0.62, Color(glow, 0.06))
	_shape.draw_circle(SHAPE_BOX / 2.0, maxf(total.x, total.y) * 0.45, Color(glow, 0.06))
	for c in _shape_part.placed_cells:
		var r := Rect2(origin + Vector2(c.y, c.x) * (cell + GAP), Vector2(cell, cell))
		PartArt.draw_part_cell(_shape, r, _shape_part, c)

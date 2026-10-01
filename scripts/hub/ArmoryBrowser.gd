class_name ArmoryBrowser
extends GlassPanel
## The Hangar's armory: every Surplus part the mech's weight class can
## mount, on a glass screen. Search matches a part's name, its cards and
## what they do; chips filter by category (with counts); the sort menu
## orders by category, name, HP, size or cheapest card. Each row shows the
## part's shape with its art, its name and a one-line summary. Hovering a
## row inspects the part; clicking it picks it up to place.

signal part_hovered(id: String)
signal part_picked(id: String)

const PAD := 12.0
const ROW_H := 50.0
const CATEGORIES := ["", ComponentData.CATEGORY_HARDPOINT, ComponentData.CATEGORY_REACTOR, ComponentData.CATEGORY_PROTOCOL]
const CATEGORY_NAMES := ["All", "Hardpoints", "Reactors", "Protocols"]
const SORTS := ["Category", "Name", "HP (high first)", "Size (small first)", "Heat (cheapest card)"]

var weight_class: String = ""
var _ids: Array[String] = []
var _category: String = ""
var _sort: int = 0
var _query: String = ""
var _header: Label
var _search: LineEdit
var _chips: HBoxContainer
var _sort_btn: OptionButton
var _scroll: ScrollContainer
var _list: VBoxContainer
var _empty: Label

func _ready() -> void:
	super()
	_header = UIKit.label("ARMORY", 12, Color("dffcf8"))
	add_child(_header)
	_search = LineEdit.new()
	_search.placeholder_text = "Search parts, cards, effects…"
	_search.clear_button_enabled = true
	_search.add_theme_font_size_override("font_size", 12)
	_search.add_theme_stylebox_override("normal", GlassPanel.control_style())
	_search.add_theme_stylebox_override("focus", GlassPanel.control_style(Palette.LINK, 0.0, 0.8))
	_search.add_theme_color_override("font_color", Palette.TEXT)
	_search.add_theme_color_override("font_placeholder_color", Color("7f9d9a"))
	_search.text_changed.connect(func(t: String): _query = t.strip_edges().to_lower(); _rebuild())
	add_child(_search)
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 5)
	add_child(_chips)
	for i in range(CATEGORIES.size()):
		var b := GlassPanel.button(CATEGORY_NAMES[i], 11, i == 0, _chip_color(i))
		b.pressed.connect(_set_category.bind(CATEGORIES[i]))
		_chips.add_child(b)
	_sort_btn = OptionButton.new()
	_sort_btn.focus_mode = Control.FOCUS_NONE
	_sort_btn.add_theme_font_size_override("font_size", 11)
	for s in SORTS:
		_sort_btn.add_item("Sort: " + s)
	for key in ["normal", "hover", "pressed"]:
		_sort_btn.add_theme_stylebox_override(key, GlassPanel.control_style(Palette.LINK if key == "hover" else GlassPanel.HOLO))
	_sort_btn.add_theme_color_override("font_color", Color("b9d8d4"))
	_sort_btn.item_selected.connect(func(i: int): _sort = i; _rebuild())
	add_child(_sort_btn)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 3)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	_empty = UIKit.label("No parts match.", 12, Color("7f9d9a"))
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_empty)
	resized.connect(_layout)
	_layout()

func _chip_color(i: int) -> Color:
	return GlassPanel.HOLO if CATEGORIES[i] == "" else Palette.category_color(CATEGORIES[i])

func _layout() -> void:
	var w := size.x - PAD * 2.0
	_header.position = Vector2(PAD, PAD - 2.0)
	_search.position = Vector2(PAD, PAD + 20.0)
	_search.size = Vector2(w, 30)
	_chips.position = Vector2(PAD, PAD + 58.0)
	_chips.size = Vector2(w, 26)
	_sort_btn.position = Vector2(PAD, PAD + 90.0)
	_sort_btn.size = Vector2(w, 26)
	_scroll.position = Vector2(PAD, PAD + 124.0)
	_scroll.size = Vector2(w, maxf(0.0, size.y - PAD * 2.0 - 124.0))
	_empty.position = _scroll.position + Vector2(0, 20)
	_empty.size = Vector2(w, 20)

## Lists the Surplus parts a `p_weight_class` chassis can mount.
func setup(p_weight_class: String) -> void:
	weight_class = p_weight_class
	_ids.clear()
	for id in ComponentLibrary.all_ids():
		var d := ComponentLibrary.definition(id)
		if d.get("rarity", "") == "surplus" and ComponentLibrary.fits_class(id, weight_class):
			_ids.append(id)
	_rebuild()

func _set_category(cat: String) -> void:
	_category = cat
	_rebuild()

func _matches(id: String) -> bool:
	var d := ComponentLibrary.definition(id)
	if _category != "" and d["category"] != _category:
		return false
	if _query == "":
		return true
	var text := "%s %s" % [d["name"], d["category"]]
	for c in d.get("cards", []):
		text += " %s %s" % [c.get("name", ""), c.get("effect_text", "")]
		for s in c.get("statuses", []):
			text += " " + str(s.get("status", "") if typeof(s) == TYPE_DICTIONARY else s)
	return text.to_lower().contains(_query)

static func _min_heat(id: String) -> int:
	var best := 999
	for c in ComponentLibrary.definition(id).get("cards", []):
		if ComponentLibrary.definition(id)["category"] != ComponentData.CATEGORY_REACTOR:
			best = mini(best, int(str(c.get("heat_cost", "0"))))
	return best

func _sorted(ids: Array[String]) -> Array[String]:
	var order := {ComponentData.CATEGORY_HARDPOINT: 0, ComponentData.CATEGORY_REACTOR: 1, ComponentData.CATEGORY_PROTOCOL: 2}
	var key := func(id: String) -> Array:
		var d := ComponentLibrary.definition(id)
		match _sort:
			1: return [str(d["name"])]
			2: return [-int(d["hp"]), str(d["name"])]
			3: return [(d["cells"] as Array).size(), str(d["name"])]
			4: return [_min_heat(id), str(d["name"])]
		return [order.get(d["category"], 3), str(d["name"])]
	var out := ids.duplicate()
	out.sort_custom(func(a, b): return key.call(a) < key.call(b))
	return out

func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	var counts := [0, 0, 0, 0]
	for id in _ids:
		counts[0] += 1
		counts[CATEGORIES.find(ComponentLibrary.definition(id)["category"])] += 1
	for i in range(_chips.get_child_count()):
		var b: Button = _chips.get_child(i)
		b.text = "%s %d" % [CATEGORY_NAMES[i], counts[i]]
		GlassPanel.style_button(b, CATEGORIES[i] == _category, _chip_color(i))
	var shown: Array[String] = []
	for id in _ids:
		if _matches(id):
			shown.append(id)
	for id in _sorted(shown):
		var row := ArmoryRow.new()
		row.custom_minimum_size = Vector2(0, ROW_H)
		row.setup(id)
		row.mouse_entered.connect(func(): part_hovered.emit(id))
		row.pressed.connect(func(): part_picked.emit(id))
		_list.add_child(row)
	_header.text = "ARMORY  ·  %d of %d Surplus parts for a %s chassis" % [shown.size(), _ids.size(), weight_class.capitalize()]
	_empty.visible = shown.is_empty()


## One armory row: the part's shape with its art, name, and a summary line.
class ArmoryRow extends Control:
	signal pressed()

	const MINI := 9.0
	const MINI_GAP := 1.0

	var id: String = ""
	var part: ComponentData
	## A price (the Autonomous Bay's stock), drawn as a chip on the right.
	var price_text: String = ""
	var price_color: Color = Palette.SCRAPS
	var _hover := false
	var _summary := ""
	var _class_tag := ""

	func setup(p_id: String) -> void:
		id = p_id
		part = ComponentLibrary.make(id)
		part.place(0, Vector2i.ZERO)
		var bits: Array[String] = ["%d HP" % part.max_hp, "%d cells" % part.cells.size()]
		if part.category == ComponentData.CATEGORY_REACTOR:
			bits.append("passive")
		elif not part.cards.is_empty():
			var lo := 999
			var hi := 0
			for c in part.cards:
				lo = mini(lo, c.heat_cost)
				hi = maxi(hi, c.heat_cost)
			bits.append("%d card%s, heat %s" % [part.cards.size(), "" if part.cards.size() == 1 else "s", str(lo) if lo == hi else "%d to %d" % [lo, hi]])
		_summary = "  ·  ".join(bits)
		var wc := ComponentLibrary.weight_class_of(id)
		_class_tag = "" if wc == "general" else wc.to_upper()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		mouse_entered.connect(func(): _hover = true; queue_redraw())
		mouse_exited.connect(func(): _hover = false; queue_redraw())

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			Audio.play("ui", 0.03)
			pressed.emit()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var cat := Palette.category_color(part.category)
		draw_rect(r, Color(cat, 0.14) if _hover else Color(0, 0, 0, 0.25), true)
		draw_rect(r, Color(Palette.LINK if _hover else cat, 0.8 if _hover else 0.25), false, 1.0)
		draw_rect(Rect2(0, 0, 3, size.y), cat, true)
		# the shape, centred in a square box on the left
		var dims := Vector2i.ZERO
		for c in part.cells:
			dims = Vector2i(maxi(dims.x, c.x + 1), maxi(dims.y, c.y + 1))
		var box := size.y - 8.0
		var total := Vector2(dims.y, dims.x) * (MINI + MINI_GAP) - Vector2(MINI_GAP, MINI_GAP)
		var o := Vector2(8.0, 4.0) + ((Vector2(box, box) - total) / 2.0).floor()
		for c in part.placed_cells:
			PartArt.draw_part_cell(self, Rect2(o + Vector2(c.y, c.x) * (MINI + MINI_GAP), Vector2(MINI, MINI)), part, c)
		var font := get_theme_default_font()
		var x := box + 16.0
		var right := size.x - 8.0
		if price_text != "": # a chip at the top right; the class tag drops to the summary line
			var pw := font.get_string_size(price_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 12.0
			var chip := Rect2(size.x - pw - 6.0, 6, pw, 19.0)
			draw_rect(chip, Color(price_color, 0.14), true)
			draw_rect(chip, Color(price_color, 0.8), false, 1.0)
			draw_string(font, chip.position + Vector2(6, 14), price_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, price_color)
			right = chip.position.x - 4.0
		var name_w := right - x - (0.0 if price_text != "" else 52.0)
		draw_string(font, Vector2(x, 20), part.name, HORIZONTAL_ALIGNMENT_LEFT, name_w, 14, Palette.TEXT if _hover else Color("dfe6ea"))
		draw_string(font, Vector2(x, 38), _summary, HORIZONTAL_ALIGNMENT_LEFT, size.x - x - 8.0 - (52.0 if price_text != "" and _class_tag != "" else 0.0), 11, Color("8fb0ac"))
		if _class_tag != "":
			var tw := font.get_string_size(_class_tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
			var tag := Rect2(right - tw - 8.0, 7, tw + 10.0, 14)
			if price_text != "":
				tag.position = Vector2(size.x - tw - 16.0, 28)
			draw_rect(tag, Color(Palette.WARNING, 0.15), true)
			draw_rect(tag, Color(Palette.WARNING, 0.7), false, 1.0)
			draw_string(font, tag.position + Vector2(5, 11), _class_tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Palette.WARNING)

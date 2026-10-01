extends HubScreen
## Info Bay: browse every component (filter by type, rarity and weight
## class; hover one for its full card), the status glossary, and the codex:
## every enemy you've met (its parts, cards and how it fights, and your
## record against it) and every deployment order you've been offered.
## Unmet ones stay hidden.
## Theorycrafting loadouts lives in the Hangar for now.

var _tabs: HBoxContainer
var _body: Control
var _list: VBoxContainer
var _list_scroll: ScrollContainer
var _detail: Control
var _filters: HBoxContainer
var _tab: String = "components"
const TABS := [["components", "Components"], ["statuses", "Statuses"], ["enemies", "Enemies"], ["orders", "Orders"]]
var _cat: String = ""
var _rarity: String = ""
var _class: String = ""

func screen_title() -> String:
	return "Info Bay"

func _build() -> void:
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	add_child(_tabs)
	for t in TABS:
		var b := UIKit.button(t[1], Color.TRANSPARENT, Vector2(150, 36), 14)
		b.pressed.connect(func(): _tab = t[0]; _rebuild())
		_tabs.add_child(b)
	var train := UIKit.button("Replay training", Palette.LINK, Vector2(160, 36), 13)
	train.disabled = SaveGame.has_save()
	train.tooltip_text = "Finish or abandon your run in progress first." if train.disabled else "Two short fights that walk you through the basics."
	train.pressed.connect(func():
		Tutorial.start()
		SceneRouter.go(SceneRouter.WAR_ROOM))
	_tabs.add_child(train)
	_body = Control.new()
	add_child(_body)
	_rebuild()

func _rebuild() -> void:
	for c in _body.get_children():
		c.queue_free()
	for i in range(TABS.size()):
		var on: bool = TABS[i][0] == _tab
		(_tabs.get_child(i) as Button).add_theme_stylebox_override("normal", UIKit.style(Palette.PANEL_2, Palette.HARDPOINT if on else Palette.BORDER, 2 if on else 1))
	match _tab:
		"components": _build_components()
		"statuses": _build_statuses()
		"enemies": _build_enemies()
		"orders": _build_orders()
	_on_resize()

## A scrolling column for the codex tabs (sized by _layout like Statuses).
func _column() -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	scroll.add_child(v)
	(func(): scroll.scroll_vertical = 0).call_deferred() # start at the top
	return v

const INTENT_WORDS := {"attack": "attack", "heavy_attack": "heavy attack", "block": "shield", "status": "status", "buff": "buff"}

## Every enemy on the roster: met ones in full, the rest as unknown contacts.
func _build_enemies() -> void:
	var v := _column()
	var ids: Array = []
	for loc in GameData.sectors():
		for id in loc.get("regulars", []) + loc.get("elites", []) + [loc.get("boss", "")]:
			if id != "" and not ids.has(id):
				ids.append(id)
	var seen := ids.filter(func(id): return Profile.seen_enemies.has(id)).size()
	v.add_child(UIKit.label("%d of %d enemies met.%s" % [seen, ids.size(), "" if seen == ids.size() else " Meet the rest in the field."], 13, Palette.TEXT_MUTED))
	for id in ids:
		v.add_child(_enemy_card(id))

func _enemy_card(id: String) -> Control:
	var m := DataLoader.load_mech_from_file("res://data/mechs/%s.json" % id)
	var box := HubScreen.card(Palette.HARDPOINT if m.tier == "boss" else (Palette.SALVAGED if m.tier == "elite" else Palette.BORDER))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	box.add_child(col)
	var where: Array[String] = []
	for loc in GameData.sectors():
		if (loc.get("regulars", []) + loc.get("elites", []) + [loc.get("boss", "")]).has(id):
			where.append(str(loc["name"]))
	if not Profile.seen_enemies.has(id):
		col.add_child(UIKit.label("Unknown contact  ·  %s" % m.tier.capitalize(), 15, Palette.TEXT_MUTED))
		col.add_child(UIKit.label("Seen near: %s. Not met yet." % ", ".join(where), 12, Palette.TEXT_MUTED))
		return box
	var rec: Dictionary = Profile.enemy_record.get(id, {})
	var title := "%s  ·  %s" % [m.name, m.tier.capitalize()] + ("  ·  %s" % m.title if m.title != "" else "")
	col.add_child(UIKit.label(title, 16, Palette.TEXT))
	col.add_child(UIKit.label("%s  ·  max heat %d  ·  %d HP%s  ·  %s" % [", ".join(where), m.max_heat, m.max_hp(),
		"" if m.defeat_hp_fraction <= 0.0 else ", beaten at %d" % m.defeat_hp_threshold(),
		"fought %d, won %d, it ended %d run%s" % [int(rec.get("fought", 0)), int(rec.get("beaten", 0)), int(rec.get("lost_to", 0)), "" if int(rec.get("lost_to", 0)) == 1 else "s"] if not rec.is_empty() else "no fights logged"], 12, Palette.TEXT_MUTED, true))
	if str(m.ai.get("_why", "")) != "":
		col.add_child(UIKit.label(str(m.ai["_why"]), 13, Palette.REACTOR, true))
	for c in m.components:
		var line := "%s (%s, %d HP)" % [c.name, c.category, c.max_hp]
		var cards: Array[String] = []
		for card in c.cards:
			var bits := [INTENT_WORDS.get(card.intent(), card.intent())]
			if card.heat_cost != 0:
				bits.append("%d heat" % card.heat_cost)
			if card.hits > 0:
				bits.append(("%d×%d–%d" % [card.hits, card.damage_min, card.damage_max]) if card.hits > 1 else "%d–%d" % [card.damage_min, card.damage_max])
			cards.append("%s [%s]" % [card.name, ", ".join(bits)])
		if not cards.is_empty():
			line += ":  " + "  ·  ".join(cards)
		elif c.passive_type() != "":
			line += ":  passive"
		col.add_child(UIKit.label(line, 12, Palette.category_color(c.category), true))
	return box

## Every deployment order: the ones offered so far, the rest hidden. (Which
## kind an order is stays unsaid, as when it's offered.)
func _build_orders() -> void:
	var v := _column()
	var all := DeploymentOrders.all()
	var seen := all.filter(func(o): return Profile.seen_orders.has(o["id"])).size()
	v.add_child(UIKit.label("%d of %d deployment orders offered so far." % [seen, all.size()], 13, Palette.TEXT_MUTED))
	for o in all:
		var box := HubScreen.card()
		var col := VBoxContainer.new()
		box.add_child(col)
		if Profile.seen_orders.has(o["id"]):
			col.add_child(UIKit.label(DeploymentOrders.title(o["id"]), 16, Palette.LINK))
			col.add_child(UIKit.label(DeploymentOrders.text(o["id"]), 13, Palette.TEXT_MUTED, true))
		else:
			col.add_child(UIKit.label("Unknown order", 16, Palette.TEXT_MUTED))
		v.add_child(box)

func _build_components() -> void:
	_filters = HBoxContainer.new()
	_filters.add_theme_constant_override("separation", 6)
	_body.add_child(_filters)
	_filter_group("", [["", "All types"], ["hardpoint", "Hardpoints"], ["reactor", "Reactors"], ["protocol", "Protocols"]], "_cat")
	_filter_group("", [["", "All rarities"], ["surplus", "Surplus"], ["salvaged", "Salvaged"], ["prototype", "Prototype"]], "_rarity")
	_filter_group("", [["", "All classes"], ["general", "General"], ["light", "Light"], ["medium", "Medium"], ["heavy", "Heavy"]], "_class")
	_list_scroll = ScrollContainer.new()
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(_list_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 3)
	_list_scroll.add_child(_list)
	_detail = Control.new()
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_detail)
	var shown := 0
	for id in ComponentLibrary.all_ids():
		var d := ComponentLibrary.definition(id)
		if (_cat != "" and d["category"] != _cat) or (_rarity != "" and d["rarity"] != _rarity) or (_class != "" and d.get("weight_class", "general") != _class):
			continue
		shown += 1
		var b := UIKit.button("%s   ·   %s · %s · %d HP" % [d["name"], str(d["rarity"]).capitalize(), str(d.get("weight_class", "general")).capitalize(), int(d["hp"])], Color.TRANSPARENT, Vector2(0, 30), 12)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_color_override("font_color", Palette.category_color(d["category"]))
		b.mouse_entered.connect(_show.bind(id))
		b.pressed.connect(_show.bind(id))
		_list.add_child(b)
	_list.add_child(UIKit.label("%d components" % shown, 12, Palette.TEXT_MUTED))

func _filter_group(_label: String, opts: Array, field: String) -> void:
	var sel := OptionButton.new()
	sel.focus_mode = Control.FOCUS_NONE
	var current: String = get(field)
	for i in range(opts.size()):
		sel.add_item(opts[i][1], i)
		if opts[i][0] == current:
			sel.select(i)
	sel.item_selected.connect(func(i): set(field, opts[i][0]); _rebuild())
	_filters.add_child(sel)

func _show(id: String) -> void:
	for c in _detail.get_children():
		c.queue_free()
	var card := PartCardUI.new()
	card.selectable = false
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail.add_child(card)
	card.setup(id, ComponentLibrary.make(id))

func _build_statuses() -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	scroll.add_child(v)
	for e in StatusGlossary.ENTRIES.values() + StatusGlossary.KEYWORDS.values():
		var box := HubScreen.card()
		var col := VBoxContainer.new()
		box.add_child(col)
		col.add_child(UIKit.label(str(e["label"]), 16, Palette.TEXT))
		col.add_child(UIKit.label(str(e.get("rule", "")), 13, Palette.TEXT_MUTED, true))
		v.add_child(box)

func _layout(screen: Vector2) -> void:
	if _tabs == null or _body == null:
		return
	_tabs.position = Vector2(MARGIN, TOP_BAR_H + 16.0)
	_body.position = Vector2(MARGIN, TOP_BAR_H + 66.0)
	var h := screen.y - _body.position.y - 20.0
	_body.size = Vector2(screen.x - MARGIN * 2.0, h)
	for c in _body.get_children():
		if c is ScrollContainer and _tab in ["statuses", "enemies", "orders"]:
			c.position = Vector2.ZERO
			c.size = Vector2(minf(900.0 if _tab == "enemies" else 760.0, _body.size.x), h)
	if _tab == "components" and _list_scroll != null and is_instance_valid(_list_scroll):
		_filters.position = Vector2.ZERO
		_list_scroll.position = Vector2(0, 44)
		_list_scroll.size = Vector2(minf(560.0, _body.size.x - PartCardUI.SIZE.x - 30.0), h - 44)
		_detail.position = Vector2(_list_scroll.size.x + 30.0, 44)

extends RunScreen
## Salvage after a fight (Logan, 2026-09-27, Slay the Spire style): a
## "Choose 1" row with the three categories, above it the fight's scraps
## (already banked; 2026-09-28). Picking a category is final and opens its parts (up to 3,
## rarity-rolled) to take one of, or skip for scraps (RunData.skip_payout;
## each card says what it would sell for, and a weapon how much it would add
## to your best turn if installed too, KitMath, to compare). A part goes into Cargo; if it
## doesn't fit, a stored part can be scrapped to make room. Continue moves
## on (to a refit on the refit rows). The reward was rolled when the fight
## ended, so leaving and continuing can't reroll it. It's shown over the
## battlefield the fight was on (dimmed), on holo glass.

const PANEL_W := 760.0

var _content: VBoxContainer
var _pick_area: VBoxContainer
var _continue: Button
var _message: Label
var _cargo_view: PackingGrid
var _scrap_pending: ComponentData = null
var _cards: Array[PartCardUI] = []
var _glass: GlassPanel
var _backdrop: Texture2D = null

func screen_phase() -> String:
	return RunData.PHASE_REWARD

func screen_title() -> String:
	return "Salvage"

## The fight's own background (the same pick CombatScene made).
func backdrop() -> Texture2D:
	return _backdrop

func _pick_backdrop() -> void:
	if run.current_node_id < 0:
		return
	var kind: String = run.current_node().get("kind", RunMap.KIND_FIGHT)
	var tier: String = kind if kind in [RunMap.KIND_ELITE, RunMap.KIND_BOSS] else "regular"
	var options := GameData.backgrounds_for(run.location.get("id", ""), tier)
	if options.is_empty():
		return
	var bg: Dictionary = options[absi(hash([run.seed_value, run.current_node_id])) % options.size()]
	var path: String = bg.get("image", "")
	_backdrop = load(path) if path != "" and ResourceLoader.exists(path) else null

func _build() -> void:
	_pick_backdrop()
	_glass = GlassPanel.new()
	_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glass)
	_content = VBoxContainer.new()
	_content.resized.connect(_fit_glass)
	_content.add_theme_constant_override("separation", 14)
	add_child(_content)
	var head := UIKit.label("FIGHT WON", 13, Palette.OK)
	_content.add_child(head)

	var scraps_box := PanelContainer.new()
	scraps_box.add_theme_stylebox_override("panel", GlassPanel.panel_style(Palette.SCRAPS, 10.0))
	var scraps_row := HBoxContainer.new()
	scraps_row.add_theme_constant_override("separation", 14)
	scraps_box.add_child(scraps_row)
	var cl := UIKit.label("+%d scraps" % run.reward["scraps"], 18, Palette.SCRAPS)
	cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	scraps_row.add_child(cl)
	scraps_row.add_child(UIKit.spacer())
	var note: String = run.reward.get("note", "")
	var banked := UIKit.label(note if note != "" else "added to your Scraps", 13, Palette.WARNING if note != "" else Color("9fb9b6"))
	banked.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	scraps_row.add_child(banked)
	_content.add_child(scraps_box)

	_pick_area = VBoxContainer.new()
	_pick_area.add_theme_constant_override("separation", 12)
	_content.add_child(_pick_area)

	_message = UIKit.label("", 13, Palette.WARNING, true)
	_content.add_child(_message)

	_cargo_view = PackingGrid.new()
	_cargo_view.part_pressed.connect(_on_cargo_part_pressed)
	_content.add_child(_cargo_view)
	_cargo_view.visible = false

	var bottom := HBoxContainer.new()
	bottom.add_child(UIKit.spacer())
	var refit_next := run.is_refit_row(run.current_node()["row"]) if run.current_node_id >= 0 else false
	_continue = GlassPanel.button("Continue to refit" if refit_next else "Continue", 15, true, Palette.HARDPOINT)
	_continue.custom_minimum_size = Vector2(190, 44)
	_continue.pressed.connect(_on_continue)
	bottom.add_child(_continue)
	_content.add_child(bottom)
	_refresh()

## Wider when a pick offers more than 3 parts (Wider Picks).
func _panel_w() -> float:
	var most := 0
	for opts in run.reward.get("options", {}).values():
		most = maxi(most, (opts as Array).size())
	return maxf(PANEL_W, most * PartCardUI.SIZE.x + (most - 1) * 20.0)

func _layout(screen: Vector2) -> void:
	_content.position = Vector2((screen.x - _panel_w()) / 2.0, TOP_BAR_H + 34.0)
	_content.size = Vector2(_panel_w(), 0)
	_fit_glass()

## The glass sits behind the content, a margin wider.
func _fit_glass() -> void:
	if _glass == null:
		return
	_glass.position = _content.position - Vector2(22, 18)
	_glass.size = _content.size + Vector2(44, 36)

func _refresh() -> void:
	for c in _pick_area.get_children():
		c.queue_free()
	_cards.clear()
	if run.reward["category"] == "":
		_build_categories()
	else:
		_build_parts()
	refresh_header()

func _build_categories() -> void:
	_pick_area.add_child(UIKit.label("Choose 1", 20, Color("dffcf8")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_pick_area.add_child(row)
	for cat in Economy.CATEGORIES:
		var n: int = (run.reward["options"].get(cat, []) as Array).size()
		var col := Palette.category_color(cat)
		var b := GlassPanel.button("%s\n%s" % [cat.capitalize(), "%d parts" % n if n > 0 else "nothing salvageable yet"], 17, false, col)
		b.custom_minimum_size = Vector2(236, 96)
		b.add_theme_stylebox_override("normal", GlassPanel.control_style(col, 0.12, 0.85))
		b.disabled = n == 0
		b.pressed.connect(_choose_category.bind(cat))
		row.add_child(b)

func _build_parts() -> void:
	var cat: String = run.reward["category"]
	var title := "Take a %s" % cat.capitalize() if not run.reward["part_taken"] else "%s salvage" % cat.capitalize()
	_pick_area.add_child(UIKit.label(title, 20, Color("dffcf8")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	_pick_area.add_child(row)
	for id in run.reward["options"].get(cat, []):
		var card := PartCardUI.new()
		card.selectable = not run.reward["part_taken"]
		row.add_child(card)
		card.setup(id)
		if not run.reward["part_taken"]:
			var fits := not run.cargo.find_fit(card.component).is_empty()
			var sells := "sells for %d" % Economy.sell_value(id)
			var footer := ("Fits in Cargo · %s" if fits else "No room in Cargo · %s") % sells
			# what it adds to your best turn if installed too (KitMath)
			if card.component.cards.any(func(c): return c.hits > 0):
				var now := KitMath.mech_turn(run.player_mech)
				var gain := KitMath.with_part(run.player_mech, card.component) - now
				footer = "Best turn %s%d (to %d)\n%s" % ["+" if gain >= 0 else "", roundi(gain), roundi(now + gain), footer]
			card.set_footer(footer, Palette.TEXT_MUTED if fits else Palette.WARNING)
		card.pressed.connect(_on_card_pressed)
		_cards.append(card)
	if not run.reward["part_taken"]:
		var skip := GlassPanel.button("Skip  (+%d scraps)" % run.skip_payout(), 13, false, Palette.SCRAPS)
		skip.custom_minimum_size = Vector2(170, 36)
		skip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		skip.pressed.connect(_on_skip)
		_pick_area.add_child(skip)

func _on_skip() -> void:
	var paid := run.skip_reward_part()
	Audio.play("shop_buy")
	_hide_cargo()
	_message.text = "Skipped: +%d scraps." % paid
	_message.add_theme_color_override("font_color", Palette.SCRAPS)
	_refresh()

func _choose_category(cat: String) -> void:
	run.choose_reward_category(cat)
	_refresh()

func _on_card_pressed(card: PartCardUI) -> void:
	if run.reward["part_taken"]:
		return
	var comp := run.take_reward_part(card.component_id)
	if comp != null:
		_message.text = "%s stowed in Cargo." % comp.name
		_message.add_theme_color_override("font_color", Palette.OK)
		_hide_cargo()
		_refresh()
		for c in _cards:
			c.set_footer("Taken" if c.component_id == comp.library_id else "", Palette.OK)
		return
	_message.text = "No room in Cargo for %s. Click a stored part twice to scrap it, or skip." % card.component.name
	_message.add_theme_color_override("font_color", Palette.WARNING)
	_show_cargo()

func _show_cargo() -> void:
	_cargo_view.setup(run.cargo.cells(), Vector2i(run.cargo.rows, run.cargo.cols), 34.0)
	_cargo_view.set_parts(run.cargo.items)
	_cargo_view.visible = true

func _hide_cargo() -> void:
	_cargo_view.visible = false
	_scrap_pending = null

func _on_cargo_part_pressed(_grid: PackingGrid, part: ComponentData, _cell: Vector2i) -> void:
	if _scrap_pending != part:
		_scrap_pending = part
		_message.text = "Click %s again to scrap it." % part.name
		return
	run.discard_from_cargo(part)
	_scrap_pending = null
	_message.text = "Scrapped %s." % part.name
	_show_cargo()
	_refresh()

func _tutorial_targets() -> Dictionary:
	return {"reward": _content}

func _on_continue() -> void:
	Tutorial.event("reward_done")
	if SceneRouter.is_busy():
		return
	run.finish_reward()
	RunState.advance()

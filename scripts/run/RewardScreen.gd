extends RunScreen
## Salvage after a fight (Logan, 2026-09-27, Slay the Spire style): a
## "Choose 1" row with the three categories, above it the fight's scraps
## (already banked; 2026-09-28). Picking a category is final and opens its parts (up to 3,
## rarity-rolled) to take one of, or skip for scraps (RunData.skip_payout;
## each card says what it would sell for). Logan, 2026-10-02: no "Take a…"
## title and no best-turn number (that's for the player to work out); the
## choices spread evenly across the box; "+N scrap" sits left of Continue.
## A part goes into Cargo; if it
## doesn't fit, a stored part can be scrapped to make room. Continue moves
## on (to a refit on the refit rows). The reward was rolled when the fight
## ended, so leaving and continuing can't reroll it. It's shown over the
## battlefield the fight was on (dimmed), on holo glass.
## SHOW MECH (bottom left; Logan, 2026-10-02) opens the mech and its Cargo
## over the box, so the player can see what they have and what would fit.

const PANEL_W := 760.0

var _content: VBoxContainer
var _pick_area: VBoxContainer
var _continue: Button
var _skip: Button
var _message: Label
var _cargo_view: PackingGrid
var _scrap_pending: ComponentData = null
var _cards: Array[PartCardUI] = []
var _glass: GlassPanel
var _backdrop: Texture2D = null
var _mech_toggle: Button
var _mech_glass: GlassPanel
var _mech_box: VBoxContainer

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
	bottom.add_theme_constant_override("separation", 12)
	_mech_toggle = GlassPanel.button("SHOW MECH", 15, false, Palette.LINK)
	_mech_toggle.custom_minimum_size = Vector2(150, 44)
	_mech_toggle.pressed.connect(_show_mech)
	bottom.add_child(_mech_toggle)
	bottom.add_child(UIKit.spacer())
	_skip = GlassPanel.button("", 15, false, Palette.SCRAPS)
	_skip.custom_minimum_size = Vector2(150, 44)
	_skip.pressed.connect(_on_skip)
	bottom.add_child(_skip)
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
	if _mech_glass != null and is_instance_valid(_mech_glass):
		_mech_glass.position = ((screen - _mech_glass.size) / 2.0).floor()

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
	_skip.visible = run.reward["category"] != "" and not run.reward["part_taken"]
	_skip.text = "+%d scrap" % run.skip_payout()
	refresh_header()

func _build_categories() -> void:
	_pick_area.add_child(UIKit.label("Choose 1", 20, Color("dffcf8")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_pick_area.add_child(row)
	for cat in Economy.CATEGORIES: # three equal buttons across the box
		var n: int = (run.reward["options"].get(cat, []) as Array).size()
		var col := Palette.category_color(cat)
		var b := GlassPanel.button("%s\n%s" % [cat.capitalize(), "%d parts" % n if n > 0 else "nothing salvageable yet"], 17, false, col)
		b.custom_minimum_size = Vector2(0, 96)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_stylebox_override("normal", GlassPanel.control_style(col, 0.12, 0.85))
		b.disabled = n == 0
		b.pressed.connect(_choose_category.bind(cat))
		row.add_child(b)

func _build_parts() -> void:
	var cat: String = run.reward["category"]
	# The parts spread evenly across the box: each sits centered in an equal share of the row.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	_pick_area.add_child(row)
	for id in run.reward["options"].get(cat, []):
		var slot := CenterContainer.new()
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(slot)
		var card := PartCardUI.new()
		card.selectable = not run.reward["part_taken"]
		slot.add_child(card)
		card.setup(id)
		if not run.reward["part_taken"]:
			var fits := not run.cargo.find_fit(card.component).is_empty()
			var sells := "sells for %d" % Economy.sell_value(id)
			card.set_footer(("Fits in Cargo · %s" if fits else "No room in Cargo · %s") % sells, Palette.TEXT_MUTED if fits else Palette.WARNING)
		card.pressed.connect(_on_card_pressed)
		_cards.append(card)

func _on_skip() -> void:
	var paid := run.skip_reward_part()
	Audio.play("shop_buy")
	_hide_cargo()
	_message.text = "Skipped: +%d scrap." % paid
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

## SHOW MECH (Logan, 2026-10-14: the small grid beside the box wasn't
## enough): a screen over the salvage with the mech's grid drawn big, its
## Cargo beside it, what it's carrying by type, and a PartPreview of
## whatever part is hovered (its cards, HP or passive). Esc, the button or
## a click outside closes it.
func _show_mech(_on: bool = true) -> void:
	if _mech_glass != null:
		_mech_glass.queue_free()
	var shade := ColorRect.new()
	shade.color = Color(0, 0.01, 0.02, 0.72)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.z_index = 200
	shade.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_hide_mech())
	add_child(shade)
	_mech_glass = GlassPanel.new()
	_mech_glass.tint = 0.85
	_mech_glass.mouse_filter = Control.MOUSE_FILTER_STOP
	# a dark backing under the glass, so the salvage behind doesn't show through
	var backing := ColorRect.new()
	backing.color = Color(0.01, 0.025, 0.03, 0.9)
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backing.set_anchors_preset(Control.PRESET_FULL_RECT)
	backing.show_behind_parent = true
	_mech_glass.add_child(backing)
	shade.add_child(_mech_glass)
	_mech_box = VBoxContainer.new()
	_mech_box.add_theme_constant_override("separation", 12)
	_mech_box.position = Vector2(24, 20)
	_mech_glass.add_child(_mech_box)
	_build_mech_view()
	Audio.play("holo", 0.03, -4.0)

func _hide_mech() -> void:
	if _mech_glass != null and is_instance_valid(_mech_glass):
		_mech_glass.get_parent().queue_free()
	_mech_glass = null
	Audio.play("ui")

## Esc closes the mech first (before the settings menu takes it).
func _input(event: InputEvent) -> void:
	if _mech_glass != null and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_hide_mech()

func _build_mech_view() -> void:
	var m := run.player_mech
	var screen := get_viewport_rect().size
	var b := Vector2i.ZERO
	for c in run.chassis_cells():
		b = Vector2i(maxi(b.x, c.x + 1), maxi(b.y, c.y + 1))
	var cell := floorf(clampf((screen.y - 380.0) / maxf(b.x, 1) - PackingGrid.GAP, 24.0, 46.0))
	var free := run.chassis_cells().size() - run.mech_occupied().size()

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	_mech_box.add_child(head)
	head.add_child(UIKit.label(m.name.to_upper(), 20, Color("eefcfa")))
	var hp := UIKit.label("%d / %d HP" % [m.current_hp(), m.max_hp()], 15, Palette.OK if m.current_hp() * 2 > m.max_hp() else Palette.WARNING)
	hp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(hp)
	head.add_child(UIKit.spacer())
	var close := GlassPanel.button("Close", 13)
	close.custom_minimum_size = Vector2(90, 32)
	close.pressed.connect(_hide_mech)
	head.add_child(close)

	# what it carries, by type, in the words training uses
	var counts := {}
	var lost := 0
	for c in m.components:
		if c.destroyed:
			lost += 1
		else:
			counts[c.category] = int(counts.get(c.category, 0)) + 1
	var kinds := HBoxContainer.new()
	kinds.add_theme_constant_override("separation", 18)
	_mech_box.add_child(kinds)
	for cat in [[ComponentData.CATEGORY_HARDPOINT, "weapons"], [ComponentData.CATEGORY_PROTOCOL, "weapon augments"], [ComponentData.CATEGORY_REACTOR, "passives"]]:
		var n := int(counts.get(cat[0], 0))
		kinds.add_child(UIKit.label("%d %s%s (%s)" % [n, str(cat[0]).capitalize(), "" if n == 1 else "s", cat[1]], 13, Palette.category_color(cat[0])))
	if lost > 0:
		kinds.add_child(UIKit.label("%d destroyed" % lost, 13, Palette.DANGER))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	_mech_box.add_child(row)
	var preview := PartPreview.new()
	preview.hint_text = "Hover a part to see its cards."
	var mech_col := VBoxContainer.new()
	mech_col.add_theme_constant_override("separation", 6)
	row.add_child(mech_col)
	mech_col.add_child(UIKit.label("FRAME  ·  %d free square%s" % [free, "" if free == 1 else "s"], 11, Color("8fd8d0")))
	var g := PackingGrid.new()
	mech_col.add_child(g)
	g.setup(run.chassis_cells(), b, cell)
	g.set_parts(m.components)
	g.part_hovered.connect(func(_g, part): preview.show_part(part))
	var cargo_col := VBoxContainer.new()
	cargo_col.add_theme_constant_override("separation", 6)
	row.add_child(cargo_col)
	cargo_col.add_child(UIKit.label("CARGO  ·  %d part%s" % [run.cargo.items.size(), "" if run.cargo.items.size() == 1 else "s"], 11, Color("8fd8d0")))
	var cg := PackingGrid.new()
	cargo_col.add_child(cg)
	cg.setup(run.cargo.cells(), Vector2i(run.cargo.rows, run.cargo.cols), minf(cell, 34.0))
	cg.set_parts(run.cargo.items)
	cg.part_hovered.connect(func(_g, part): preview.show_part(part))
	preview.custom_minimum_size = Vector2(420, maxf(g.size.y, 260.0) + 18.0)
	row.add_child(preview)

	_mech_box.add_child(UIKit.label("Parts in Cargo go into the frame at the next refit. Destroyed parts (crossed out) are cleared then.", 12, Color("9fb9b6")))
	_mech_box.reset_size()
	_mech_glass.size = _mech_box.get_combined_minimum_size() + Vector2(48, 40)
	_mech_glass.position = ((screen - _mech_glass.size) / 2.0).floor()

func _tutorial_targets() -> Dictionary:
	# the choices and Continue, not the whole box
	return {"reward": [_pick_area, _continue], "keep_clear": [_content]}

func _on_continue() -> void:
	Tutorial.event("reward_done")
	if SceneRouter.is_busy():
		return
	run.finish_reward()
	RunState.advance()

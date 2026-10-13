extends WorkshopScreen
## Autonomous bay (Logan, 2026-09-27), in its supply depot
## (assets/run/autonomous_bay.png): parts of each type for scraps
## (2026-09-30 rework: economy.shop_offers per type, mixed rarity, no
## rerolls, and two services on the part last hovered in Cargo or on the
## bench: sell it, or refine it one rarity up once a visit),
## +1 row or column of Cargo (once per visit), and frame squares
## (2026-09-28: click a "+" beside the frame, 25 scraps and then 25 more each
## time). Bought parts land on the 6×6 workbench (WorkshopScreen; into Cargo
## if the bench is full): drag them into Cargo to keep them, since whatever
## is left on the bench is scrapped when you leave. While economy.shop_refit
## is on (a trial, Logan 2026-10-02) the frame grid takes parts too: drag
## them between Cargo, the bench and the mech as at a refit (leaving needs a
## working hardpoint, as a refit does). Stock is rolled on arrival and
## saved, so leaving and continuing doesn't reroll it.

const ROW_H := 44.0
const ROW_GAP := 4.0
const FRAME_TOP := 470.0
const FRAME_MAX := Vector2(306, 170)
const FRAME_CELL := 26.0

var _sale: VBoxContainer
var _upgrade_label: Label
var _row_btn: Button
var _col_btn: Button
var _frame_label: Label
var _frame_grid: PackingGrid
var _sell_btn: Button
var _refine_btn: Button
## The part last hovered in Cargo or on the workbench (what Sell / Refine act on).
var _picked: ComponentData = null

func screen_phase() -> String:
	return RunData.PHASE_SHOP

func screen_title() -> String:
	return "Autonomous Bay"

func bay_art() -> String:
	return "res://assets/run/autonomous_bay.png"

func pad_center() -> Vector2:
	return Vector2(310, 346)

func leave_text() -> String:
	return "Leave the bay"

func _build_left() -> void:
	var y := 10.0
	_left.add_child(_title_at("FOR SALE  ·  bought parts land on the workbench", y))
	var slots := Economy.CATEGORIES.size() * maxi(1, Balance.get_int("economy", "shop_offers", 2))
	_sale = VBoxContainer.new()
	_sale.add_theme_constant_override("separation", int(ROW_GAP))
	_sale.position = Vector2(12, y + 20.0)
	_sale.size = Vector2(LEFT.size.x - 24, (ROW_H + ROW_GAP) * slots)
	_left.add_child(_sale)
	y = _sale.position.y + (ROW_H + ROW_GAP) * slots + 12.0
	_left.add_child(_title_at("SERVICES  ·  on the last part hovered in Cargo or bench", y))
	var services := HBoxContainer.new()
	services.add_theme_constant_override("separation", 8)
	services.position = Vector2(12, y + 18.0)
	_left.add_child(services)
	_sell_btn = GlassPanel.button("", 11)
	_sell_btn.custom_minimum_size = Vector2(149, 30)
	_sell_btn.pressed.connect(_sell)
	services.add_child(_sell_btn)
	_refine_btn = GlassPanel.button("", 11)
	_refine_btn.custom_minimum_size = Vector2(149, 30)
	_refine_btn.pressed.connect(_refine)
	services.add_child(_refine_btn)
	y += 56.0
	_upgrade_label = _title_at("", y + 8.0)
	_left.add_child(_upgrade_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.position = Vector2(LEFT.size.x - 12 - 176, y)
	_left.add_child(row)
	_row_btn = GlassPanel.button("+1 row", 11)
	_row_btn.custom_minimum_size = Vector2(85, 28)
	_row_btn.pressed.connect(_buy_upgrade.bind(true))
	row.add_child(_row_btn)
	_col_btn = GlassPanel.button("+1 column", 11)
	_col_btn.custom_minimum_size = Vector2(85, 28)
	_col_btn.pressed.connect(_buy_upgrade.bind(false))
	row.add_child(_col_btn)
	y += 36.0
	_frame_label = _title_at("", y)
	_left.add_child(_frame_label)
	_frame_grid = _add_grid(_left, RunData.MECH)
	_frame_grid.cell_pressed.connect(_buy_cell)

func _title_at(text: String, y: float) -> Label:
	var l := UIKit.label(text, 11, Color("b9d8d4"))
	l.position = Vector2(12, y)
	return l

func _after_build() -> void:
	if int(run.mod("free_parts")) > 0:
		_say("Friendly Merchant: one part here is free. Take your pick.", Palette.OK)
	elif run.shop.get("from_event", false):
		_say("The signal led to an abandoned autonomous bay, still stocked. Buy a part, then drag it into Cargo to keep it.", Palette.OK)
	elif run.can_rearrange(RunData.MECH):
		_say("Buy a part, then drag it into Cargo or onto your frame to keep it.")
	else:
		_say("Buy a part, then drag it into Cargo to keep it.")

func _refresh_extra() -> void:
	_refresh_sale()
	var price := run.cargo_upgrade_price()
	var bought: bool = run.shop.get("upgrade_bought", false)
	_upgrade_label.text = "CARGO  ·  %d scraps" % price if not bought else "CARGO EXPANDED"
	_row_btn.disabled = bought or run.scraps < price
	_col_btn.disabled = bought or run.scraps < price
	_refresh_services()
	_refresh_frame()
	if not _can_leave():
		_say("Install at least one working hardpoint before you leave.", Palette.WARNING)

func _refresh_services() -> void:
	if _picked != null and not run.can_sell(_picked):
		_picked = null
	if _picked != _sell_armed:
		_sell_armed = null
	if _picked == null:
		_sell_btn.text = "Sell  ·  hover a part"
		_sell_btn.disabled = true
		_refine_btn.text = "Refine  ·  hover a part"
		_refine_btn.disabled = true
		return
	_sell_btn.text = "%sSell %s  +%d" % ["Sure? " if _sell_armed == _picked else "", _short(_picked.name), Economy.scrap_value(_picked)]
	_sell_btn.disabled = false
	var price := run.refine_price(_picked)
	if run.shop.get("refined", false):
		_refine_btn.text = "Refined (once a visit)"
	elif price < 0:
		_refine_btn.text = "Refine  ·  already top rarity"
	else:
		_refine_btn.text = "Refine %s  ·  %d" % [_short(_picked.name), price]
	_refine_btn.disabled = not run.can_refine(_picked)

static func _short(n: String) -> String:
	return n if n.length() <= 12 else n.substr(0, 11) + "…"

func _on_part_hovered(g: PackingGrid, part: ComponentData) -> void:
	super(g, part)
	if part != null and _grids.get(g, "") != RunData.MECH and run.can_sell(part) and part != _picked:
		_picked = part
		_refresh_services()

var _sell_armed: ComponentData = null

## Selling a Salvaged or Prototype part takes a second click.
func _sell() -> void:
	if _picked == null:
		return
	var rarity := str(ComponentLibrary.definition(_picked.library_id).get("rarity", ""))
	if rarity in ["salvaged", "prototype"] and _sell_armed != _picked:
		_sell_armed = _picked
		Audio.play("ui")
		_sell_btn.text = "Sure? Sell %s  +%d" % [_short(_picked.name), Economy.scrap_value(_picked)]
		_say("%s is %s. Click Sell again to sell it." % [_picked.name, rarity.capitalize()], Palette.WARNING)
		return
	_sell_armed = null
	var n := _picked.name
	var got := run.sell_part(_picked)
	if got > 0:
		Audio.play("card")
		_say("Sold %s for %d scraps." % [n, got], Palette.OK)
	_picked = null
	_refresh()

func _refine() -> void:
	if _picked == null:
		return
	var n := _picked.name
	var fresh := run.refine_part(_picked)
	if fresh == null:
		_say("Nothing to refine %s into (or no room for its shape)." % n, Palette.WARNING)
	else:
		Audio.play("prime")
		_preview.show_part(fresh)
		_say("%s refined into %s (%s)." % [n, fresh.name, str(ComponentLibrary.definition(fresh.library_id).get("rarity", "")).capitalize()], Palette.OK)
		_picked = fresh
	_refresh()

func _refresh_sale() -> void:
	for c in _sale.get_children():
		c.queue_free()
	var parts: Array = run.shop.get("parts", [])
	for i in range(parts.size()):
		var id: String = parts[i]
		if id == "" or id == RunData.NO_STOCK:
			var l := UIKit.label("Sold" if id == "" else "No %s in stock" % str(Economy.CATEGORIES[i]), 12, Color("7f9d9a"))
			l.custom_minimum_size = Vector2(0, ROW_H)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			l.add_theme_stylebox_override("normal", GlassPanel.control_style(Palette.TEXT_MUTED, 0.0, 0.25))
			_sale.add_child(l)
			continue
		var r := ArmoryBrowser.ArmoryRow.new()
		r.custom_minimum_size = Vector2(0, ROW_H)
		r.setup(id)
		var price := run.part_price(id)
		r.price_text = "%d scraps" % price if price > 0 else "FREE"
		r.price_color = Palette.OK if price == 0 else (Palette.SCRAPS if run.scraps >= price else Palette.DANGER)
		if run.scraps < price: # out of reach: greyed (it still says why on click)
			r.modulate = Color(1, 1, 1, 0.45)
			r.tooltip_text = "%d more scraps needed." % (price - run.scraps)
		r.mouse_entered.connect(func(): if _drag == null: _preview.show_part(r.part))
		r.pressed.connect(_buy.bind(i))
		_sale.add_child(r)

func _refresh_frame() -> void:
	var mech := run.player_mech
	var b := Vector2i.ZERO
	for c in mech.cells:
		b = Vector2i(maxi(b.x, c.x + 1), maxi(b.y, c.y + 1))
	_frame_grid.origin = Vector2i(1, 1) # room for squares above and left
	var bounds := b + Vector2i(2, 2)
	var cell := minf(FRAME_CELL, minf((FRAME_MAX.x + PackingGrid.GAP) / bounds.y, (FRAME_MAX.y + PackingGrid.GAP) / bounds.x) - PackingGrid.GAP)
	_frame_grid.setup(run.chassis_cells(), bounds, floorf(cell))
	_frame_grid.set_parts(_shown(mech.components))
	_frame_grid.position = Vector2(floorf((LEFT.size.x - _frame_grid.size.x) / 2.0), FRAME_TOP)
	var price := run.cell_price()
	_frame_grid.set_offers(run.cell_options(), run.scraps >= price)
	_frame_label.text = ("YOUR FRAME  ·  drag parts on  ·  + buys a square (%d)" if run.can_rearrange(RunData.MECH) \
		else "FRAME SQUARE  ·  %d scraps  ·  click a + beside the frame") % price

func _buy_cell(_grid: PackingGrid, cell: Vector2i) -> void:
	if run.scraps < run.cell_price():
		Audio.play("denied", 0.0)
		_say("Not enough scraps.", Palette.WARNING)
		return
	if run.buy_cell(cell):
		Audio.play("frame_square", 0.02)
		_say("Square added to your frame." + ("" if run.can_rearrange(RunData.MECH) else " Fill it at the next refit."), Palette.OK)
	_refresh()

func _buy(slot: int) -> void:
	var id: String = run.shop["parts"][slot]
	if run.scraps < run.part_price(id):
		Audio.play("denied", 0.0)
		_say("Not enough scraps.", Palette.WARNING)
		return
	var comp := run.buy_part(slot)
	if comp == null:
		_say("No room on the workbench or in Cargo for %s. Make room first." % ComponentLibrary.definition(id).get("name", id), Palette.WARNING)
		return
	Audio.play("shop_buy", 0.03)
	_preview.show_part(comp)
	if run.bench.items.has(comp):
		_say("%s is on the workbench. Drag it into Cargo to keep it." % comp.name, Palette.OK)
	else:
		_say("%s stowed in Cargo (the workbench was full)." % comp.name, Palette.OK)
	_refresh()

func _buy_upgrade(add_row: bool) -> void:
	if run.buy_cargo_upgrade(add_row):
		_say("Cargo expanded.", Palette.OK)
	_refresh()

## Unspent scraps that would still buy something here.
func leave_warnings() -> Array[String]:
	var out := super()
	var affordable := 0
	for id in run.shop.get("parts", []):
		if id != "" and id != RunData.NO_STOCK and run.part_price(id) <= run.scraps:
			affordable += 1
	if affordable > 0:
		out.append("you still have %d scraps, enough for %d of the parts on offer" % [run.scraps, affordable])
	return out

## With the frame open here, the mech can't leave without a working hardpoint.
func _can_leave() -> bool:
	return not run.can_rearrange(RunData.MECH) or run.can_finish_refit()

func _on_leave() -> void:
	if SceneRouter.is_busy():
		return
	if not _can_leave():
		_say("Install at least one working hardpoint before you leave.", Palette.WARNING)
		return
	if not _confirm_leave():
		return
	run.leave_shop()
	RunState.advance()

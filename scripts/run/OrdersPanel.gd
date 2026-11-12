class_name OrdersPanel
extends Control
## The Operator's deployment orders (DeploymentOrders), on a glass comm
## panel over the location map right after Launch (Logan, 2026-09-29): three
## offers, one to take, never labelled boost / tradeoff / gamble. Then any
## step the order needs: pick a category and a part, place frame squares on
## the chassis, or choose a component to strip out or transmute. "Hide"
## drops the panel to a tab so the map can be looked over (the map's stops
## wait until the orders are done); the tab or a click on a stop brings it
## back. Once done, the Operator signs off on a smaller panel, centered;
## its button drops the panel off the bottom of the screen (dismiss) and
## the map's stops pop up, with no reload (Logan, 2026-10-16).
##
## Logan, 2026-11-12: a pick is the salvage screen's crates (SalvageCrate):
## pick one and it rattles open and its parts spin in on reels (SlotReel), or
## SURPRISE ME rolls a light over the crates and then the parts and takes one.
## A gamble shows its roll on the sign-off before its result is printed: a
## coin for Coin Flip, reels for the parts a random order handed out, the
## route's odds ticking in for Unmapped Route (orders "reveal", played once).

signal done()

const W := 760.0
const DONE_W := 460.0 # the sign-off: just the Operator's line, the order and the button
const CARD := Vector2(230, 150)
const GRID_CELL := 32.0
const STAND := Vector2(200, 150) # each crate's spot in a pick's row
const CRATE_SCALE := 1.6

var run: RunData
var _dim: ColorRect
var _box: PanelContainer
var _face: OperatorPortrait
var _line: Label
var _body: VBoxContainer
var _message: Label
var _hide_btn: Button
var _tab: Button
var _talk: Tween
var _notes: Array[String] = []
var _hover_label: Label
var _column: VBoxContainer
var _busy: bool = false # a crate opening, reels or Surprise me's light is playing
var _crates: Dictionary = {} # category -> SalvageCrate in a pick's row
var _cards: Array[PartCardUI] = []

func setup(p_run: RunData) -> void:
	run = p_run
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.45)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)
	_box = PanelContainer.new()
	_box.add_theme_stylebox_override("panel", GlassPanel.panel_style(GlassPanel.HOLO, 16.0))
	_box.draw.connect(func(): GlassPanel.draw_frame(_box, Rect2(Vector2.ZERO, _box.size)))
	_box.resized.connect(_place)
	add_child(_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.custom_minimum_size = Vector2(W, 0)
	_box.add_child(v)
	_column = v
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	v.add_child(head)
	_face = OperatorPortrait.new()
	_face.custom_minimum_size = Vector2(72, 92)
	_face.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(_face)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 8)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	hv.add_child(UIKit.label("OPERATOR  ·  DEPLOYMENT ORDERS", 10, Color("b9d8d4")))
	_line = UIKit.label("", 15, Color("eefcfa"), true)
	hv.add_child(_line)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	v.add_child(_body)
	_message = UIKit.label("", 12, Palette.WARNING, true)
	v.add_child(_message)
	var foot := HBoxContainer.new()
	v.add_child(foot)
	foot.add_child(UIKit.spacer())
	_hide_btn = GlassPanel.button("Hide  ·  look at the map", 12)
	_hide_btn.custom_minimum_size = Vector2(190, 32)
	_hide_btn.pressed.connect(hide_panel)
	foot.add_child(_hide_btn)
	_tab = GlassPanel.button("Deployment orders  ·  show", 13, true, Palette.LINK)
	_tab.custom_minimum_size = Vector2(240, 36)
	_tab.pressed.connect(show_panel)
	_tab.visible = false
	add_child(_tab)
	get_viewport().size_changed.connect(_place)
	_refresh()

func is_open() -> bool:
	return _box.visible

func hide_panel() -> void:
	_box.visible = false
	_dim.visible = false
	_tab.visible = true
	_place()

func show_panel() -> void:
	_box.visible = true
	_dim.visible = true
	_tab.visible = false
	Audio.play("holo", 0.04, -6.0)
	_place()

func _place() -> void:
	if _tab == null: # still being built
		return
	var screen := get_viewport_rect().size
	_box.reset_size()
	_box.position = ((screen - _box.size) / 2.0).floor()
	_box.position.y = maxf(56.0, _box.position.y)
	_tab.position = Vector2(floorf((screen.x - _tab.custom_minimum_size.x) / 2.0), screen.y - 60.0)

func _say(text: String) -> void:
	if _line.text == text:
		return
	_line.text = text
	_line.visible_ratio = 0.0
	if _talk != null:
		_talk.kill()
	_face.talking = true
	_talk = create_tween()
	_talk.tween_property(_line, "visible_ratio", 1.0, clampf(text.length() / 55.0, 0.4, 2.2))
	_talk.tween_callback(func(): _face.talking = false)

func _warn(text: String) -> void:
	_message.text = text

## Rebuilds the body for where the orders are now.
func _refresh() -> void:
	for c in _body.get_children():
		_body.remove_child(c) # now, so the box measures only what's next
		c.queue_free()
	_hover_label = null
	_cards.clear()
	_message.text = ""
	if run.orders.get("chosen", "") == "":
		_build_offers()
	elif not run.orders_pending():
		_build_done()
	else:
		var step := DeploymentOrders.current_step(run)
		match step.get("type", ""):
			DeploymentOrders.STEP_PICK: _build_pick(step)
			DeploymentOrders.STEP_CELLS: _build_cells(step)
			DeploymentOrders.STEP_REMOVE, DeploymentOrders.STEP_TRANSMUTE: _build_choose_part(step)
	_place.call_deferred()

# ---------- the three offers ----------

func _build_offers() -> void:
	_say("Before you drop: command cleared three packages for this op. You get one. Choose.")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_child(row)
	for id in run.orders.get("offer", []):
		row.add_child(_order_card(id))

func _order_card(id: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = CARD
	GlassPanel.style_button(b, false)
	b.mouse_entered.connect(func(): Audio.play("holo", 0.04, -10.0))
	b.pressed.connect(_take.bind(id))
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_top = 10
	v.offset_right = -12
	v.offset_bottom = -10
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	v.add_child(UIKit.label(DeploymentOrders.title(id).to_upper(), 15, Color("dffcf8"), true))
	var rule := ColorRect.new()
	rule.color = Color(GlassPanel.HOLO, 0.35)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(rule)
	v.add_child(UIKit.label(DeploymentOrders.text(id), 12, Color("b9d8d4"), true))
	return b

func _take(id: String) -> void:
	var note := DeploymentOrders.choose(run, id)
	if run.orders.get("chosen", "") != id:
		return
	Audio.play("prime")
	if note != "":
		_notes.append(note)
	SaveGame.save(run)
	_refresh()

# ---------- steps ----------

func _build_pick(step: Dictionary) -> void:
	var rarity := str(step.get("rarity", "salvaged")).capitalize()
	var left := (run.orders.get("steps", []) as Array).filter(func(s): return s.get("type", "") == DeploymentOrders.STEP_PICK).size()
	var blind: bool = step.get("blind", false)
	if step["category"] == "":
		if blind:
			_say("Three crates, all sealed. Pick one and see what you get.")
		else:
			_say("%s stock's on the pallet. Pick a crate.%s" % [rarity, "" if left <= 1 else " (%d picks)" % left])
		_crates.clear()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		_body.add_child(row)
		for cat in Economy.CATEGORIES:
			var column := VBoxContainer.new()
			column.custom_minimum_size.x = 220.0
			column.add_theme_constant_override("separation", 2)
			row.add_child(column)
			var stand := Control.new()
			stand.custom_minimum_size = STAND
			stand.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			stand.mouse_filter = Control.MOUSE_FILTER_IGNORE
			column.add_child(stand)
			var crate := SalvageCrate.new()
			crate.setup(cat, CRATE_SCALE)
			crate.beam_elsewhere = true # no beam over the panel
			crate.pressed.connect(_pick_crate.bind(cat))
			stand.add_child(crate)
			crate.position = (Vector2(STAND.x / 2.0, STAND.y - 6.0) - crate.foot()).floor()
			_crates[cat] = crate
			var title := UIKit.label(cat.to_upper(), 16, Palette.category_color(cat))
			title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			column.add_child(title)
		var under := CenterContainer.new()
		_body.add_child(under)
		var surprise := GlassPanel.button("SURPRISE ME", 14, false, Palette.LINK)
		surprise.custom_minimum_size = Vector2(200, 38)
		surprise.tooltip_text = "A random crate, and a random part from it."
		surprise.pressed.connect(_surprise_pick)
		under.add_child(surprise)
		return
	var surprise: String = step.get("surprise", "")
	_say("Take one. It goes in your Cargo." if surprise == "" else "Here's what came out of the crate.")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_child(row)
	for id in step.get("options", []):
		var card := PartCardUI.new()
		card.selectable = surprise in ["", id] and not _busy
		row.add_child(card)
		card.setup(id)
		if surprise not in ["", id]: # a surprise pick: only its part stays (in its place)
			card.modulate.a = 0.0
			card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.pressed.connect(func(_c): _take_part(id))
		_cards.append(card)

func _take_part(id: String) -> void:
	if _busy:
		return
	var note := DeploymentOrders.pick_part(run, id)
	if note != "":
		Audio.play("prime")
		_notes.append(note)
		SaveGame.save(run)
		_refresh()

func _lock(on: bool) -> void:
	_busy = on
	_hide_btn.disabled = on

## A crate picked: it rattles open where it stands, then its parts spin in.
func _pick_crate(cat: String) -> void:
	if _busy or DeploymentOrders.current_step(run).get("category", "x") != "":
		return
	DeploymentOrders.pick_category(run, cat)
	SaveGame.save(run)
	CrashLog.crumb("order pick crate: " + cat)
	Audio.play("ui")
	_lock(true)
	await _open_crate(cat)
	await _spin_reels()
	_lock(false)
	var step := DeploymentOrders.current_step(run)
	if step.get("blind", false) and (step.get("options", []) as Array).size() == 1: # Mystery Crate: the part is yours as it lands
		_lock(true)
		await get_tree().create_timer(0.3 if GameSettings.reduce_motion else 1.2).timeout # a look at it first
		_lock(false)
		_take_part(step["options"][0])
		return
	_refresh()

## Surprise me: the light runs over the crates and stops on one, it opens, its
## parts spin in, the light runs over them and stops on one, and it's taken.
func _surprise_pick() -> void:
	if _busy:
		return
	var id := DeploymentOrders.surprise_pick(run)
	if id == "":
		return
	SaveGame.save(run)
	var cat: String = DeploymentOrders.current_step(run)["category"]
	CrashLog.crumb("order pick surprise: %s, %s" % [cat, id])
	Audio.play("ui")
	_lock(true)
	var lit: Array = []
	for c in Economy.CATEGORIES:
		if _crates.has(c):
			lit.append(_crates[c])
	await SlotReel.roll_light(self, lit, lit.find(_crates[cat]), func(n, on): n.spotlight = on)
	await get_tree().create_timer(0.1 if GameSettings.reduce_motion else 0.3).timeout
	(_crates[cat] as SalvageCrate).spotlight = false
	await _open_crate(cat)
	await _spin_reels()
	_refresh() # the cards, not pickable yet (busy)
	for c in _cards:
		c.modulate.a = 1.0
	var target: PartCardUI = null
	for c in _cards:
		if c.component_id == id:
			target = c
	await SlotReel.roll_light(self, _cards, _cards.find(target), func(n, on): n.spotlight = on)
	var fade := create_tween().set_parallel(true)
	for c in _cards:
		if c != target:
			fade.tween_property(c, "modulate:a", 0.0, 0.15 if GameSettings.reduce_motion else 0.4)
	await fade.finished
	await get_tree().create_timer(0.1 if GameSettings.reduce_motion else 0.5).timeout
	_lock(false)
	_take_part(id)

## The other crates fade; the picked one rattles and its lid blows off.
func _open_crate(cat: String) -> void:
	var quick := GameSettings.reduce_motion
	var crate: SalvageCrate = _crates[cat]
	for c in _crates.values():
		(c as SalvageCrate).interactive = false
	var fade := create_tween().set_parallel(true)
	for c in _crates:
		if c != cat:
			fade.tween_property((_crates[c] as Control).get_parent().get_parent(), "modulate:a", 0.15, 0.25)
	for n in _body.get_children():
		if n is CenterContainer: # Surprise me
			fade.tween_property(n, "modulate:a", 0.0, 0.25)
	if not quick:
		var rattle := create_tween()
		rattle.tween_callback(Audio.play.bind("crate_rattle", 0.1, -4.0))
		rattle.tween_property(crate, "shake", 1.2, 0.25)
		rattle.tween_callback(Audio.play.bind("crate_rattle", 0.1, -1.0))
		rattle.tween_property(crate, "shake", 2.6, 0.25)
		rattle.tween_callback(Audio.play.bind("crate_rattle", 0.1, 1.0))
		await rattle.finished
	crate.shake = 0.0
	crate.open()
	Audio.play("crate_open", 0.02)
	await get_tree().create_timer(0.15 if quick else 0.55).timeout

## The crate's parts spin in on reels, landing one after another.
func _spin_reels() -> void:
	var step := DeploymentOrders.current_step(run)
	await _reels(step.get("options", []), str(step.get("category", "")))

## Reels for `ids` in the body (each in its own part's category unless `cat`
## is given), spinning and landing one after another.
func _reels(ids: Array, cat: String = "") -> void:
	var quick := GameSettings.reduce_motion
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_child(row)
	var last: SlotReel = null
	var i := 0
	for id in ids:
		var reel := SlotReel.new()
		row.add_child(reel)
		reel.setup(id, cat if cat != "" else str(ComponentLibrary.definition(id).get("category", "hardpoint")))
		reel.spin((0.35 + 0.2 * i) if quick else (1.0 + 0.55 * i))
		last = reel
		i += 1
	_place.call_deferred()
	if last != null:
		await last.landed
		await get_tree().create_timer(0.3).timeout

## A PackingGrid of the chassis and its parts (room around it for new squares).
func _chassis_grid(with_offers: bool) -> PackingGrid:
	var g := PackingGrid.new()
	var mech := run.player_mech
	var b := Vector2i.ZERO
	for c in mech.cells:
		b = Vector2i(maxi(b.x, c.x + 1), maxi(b.y, c.y + 1))
	if with_offers:
		g.origin = Vector2i(1, 1)
		b += Vector2i(2, 2)
	g.setup(run.chassis_cells(), b, GRID_CELL)
	g.set_parts(mech.components)
	if with_offers:
		g.set_offers(run.cell_options(), true)
	var holder := CenterContainer.new()
	holder.add_child(g)
	_body.add_child(holder)
	return g

func _build_cells(step: Dictionary) -> void:
	var left := int(step["left"])
	_say("The frame's modular. Click a + to add a square, %d to place. Fill them at a refit." % left if left > 1 \
		else "Click a + to add a square to your frame. Fill it at a refit.")
	var g := _chassis_grid(true)
	g.cell_pressed.connect(func(_g, cell):
		if DeploymentOrders.add_cell(run, cell):
			Audio.play("frame_square", 0.02)
			SaveGame.save(run)
			_refresh())

func _build_choose_part(step: Dictionary) -> void:
	var strip: bool = step["type"] == DeploymentOrders.STEP_REMOVE
	_say("Click the component to strip out. It's gone for the mission." if strip \
		else "Click the component to transmute. What comes back is random.")
	var g := _chassis_grid(false)
	_hover_label = UIKit.label("Hover a component.", 12, Color("9fb9b6"))
	_hover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(_hover_label)
	g.part_hovered.connect(func(_g, part):
		if _hover_label != null:
			_hover_label.text = "Hover a component." if part == null else "%s  ·  %s  ·  %s  ·  %d HP" % [part.name, part.category.capitalize(), part.rarity.capitalize(), part.max_hp])
	g.part_pressed.connect(func(_g, part, _cell):
		if not DeploymentOrders.can_choose_part(run, part):
			_warn("That's your last working hardpoint. Pick something else.")
			return
		var note := DeploymentOrders.choose_part(run, part)
		Audio.play("prime")
		_notes.append(note)
		SaveGame.save(run)
		_refresh())

# ---------- signing off ----------

func _build_done() -> void:
	_column.custom_minimum_size.x = DONE_W
	var chosen: String = run.orders["chosen"]
	_say("%s, confirmed. Good hunting, pilot." % DeploymentOrders.title(chosen))
	var summary := UIKit.label(DeploymentOrders.text(chosen), 13, Color("b9d8d4"), true)
	_body.add_child(summary)
	var reveal: Dictionary = run.orders.get("reveal", {})
	var stage := VBoxContainer.new() # the roll plays here
	stage.add_theme_constant_override("separation", 8)
	_body.add_child(stage)
	var after: Array[Control] = [] # shown once it has played
	for n in _notes:
		var l := UIKit.label(n, 12, Palette.OK, true)
		_body.add_child(l)
		after.append(l)
	var row := HBoxContainer.new()
	row.add_child(UIKit.spacer())
	var go := GlassPanel.button("To the refit" if run.phase == RunData.PHASE_REFIT else "To the map", 14, true, Palette.HARDPOINT)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.custom_minimum_size = Vector2(180, 40)
	go.pressed.connect(func(): done.emit())
	row.add_child(go)
	row.add_child(UIKit.spacer())
	_body.add_child(row)
	_hide_btn.visible = false
	after.append(row)
	if not reveal.is_empty():
		if reveal.get("type", "") == "parts":
			var n := (reveal.get("ids", []) as Array).size()
			_column.custom_minimum_size.x = maxf(DONE_W, n * PartCardUI.SIZE.x + (n - 1) * 20.0)
		for c in after:
			c.modulate.a = 0.0
		_play_reveal(reveal, stage, after)

## Plays a gamble's roll on the sign-off, then shows what it did and the
## button. Once played it's dropped from the run (a reload goes straight on).
func _play_reveal(reveal: Dictionary, stage: VBoxContainer, after: Array[Control]) -> void:
	var quick := GameSettings.reduce_motion
	_busy = true
	match reveal.get("type", ""):
		"coin":
			var holder := CenterContainer.new()
			stage.add_child(holder)
			var coin := Coin.new()
			holder.add_child(coin)
			await get_tree().create_timer(0.3).timeout
			await coin.flip(bool(reveal.get("heads", true)), quick)
			Audio.play("reel_land", 0.03)
			var heads := bool(reveal.get("heads", true))
			var face := UIKit.label("HEADS" if heads else "TAILS", 20, Palette.SCRAPS if heads else Palette.WARNING)
			face.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			stage.add_child(face)
		"parts":
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 20)
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			stage.add_child(row)
			var last: SlotReel = null
			var i := 0
			var any: Array = _usable_parts() if reveal.get("any_part", false) else []
			for id in reveal.get("ids", []):
				var reel := SlotReel.new()
				row.add_child(reel)
				reel.setup(id, str(ComponentLibrary.definition(id).get("category", "hardpoint")), any)
				last = reel
			_place.call_deferred()
			await get_tree().create_timer(0.3).timeout
			for reel in row.get_children():
				(reel as SlotReel).spin((0.35 + 0.2 * i) if quick else (1.0 + 0.55 * i))
				i += 1
			if last != null:
				await last.landed
		"odds":
			await _odds_roll(stage, reveal.get("mults", {}), quick)
	await get_tree().create_timer(0.25).timeout
	run.orders.erase("reveal")
	SaveGame.save(run)
	_busy = false
	var show := create_tween().set_parallel(true)
	for c in after:
		show.tween_property(c, "modulate:a", 1.0, 0.3)

## Every part the mech could get: any category or rarity that fits its weight class.
func _usable_parts() -> Array:
	var out: Array = []
	for cat in Economy.CATEGORIES:
		for rar in Economy.RARITIES:
			out.append_array(ComponentLibrary.pool(cat, rar, run.player_mech.weight_class))
	out.shuffle()
	return out

## Unmapped Route: each stop type's number flickers, then settles on what it rolled, one after another.
func _odds_roll(stage: VBoxContainer, mults: Dictionary, quick: bool) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 4)
	var holder := CenterContainer.new()
	holder.add_child(grid)
	stage.add_child(holder)
	var values: Array[Label] = []
	var keys: Array = []
	for key in DeploymentOrders.ROUTE_ODDS:
		if not mults.has(key):
			continue
		grid.add_child(UIKit.label(DeploymentOrders.ROUTE_NAMES[key], 14, Color("dffcf8")))
		var v := UIKit.label("×?.??", 14, Palette.LINK)
		v.custom_minimum_size.x = 190.0
		grid.add_child(v)
		values.append(v)
		keys.append(key)
	_place.call_deferred()
	var settled := 0
	var t := 0.0
	var step := 0.05
	while settled < values.size():
		await get_tree().create_timer(step).timeout
		t += step
		for i in range(settled, values.size()):
			values[i].text = "×%.2f" % randf_range(0.5, 2.0)
		if t >= (0.25 if quick else 0.7) + settled * (0.15 if quick else 0.45):
			var m := float(mults[keys[settled]])
			values[settled].text = "×%.2f  %s" % [m, "more often" if m > 1.05 else ("less often" if m < 0.95 else "as usual")]
			values[settled].add_theme_color_override("font_color", Palette.LINK if m >= 1.0 else Palette.WARNING)
			Audio.play("reel_land", 0.03, -3.0)
			settled += 1
		elif int(t / step) % 2 == 0:
			Audio.play("reel_tick", 0.08, -8.0)

## Coin Flip's coin: tossed up, spinning (squashed sideways), landing on its face.
class Coin extends Control:
	var angle: float = 0.0
	var lift: float = 0.0
	var _half: int = 0

	func _init() -> void:
		custom_minimum_size = Vector2(160, 190)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func flip(heads: bool, quick: bool) -> void:
		var turns := 3 if quick else 8
		var dur := 0.6 if quick else 1.9
		var end := PI * (2.0 * turns + (0.0 if heads else 1.0))
		var spin := create_tween()
		spin.tween_property(self, "angle", end, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var toss := create_tween()
		toss.tween_property(self, "lift", 1.0, dur * 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		toss.tween_property(self, "lift", 0.0, dur * 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		await spin.finished

	func _process(_delta: float) -> void:
		var half := int(floor(angle / PI))
		if half != _half:
			_half = half
			Audio.play("reel_tick", 0.1, -6.0)
		queue_redraw()

	func _draw() -> void:
		var r := 48.0
		var ground := size.y - 18.0
		draw_set_transform(Vector2(size.x / 2.0, ground), 0.0, Vector2(1.0, 0.25))
		draw_circle(Vector2.ZERO, r * (1.0 - 0.45 * lift), Color(0, 0, 0, 0.4))
		var front := cos(angle) >= 0.0
		var col: Color = Palette.SCRAPS if front else Color("9fb4b8")
		var at := Vector2(size.x / 2.0, ground - r - 6.0 - lift * 70.0)
		draw_set_transform(at, 0.0, Vector2(maxf(absf(cos(angle)), 0.06), 1.0))
		draw_circle(Vector2.ZERO, r, col.darkened(0.5))
		draw_circle(Vector2.ZERO, r - 5.0, col)
		draw_arc(Vector2.ZERO, r - 10.0, 0.0, TAU, 48, col.lightened(0.35), 2.0)
		var font := get_theme_default_font()
		var letter := "H" if front else "T"
		var w := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 42).x
		draw_string(font, Vector2(-w / 2.0, 15.0), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 42, col.darkened(0.6))
		draw_set_transform_matrix(Transform2D.IDENTITY)

## Drops the panel off the bottom of the screen and lifts the dim, then
## frees itself.
func dismiss() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_box, "position:y", get_viewport_rect().size.y + 20.0, 0.35).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_dim, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(queue_free)

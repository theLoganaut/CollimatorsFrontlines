extends CanvasLayer
## Autoload. The training run's coach (Logan, 2026-09-28: the tutorial goes
## over getting to a fight, fighting, and placing and arranging parts).
##
## A short run on the "training" mission: two single-enemy fights, with a
## salvage and a refit between them. The coach dims the screen, rings the
## thing it's talking about and explains it; some steps wait for "Next",
## others for the pilot to do the thing (click the War Table, play a card,
## end the turn...). Screens tell the coach where they are with
## reached(point, targets) and what just happened with event(name).
## Skippable at any time; replayable from the Info Bay.

const TRAINING_MISSION := "training"

## [point, target name(s) ("" = none; "a+b" rings both), text, wait ("next" or an event)].
## The first sentence is the step's topic (lit in the box), so it says what the step is about.
const STEPS := [
	["war_room", "table", "Every mission starts at the War Table. Welcome aboard, pilot: click the table.", "table_opened"],
	["sector_map", "map", "This is a simulated mission at the Shipyard. Real missions offer three locations to choose from; for training there's just this one. Click it.", "location_opened"],
	["popup", "launch", "Launch to drop in. Your HP and any parts you lose carry through the whole mission.", "launched"],
	["location_map", "starts", "This is your route through the location. One stop per row, bottom to top: fights, repair bays, shops and events. Click the lit stop.", "node_chosen"],
	["combat", "player", "This is your mech, built from parts. Each colored block is one part with its own HP, and enemy attacks hit parts, not the whole mech.", "next"],
	["combat", "player+hand", "Your cards come from your parts. Hardpoints (orange) are weapons: they give attack cards. Protocols (purple) are weapon augments: prime one and it powers up your next attack. Reactors (teal) are passives: always on, no cards.", "next"],
	["combat", "hand", "This is your hand: every card your parts give you. Hover a card to see the part it comes from. Each card plays once a turn and comes back next turn.", "next"],
	["combat", "heat", "Cards cost Heat. Go over your max and you overheat: it damages your parts and ends your turn.", "next"],
	["combat", "intents", "These icons are what the enemy plans to do next. Hover one to see the card and which of your parts it's aiming at.", "next"],
	["combat", "hand+enemy", "You win by destroying all of an enemy's hardpoints: with no weapons left, it explodes or retreats. Drag an attack card from your hand onto one of its parts.", "card_played"],
	["combat", "enemy", "A part at 0 HP is destroyed. Its cards and passive are gone, and it stays wrecked for the rest of the mission. The same goes for yours: lose all your hardpoints and you're out.", "next"],
	["combat", "end_turn", "Press End Turn when you're done. The enemy acts, then your heat vents for your next turn.", "turn_ended"],
	["combat", "", "That's the whole loop. Finish it off.", "next"],
	["reward", "reward", "Salvage comes after every win. Your scraps are already banked. Pick a category, then one part for your Cargo (or skip it for a few scraps), then Continue.", "reward_done"],
	["refit", "mech", "A refit lets you rebuild your mech. Click a part to pick it up, then click where it goes. R or right-click rotates it. Lit squares show where it fits.", "next"],
	["refit", "cargo", "Yellow arrows are links. A part with arrows affects whatever part they point at. Parts in Cargo wait here until you fit them.", "next"],
	["refit", "leave", "Finish the refit when you're happy with the build.", "refit_done"],
	["combat", "", "One more fight with your new setup.", "next"],
	["debrief", "", "Training complete. Pick a location on the War Table for a real mission. The Hangar lets you change mechs and loadouts.", "next"],
]

signal finished()
## The War Room got (or changed) its name.
signal base_named()

var active: bool = false
var step: int = 0
var _point: String = ""
var _targets: Dictionary = {}
var _offer: bool = false
## Asking for the War Room's name (the box shows a text field instead of Next).
var _naming: bool = false
## Showing a one-time hint (hint_once): its button just closes it.
var _hinting: bool = false
var _name_row: HBoxContainer
var _name_edit: LineEdit
var _name_btn: Button

var _root: Control
var _dim: Control
var _box: PanelContainer
var _face: OperatorPortrait
var _head: Label
var _text: RichTextLabel
var _talk: Tween
var _next_btn: Button
var _skip_btn: Button
var _skip_corner: Button
const SKIP_SIZE := Vector2(124, 30)
## Under the settings button in every screen's top right corner.
const SKIP_TOP := 62.0
## On a step that waits for the pilot to do something, the box fades back
## after it's spoken, so it doesn't hide what's under it (full again under
## the mouse).
const FADE_DELAY := 1.0
const FADED_ALPHA := 0.4
var _placed: bool = false
var _fades: bool = false
var _spoken_at: float = -1.0
var _start_btn: Button
var _t: float = 0.0

func _ready() -> void:
	layer = 150
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)
	_dim = Control.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.draw.connect(_draw_dim)
	_root.add_child(_dim)
	_box = PanelContainer.new()
	_box.add_theme_stylebox_override("panel", GlassPanel.panel_style(GlassPanel.HOLO, 12.0))
	_box.draw.connect(func(): GlassPanel.draw_frame(_box, Rect2(Vector2.ZERO, _box.size)))
	_root.add_child(_box)
	get_viewport().size_changed.connect(func(): _place_skip())
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	_box.add_child(h)
	_face = OperatorPortrait.new()
	_face.custom_minimum_size = Vector2(72, 92)
	_face.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(_face)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	h.add_child(v)
	_head = UIKit.label("OPERATOR  ·  TRAINING", 10, Color("b9d8d4"))
	v.add_child(_head)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_theme_font_size_override("normal_font_size", 15)
	_text.add_theme_color_override("default_color", Color("eefcfa"))
	_text.custom_minimum_size = Vector2(380, 0)
	v.add_child(_text)
	_name_row = HBoxContainer.new()
	_name_row.add_theme_constant_override("separation", 8)
	_name_row.visible = false
	v.add_child(_name_row)
	_name_edit = LineEdit.new()
	_name_edit.max_length = Profile.BASE_NAME_MAX
	_name_edit.placeholder_text = "Name the base"
	_name_edit.custom_minimum_size = Vector2(240, 34)
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.add_theme_font_size_override("font_size", 15)
	_name_edit.text_changed.connect(func(t: String): _name_btn.disabled = t.strip_edges() == "")
	_name_edit.text_submitted.connect(func(_t: String): _confirm_name())
	_name_row.add_child(_name_edit)
	_name_btn = GlassPanel.button("Name it", 13, true, Palette.LINK)
	_name_btn.custom_minimum_size = Vector2(100, 34)
	_name_btn.pressed.connect(_confirm_name)
	_name_row.add_child(_name_btn)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	_skip_btn = GlassPanel.button("Not now", 12)
	_skip_btn.custom_minimum_size = Vector2(120, 32)
	_skip_btn.pressed.connect(skip)
	row.add_child(_skip_btn)
	# During training, Skip sits on its own at the top right, under the
	# settings button (Logan, 2026-10-14), not in the coach's box.
	_skip_corner = GlassPanel.button("Skip training", 12)
	_skip_corner.custom_minimum_size = SKIP_SIZE
	_skip_corner.size = SKIP_SIZE
	_skip_corner.pressed.connect(skip)
	_skip_corner.visible = false
	add_child(_skip_corner) # not in _root: it stays up between the coach's steps
	row.add_child(UIKit.spacer())
	_start_btn = GlassPanel.button("Start training", 13, true, Palette.LINK)
	_start_btn.custom_minimum_size = Vector2(140, 32)
	_start_btn.pressed.connect(_accept_offer)
	row.add_child(_start_btn)
	_next_btn = GlassPanel.button("Next", 13, true, Palette.LINK)
	_next_btn.custom_minimum_size = Vector2(100, 32)
	_next_btn.pressed.connect(_on_next)
	row.add_child(_next_btn)

# ---------- control ----------

## A one-time note from the Operator the first time a pilot meets
## something training doesn't cover (the first shop; later, statuses and
## keywords). Shown once per profile, never during training.
func hint_once(key: String, text: String) -> void:
	if active or _naming or _hinting or not GameSettings.operator_tips or Profile.seen_hints.has(key):
		return
	Profile.seen_hints.append(key)
	Profile.save()
	_hinting = true
	_targets = {}
	_head.text = "OPERATOR  ·  SECURE CHANNEL"
	_show(text, "", true)

func _on_next() -> void:
	if _hinting:
		_hinting = false
		_root.visible = false
		_head.text = "OPERATOR  ·  TRAINING"
		return
	event("next")

## The Operator asks what to call the War Room (the first time the game
## opens, or again when its name in the top bar is clicked). Training is
## offered once it has a name.
func ask_base_name() -> void:
	_naming = true
	_targets = {}
	_name_edit.text = Profile.base_name
	_name_btn.disabled = Profile.base_name.strip_edges() == ""
	_head.text = "OPERATOR  ·  SECURE CHANNEL"
	_show("First things first, pilot: this place needs a name. What are we calling it?" if Profile.base_name == "" \
		else "Renaming the place? Fine by me. Logistics will grumble.", "", false)
	_name_edit.grab_focus.call_deferred()

func _confirm_name() -> void:
	var n := _name_edit.text.strip_edges()
	if n == "":
		return
	_naming = false
	Profile.base_name = n
	Profile.save()
	Audio.play("ui")
	_root.visible = false
	_head.text = "OPERATOR  ·  TRAINING"
	base_named.emit()
	if not Profile.tutorial_done and not active:
		offer()

## The War Room asks a pilot who hasn't trained yet.
func offer() -> void:
	if active or Profile.tutorial_done:
		return
	_offer = true
	_targets = {}
	_show("New pilot? Take the training mission: two short fights that walk you through the War Table, combat, and fitting parts. About five minutes.", "", false)

func _accept_offer() -> void:
	_offer = false
	start()
	reached("war_room", _targets)

func start() -> void:
	active = true
	step = 0
	_place_skip()
	_skip_corner.visible = true

func skip() -> void:
	_offer = false
	active = false
	Profile.tutorial_done = true
	Profile.save()
	_root.visible = false
	_skip_corner.visible = false
	finished.emit()

func is_training_run(run: RunData) -> bool:
	return run != null and run.mission.get("id", "") == TRAINING_MISSION

## A screen is showing `point`; `targets` names the controls it can ring.
## If training has moved past steps on the way (say, a fight won early),
## it catches up to the first step for this point.
func reached(point: String, targets: Dictionary) -> void:
	_point = point
	_targets = targets
	if not active:
		if not _offer and not _naming and not _hinting:
			_root.visible = false
		return
	if STEPS[step][0] != point:
		for i in range(step + 1, STEPS.size()):
			if STEPS[i][0] == point:
				step = i
				break
	_refresh()

## Something happened; a step waiting on it moves on.
func event(name: String) -> void:
	if not active or step >= STEPS.size():
		return
	if STEPS[step][3] != name:
		return
	step += 1
	if step >= STEPS.size():
		active = false
		Profile.tutorial_done = true
		Profile.save()
		_root.visible = false
		_skip_corner.visible = false
		finished.emit()
		return
	_refresh()

func _refresh() -> void:
	var s: Array = STEPS[step]
	if s[0] != _point:
		_root.visible = false
		return
	_show(s[2], s[1], s[3] == "next")

func _show(text: String, target: String, wait_next: bool) -> void:
	_root.visible = true
	_text.text = _topic(text) if active and not _hinting else _escape(text)
	_text.visible_ratio = 0.0
	_name_row.visible = _naming
	_start_btn.visible = _offer and not _naming
	_next_btn.visible = not _offer and not _naming and wait_next
	_next_btn.text = "Got it" if _hinting or step >= STEPS.size() - 1 or text.ends_with("off.") else "Next"
	_skip_btn.visible = _offer and not _naming
	_place_skip()
	# The offer and the name hold the screen. Training steps never do: the
	# pilot can hover the mech, cards and icons while the coach talks
	# (Logan, 2026-10-14); "Next" steps just dim more.
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP if (_offer or _naming) else Control.MOUSE_FILTER_IGNORE
	_hold = wait_next or _offer or _naming
	_fades = active and not wait_next and not _offer and not _naming and not _hinting
	_current_target = target
	_t = 0.0
	_place_box()

## Whether this step waits on "Next" (a darker dim) rather than an action.
var _hold: bool = false

## The step's first sentence (its topic) lit, the rest as is.
static func _topic(text: String) -> String:
	var m := RegEx.create_from_string("^(.+?[.!?])(\\s|$)").search(text)
	if m == null:
		return _escape(text)
	var head := m.get_string(1)
	return "[color=#%s]%s[/color]%s" % [Palette.LINK.to_html(false), _escape(head), _escape(text.substr(head.length()))]

static func _escape(s: String) -> String:
	return s.replace("[", "[lb]")

func _place_skip() -> void:
	var screen: Vector2 = _root.get_viewport_rect().size
	_skip_corner.position = Vector2(screen.x - SKIP_SIZE.x - 16.0, SKIP_TOP)

var _current_target: String = ""

## A target entry (a Control, a screen Rect2, or an Array of them) as screen rects.
static func _rects_of(t) -> Array[Rect2]:
	var list: Array = t if typeof(t) == TYPE_ARRAY else ([t] if t != null else [])
	var out: Array[Rect2] = []
	for c in list:
		if typeof(c) == TYPE_RECT2:
			out.append(c)
		elif c is Control and is_instance_valid(c) and c.is_visible_in_tree():
			out.append((c as Control).get_global_rect())
	return out

## The ringed rects, in screen space (empty if there's nothing to ring).
func _target_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	if _current_target == "":
		return out
	for name in _current_target.split("+"):
		for r in _rects_of(_targets.get(name, null)):
			out.append(r.grow(8.0))
	return out

## All ringed rects merged into one (empty Rect2 if none).
func _target_rect() -> Rect2:
	var rs := _target_rects()
	if rs.is_empty():
		return Rect2()
	var out := rs[0]
	for r in rs:
		out = out.merge(r)
	return out

## Box widths tried, widest last: a wider box is shorter, which sometimes is
## what lets it fit under a pop-up.
const BOX_WIDTHS := [380.0, 520.0, 300.0]

## Puts the box where it covers the least of what matters (Logan,
## 2026-09-28: the coach sat on the sector map and the refit's grids). Hard
## to cover: the ringed things and anything a screen lists under
## "keep_clear". Softer: the screen's other named parts. Among spots that
## tie, the one nearest the ringed thing wins.
var _place_gen: int = 0

func _place_box() -> void:
	_place_gen += 1
	var gen := _place_gen
	_placed = false
	_spoken_at = -1.0
	_box.modulate.a = 0.0
	var screen: Vector2 = _root.get_viewport_rect().size
	var ring := _target_rects()
	var merged := _target_rect()
	var hard: Array[Rect2] = []
	for r in ring:
		# A ring that fills most of the screen (a whole map) can't be avoided.
		if r.get_area() < screen.x * screen.y * 0.5:
			hard.append(r)
	hard.append_array(_rects_of(_targets.get("keep_clear", null)))
	if _skip_corner.visible:
		hard.append(_skip_corner.get_global_rect().grow(6.0))
	var soft: Array[Rect2] = []
	for key in _targets:
		if not (key in _current_target.split("+")) and key != "keep_clear":
			for o in _rects_of(_targets[key]):
				if merged.size == Vector2.ZERO or not o.encloses(merged):
					soft.append(o)
	var anchor := merged.get_center() if merged.size != Vector2.ZERO else Vector2(screen.x / 2.0, screen.y * 0.45)
	var best_cost := INF
	var best_pos := Vector2.ZERO
	var best_w: float = BOX_WIDTHS[0]
	for w in BOX_WIDTHS:
		_text.custom_minimum_size.x = w
		_box.reset_size()
		await get_tree().process_frame
		if gen != _place_gen:
			return # a newer step took over
		var bs := _box.size
		for pos in _candidates(screen, bs, merged):
			var box := Rect2(pos, bs)
			var cost := 0.0
			for h in hard:
				cost += box.intersection(h).get_area() * 100.0
			for o in soft:
				cost += box.intersection(o).get_area() * 5.0
			cost += box.get_center().distance_to(anchor)
			if w != BOX_WIDTHS[0]:
				cost += 60.0 # the standard width, unless another one clears more
			if cost < best_cost:
				best_cost = cost
				best_pos = pos
				best_w = w
	_text.custom_minimum_size.x = best_w
	_box.reset_size()
	await get_tree().process_frame
	if gen != _place_gen:
		return
	_box.position = best_pos
	_box.modulate.a = 1.0
	_placed = true
	_speak()

## The line comes in over the channel a few letters at a time.
func _speak() -> void:
	if _talk != null:
		_talk.kill()
	_face.talking = true
	_talk = create_tween()
	_talk.tween_property(_text, "visible_ratio", 1.0, clampf(_text.text.length() / 60.0, 0.4, 2.2))
	_talk.tween_callback(func():
		_face.talking = false
		_spoken_at = _t)

## Spots to try: beside the ringed thing on each side, then a scan of the screen.
func _candidates(screen: Vector2, bs: Vector2, r: Rect2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if r.size != Vector2.ZERO:
		out.append(Vector2(r.get_center().x - bs.x / 2.0, r.end.y + 14.0))
		out.append(Vector2(r.get_center().x - bs.x / 2.0, r.position.y - bs.y - 14.0))
		out.append(Vector2(r.end.x + 16.0, r.get_center().y - bs.y / 2.0))
		out.append(Vector2(r.position.x - bs.x - 16.0, r.get_center().y - bs.y / 2.0))
	var step := 24.0
	var y := 12.0
	while y + bs.y <= screen.y - 12.0:
		var x := 12.0
		while x + bs.x <= screen.x - 12.0:
			out.append(Vector2(x, y))
			x += step
		y += step
	var kept: Array[Vector2] = []
	for c in out:
		var q := Vector2(clampf(c.x, 12.0, screen.x - bs.x - 12.0), clampf(c.y, 12.0, screen.y - bs.y - 12.0))
		kept.append(q)
	return kept

func _process(delta: float) -> void:
	if _root.visible:
		_t += delta
		_dim.queue_redraw()
		if _placed:
			var faded := _fades and _spoken_at >= 0.0 and _t - _spoken_at >= FADE_DELAY \
				and not _box.get_global_rect().has_point(_box.get_global_mouse_position())
			_box.modulate.a = move_toward(_box.modulate.a, FADED_ALPHA if faded else 1.0, delta * 3.0)

func _draw_dim() -> void:
	var screen: Vector2 = _root.get_viewport_rect().size
	var shade := Color(0, 0, 0, 0.45 if _hold else 0.22)
	var holes := _target_rects()
	if holes.is_empty():
		_dim.draw_rect(Rect2(Vector2.ZERO, screen), Color(0, 0, 0, 0.35), true)
		return
	# Shade the screen minus the ringed rects: split it along every hole
	# edge and fill the pieces no hole covers.
	var xs := [0.0, screen.x]
	var ys := [0.0, screen.y]
	for h in holes:
		xs.append_array([clampf(h.position.x, 0.0, screen.x), clampf(h.end.x, 0.0, screen.x)])
		ys.append_array([clampf(h.position.y, 0.0, screen.y), clampf(h.end.y, 0.0, screen.y)])
	xs.sort()
	ys.sort()
	for i in range(xs.size() - 1):
		for j in range(ys.size() - 1):
			var cell := Rect2(xs[i], ys[j], xs[i + 1] - xs[i], ys[j + 1] - ys[j])
			if cell.size.x <= 0.0 or cell.size.y <= 0.0:
				continue
			var mid := cell.get_center()
			if not holes.any(func(h): return h.has_point(mid)):
				_dim.draw_rect(cell, shade, true)
	var pulse := 0.6 + 0.4 * sin(_t * 5.0)
	for h in holes:
		_dim.draw_rect(h, Color(Palette.LINK, pulse), false, 3.0)

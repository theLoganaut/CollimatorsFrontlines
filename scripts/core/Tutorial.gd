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

## [point, target name ("" = none), text, wait ("next" or an event)]
const STEPS := [
	["war_room", "table", "Welcome aboard, pilot. This is the War Room, and every sortie starts at the War Table. Click it.", "table_opened"],
	["sector_map", "map", "The sector: three locations, each running a mission. Pick any of them. For training they all run the same short route.", "location_opened"],
	["popup", "launch", "Launch drops you in. Your mech's HP and any parts you lose carry through the whole run, so every fight counts.", "launched"],
	["location_map", "starts", "The route: one stop per row, bottom to top. Fights, repair bays, autonomous bays and events, with a boss waiting at the top of a real run. Pick where to start.", "node_chosen"],
	["combat", "player", "Your mech. Each coloured block is a component with its own HP. Red ones are hardpoints (your weapons): lose all of them and you're out. Hover any part for its details; hover a card and its part lights up.", "next"],
	["combat", "hand", "Your hand. Every component still standing gives you its cards. Lose a part, lose its cards. Each card plays once per turn, and they all come back when your next turn starts.", "next"],
	["combat", "heat", "Heat. Cards cost heat. Go over your max and you overheat: the backlash deals 15% of your max HP across random parts, and your turn ends. You vent some heat every turn: the line under the box says how far.", "next"],
	["combat", "intents", "Enemy intent: what it'll do on its turn. Hover an icon to see the card, and which of your parts it's aiming at.", "next"],
	["combat", "enemy", "Drag an attack card onto one of its parts to hit that part: the number over the part is what it'll deal. Knock out its hardpoints, or wear its HP down into the dark red on its bar.", "card_played"],
	["combat", "end_turn", "Play what you can afford, then End Turn. The enemy acts, then your heat vents. Too hot to play anything? Vent instead: it takes your turn and dumps most of your heat. Number keys play cards too, the Log button keeps a record, and every key is in Settings.", "turn_ended"],
	["combat", "", "That's the loop. Finish it off.", "next"],
	["reward", "reward", "Salvage. Your Scraps are banked automatically (spend them at autonomous bays). Choose one category and take one part: new parts go into your Cargo. Or skip it for a few scraps.", "reward_done"],
	["refit", "mech", "A refit. Drag parts between your mech and your Cargo; R or right-click rotates. Lit squares show where a part fits, and Undo puts a move back.", "next"],
	["refit", "cargo", "Where a part sits matters. Yellow arrows are links: some parts affect whatever they point at. Finish the refit when you're happy.", "refit_done"],
	["combat", "", "One more fight with your new setup. Then you're cleared.", "next"],
	["debrief", "", "Training complete. The War Table's yours now: pick a sector for a real run. Directives pay Chips every day, and the Hangar lets you change mechs and loadouts.", "next"],
]

signal finished()

var active: bool = false
var step: int = 0
var _point: String = ""
var _targets: Dictionary = {}
var _offer: bool = false

var _root: Control
var _dim: Control
var _box: PanelContainer
var _face: OperatorPortrait
var _head: Label
var _text: Label
var _talk: Tween
var _next_btn: Button
var _skip_btn: Button
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
	_text = UIKit.label("", 15, Color("eefcfa"), true)
	_text.custom_minimum_size = Vector2(380, 0)
	v.add_child(_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	_skip_btn = GlassPanel.button("Skip training", 12)
	_skip_btn.custom_minimum_size = Vector2(120, 32)
	_skip_btn.pressed.connect(skip)
	row.add_child(_skip_btn)
	row.add_child(UIKit.spacer())
	_start_btn = GlassPanel.button("Start training", 13, true, Palette.LINK)
	_start_btn.custom_minimum_size = Vector2(140, 32)
	_start_btn.pressed.connect(_accept_offer)
	row.add_child(_start_btn)
	_next_btn = GlassPanel.button("Next", 13, true, Palette.LINK)
	_next_btn.custom_minimum_size = Vector2(100, 32)
	_next_btn.pressed.connect(func(): event("next"))
	row.add_child(_next_btn)

# ---------- control ----------

## The War Room asks a pilot who hasn't trained yet.
func offer() -> void:
	if active or Profile.tutorial_done:
		return
	_offer = true
	_targets = {}
	_show("New pilot? Take the training run: two short fights that walk you through the War Table, combat, and fitting parts. About five minutes.", "", false)

func _accept_offer() -> void:
	_offer = false
	start()
	reached("war_room", _targets)

func start() -> void:
	active = true
	step = 0

func skip() -> void:
	_offer = false
	active = false
	Profile.tutorial_done = true
	Profile.save()
	_root.visible = false
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
		if not _offer:
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
	_text.text = text
	_text.visible_ratio = 0.0
	_start_btn.visible = _offer
	_next_btn.visible = not _offer and wait_next
	_next_btn.text = "Got it" if step >= STEPS.size() - 1 or text.ends_with("off.") else "Next"
	_skip_btn.text = "Not now" if _offer else "Skip training"
	# "Next" steps hold the screen; action steps let clicks through.
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP if (wait_next or _offer) else Control.MOUSE_FILTER_IGNORE
	_current_target = target
	_t = 0.0
	_place_box()

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
	for r in _rects_of(_targets.get(_current_target, null)):
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
	var soft: Array[Rect2] = []
	for key in _targets:
		if key != _current_target and key != "keep_clear":
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
	_speak()

## The line comes in over the channel a few letters at a time.
func _speak() -> void:
	if _talk != null:
		_talk.kill()
	_face.talking = true
	_talk = create_tween()
	_talk.tween_property(_text, "visible_ratio", 1.0, clampf(_text.text.length() / 60.0, 0.4, 2.2))
	_talk.tween_callback(func(): _face.talking = false)

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

func _draw_dim() -> void:
	var screen: Vector2 = _root.get_viewport_rect().size
	var shade := Color(0, 0, 0, 0.5 if _dim.mouse_filter == Control.MOUSE_FILTER_STOP else 0.28)
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

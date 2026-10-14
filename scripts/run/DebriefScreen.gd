extends Control
## After every run (Logan, 2026-09-27): how it ended, where, Logan's pick
## of stats counting up (RunStats.DEBRIEF, 2026-10-13: the full wall was
## too much), and the Chips the run earned with where they came from (the
## mission, directives finished, achievements). On holo glass,
## over the War Room (dimmed): the pilot is back at base.

const COLS := 4
const TILE := Vector2(236, 66)
const COUNT_TIME := 0.9

var _content: VBoxContainer
var _tiles: Array = [] # [Label, target value]
var _t: float = 0.0
var _glass: GlassPanel
var _room: Texture2D
var _layers: Array = [] # [texture, rect in room-art pixels (empty = room-sized)]

func _ready() -> void:
	UIState.reset()
	get_tree().paused = false
	Audio.music("hub")
	Audio.ambience("hub")
	var run: RunData = RunState.last_run
	_room = load("res://assets/warroom/room.png")
	for l in [["floor_left.png", Rect2()], ["floor_right.png", Rect2()], ["war_table.png", Rect2(203.7, 216.7, 216.6, 114.8)]]:
		_layers.append([load("res://assets/warroom/" + l[0]), l[1]])
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_glass = GlassPanel.new()
	_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glass)
	_content = VBoxContainer.new()
	_content.resized.connect(_fit_glass)
	_content.add_theme_constant_override("separation", 10)
	add_child(_content)
	if run == null:
		_content.add_child(UIKit.label("No mission to debrief.", 18))
	else:
		_build(run)
	var back := GlassPanel.button("Return to the War Room", 15, true, Palette.HARDPOINT)
	back.custom_minimum_size = Vector2(240, 44)
	back.pressed.connect(func(): SceneRouter.go(SceneRouter.WAR_ROOM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(UIKit.spacer())
	if _can_run_again(run):
		var again := GlassPanel.button("Run it again", 15)
		again.custom_minimum_size = Vector2(170, 44)
		again.tooltip_text = "Same location and mech, a new seed: straight back in without the War Table."
		again.pressed.connect(_run_again.bind(run))
		row.add_child(again)
	row.add_child(back)
	_content.add_child(row)
	get_viewport().size_changed.connect(_layout)
	_layout()
	Tutorial.reached("debrief", {})
	# wrapped lines know their height only once laid out at full width
	await get_tree().process_frame
	await get_tree().process_frame
	_fit_glass()

## A quick restart (Logan, 2026-10-13): not after training or the Daily
## Operation (one attempt a day).
func _can_run_again(run: RunData) -> bool:
	return run != null and not run.mission.get("training", false) and not Daily.is_daily(run) and not Tutorial.active

func _run_again(run: RunData) -> void:
	if SceneRouter.is_busy():
		return
	RunState.start_run(str(run.location.get("id", "")))
	RunState.advance()

func _build(run: RunData) -> void:
	var cleared := run.result == RunData.Result.CLEARED
	_content.add_child(UIKit.label("DEBRIEF", 13, Color("7f9d9a")))
	_content.add_child(UIKit.label("Sector cleared" if cleared else "Pilot ejected", 34, Palette.OK if cleared else Palette.DANGER))
	var where := HBoxContainer.new()
	where.add_theme_constant_override("separation", 12)
	where.add_child(UIKit.label("%s  ·  %s  ·  %d / %d encounters" % [run.location.get("name", ""), run.mission_name(), run.path.size(), run.encounter_count()], 14, Color("9fb9b6")))
	where.add_child(UIKit.seed_row(run.seed_value, 14, Color("9fb9b6")))
	_content.add_child(where)
	if run.mission.get("training", false):
		_content.add_child(UIKit.label("Training doesn't count toward your record.", 16, Palette.TEXT_MUTED))
	else:
		var report: Dictionary = Profile.last_report
		if report.has("daily_score"):
			_content.add_child(UIKit.label("Daily Operation score: %d%s" % [int(report["daily_score"]), "  ·  a new best!" if report.get("daily_best", false) else "  ·  best %d" % int(Profile.daily.get("best", 0))], 16, Palette.LINK))
	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	_content.add_child(gap)
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_content.add_child(grid)
	for key in RunStats.DEBRIEF:
		var v := run.stats.get_stat(key)
		var tile := PanelContainer.new()
		tile.custom_minimum_size = TILE
		var st := GlassPanel.panel_style(GlassPanel.HOLO, 8.0)
		st.content_margin_left = 14
		st.border_color = Color(GlassPanel.HOLO, 0.45)
		st.bg_color = Color(0.02, 0.06, 0.08, 0.6)
		tile.add_theme_stylebox_override("panel", st)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 0)
		tile.add_child(box)
		var num := UIKit.label("0", 28, Color("dffcf8"))
		box.add_child(num)
		box.add_child(UIKit.label(RunStats.label(key), 11, Color("9fb9b6")))
		grid.add_child(tile)
		if v == 0 and key in RunStats.MIN_KEYS: # no fight won: no fastest fight
			num.text = "—"
			continue
		_tiles.append([num, v])
	if not run.mission.get("training", false):
		_content.add_child(_chips_tile(Profile.last_report))
	set_process(true)

## The run's Chips, full width under the stats: the total counting up, then
## what it's made of (the mission, each directive, each achievement).
func _chips_tile(report: Dictionary) -> Control:
	var mission := int(report.get("chips", 0))
	var parts: Array[String] = ["Mission +%d" % mission]
	var total := mission
	for f in report.get("directives", []):
		parts.append("Directive: %s +%d" % [f["text"], int(f["chips"])])
		total += int(f["chips"])
	for a in report.get("achievements", []):
		parts.append("Achievement: %s +%d" % [a["name"], int(a["chips"])])
		total += int(a["chips"])
	var tile := PanelContainer.new()
	var st := GlassPanel.panel_style(Palette.SCRAPS, 8.0)
	st.content_margin_left = 14
	st.content_margin_right = 14
	st.border_color = Color(Palette.SCRAPS, 0.55)
	st.bg_color = Color(0.08, 0.06, 0.02, 0.6)
	tile.add_theme_stylebox_override("panel", st)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	tile.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var num := UIKit.label("0", 24, Palette.SCRAPS)
	row.add_child(num)
	var unit := UIKit.label("Chips earned", 13, Color("d8c79a"))
	unit.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(unit)
	box.add_child(UIKit.label("   ·   ".join(parts), 12, Color("d8c79a"), true))
	_tiles.append([num, total])
	return tile

func _process(delta: float) -> void:
	_t = minf(_t + delta, COUNT_TIME)
	var k := ease(_t / COUNT_TIME, 0.4)
	for t in _tiles:
		t[0].text = str(int(round(float(t[1]) * k)))
	if _t >= COUNT_TIME:
		set_process(false)

func _layout() -> void:
	var screen: Vector2 = get_viewport_rect().size
	size = screen
	var w := COLS * TILE.x + (COLS - 1) * 12.0
	_content.position = Vector2((screen.x - w) / 2.0, 60.0)
	_content.size = Vector2(w, 0)
	_fit_glass()
	queue_redraw()

func _fit_glass() -> void:
	if _glass == null:
		return
	# a wrapped line can leave the box taller than its content; size to what's on it
	var h := _content.get_combined_minimum_size().y
	if _content.size.y != h:
		_content.size.y = h
	_glass.position = _content.position - Vector2(24, 20)
	_glass.size = Vector2(_content.size.x, h) + Vector2(48, 40)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BG, true)
	if _room != null:
		var k := maxf(size.x / _room.get_width(), size.y / _room.get_height())
		var s := _room.get_size() * k
		var origin := (size - s) / 2.0
		draw_texture_rect(_room, Rect2(origin, s), false)
		for l in _layers: # the floors and the War Table, as in the War Room
			var r: Rect2 = l[1] if (l[1] as Rect2).size != Vector2.ZERO else Rect2(Vector2.ZERO, _room.get_size())
			draw_texture_rect(l[0], Rect2(origin + r.position * k, r.size * k), false)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.02, 0.03, 0.7), true)

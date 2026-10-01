extends Control
## After every run (Logan, 2026-09-27): how it ended, where, and a wall of
## stats that count up (RunStats.DEFS, in order). Stats that stayed at 0
## are left off so the wall shows what actually happened. On holo glass,
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
		_content.add_child(UIKit.label("No run to debrief.", 18))
	else:
		_build(run)
	var back := GlassPanel.button("Return to the War Room", 15, true, Palette.HARDPOINT)
	back.custom_minimum_size = Vector2(240, 44)
	back.pressed.connect(func(): SceneRouter.go(SceneRouter.WAR_ROOM))
	var row := HBoxContainer.new()
	row.add_child(UIKit.spacer())
	row.add_child(back)
	_content.add_child(row)
	get_viewport().size_changed.connect(_layout)
	_layout()
	Tutorial.reached("debrief", {})

func _build(run: RunData) -> void:
	var cleared := run.result == RunData.Result.CLEARED
	_content.add_child(UIKit.label("DEBRIEF", 13, Color("7f9d9a")))
	_content.add_child(UIKit.label("Sector cleared" if cleared else "Pilot ejected", 34, Palette.OK if cleared else Palette.DANGER))
	var where := HBoxContainer.new()
	where.add_theme_constant_override("separation", 12)
	where.add_child(UIKit.label("%s  ·  %s  ·  %d / %d stops" % [run.location.get("name", ""), run.mission_name(), run.path.size(), run.encounter_count()], 14, Color("9fb9b6")))
	where.add_child(UIKit.seed_row(run.seed_value, 14, Color("9fb9b6")))
	_content.add_child(where)
	if run.mission.get("training", false):
		_content.add_child(UIKit.label("Training doesn't count toward your record.", 16, Palette.TEXT_MUTED))
	else:
		var report: Dictionary = Profile.last_report
		var line := "+%d Chips" % int(report.get("chips", 0))
		for f in report.get("directives", []):
			line += "   ·   Directive done: %s (+%d)" % [f["text"], int(f["chips"])]
		_content.add_child(UIKit.label(line, 16, Palette.SCRAPS))
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
	for def in RunStats.DEFS:
		var v := run.stats.get_stat(def[0])
		if v == 0 and not ["damage_dealt", "damage_taken", "fights_won"].has(def[0]):
			continue
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
		var num := UIKit.label("0", 24, Color("dffcf8"))
		box.add_child(num)
		box.add_child(UIKit.label(def[1], 11, Color("9fb9b6")))
		grid.add_child(tile)
		_tiles.append([num, v])
	set_process(true)

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
	_glass.position = _content.position - Vector2(24, 20)
	_glass.size = _content.size + Vector2(48, 40)

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

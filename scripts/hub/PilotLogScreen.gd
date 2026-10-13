extends HubScreen
## Pilot Log: your career in numbers (runs, clears, Chips, lifetime bests),
## then three tabs: the last runs, newest first (with the order taken, the
## variant, elites and bosses); each mech's record; and every enemy you've
## fought (how often you beat it, and lost to it); and the achievements
## (Achievements), earned or not. A run's recorded fights can be watched
## again (Watch: the combat screen's replay mode), and its playtest report
## is in the reports folder. Other players' stats and
## directive rankings need online play, so they wait for later.

var _col: VBoxContainer
var _scroll: ScrollContainer
var _list: VBoxContainer
var _tab_buttons: Dictionary = {}
var _tab: String = "runs"

func screen_title() -> String:
	return "Pilot Log"

func _build() -> void:
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 12)
	add_child(_col)

	var totals := HBoxContainer.new()
	totals.add_theme_constant_override("separation", 12)
	var best := _lifetime()
	for t in [["Missions", str(Profile.runs)], ["Cleared", str(Profile.clears)],
			["Chips earned", HubScreen._thousands(Profile.chips_earned)], ["Directives", str(Profile.directives_done_total)],
			["Biggest hit", str(best.get("biggest_hit", 0))], ["Fights won", str(best.get("fights_won", 0))]]:
		totals.add_child(_stat_tile(t[0], t[1]))
	_col.add_child(totals)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	_col.add_child(tabs)
	for t in [["runs", "Recent missions"], ["mechs", "By mech"], ["enemies", "Enemies"], ["achievements", "Achievements"]]:
		var b := UIKit.button(t[1], Color.TRANSPARENT, Vector2(140, 32), 13)
		b.toggle_mode = true
		b.add_theme_stylebox_override("pressed", UIKit.style(Palette.PANEL_2, Palette.HARDPOINT, 2))
		b.pressed.connect(func():
			_tab = t[0]
			_fill())
		tabs.add_child(b)
		_tab_buttons[t[0]] = b
	tabs.add_child(UIKit.spacer())
	var folder := UIKit.button("Playtest reports", Color.TRANSPARENT, Vector2(150, 32), 12)
	folder.tooltip_text = "Opens the folder of playtest reports: every finished mission, written out to send in, and a crash report for any time the game closed without quitting."
	folder.pressed.connect(func(): OS.shell_open(PlaytestReport.folder()))
	tabs.add_child(folder)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_col.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)
	_fill()

func _fill() -> void:
	for t in _tab_buttons:
		_tab_buttons[t].set_pressed_no_signal(t == _tab)
	for c in _list.get_children():
		c.queue_free()
	match _tab:
		"runs":
			if Profile.history.is_empty():
				_list.add_child(UIKit.label("No missions logged yet. The War Table's waiting.", 14, Palette.TEXT_MUTED))
			for h in Profile.history:
				_list.add_child(_run_row(h))
		"mechs":
			for id in GameData.PLAYER_MECHS:
				_list.add_child(_mech_row(id))
		"enemies":
			_fill_enemies()
		"achievements":
			_fill_achievements()

## Every achievement: earned ones lit with the date, the rest dim.
func _fill_achievements() -> void:
	var defs := Achievements.defs()
	var have := Profile.achievements
	_list.add_child(UIKit.label("%d of %d earned" % [have.size(), defs.size()], 13, Palette.TEXT_MUTED))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_list.add_child(grid)
	for d in defs:
		var got: bool = have.has(d["id"])
		var box := HubScreen.card(Palette.OK if got else Palette.BORDER)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.modulate.a = 1.0 if got else 0.6
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		box.add_child(row)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(UIKit.label(d["name"], 15, Palette.TEXT if got else Palette.TEXT_MUTED))
		v.add_child(UIKit.label(d["text"], 12, Color("9fb9b6"), true))
		row.add_child(v)
		row.add_child(UIKit.label("Earned %s" % have[d["id"]] if got else "+%d Chips" % int(d.get("chips", 0)), 12, Palette.OK if got else Palette.SCRAPS))
		grid.add_child(box)

## One mech's record: runs, clears (and the rate), fights won, furthest stop.
func _mech_row(id: String) -> Control:
	var rec: Dictionary = Profile.mech_record.get(id, {})
	var box := HubScreen.card()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	var name_l := UIKit.label(id.capitalize(), 17, Palette.TEXT)
	name_l.custom_minimum_size.x = 120
	row.add_child(name_l)
	var runs := int(rec.get("runs", 0))
	if runs == 0:
		row.add_child(UIKit.label("Not flown yet.", 14, Palette.TEXT_MUTED))
		return box
	var clears := int(rec.get("clears", 0))
	for t in [["%d" % runs, "runs"], ["%d (%d%%)" % [clears, roundi(100.0 * clears / runs)], "cleared"],
			["%d" % int(rec.get("fights_won", 0)), "fights won"], ["%d" % int(rec.get("best_stops", 0)), "furthest encounter"]]:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.custom_minimum_size.x = 120
		v.add_child(UIKit.label(t[0], 18, Palette.TEXT))
		v.add_child(UIKit.label(t[1], 11, Palette.TEXT_MUTED))
		row.add_child(v)
	return box

## Every enemy fought: fights, how often you won them, how often it beat you.
func _fill_enemies() -> void:
	var ids := Profile.enemy_record.keys()
	if ids.is_empty():
		_list.add_child(UIKit.label("No fights logged yet (enemy records start with the next mission).", 14, Palette.TEXT_MUTED))
		return
	ids.sort_custom(func(a, b): return int(Profile.enemy_record[a]["fought"]) > int(Profile.enemy_record[b]["fought"]))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 32)
	grid.add_theme_constant_override("v_separation", 6)
	_list.add_child(grid)
	for h in ["ENEMY", "FIGHTS", "YOU WON", "IT ENDED A MISSION"]:
		grid.add_child(UIKit.label(h, 11, Palette.TEXT_MUTED))
	for id in ids:
		var rec: Dictionary = Profile.enemy_record[id]
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/mechs/%s.json" % id))
		var tier: String = d.get("tier", "") if typeof(d) == TYPE_DICTIONARY else ""
		grid.add_child(UIKit.label("%s%s" % [d.get("name", id) if typeof(d) == TYPE_DICTIONARY else id, "" if tier in ["", "regular"] else "  (%s)" % tier], 14, Palette.TEXT))
		grid.add_child(UIKit.label(str(int(rec["fought"])), 14, Palette.TEXT))
		grid.add_child(UIKit.label("%d%%" % roundi(100.0 * int(rec["beaten"]) / maxf(1.0, int(rec["fought"]))), 14, Palette.OK))
		grid.add_child(UIKit.label(str(int(rec["lost_to"])), 14, Palette.DANGER if int(rec["lost_to"]) > 0 else Palette.TEXT_MUTED))

## Sums (and bests) across every logged run.
func _lifetime() -> Dictionary:
	var out := {}
	for h in Profile.history:
		var s: Dictionary = h.get("stats", {})
		out["biggest_hit"] = maxi(int(out.get("biggest_hit", 0)), int(s.get("biggest_hit", 0)))
		out["fights_won"] = int(out.get("fights_won", 0)) + int(s.get("fights_won", 0))
	return out

func _stat_tile(label: String, value: String) -> Control:
	var box := HubScreen.card()
	box.custom_minimum_size = Vector2(120, 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	box.add_child(v)
	v.add_child(UIKit.label(value, 24, Palette.TEXT))
	v.add_child(UIKit.label(label, 11, Palette.TEXT_MUTED))
	return box

func _run_row(h: Dictionary) -> Control:
	var cleared: bool = h.get("result", "") == "cleared"
	var box := HubScreen.card(Palette.OK if cleared else Palette.BORDER)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 2)
	box.add_child(lines)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	lines.add_child(row)
	var detail := _run_detail(h)
	if detail != "":
		lines.add_child(UIKit.label(detail, 11, Color("9fb9b6")))
	var watch := _watch_row(h)
	if watch != null:
		lines.add_child(watch)
	row.add_child(UIKit.label("CLEARED" if cleared else "EJECTED", 13, Palette.OK if cleared else Palette.DANGER))
	row.add_child(UIKit.label("%s · %s" % [h.get("location", ""), h.get("mission", "")], 14, Palette.TEXT))
	if str(h.get("cause", "")) != "":
		row.add_child(UIKit.label(str(h["cause"]), 12, Palette.DANGER))
	row.add_child(UIKit.label(str(h.get("mech", "")).capitalize(), 13, Palette.TEXT_MUTED))
	row.add_child(UIKit.spacer())
	var s: Dictionary = h.get("stats", {})
	row.add_child(UIKit.label("%d stops · %d won · %s dmg" % [int(h.get("stops", 0)), int(s.get("fights_won", 0)), HubScreen._thousands(int(s.get("damage_dealt", 0)))], 13, Palette.TEXT_MUTED))
	row.add_child(UIKit.label("+%d Chips" % int(h.get("chips", 0)), 13, Palette.SCRAPS))
	row.add_child(UIKit.label(str(h.get("date", "")), 12, Palette.TEXT_MUTED))
	if h.has("seed"):
		row.add_child(UIKit.seed_row(int(h["seed"]), 11))
	return box

## A button per recorded fight still on disk (Replays): watch it again.
func _watch_row(h: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var n := 0
	for f in h.get("fights", []):
		n += 1
		if not Replays.exists(str(f.get("replay", ""))):
			continue
		if row.get_child_count() == 0:
			row.add_child(UIKit.label("Watch:", 11, Palette.TEXT_MUTED))
		var b := UIKit.button("%d%s" % [n, "" if f.get("won", false) else " ✕"], Color.TRANSPARENT, Vector2(34, 22), 11)
		b.tooltip_text = "Fight %d: %s (%s, %d turns)" % [n, ", ".join(f.get("enemies", []).map(_enemy_name)), "won" if f.get("won", false) else "lost", int(f.get("turns", 0))]
		b.pressed.connect(_watch.bind(str(f["replay"])))
		row.add_child(b)
	if row.get_child_count() == 0:
		row.queue_free()
		return null
	return row

## Plays a recorded fight in the combat screen, then comes back here.
func _watch(file: String) -> void:
	var rec := Replays.load_record(file)
	if rec.is_empty() or SceneRouter.is_busy():
		return
	Audio.play("ui")
	CombatScene.replay_record = rec
	CombatScene.replay_return = SceneRouter.PILOT_LOG
	SceneRouter.go(SceneRouter.COMBAT)

static func _enemy_name(id) -> String:
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/mechs/%s.json" % str(id)))
	return d.get("name", str(id)) if typeof(d) == TYPE_DICTIONARY else str(id)

## The second line of a run: its order, variant, elites and bosses, fights.
static func _run_detail(h: Dictionary) -> String:
	var parts: Array[String] = []
	if h.get("daily", false):
		parts.append("Daily Operation")
	if str(h.get("variant", "")) != "":
		parts.append(str(h["variant"]))
	if str(h.get("order", "")) != "":
		parts.append("Order: %s" % DeploymentOrders.title(h["order"]))
	var s: Dictionary = h.get("stats", {})
	var elites := int(s.get("elites_beaten", 0))
	var bosses := int(s.get("bosses_beaten", 0))
	if elites > 0:
		parts.append("%d elite%s" % [elites, "" if elites == 1 else "s"])
	if bosses > 0:
		parts.append("boss beaten")
	var fights: Array = h.get("fights", [])
	if not fights.is_empty():
		var turns := 0
		for f in fights:
			turns += int(f.get("turns", 0))
		parts.append("%d fights, %.1f turns each" % [fights.size(), float(turns) / fights.size()])
	return "  ·  ".join(parts)

func _layout(screen: Vector2) -> void:
	var w := minf(980.0, screen.x - MARGIN * 2.0)
	_col.position = Vector2((screen.x - w) / 2.0, TOP_BAR_H + 24.0)
	_col.size = Vector2(w, 0)
	_scroll.custom_minimum_size = Vector2(w, screen.y - TOP_BAR_H - 200.0)

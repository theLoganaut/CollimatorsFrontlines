extends HubScreen
## Directives (Logan, 2026-09-28): today's three rotating goals, each worth
## Chips, completable in an hour or two of play. Progress builds as runs
## end; a finished one has already paid out. New ones at midnight. Below
## them, this week's bigger weeklies and the streak (all of a day's done,
## days in a row).

var _col: VBoxContainer

func screen_title() -> String:
	return "Directives"

func _build() -> void:
	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 12)
	add_child(_col)
	var today := Profile.todays_directives()
	var week := Profile.this_weeks_directives()
	Profile.save()
	_col.add_child(UIKit.label("TODAY'S DIRECTIVES", 12, Palette.TEXT_MUTED))
	_col.add_child(UIKit.label("Three new ones every day. Progress counts when a mission ends.", 14, Palette.TEXT_MUTED))
	for id in today["ids"]:
		var d := Meta.directive(id)
		if d.is_empty():
			continue
		_col.add_child(_directive_card(d, int(today["progress"].get(id, 0)), (today["done"] as Array).has(id)))
	var left := _time_to_midnight()
	var days := Profile.streak_days()
	var per := Balance.get_int("meta", "streak_chips_per_day", 5)
	var next := mini(days + 1, Balance.get_int("meta", "streak_max_days", 5)) * per
	_col.add_child(UIKit.label("New directives in %dh %02dm  ·  streak: %d day%s (finish all three for +%d Chips)  ·  %d completed all time" % [left / 3600, (left % 3600) / 60, days, "" if days == 1 else "s", next, Profile.directives_done_total], 13, Palette.TEXT_MUTED))
	_col.add_child(UIKit.label("THIS WEEK  ·  %s" % week["week"], 12, Palette.TEXT_MUTED))
	for id in week["ids"]:
		var wd := Meta.directive(id)
		if not wd.is_empty():
			_col.add_child(_directive_card(wd, int(week["progress"].get(id, 0)), (week["done"] as Array).has(id)))

func _directive_card(d: Dictionary, progress: int, done: bool) -> Control:
	var goal := Meta.directive_goal(d)
	var box := HubScreen.card(Palette.OK if done else Palette.BORDER)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	box.add_child(v)
	var top := HBoxContainer.new()
	top.add_child(UIKit.label(Meta.directive_text(d), 17, Palette.TEXT))
	top.add_child(UIKit.spacer())
	top.add_child(UIKit.label(("Done  ·  +%d Chips" if done else "+%d Chips") % int(d.get("chips", 0)), 15, Palette.OK if done else Palette.SCRAPS))
	v.add_child(top)
	var bar := ProgressBar.new()
	bar.max_value = goal
	bar.value = goal if done else progress
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	var fill := UIKit.style(Palette.OK if done else Palette.SCRAPS, Color.TRANSPARENT, 0, 3)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", UIKit.style(Palette.PANEL_2, Palette.BORDER, 1, 3))
	v.add_child(bar)
	var note := "%d / %d" % [mini(progress, goal), goal] if str(d.get("kind", "sum")) == "sum" else ("Done in one mission" if done else "In a single mission")
	if d.has("mech"):
		note += "  ·  in %s" % str(d["mech"]).capitalize()
	if d.has("mission"):
		note += "  ·  on %s" % str(GameData.mission(d["mission"]).get("name", d["mission"]))
	if d.has("location"):
		note += "  ·  at %s" % str(GameData.sector(d["location"]).get("name", d["location"]))
	v.add_child(UIKit.label(note, 12, Palette.TEXT_MUTED))
	return box

static func _time_to_midnight() -> int:
	var t := Time.get_datetime_dict_from_system()
	return 86400 - (int(t["hour"]) * 3600 + int(t["minute"]) * 60 + int(t["second"]))

func _layout(screen: Vector2) -> void:
	var w := minf(720.0, screen.x - MARGIN * 2.0)
	_col.position = Vector2((screen.x - w) / 2.0, TOP_BAR_H + 30.0)
	_col.size = Vector2(w, 0)

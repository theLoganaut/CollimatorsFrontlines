extends HubScreen
## Memorial Wall: the corrupted Collimators you've faced. One plaque per
## boss in the sector: its pilot, where it holds, and your record against
## it. Bosses you haven't met stay dark.

var _grid: GridContainer

func screen_title() -> String:
	return "Memorial Wall"

func _build() -> void:
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 16)
	_grid.add_theme_constant_override("v_separation", 16)
	add_child(_grid)
	var seen := {}
	for loc in GameData.sectors():
		var id: String = loc.get("boss", "")
		if id == "" or seen.has(id):
			continue
		seen[id] = true
		_grid.add_child(_plaque(id, loc))

func _plaque(id: String, loc: Dictionary) -> Control:
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/mechs/%s.json" % id))
	var mech: Dictionary = d if typeof(d) == TYPE_DICTIONARY else {}
	var rec: Dictionary = Profile.boss_record.get(id, {})
	var met := Profile.bosses_faced.has(id) or int(rec.get("faced", 0)) > 0
	var box := HubScreen.card(Palette.PROTOCOL if met else Palette.BORDER)
	box.custom_minimum_size = Vector2(300, 220)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	box.add_child(v)
	if not met:
		v.add_child(UIKit.label("UNKNOWN", 20, Palette.TEXT_MUTED))
		v.add_child(UIKit.label("Holds %s. Not yet encountered." % loc.get("name", ""), 13, Palette.TEXT_MUTED, true))
		return box
	v.add_child(UIKit.label(str(mech.get("title", "")).to_upper(), 12, Palette.PROTOCOL))
	v.add_child(UIKit.label(str(mech.get("name", id)), 24, Palette.TEXT))
	v.add_child(UIKit.label("Holds %s" % loc.get("name", ""), 13, Palette.TEXT_MUTED))
	var line: String = mech.get("lines", {}).get("intro", "")
	if line != "":
		v.add_child(UIKit.label("\"%s\"" % line, 13, Palette.TEXT, true))
	v.add_child(UIKit.spacer())
	v.add_child(UIKit.label("Faced %d  ·  Beaten %d" % [int(rec.get("faced", 1)), int(rec.get("beaten", 0))], 14, Palette.LINK))
	return box

func _layout(screen: Vector2) -> void:
	var w := 3 * 300.0 + 2 * 16.0
	_grid.position = Vector2((screen.x - w) / 2.0, TOP_BAR_H + 40.0)

extends Control
## The War Room: the pixel-art bunker (assets/warroom/, 624×390 art drawn
## ×ART_SCALE onto the game's 1152×720 logical canvas, centered on the
## aspect-expanded screen). The room is one background plus a piece of art
## per station (Hotspot), stacked back to front: the three wall bays, the
## back-corner units, the War Table, then the front-corner stations. Live
## content is drawn on the art: the mechs as holograms on the Hangar pads,
## today's dailies on the Directives glass, the sectors on the table, and
## the Memorial Wall's trophies (Profile.memorial_points).
##
## Hovering a station outlines it and projects its HoloLabel from a fixed
## emitter on it. Clicking the War Table zooms the room in on the table's
## glass and dims it, then the theater (WarMap, generated from the sector
## seed) rises out of the table as a 3D hologram (SectorMapView). Picking a
## location projects its glass pop-up from its marker; Launch starts a run
## and fades to that location's map. The other stations open their own screens; the Research
## Bay waits for unlocks.

const BASE := Vector2(1152, 720)
const ART := "res://assets/warroom/"
const ART_SCALE := 1152.0 / 624.0
const TOP_BAR_H := TopBar.HEIGHT
const ZOOM_TIME := 0.6
const ZOOM_FILL := 0.9 # share of the free screen the table's glass fills when zoomed in
const ZOOM_DIM := 0.86 # how dark the room gets behind the hologram
const STATION_ZOOM_MAX := 3.0 # how far the camera pushes in on a station as its screen opens
const MEMORIAL_SLOTS := 14

## [id, title, subtitle, art file, rect in room-art pixels (empty: the art
##  is a room-sized layer, cut to what it covers), label emitter in
##  room-art pixels, which way the label grows]. Back to front.
const STATIONS := [
	["memorial_wall", "Memorial Wall", "The corrupted Collimators you've faced.", "memorial_wall_empty.png", Rect2(67, 124, 118, 115), Vector2(126, 124), "up"],
	["hangar", "Hangar", "Pick your mech and loadout.", "hangar.png", Rect2(231, 124, 164, 115), Vector2(313, 124), "up"],
	["directives", "Directives", "Today's three goals. Earn Chips.", "directives.png", Rect2(438, 124, 118, 115), Vector2(497, 124), "up"],
	["research_bay", "Research Bay", "Permanent unlocks, paid in Chips.", "research_bay.png", Rect2(), Vector2(34, 128), "up_right"],
	["livery_bay", "Livery Bay", "Paint schemes, paid in Chips.", "livery_bay.png", Rect2(), Vector2(590, 124), "up_left"],
	["war_table", "War Table", "Sector Select: pick where to drop in.", "war_table.png", Rect2(203.7, 216.7, 216.6, 114.8), Vector2(418, 255), "right"],
	["info_bay", "Info Bay", "Browse every component and status.", "info_bay.png", Rect2(), Vector2(60, 242), "up_right"],
	["pilot_log", "Pilot Log", "Your stats and mission history.", "pilot_log.png", Rect2(), Vector2(562, 246), "up_left"],
]
## Where each station goes (the Research Bay has no unlocks yet).
const STATION_SCENES := {
	"hangar": "res://scenes/HangarScreen.tscn", "directives": "res://scenes/DirectivesScreen.tscn",
	"pilot_log": "res://scenes/PilotLogScreen.tscn", "memorial_wall": "res://scenes/MemorialWallScreen.tscn",
	"info_bay": "res://scenes/InfoBayScreen.tscn", "livery_bay": "res://scenes/LiveryBayScreen.tscn",
}
## The table's glass (war_table.png pixels): the sectors show on it, and
## the camera zooms in to it.
const TABLE_GLASS := Rect2(20, 6, 228, 73)
## Hangar pads (hangar.png pixels): x of each pad's centre, the pads' floor
## line, and hologram height. Mechs left to right.
const HANGAR_PADS := [["redline", 57.0], ["bastion", 124.0], ["jackal", 191.0]]
const HANGAR_PAD_FLOOR := 126.0
const HANGAR_HOLO_H := 62.0
## The dailies' rows on the Directives glass (directives.png pixels).
const DIRECTIVE_ROWS := Rect2(27, 65, 91, 45)
const OPERATOR_RECT := Rect2(256, 604, 640, 104)

var room: Control
var table: Hotspot
var sector_map: SectorMapView
var war_map: WarMap
var popup: LocationPopup
var settings_menu: SettingsMenu
var _stations: Dictionary = {} # id -> Hotspot
var _label: HoloLabel
var _label_owner: Hotspot
var _room_tex: Texture2D
var _floors: Array[Texture2D] = []
var _top_bar: TopBar
var _settings_button: SettingsButton
var _build_label: Label # which build this is (BuildInfo), bottom right
var _whats_new_btn: Button
## Said instead of the usual line (a saved run closed after an update).
var _operator_override: String = ""
var _back_button: Button
var _daily_button: Button
var _operator: GlassPanel
var _operator_face: OperatorPortrait
var _operator_line: Label
var _operator_tw: Tween
var _operator_dismissed: bool = false
var _dim: Control
var _dim_a: float = 0.0
var _zoomed: bool = false
var _zooming: bool = false
var _time: float = 0.0

static func _art(r: Rect2) -> Rect2:
	return Rect2(r.position * ART_SCALE, r.size * ART_SCALE)

func _ready() -> void:
	UIState.reset()
	get_tree().paused = false
	Audio.music("hub")
	Audio.ambience("hub")
	room = Control.new()
	room.size = BASE
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	room.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	room.draw.connect(_draw_room)
	add_child(room)
	_room_tex = load(ART + "room.png")
	for f in ["floor_left.png", "floor_right.png"]:
		_floors.append(load(ART + f))

	var saved := SaveGame.has_save()
	var closed_run := false
	if saved and not SaveGame.problems().is_empty(): # an update removed something it needs
		CrashLog.crumb("run save can't load after an update: %s" % ", ".join(SaveGame.problems()))
		SaveGame.set_aside()
		saved = false
		closed_run = true
	for s in STATIONS:
		var spot := _build_station(s)
		if s[0] == "war_table":
			table = spot
			if saved:
				spot.subtitle = "A mission is in progress."
			spot.pressed.connect(_on_table_pressed)
		elif STATION_SCENES.has(s[0]):
			spot.pressed.connect(_open_station.bind(s[0]))

	_add_holograms(_stations["hangar"])
	_stations["directives"].draw_extra = _draw_dailies
	table.draw_extra = _draw_table_sectors
	_update_memorial()

	_label = HoloLabel.new()
	_label.size = BASE
	_label.bounds = Rect2(6, TOP_BAR_H + 6, BASE.x - 12, BASE.y - TOP_BAR_H - 12)
	room.add_child(_label)

	if closed_run:
		_operator_override = "Your last sortie was logged on an older build and can't be picked up after the update. I've closed it out. Your Chips, record and hangar are untouched."
	_build_operator()
	_build_top_bar()
	_build_label = UIKit.label(BuildInfo.label(), 10, Color(Palette.TEXT_MUTED, 0.7))
	_build_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_build_label)

	# the room darkens behind the table's hologram
	_dim = Control.new()
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.draw.connect(func(): _dim.draw_rect(Rect2(Vector2.ZERO, _dim.size), Color(0.0, 0.01, 0.02, _dim_a), true))
	add_child(_dim)
	move_child(_dim, room.get_index() + 1)

	war_map = WarMap.generate(Profile.sector_seed, GameData.sectors())
	sector_map = SectorMapView.new()
	sector_map.visible = false
	sector_map.location_chosen.connect(_on_location_chosen)
	add_child(sector_map)
	var missions := {}
	var rolled := Profile.sector_missions()
	for loc_id in rolled.keys():
		missions[loc_id] = GameData.mission(rolled[loc_id])
	sector_map.setup(GameData.sectors(), missions, war_map)

	_back_button = GlassPanel.button("◀  War Room", 13)
	_back_button.custom_minimum_size = Vector2(130, 36)
	_back_button.visible = false
	_back_button.pressed.connect(_zoom_out)
	add_child(_back_button)
	_daily_button = GlassPanel.button("Daily Operation", 13, false, Palette.LINK)
	_daily_button.custom_minimum_size = Vector2(130, 36)
	_daily_button.visible = false
	_daily_button.tooltip_text = "Today's mission: the same for every pilot, one scored attempt."
	_daily_button.pressed.connect(_on_daily)
	add_child(_daily_button)

	popup = LocationPopup.new()
	popup.z_index = 300
	popup.launch_pressed.connect(_on_launch)
	popup.daily_launch_pressed.connect(_on_daily_launch)
	popup.continue_pressed.connect(_on_continue_run)
	popup.abandon_pressed.connect(_on_abandon_run)
	popup.closed.connect(func(): sector_map.selected_id = "")
	add_child(popup)

	settings_menu = SettingsMenu.new()
	settings_menu.z_index = 400
	add_child(settings_menu)
	settings_menu.set_restart_action("") # nothing to restart or eject from here
	_settings_button.pressed.connect(settings_menu.open)

	get_viewport().size_changed.connect(_layout)
	_layout()
	Tutorial.base_named.connect(_on_base_named)
	if Profile.base_name == "" and not Tutorial.active:
		_operator.visible = false # one Operator at a time: his War Room line waits for the name
		Tutorial.ask_base_name() # offers training after, if it's due
	elif not Tutorial.active and not Profile.tutorial_done and not saved:
		Tutorial.offer()
	Tutorial.reached("war_room", {"table": table})

func _process(delta: float) -> void:
	_time += delta
	if not _zoomed:
		table.queue_redraw() # the sector beacons pulse

func _layout() -> void:
	var screen: Vector2 = get_viewport_rect().size
	size = screen
	if not _zoomed and not _zooming:
		room.scale = Vector2.ONE
		room.position = ((screen - BASE) / 2.0).floor()
	else:
		var z := _zoom_target(screen)
		room.scale = Vector2(z[0], z[0])
		room.position = z[1]
		_place_sector_map()
	_dim.position = Vector2(0, TOP_BAR_H)
	_dim.size = Vector2(screen.x, screen.y - TOP_BAR_H)
	_back_button.position = Vector2(16, TOP_BAR_H + 12)
	_daily_button.position = Vector2(16, TOP_BAR_H + 56)
	popup.size = screen
	settings_menu.size = screen
	_build_label.position = screen - _build_label.get_minimum_size() - Vector2(10, 6)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BG, true)

## The room behind every station, and the plating over its corner trenches.
func _draw_room() -> void:
	var r := Rect2(Vector2.ZERO, BASE)
	room.draw_texture_rect(_room_tex, r, false)
	for f in _floors:
		room.draw_texture_rect(f, r, false)

# ---------- building ----------

func _build_station(s: Array) -> Hotspot:
	var tex: Texture2D = load(ART + s[3])
	var art_rect: Rect2 = s[4]
	var region := Rect2()
	if not art_rect.has_area(): # a room-sized layer: just the part it covers
		region = Rect2(tex.get_image().get_used_rect())
		art_rect = region
	var spot := Hotspot.new()
	spot.setup(s[0], s[1], s[2], s[0] == "war_table" or STATION_SCENES.has(s[0]), tex, _art(art_rect), region)
	spot.anchor = (s[5] as Vector2) * ART_SCALE
	spot.label_dir = s[6]
	spot.hover_changed.connect(_on_station_hover.bind(spot))
	room.add_child(spot)
	_stations[s[0]] = spot
	return spot

## The mechs stand on the Hangar's pads as holograms; the one you'll
## launch in burns brighter.
func _add_holograms(hangar: Hotspot) -> void:
	var k := hangar.size.x / hangar.texture.get_width()
	for pad in HANGAR_PADS:
		var tex := MechArt.player_front(pad[0])
		if tex == null:
			continue
		var used := tex.get_image().get_used_rect()
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(used)
		var h := HANGAR_HOLO_H * k
		var w := h * used.size.x / used.size.y
		var holo := TextureRect.new()
		holo.texture = atlas
		holo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		holo.stretch_mode = TextureRect.STRETCH_SCALE
		holo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holo.size = Vector2(w, h)
		holo.position = Vector2(pad[1] * k - w / 2.0, HANGAR_PAD_FLOOR * k - h)
		holo.material = MechArt.hologram_material(0.9 if pad[0] == Profile.mech else 0.6)
		hangar.add_child(holo)

## Trophies appear on the Memorial Wall as Memorial points build up.
func _update_memorial() -> void:
	var wall: Hotspot = _stations["memorial_wall"]
	var img := wall.texture.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	for i in range(Meta.memorial_trophies(Profile.memorial_points, MEMORIAL_SLOTS)):
		var slot: Texture2D = load(ART + "memorial/slot_%02d.png" % i)
		if slot == null:
			continue
		var s_img := slot.get_image()
		if s_img.is_compressed():
			s_img.decompress()
		s_img.convert(Image.FORMAT_RGBA8)
		img.blend_rect(s_img, Rect2i(Vector2i.ZERO, s_img.get_size()), Vector2i.ZERO)
	wall.set_texture(ImageTexture.create_from_image(img))

## Today's directives on the glass board: text, then progress or DONE.
func _draw_dailies(spot: Hotspot) -> void:
	var k := spot.size.x / spot.texture.get_width()
	var rows := Rect2(DIRECTIVE_ROWS.position * k, DIRECTIVE_ROWS.size * k)
	var today := Profile.todays_directives()
	var font := get_theme_default_font()
	var fs := 9
	var row_h := rows.size.y / 3.0
	var i := 0
	for id in today["ids"]:
		var d := Meta.directive(id)
		if d.is_empty():
			continue
		var done: bool = (today["done"] as Array).has(id)
		var right := "DONE" if done else "%d/%d" % [int(today["progress"].get(id, 0)), Meta.directive_goal(d)]
		var rw := font.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var y := rows.position.y + row_h * i + fs + 1.0
		var text := _fit(font, Meta.directive_text(d), fs, rows.size.x - rw - 6.0)
		spot.draw_string(font, Vector2(rows.position.x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(Palette.REACTOR, 0.95))
		spot.draw_string(font, Vector2(rows.end.x - rw, y), right, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.OK if done else Palette.LINK)
		i += 1

## `text` cut to `width` with an ellipsis.
static func _fit(font: Font, text: String, fs: int, width: float) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= width:
		return text
	while text.length() > 1 and font.get_string_size(text + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
		text = text.substr(0, text.length() - 1)
	return text.strip_edges() + "…"

## The table's glass in its own coordinates.
func _glass_local(spot: Hotspot) -> Rect2:
	var k := spot.size.x / spot.texture.get_width()
	return Rect2(TABLE_GLASS.position * k, TABLE_GLASS.size * k)

## The sectors as beacons on the table's glass (the zoomed-in sector map
## takes over when the camera moves in).
func _draw_table_sectors(spot: Hotspot) -> void:
	if _zoomed or _zooming:
		return
	var glass := _glass_local(spot)
	# the theater squeezed into the glass, clear of its rounded ends and rim
	var inner := Rect2(glass.position + glass.size * Vector2(0.14, 0.3), glass.size * Vector2(0.72, 0.6))
	var font := get_theme_default_font()
	var c := Palette.HARDPOINT
	var front := PackedVector2Array()
	for uv in war_map.front:
		front.append(inner.position + uv * inner.size)
	spot.draw_polyline(front, Color(c, 0.3), 3.0, true)
	spot.draw_polyline(front, Color(c, 0.6), 1.0, true)
	for i in range(GameData.sectors().size()):
		var loc: Dictionary = GameData.sectors()[i]
		var p := inner.position + (war_map.sites.get(loc["id"], Vector2(0.5, 0.5)) as Vector2) * inner.size
		var pulse := 0.5 + 0.5 * sin(_time * 2.5 + float(i) * 1.7)
		spot.draw_set_transform(p, 0.0, Vector2(1.0, 0.42)) # rings lie flat on the glass
		spot.draw_arc(Vector2.ZERO, 12.0 + pulse * 4.0, 0.0, TAU, 32, Color(c, 0.35 * (1.0 - pulse)), 2.0, true)
		spot.draw_arc(Vector2.ZERO, 11.0, 0.0, TAU, 32, c, 2.0, true)
		spot.draw_set_transform_matrix(Transform2D.IDENTITY)
		spot.draw_line(p, p - Vector2(0, 30), Color(c, 0.3), 4.0)
		spot.draw_line(p, p - Vector2(0, 30), Color(c, 0.75), 1.0)
		spot.draw_rect(Rect2(p - Vector2(3, 36), Vector2(6, 6)), c, true)
		var name := str(loc.get("name", "")).to_upper()
		var w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		spot.draw_string(font, p + Vector2(-w / 2.0, -42), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, c)

# ---------- hover labels ----------

func _on_station_hover(hovered: bool, spot: Hotspot) -> void:
	if hovered:
		_label_owner = spot
		Audio.play("holo", 0.04, -6.0)
		var info := _label_info(spot)
		_label.show_for(spot.anchor, spot.label_dir, spot.title, info[0], info[1], info[2])
	elif _label_owner == spot:
		_label_owner = null
		_label.hide_label()

## [detail lines, tag, tag color] for a station's label.
func _label_info(spot: Hotspot) -> Array:
	var lines: Array = [spot.subtitle]
	var tag := ""
	var tag_color := Palette.REACTOR
	match spot.id:
		"memorial_wall":
			lines.append("Trophies: %d / %d" % [Meta.memorial_trophies(Profile.memorial_points, MEMORIAL_SLOTS), MEMORIAL_SLOTS])
		"hangar":
			lines.append("Ready to launch: %s" % Profile.mech.capitalize())
		"directives":
			var today := Profile.todays_directives()
			lines.append("%d of %d done today" % [(today["done"] as Array).size(), (today["ids"] as Array).size()])
		"pilot_log":
			lines.append("Missions %d  ·  Clears %d" % [Profile.runs, Profile.clears])
		"livery_bay":
			lines.append("Chips: %s" % HubScreen._thousands(Profile.chips))
		"war_table":
			tag = "CONTINUE MISSION" if SaveGame.has_save() else "START MISSION"
			tag_color = Palette.HARDPOINT
	if not spot.enabled:
		tag = "NOT BUILT YET"
		tag_color = Palette.TEXT_MUTED
	return [lines, tag, tag_color]

func _set_stations_interactive(v: bool) -> void:
	for spot in _stations.values():
		(spot as Hotspot).interactive = v
	if not v:
		_label_owner = null
		_label.hide_label()

func _build_operator() -> void:
	var r := OPERATOR_RECT
	_operator = GlassPanel.new()
	_operator.position = r.position
	_operator.size = r.size
	room.add_child(_operator)
	_operator_face = OperatorPortrait.new()
	_operator_face.position = Vector2(10, 10)
	_operator_face.size = Vector2(76, r.size.y - 20)
	_operator.add_child(_operator_face)
	var who := UIKit.label("OPERATOR  ·  SECURE CHANNEL", 10, Color("b9d8d4"))
	who.position = Vector2(100, 10)
	_operator.add_child(who)
	var said := _operator_override if _operator_override != "" else Operator.line(Profile.last_report, Profile.runs, SaveGame.summary() if SaveGame.has_save() else {})
	_operator_line = UIKit.label(said, 14, Color("eefcfa"), true)
	_operator_line.position = Vector2(100, 30)
	_operator_line.size = Vector2(r.size.x - 100 - 124, r.size.y - 40)
	_operator_line.visible_ratio = 0.0
	_operator.add_child(_operator_line)
	var cont := GlassPanel.button("Continue", 13)
	cont.size = Vector2(98, 34)
	cont.position = Vector2(r.size.x - 110, r.size.y - 46)
	cont.pressed.connect(_dismiss_operator)
	_operator.add_child(cont)
	_operator_talk()

## His line comes in over the channel a few letters at a time.
func _operator_talk() -> void:
	var n := _operator_line.text.length()
	if n == 0:
		_operator_line.visible_ratio = 1.0
		return
	_operator_face.talking = true
	_operator_tw = create_tween()
	var tw := _operator_tw
	tw.tween_interval(0.35)
	tw.tween_property(_operator_line, "visible_ratio", 1.0, clampf(n / 45.0, 0.6, 2.6))
	tw.tween_callback(func(): _operator_face.talking = false)

func _dismiss_operator() -> void:
	if _operator_line.visible_ratio < 1.0: # first click finishes the line
		_operator_tw.kill()
		_operator_line.visible_ratio = 1.0
		_operator_face.talking = false
		return
	_operator_dismissed = true
	_operator.visible = false

func _build_top_bar() -> void:
	# the title is the base's name (Profile.base_name); click it to rename
	_top_bar = TopBar.make(self, "Home Base")
	_top_bar.clickable_title(func(): if not Tutorial.active: Tutorial.ask_base_name(), "Rename the base")
	var row := _top_bar.row
	_on_base_named()
	row.add_child(UIKit.spacer())
	# the update notes (WhatsNewDialog): lit until opened for this version
	_whats_new_btn = GlassPanel.button("What's New?!", 12)
	_whats_new_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_whats_new_btn.tooltip_text = "What changed in this update, and what's coming next"
	_whats_new_btn.pressed.connect(func():
		if Tutorial.active:
			return
		WhatsNewDialog.open(get_tree())
		_style_whats_new())
	row.add_child(_whats_new_btn)
	_style_whats_new()
	row.add_child(TopBar.chip(_bar_label("%s Chips" % HubScreen._thousands(Profile.chips), 14, Palette.SCRAPS), Palette.SCRAPS))
	# (the co-op lobby button comes back once co-op exists; Logan, 2026-10-13)
	_settings_button = SettingsButton.new()
	_settings_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_settings_button)

func _style_whats_new() -> void:
	GlassPanel.style_button(_whats_new_btn, WhatsNewDialog.unread(), Palette.LINK)

func _on_base_named() -> void:
	_top_bar.set_title(Profile.base_name if Profile.base_name.strip_edges() != "" else "Home Base")
	if _operator != null and not _operator.visible and not _operator_dismissed and not _zoomed:
		_operator.visible = true # held back while the base was being named
		_operator_talk()

func _bar_label(text: String, font_size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", c)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l

# ---------- zoom into the table / sector map ----------

## The table's glass in room coordinates.
func _glass_rect() -> Rect2:
	var g := _glass_local(table)
	return Rect2(table.position + g.position, g.size)

## [scale, room position] that puts the War Table's glass in the middle of
## the space under the top bar, filling ZOOM_FILL of it.
func _zoom_target(screen: Vector2) -> Array:
	var t := _glass_rect()
	var free := Vector2(screen.x, screen.y - TOP_BAR_H)
	var s := minf(free.x * ZOOM_FILL / t.size.x, free.y * ZOOM_FILL / t.size.y)
	var center := Vector2(screen.x / 2.0, TOP_BAR_H + free.y / 2.0)
	return [s, center - t.get_center() * s]

## The hologram fills the screen under the top bar.
func _place_sector_map() -> void:
	var screen: Vector2 = get_viewport_rect().size
	sector_map.position = Vector2(0, TOP_BAR_H)
	sector_map.size = Vector2(screen.x, screen.y - TOP_BAR_H)

func _set_dim(a: float) -> void:
	_dim_a = a
	_dim.queue_redraw()

func _zoom_in() -> void:
	if _zoomed or _zooming:
		return
	_zooming = true
	Tutorial.event("table_opened")
	_set_stations_interactive(false)
	table.queue_redraw()
	var z := _zoom_target(get_viewport_rect().size)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(room, "scale", Vector2(z[0], z[0]), ZOOM_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(room, "position", z[1], ZOOM_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_operator, "modulate:a", 0.0, ZOOM_TIME * 0.6)
	tw.tween_method(_set_dim, _dim_a, ZOOM_DIM, ZOOM_TIME).set_delay(ZOOM_TIME * 0.3)
	await tw.finished
	_zooming = false
	_zoomed = true
	_operator.visible = false
	_place_sector_map()
	sector_map.visible = true
	Audio.play("holo", 0.02, -2.0)
	_back_button.visible = true
	_daily_button.visible = not Tutorial.active and not SaveGame.has_save() # a run in progress comes first
	await sector_map.project_in().finished
	Tutorial.reached("sector_map", {"map": sector_map.marker_rects(), "keep_clear": [_back_button]})

func _zoom_out() -> void:
	if not _zoomed or _zooming:
		return
	_zooming = true
	_zoomed = false
	popup.close()
	sector_map.visible = false
	_back_button.visible = false
	_daily_button.visible = false
	var screen: Vector2 = get_viewport_rect().size
	_operator.visible = not _operator_dismissed
	var tw := create_tween().set_parallel(true)
	tw.tween_property(room, "scale", Vector2.ONE, ZOOM_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(room, "position", ((screen - BASE) / 2.0).floor(), ZOOM_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_operator, "modulate:a", 1.0, ZOOM_TIME).set_delay(ZOOM_TIME * 0.3)
	tw.tween_method(_set_dim, _dim_a, 0.0, ZOOM_TIME * 0.7)
	await tw.finished
	_zooming = false
	_set_stations_interactive(true)
	table.queue_redraw()

## The camera pushes in on the station while the screen fades, so its
## screen opens as a step into that part of the room.
func _open_station(id: String) -> void:
	if SceneRouter.is_busy() or _zooming or _zoomed:
		return
	_zooming = true
	_set_stations_interactive(false)
	var spot: Hotspot = _stations[id]
	var r := Rect2(spot.position, spot.size)
	var screen: Vector2 = get_viewport_rect().size
	var free := Vector2(screen.x, screen.y - TOP_BAR_H)
	var s := minf(STATION_ZOOM_MAX, minf(free.x / r.size.x, free.y / r.size.y))
	var center := Vector2(screen.x / 2.0, TOP_BAR_H + free.y / 2.0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(room, "scale", Vector2(s, s), SceneRouter.FADE_OUT + 0.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(room, "position", center - r.get_center() * s, SceneRouter.FADE_OUT + 0.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(_operator, "modulate:a", 0.0, 0.2)
	SceneRouter.go(STATION_SCENES[id])

## With a saved run, the table offers to continue it instead of a new one.
func _on_table_pressed() -> void:
	if SaveGame.has_save():
		popup.open_continue(SaveGame.summary())
	else:
		_zoom_in()

func _on_continue_run() -> void:
	if SceneRouter.is_busy():
		return
	if RunState.continue_run():
		RunState.advance()
	else:
		SaveGame.clear() # unreadable save: start fresh
		popup.close()

func _on_abandon_run() -> void:
	if SceneRouter.is_busy():
		return
	if RunState.continue_run():
		RunState.run.eject()
		RunState.advance() # -> debrief
	else:
		SaveGame.clear()
		popup.close()

func _on_location_chosen(location: Dictionary) -> void:
	var mission: Dictionary = GameData.mission(Tutorial.TRAINING_MISSION) if Tutorial.active else Profile.sector_mission(location["id"])
	sector_map.selected_id = location["id"]
	var uv: Vector2 = war_map.sites.get(location["id"], Vector2(0.5, 0.5))
	popup.open(location, mission, sector_map.anchor_for(location["id"]), WarMap.grid_ref(uv))
	Tutorial.event("location_opened")
	Tutorial.reached("popup", {"launch": popup._primary, "keep_clear": [popup._panel]})

## The Daily Operation's pop-up, beamed from its location's marker.
func _on_daily() -> void:
	var d := Daily.setup(Meta.today())
	sector_map.selected_id = d["location_id"]
	popup.open_daily(d, sector_map.anchor_for(d["location_id"]))

func _on_daily_launch() -> void:
	if SceneRouter.is_busy() or Profile.daily_played_today():
		return
	RunState.start_daily()
	RunState.advance()

func _on_launch(location: Dictionary) -> void:
	if SceneRouter.is_busy():
		return
	RunState.start_run(location.get("id", ""), popup.seed_value(), Tutorial.TRAINING_MISSION if Tutorial.active else "")
	Tutorial.event("launched")
	RunState.advance()

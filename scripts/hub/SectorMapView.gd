class_name SectorMapView
extends Control
## The War Table's hologram: the theater (WarMap) as a live 3D topographic
## map rising out of the table (HoloTerrain: contour lines, grid squares, our
## ground teal and theirs red, water, a cut-away plate edge). On top, in 2D: the front line
## (with its hostile-side teeth), both sides' units, contact flashes, our HQ,
## the route to each location, and each location as a hostile objective
## symbol on a pin with its name and rolled mission. Hovering a location
## projects a HoloLabel from its pin; clicking it asks WarRoomScreen to open
## that location's pop-up. project_in() raises the terrain out of the table.

signal location_chosen(location: Dictionary)

const HOLO := Palette.REACTOR
const HOSTILE := Palette.HARDPOINT
const FRIENDLY := Palette.CHASSIS
const PITCH := 47.0            # camera elevation, degrees
const INSET_TOP := 70.0        # room kept for the title strip
const INSET_BOTTOM := 64.0     # and for the legend
const INSET_SIDE := 24.0
const STEM := 46.0             # a location symbol's height above its ground
const SYMBOL := 17.0           # half-size of a location's diamond
const HIT_R := 30.0
const FLASH_LIFE := 1.6

var map: WarMap
var _markers: Array[Dictionary] = [] # {location, mission (dict), uv}
var _hovered: int = -1
var selected_id: String = ""
var _time: float = 0.0
var _overlay_a: float = 0.0
var _flashes: Array = [] # {uv, age}
var _next_flash: float = 0.5
var _rng := RandomNumberGenerator.new()

var _overlay: Control
var _label: HoloLabel
var _terrain: HoloTerrain

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_terrain = HoloTerrain.new()
	_terrain.pitch = PITCH
	_terrain.inset_top = INSET_TOP
	_terrain.inset_bottom = INSET_BOTTOM
	_terrain.inset_side = INSET_SIDE
	_terrain.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_terrain)

	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_label = HoloLabel.new()
	add_child(_label)
	_rng.seed = 7
	resized.connect(_layout)

## The theater to show, the locations on it and this roll's mission per
## location (id -> mission dict).
func setup(locations: Array, missions: Dictionary, p_map: WarMap) -> void:
	map = p_map
	_markers.clear()
	for loc in locations:
		_markers.append({"location": loc, "mission": missions.get(loc["id"], {}), "uv": map.sites.get(loc["id"], Vector2(0.5, 0.3))})
	_terrain.setup(map)
	_layout()

## Raises the terrain out of the table, then the markers fade in.
func project_in() -> Tween:
	_overlay_a = 0.0
	var tw := _terrain.project_in()
	tw.tween_property(self, "_overlay_a", 1.0, 0.35).set_delay(0.75)
	return tw

## Shows it fully at once (screenshots, tests).
func show_now() -> void:
	_terrain.show_now()
	_overlay_a = 1.0

func _layout() -> void:
	if _overlay == null:
		return
	_overlay.size = size
	_label.size = size
	_label.bounds = Rect2(Vector2(6, 6), size - Vector2(12, 12))

func _proj(uv: Vector2, above: float = 0.0, ground: bool = true) -> Vector2:
	return _terrain.proj(uv, above, ground)

func _proj_line(pts: PackedVector2Array, above: float = 0.015) -> PackedVector2Array:
	return _terrain.proj_line(pts, above)

func _ground_ring(uv: Vector2, radius: float, above: float = 0.02) -> PackedVector2Array:
	return _terrain.ground_ring(uv, radius, above)

# ---------- live ----------

func _process(delta: float) -> void:
	if not is_visible_in_tree() or map == null:
		return
	_time += delta
	_terrain.hold_still = selected_id != "" # a pop-up projects from a marker
	_next_flash -= delta
	if _next_flash <= 0.0 and _overlay_a > 0.5:
		_next_flash = _rng.randf_range(0.5, 1.4)
		var u := _rng.randf_range(0.05, 0.95)
		var uv := Vector2(u, map.front_at(u) + _rng.randf_range(-0.07, 0.05))
		if not map.is_water(uv):
			_flashes.append({"uv": uv, "age": 0.0, "hostile": _rng.randf() < 0.6})
	for f in _flashes:
		f["age"] += delta
	_flashes = _flashes.filter(func(f): return f["age"] < FLASH_LIFE)
	if _hovered >= 0:
		_label.show_for(_symbol_pos(_hovered) + Vector2(0, -SYMBOL - 4.0), "up", _markers[_hovered]["location"].get("name", ""), _hover_lines(_hovered), "CLICK TO PLAN THE DROP", Palette.LINK)
	_overlay.modulate.a = _overlay_a
	_overlay.queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if map == null:
		return
	if event is InputEventMouseMotion:
		var h := _marker_at(event.position)
		if h != _hovered:
			_hovered = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h >= 0 else Control.CURSOR_ARROW
			if h >= 0:
				Audio.play("holo", 0.04, -6.0)
			else:
				_label.hide_label()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := _marker_at(event.position)
		if i >= 0:
			accept_event()
			_hovered = -1
			_label.hide_label()
			location_chosen.emit(_markers[i]["location"])

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hovered >= 0:
		_hovered = -1
		_label.hide_label()

func _ground_pos(i: int) -> Vector2:
	return _proj(_markers[i]["uv"])

func _symbol_pos(i: int) -> Vector2:
	return _ground_pos(i) + Vector2(0, -STEM)

func _marker_at(p: Vector2) -> int:
	if _overlay_a < 0.5:
		return -1
	for i in range(_markers.size()):
		if p.distance_to(_symbol_pos(i)) <= HIT_R or p.distance_to(_ground_pos(i)) <= HIT_R * 0.6:
			return i
	return -1

## A location's symbol and name chip, in global coordinates: its pop-up
## projects from the side of this.
func anchor_for(location_id: String) -> Rect2:
	for i in range(_markers.size()):
		if _markers[i]["location"]["id"] == location_id:
			var p := _symbol_pos(i)
			var r := Rect2(p - Vector2(SYMBOL, SYMBOL), Vector2(SYMBOL, SYMBOL) * 2.0).merge(_markers[i].get("chip", Rect2(p, Vector2.ZERO)))
			return Rect2(get_global_transform() * r.position, r.size)
	return Rect2()

## Each location's symbol, pin and name chip, in screen space (the training
## coach rings these).
func marker_rects() -> Array:
	var out: Array = []
	for i in range(_markers.size()):
		var c: Vector2 = get_global_transform() * _symbol_pos(i)
		out.append(Rect2(c - Vector2(SYMBOL + 8.0, SYMBOL + 8.0), Vector2(SYMBOL * 2.0 + 150.0, STEM + SYMBOL + 16.0)))
	return out

func _hover_lines(i: int) -> Array:
	var loc: Dictionary = _markers[i]["location"]
	var mission: Dictionary = _markers[i]["mission"]
	var stops := int(mission.get("rows", 7)) + (1 if mission.get("boss", false) else 0)
	var lines: Array = ["%s  ·  %d stops  ·  grid %s" % [str(mission.get("name", "")).to_upper(), stops, WarMap.grid_ref(_markers[i]["uv"])]]
	lines.append_array(_wrap(str(mission.get("summary", "")), 52))
	var desc := str(loc.get("description", ""))
	if desc != "" and not desc.begins_with("["):
		lines.append_array(_wrap(desc, 52))
	return lines

static func _wrap(text: String, width: int) -> Array:
	var out: Array = []
	var line := ""
	for word in text.split(" ", false):
		if line != "" and line.length() + 1 + word.length() > width:
			out.append(line)
			line = word
		else:
			line = word if line == "" else line + " " + word
	if line != "":
		out.append(line)
	return out

# ---------- the overlay ----------

func _draw_overlay() -> void:
	if map == null:
		return
	var a := _overlay_a
	var font := get_theme_default_font()
	if a <= 0.0:
		return
	_draw_hud(font)
	_draw_grid_labels(font)
	# routes from HQ, the hovered or chosen one lit
	for i in range(_markers.size()):
		var id: String = _markers[i]["location"]["id"]
		var lit := i == _hovered or id == selected_id
		var pts := _proj_line(map.routes[id])
		HoloTerrain.draw_dashed(_overlay, pts, 7.0, 5.0, -_time * (24.0 if lit else 8.0), Color(Palette.LINK if lit else HOLO, 0.95 if lit else 0.4), 2.0 if lit else 1.2)
	_draw_front()
	for u in map.units:
		_draw_unit(_proj(u["uv"], 0.03), u["hostile"], u["kind"], 1.0)
	for f in _flashes:
		_draw_flash(f)
	_draw_hq(font)
	# locations, far ones first
	var order := range(_markers.size())
	order.sort_custom(func(x, y): return _markers[x]["uv"].y < _markers[y]["uv"].y)
	for i in order:
		_draw_location(i, font)

## The front line: the forward line of our troops, with its teeth facing them.
func _draw_front() -> void:
	var pts := _proj_line(map.front, 0.02)
	_overlay.draw_polyline(pts, Color(HOSTILE, 0.25), 6.0, true)
	_overlay.draw_polyline(pts, Color(Color("ff9a6a"), 0.95), 1.8, true)
	var far := _proj(Vector2(0.5, 0.2)) - _proj(Vector2(0.5, 0.8)) # toward their side on screen
	var next := 11.0
	var dist := 0.0
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		var dir := (b - a) / maxf(seg, 0.001)
		var n := Vector2(-dir.y, dir.x)
		if n.dot(far) < 0.0:
			n = -n
		while next <= dist + seg:
			var ang := n.angle()
			_overlay.draw_arc(a + dir * (next - dist), 4.0, ang - PI / 2.0, ang + PI / 2.0, 8, Color("ff9a6a"), 1.5, true)
			next += 22.0
		dist += seg

## A unit counter: ours a blue rectangle, theirs a red diamond (NATO style),
## with its kind drawn inside.
func _draw_unit(p: Vector2, hostile: bool, kind: String, k: float) -> void:
	var c := Color("ff8a5c") if hostile else Color("8fb8e8")
	var fill := Color(HOSTILE if hostile else FRIENDLY, 0.25)
	if hostile:
		var s := 7.5 * k
		var poly := PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)])
		_overlay.draw_colored_polygon(poly, fill)
		poly.append(poly[0])
		_overlay.draw_polyline(poly, c, 1.3, true)
	else:
		var r := Rect2(p - Vector2(8, 5.5) * k, Vector2(16, 11) * k)
		_overlay.draw_rect(r, fill, true)
		_overlay.draw_rect(r, c, false, 1.3)
	match kind:
		"armor":
			_overlay.draw_arc(p, 3.2 * k, 0, TAU, 12, c, 1.0, true)
		"artillery":
			_overlay.draw_circle(p, 1.8 * k, c)
		_:
			_overlay.draw_line(p + Vector2(-3, -2.5) * k, p + Vector2(3, 2.5) * k, c, 1.0, true)
			_overlay.draw_line(p + Vector2(-3, 2.5) * k, p + Vector2(3, -2.5) * k, c, 1.0, true)

func _draw_flash(f: Dictionary) -> void:
	var t: float = f["age"] / FLASH_LIFE
	var c := Color("ffb070") if f["hostile"] else Color("9fd0ff")
	_overlay.draw_polyline(_ground_ring(f["uv"], 0.05 + t * 0.35), Color(c, 0.8 * (1.0 - t)), 1.5, true)
	if t < 0.25:
		_overlay.draw_circle(_proj(f["uv"], 0.03), 3.0 * (1.0 - t * 4.0), Color(c, 0.9))

func _draw_hq(font: Font) -> void:
	var g := _proj(map.hq)
	_overlay.draw_polyline(_ground_ring(map.hq, 0.4), Color(FRIENDLY, 0.6), 1.2, true)
	var p := g + Vector2(0, -28)
	_overlay.draw_line(g, p + Vector2(0, 9), Color(FRIENDLY, 0.7), 1.2)
	var r := Rect2(p - Vector2(17, 10), Vector2(34, 20))
	_overlay.draw_rect(r, Color(FRIENDLY, 0.3), true)
	_overlay.draw_rect(r, Color("9fc6f0"), false, 1.5)
	_overlay.draw_string(font, r.position + Vector2(0, 15), "HQ", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 11, Color("dcecff"))
	_overlay.draw_line(r.position + Vector2(0, r.size.y), r.position + Vector2(0, r.size.y + 9), Color("9fc6f0"), 1.5)
	_overlay.draw_string(font, Vector2(r.end.x + 6, p.y + 4), "HOME BASE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("9fc6f0"))

func _draw_location(i: int, font: Font) -> void:
	var loc: Dictionary = _markers[i]["location"]
	var hot: bool = i == _hovered or loc["id"] == selected_id
	var uv: Vector2 = _markers[i]["uv"]
	var g := _ground_pos(i)
	var p := _symbol_pos(i)
	var pulse := 0.5 + 0.5 * sin(_time * 2.6 + float(i) * 1.9)
	var edge := Palette.LINK if hot else Color("ff8a5c")
	# ground rings and the pin
	_overlay.draw_colored_polygon(_ground_ring(uv, 0.32), Color(HOSTILE, 0.12 if hot else 0.07))
	_overlay.draw_polyline(_ground_ring(uv, 0.32), Color(edge, 0.7), 1.3, true)
	_overlay.draw_polyline(_ground_ring(uv, 0.36 + pulse * 0.3), Color(edge, 0.45 * (1.0 - pulse)), 1.2, true)
	_overlay.draw_line(g, p + Vector2(0, SYMBOL), Color(edge, 0.3), 5.0)
	_overlay.draw_line(g, p + Vector2(0, SYMBOL), Color(edge, 0.9), 1.3)
	_overlay.draw_circle(g, 2.5, edge)
	# the hostile objective: a diamond with the place's glyph
	var s := SYMBOL * (1.12 if hot else 1.0)
	var poly := PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)])
	_overlay.draw_colored_polygon(poly, Color(0.1, 0.03, 0.02, 0.8))
	_overlay.draw_colored_polygon(poly, Color(HOSTILE, 0.3 if hot else 0.18))
	poly.append(poly[0])
	_overlay.draw_polyline(poly, Color(edge, 0.35), 5.0, true)
	_overlay.draw_polyline(poly, edge, 2.0, true)
	_draw_glyph(str(loc.get("map_icon", "")), p, s * 0.5, Color("ffe6d8") if not hot else Palette.LINK)
	# name and mission on a glass chip
	var name := str(loc.get("name", "")).to_upper()
	var mission := str(_markers[i]["mission"].get("name", "")).to_upper()
	var w := maxf(font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, font.get_string_size(mission, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x) + 16.0
	var chip := Rect2(p + Vector2(s + 8.0, -17.0), Vector2(w, 34.0))
	_markers[i]["chip"] = chip
	GlassPanel.draw_glass(_overlay, chip, 1.0, edge if hot else HOSTILE, 5.0, 0.8)
	_overlay.draw_string(font, chip.position + Vector2(8, 15), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("fff1e8") if not hot else Palette.LINK)
	_overlay.draw_string(font, chip.position + Vector2(8, 28), mission, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Palette.LINK if hot else Color("f0b48f"))

## Simple map glyphs: an anchor (shipyard), crossed picks (mine), stacked
## data discs (archives); anything else gets a star.
func _draw_glyph(kind: String, p: Vector2, r: float, c: Color) -> void:
	match kind:
		"anchor":
			_overlay.draw_line(p + Vector2(0, -r), p + Vector2(0, r), c, 1.6)
			_overlay.draw_line(p + Vector2(-r * 0.5, -r * 0.45), p + Vector2(r * 0.5, -r * 0.45), c, 1.6)
			_overlay.draw_arc(p + Vector2(0, r * 0.1), r * 0.85, 0.35, PI - 0.35, 10, c, 1.6, true)
			_overlay.draw_arc(p + Vector2(0, -r * 0.95), r * 0.22, 0, TAU, 8, c, 1.4, true)
		"pick":
			for sx in [-1.0, 1.0]:
				var a := p + Vector2(-r * 0.8 * sx, r * 0.85)
				var b := p + Vector2(r * 0.7 * sx, -r * 0.7)
				_overlay.draw_line(a, b, c, 1.6, true)
				var head := (b - a).normalized().orthogonal() * r * 0.45
				_overlay.draw_line(b - head, b + head, c, 1.8, true)
		"data":
			for k in range(3):
				var cy := p.y - r * 0.6 + k * r * 0.6
				_overlay.draw_set_transform(Vector2(p.x, cy), 0.0, Vector2(1.0, 0.4))
				_overlay.draw_arc(Vector2.ZERO, r * 0.8, 0, TAU, 16, c, 1.5, true)
				_overlay.draw_set_transform_matrix(Transform2D.IDENTITY)
		_:
			var pts := PackedVector2Array()
			for k in range(11):
				var ang := -PI / 2.0 + TAU * k / 10.0
				pts.append(p + Vector2(cos(ang), sin(ang)) * (r if k % 2 == 0 else r * 0.45))
			_overlay.draw_polyline(pts, c, 1.4, true)

## Column letters along the near edge, row numbers down the left.
func _draw_grid_labels(font: Font) -> void:
	var c := Color(HOLO, 0.55)
	for col in range(int(map.dims.x)):
		var p := _proj(Vector2((col + 0.5) / map.dims.x, 1.0), -HoloTerrain.PLATE_DEPTH, false) + Vector2(0, 14)
		_overlay.draw_string(font, p - Vector2(10, 0), char(65 + col), HORIZONTAL_ALIGNMENT_CENTER, 20, 10, c)
	for row in range(int(map.dims.y)):
		var p := _proj(Vector2(0.0, (row + 0.5) / map.dims.y), -HoloTerrain.PLATE_DEPTH, false) + Vector2(-18, 4)
		_overlay.draw_string(font, p - Vector2(10, 0), str(row + 1), HORIZONTAL_ALIGNMENT_RIGHT, 20, 10, c)

## The title strip and the legend, on glass.
func _draw_hud(font: Font) -> void:
	var a := 1.0
	var title := Rect2(Vector2(size.x / 2.0 - 230.0, 10), Vector2(460, 44))
	GlassPanel.draw_glass(_overlay, title, a, HOLO, 7.0, 0.8)
	_overlay.draw_string(font, title.position + Vector2(0, 19), "WAR TABLE  ·  THEATER %s" % _theater_code(), HORIZONTAL_ALIGNMENT_CENTER, title.size.x, 14, Color(Color("dffcf8"), a))
	_overlay.draw_string(font, title.position + Vector2(0, 36), "Pick a location to drop in. The front shifts with every sector roll.", HORIZONTAL_ALIGNMENT_CENTER, title.size.x, 11, Color(Color("9fc9c4"), a))
	var legend := Rect2(Vector2(14, size.y - 50), Vector2(520, 36))
	GlassPanel.draw_glass(_overlay, legend, a, HOLO, 6.0, 0.6)
	var x := legend.position.x + 16.0
	var y := legend.get_center().y
	var items := [["objective", "Hostile objective"], ["hostile", "Enemy unit"], ["ours", "Our unit"], ["front", "Front line"], ["route", "Route"]]
	for it in items:
		var p := Vector2(x + 8.0, y)
		match it[0]:
			"objective":
				var s := 7.0
				var poly := PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0), p + Vector2(0, -s)])
				_overlay.draw_polyline(poly, Color(Color("ff8a5c"), a), 1.8)
			"hostile":
				_draw_unit(p, true, "mech", 0.8)
			"ours":
				_draw_unit(p, false, "armor", 0.8)
			"front":
				_overlay.draw_line(p - Vector2(9, 0), p + Vector2(9, 0), Color(Color("ff9a6a"), a), 1.8)
				_overlay.draw_arc(p, 4.0, PI, TAU, 8, Color(Color("ff9a6a"), a), 1.5)
			"route":
				_overlay.draw_line(p - Vector2(9, 0), p - Vector2(2, 0), Color(HOLO, a), 1.5)
				_overlay.draw_line(p + Vector2(2, 0), p + Vector2(9, 0), Color(HOLO, a), 1.5)
		_overlay.draw_string(font, Vector2(x + 22.0, y + 4.0), it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(Color("b9d8d4"), a))
		x += 30.0 + font.get_string_size(it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 12.0
	legend.size.x = x - legend.position.x
	# scale bar and north arrow
	var sb := Vector2(size.x - 200.0, size.y - 30.0)
	var km := _proj(Vector2(0.5 + 1.0 / map.dims.x, 0.9), 0.0, false).x - _proj(Vector2(0.5, 0.9), 0.0, false).x
	_overlay.draw_line(sb, sb + Vector2(km, 0), Color(HOLO, 0.8 * a), 2.0)
	for k in [0.0, 1.0]:
		_overlay.draw_line(sb + Vector2(km * k, -4), sb + Vector2(km * k, 4), Color(HOLO, 0.8 * a), 1.5)
	_overlay.draw_string(font, sb + Vector2(km + 8.0, 4), "1 grid = 2 km", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(Color("9fc9c4"), a))
	var n := Vector2(size.x - 40.0, 30.0)
	_overlay.draw_colored_polygon(PackedVector2Array([n + Vector2(0, -12), n + Vector2(6, 6), n + Vector2(0, 2), n + Vector2(-6, 6)]), Color(HOLO, 0.8 * a))
	_overlay.draw_string(font, n + Vector2(-10, 22), "N", HORIZONTAL_ALIGNMENT_CENTER, 20, 11, Color(HOLO, a))

## A short code for this theater, from its seed ("K-47").
func _theater_code() -> String:
	return "%s-%02d" % [char(65 + map.seed_value % 26), (map.seed_value / 26) % 100]

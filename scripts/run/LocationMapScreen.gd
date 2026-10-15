class_name LocationMapScreen
extends Control
## A location's encounter map (Slay the Spire style), as a hologram of the
## location's ground (HoloTerrain over WarMap.location_terrain, seeded by
## the run and shaped by the location's `map_zone`: a coast, a mining flank,
## the backlines). Each stop stands on a pin over the terrain, from the
## starting spots at the near edge to the last stop (the boss) at the far
## one, with the routes between them drawn over the ground: the path taken
## so far solid, the links on offer bright, the rest faint. The pilot picks
## a starting spot, fights, comes back here after each stop, and picks one
## linked to the one just finished. Glass screens: the mission on the left,
## the hovered stop on the right. Settings has Eject, which ends the run.
## Right after Launch the Operator's deployment orders (OrdersPanel) sit over
## the map until one is taken; Blind Drop hides every row past the next two.
##
## peek(): the same map over a fight or a stop's screen (the Map button,
## Logan 2026-10-02), to look only: hovering shows routes, nothing can be
## picked, the game under it is paused, and Close (or Esc, or the map key)
## shuts it.

signal closed()

const SCENE := "res://scenes/LocationMap.tscn"

## Opened over another screen, to look only.
var peeking: bool = false
## The stops taken (peeking: and the one you're at), and the ones on offer
## from the last of them.
var _path: Array = []
var _offered: Array = []

const TOP_BAR_H := TopBar.HEIGHT
const MAP_DIMS := Vector2(8.0, 12.0)
const PITCH := 58.0
const SIDE_W := 250.0          # the glass screens either side of the map
const STEM := 24.0             # a stop's badge height above its ground
const U_RANGE := Vector2(0.12, 0.88)
const V_RANGE := Vector2(0.94, 0.07) # the first row near, the last far
const DASH := 6.0
const LEFT := Rect2(12, TOP_BAR_H + 12.0, SIDE_W, 300)
const RIGHT_W := SIDE_W

var run: RunData
var _terrain: HoloTerrain
var _nodes: Dictionary = {} # id -> MapNodeUI
var _uv: Dictionary = {}    # id -> map UV
var _map_layer: Control
var _left: GlassPanel
var _right: GlassPanel
var _info_title: Label
var _info_body: Label
var _progress: Label
var _hp: Label
var _settings_button: SettingsButton
var settings_menu: SettingsMenu
var _time: float = 0.0
var _hover_id: int = -1
## Path preview: the links on every route from where you are, through the
## hovered stop, to the end ("from:to" -> true).
var _preview: Dictionary = {}
var _shown: float = 0.0 # markers fade in once the ground has risen
var _orders: OrdersPanel

## Opens the map over the current screen, pausing it until it's closed.
static func peek(host: Node) -> void:
	if not RunState.is_active() or host.get_tree().paused:
		return
	var layer := CanvasLayer.new()
	layer.layer = 120
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var map: Control = load(SCENE).instantiate()
	map.peeking = true
	layer.add_child(map)
	host.get_tree().root.add_child(layer)
	host.get_tree().paused = true
	map.closed.connect(func():
		host.get_tree().paused = false
		layer.queue_free())

func _ready() -> void:
	if not peeking:
		UIState.reset()
		get_tree().paused = false
	if not RunState.is_active():
		SceneRouter.go.call_deferred(SceneRouter.WAR_ROOM)
		return
	run = RunState.run
	_path = run.path.duplicate()
	_offered = run.available_nodes()
	if peeking and run.current_node_id >= 0 and not _path.has(run.current_node_id):
		_path.append(run.current_node_id)
		_offered = run.map.get_map_node(run.current_node_id)["next"].duplicate()
	if not peeking:
		Audio.music("map")
		Audio.ambience(Audio.location_ambience(run.location))
	_terrain = HoloTerrain.new()
	_terrain.pitch = PITCH
	_terrain.yaw_sway = 1.5
	_terrain.inset_top = TOP_BAR_H + 14.0
	_terrain.inset_bottom = 18.0
	_terrain.inset_side = SIDE_W + 30.0
	add_child(_terrain)
	_terrain.setup(WarMap.location_terrain(run.seed_value, str(run.location.get("map_zone", "")), MAP_DIMS))

	_map_layer = Control.new()
	_map_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_layer.draw.connect(_draw_map)
	add_child(_map_layer)
	# A map of two rows (training) puts its second at mid-map, not at the far edge.
	var rows := maxi(run.map.row_count - 1, 2)
	for n in run.map.nodes:
		var ui := MapNodeUI.new()
		add_child(ui)
		ui.setup(n["id"], n["kind"], n["enemy_count"], _state_for(n["id"]))
		ui.pressed.connect(_on_node_pressed)
		ui.hover_changed.connect(_on_node_hover)
		ui.modulate.a = 0.0
		_nodes[n["id"]] = ui
		var t := float(n["row"]) / rows
		_uv[n["id"]] = Vector2(lerpf(U_RANGE.x, U_RANGE.y, float(n["x"])), lerpf(V_RANGE.x, V_RANGE.y, t))

	_build_panels()
	_build_top_bar()
	if not peeking:
		settings_menu = SettingsMenu.new()
		settings_menu.z_index = 400
		settings_menu.restart_requested.connect(_eject)
		add_child(settings_menu)
		settings_menu.set_restart_action("Eject (ends the mission)", "Click again to eject")
		_settings_button.pressed.connect(settings_menu.open)
	if run.orders_pending() and not peeking:
		_orders = OrdersPanel.new()
		_orders.z_index = 300
		add_child(_orders)
		_orders.setup(run)
		_orders.done.connect(func(): if not SceneRouter.is_busy(): RunState.advance())

	get_viewport().size_changed.connect(_layout)
	_layout()
	_show_default_info()
	var tw := _terrain.project_in(0.7)
	tw.tween_property(self, "_shown", 1.0, 0.3).set_delay(0.5)
	await tw.finished
	if peeking:
		return
	var open: Array = run.available_nodes().map(func(id): return _nodes[id])
	Tutorial.reached("location_map", {"starts": open})

func _state_for(id: int) -> MapNodeUI.State:
	if _path.has(id):
		return MapNodeUI.State.CLEARED
	if _offered.has(id):
		return MapNodeUI.State.AVAILABLE
	return MapNodeUI.State.LOCKED

func _layout() -> void:
	var screen: Vector2 = get_viewport_rect().size
	size = screen
	_terrain.position = Vector2.ZERO
	_terrain.size = screen
	_map_layer.size = screen
	_right.position = Vector2(screen.x - RIGHT_W - 12.0, TOP_BAR_H + 12.0)
	_place_nodes()

## Each stop's badge on its pin over the ground (boss badges bigger; long
## maps get smaller badges).
func _place_nodes() -> void:
	var k := clampf(float(9) / float(maxi(run.map.row_count, 1)), 0.72, 1.0)
	for n in run.map.nodes:
		var ui: MapNodeUI = _nodes[n["id"]]
		var p := _terrain.proj(_uv[n["id"]]) + Vector2(0, -STEM * k)
		var sk := k * (1.3 if n["kind"] == RunMap.KIND_BOSS else 1.0)
		ui.scale = Vector2(sk, sk)
		ui.position = p - Vector2(MapNodeUI.SIZE.x / 2.0, MapNodeUI.RADIUS + 2.0) * sk

func _process(delta: float) -> void:
	if run == null:
		return
	_time += delta
	_place_nodes()
	for ui in _nodes.values():
		ui.modulate.a = _shown
	for id in _nodes:
		_nodes[id].visible = not _fogged(id)
	_map_layer.queue_redraw()

## Blind Drop and Low Visibility: only the stops done, and the next few
## rows, can be seen (the shorter sight when both apply).
func _fogged(id: int) -> bool:
	var sights := [int(run.mod("fog", 0)), Conditions.sight_rows(run.mission)].filter(func(s): return s > 0)
	var sight: int = sights.min() if not sights.is_empty() else 0
	if sight <= 0 or _path.has(id):
		return false
	var frontier: int = 0 if _path.is_empty() else int(run.map.get_map_node(_path[-1])["row"]) + 1
	return int(run.map.get_map_node(id)["row"]) > frontier + sight - 1

# ---------- glass screens ----------

func _build_panels() -> void:
	_left = GlassPanel.new()
	_left.position = LEFT.position
	_left.size = LEFT.size
	_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_left)
	var box := VBoxContainer.new()
	box.position = Vector2(14, 12)
	box.size = LEFT.size - Vector2(28, 24)
	box.add_theme_constant_override("separation", 5)
	_left.add_child(box)
	box.add_child(UIKit.label("OPERATION", 10, Color("7f9d9a")))
	box.add_child(UIKit.label(str(run.location.get("name", "")), 20, Color("dffcf8")))
	if run.mission_name() != "":
		box.add_child(UIKit.label(run.mission_name().to_upper(), 12, Palette.LINK))
		var summary := UIKit.label(str(run.mission.get("summary", "")), 11, Color("9fb9b6"), true)
		box.add_child(summary)
	var rule := ColorRect.new()
	rule.color = Color(GlassPanel.HOLO, 0.35)
	rule.custom_minimum_size = Vector2(0, 1)
	box.add_child(rule)
	var refits: Array = []
	for r in run.refit_rows():
		refits.append(str(int(r) + 1))
	box.add_child(UIKit.label("Encounter %d of %d" % [_path.size(), run.encounter_count()], 12, Palette.TEXT))
	if not refits.is_empty():
		box.add_child(UIKit.label("Refit after encounters %s" % ", ".join(refits), 11, Palette.REACTOR, true))
	if not run.mission.get("alert", {}).is_empty():
		var alert := UIKit.label("Alert %d: rises every %d turns spent fighting." % [run.alert_tier(), int(run.mission["alert"].get("turns_per_tier", 6))], 11, Palette.DANGER if run.alert_tier() > 0 else Color("9fb9b6"), true)
		box.add_child(alert)
	for line in Conditions.describe(run.location, run.mission):
		box.add_child(UIKit.label(line, 10, Palette.WARNING, true))
	var chosen: String = run.orders.get("chosen", "")
	if chosen != "":
		box.add_child(UIKit.label("ORDERS  ·  %s" % DeploymentOrders.title(chosen).to_upper(), 11, Palette.LINK))
		box.add_child(UIKit.label(DeploymentOrders.text(chosen), 10, Color("9fb9b6"), true))
	box.add_child(UIKit.seed_row(run.seed_value))
	_left.size.y = 300.0
	(func(): _left.size.y = maxf(300.0, box.get_combined_minimum_size().y + 24.0)).call_deferred() # room for the orders' text

	_right = GlassPanel.new()
	_right.size = Vector2(RIGHT_W, 150)
	_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_right)
	var rbox := VBoxContainer.new()
	rbox.position = Vector2(14, 12)
	rbox.size = _right.size - Vector2(28, 24)
	rbox.add_theme_constant_override("separation", 6)
	_right.add_child(rbox)
	rbox.add_child(UIKit.label("NEXT ENCOUNTER", 10, Color("7f9d9a")))
	_info_title = UIKit.label("", 17, Color("dffcf8"), true)
	rbox.add_child(_info_title)
	_info_body = UIKit.label("", 12, Color("b9d8d4"), true)
	rbox.add_child(_info_body)

func _show_default_info() -> void:
	if peeking:
		_info_title.text = "You are here"
		_info_title.add_theme_color_override("font_color", Color("dffcf8"))
		_info_body.text = "The green route is the way you came; the orange links are where you can go next. Hover an encounter to see what's there."
		return
	_info_title.text = "Choose a starting spot" if _path.is_empty() else "Choose your next encounter"
	_info_title.add_theme_color_override("font_color", Color("dffcf8"))
	_info_body.text = "The lit encounters are linked to where you are. Hover one to see what's there."

func _build_top_bar() -> void:
	var bar := TopBar.make(self, run.location.get("name", ""))
	var row := bar.row
	row.add_child(FeedbackDialog.button())
	if run.mission_name() != "":
		row.add_child(_bar_label(run.mission_name().to_upper(), 12, Palette.LINK))
	if not run.mission.get("alert", {}).is_empty():
		var alert := _bar_label("Alert %d" % run.alert_tier(), 12, Palette.DANGER if run.alert_tier() > 0 else Palette.TEXT_MUTED)
		alert.tooltip_text = "Rises every 6 turns spent fighting. Each level braces every enemy with Deflect 2; from level 3, smaller fights get a reinforcement."
		alert.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(alert)
	_progress = _bar_label("ENCOUNTER %d / %d" % [_path.size(), run.encounter_count()], 12, Color("8fd8d0"))
	row.add_child(_progress)
	row.add_child(UIKit.spacer())
	row.add_child(TopBar.chip(UIKit.scraps_label(run.scraps, 14), Palette.SCRAPS))
	var mech := run.player_mech
	_hp = _bar_label("%s  %d / %d HP" % [mech.name, mech.current_hp(), mech.max_hp()], 13, Palette.TEXT)
	if mech.current_hp() < mech.max_hp():
		_hp.add_theme_color_override("font_color", Palette.WARNING)
	row.add_child(TopBar.chip(_hp))
	if peeking:
		var close := GlassPanel.button("Close map", 13, true)
		close.custom_minimum_size = Vector2(120, TopBar.CHIP_H)
		close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		close.pressed.connect(func(): closed.emit())
		row.add_child(close)
		return
	_settings_button = SettingsButton.new()
	_settings_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_settings_button)

func _bar_label(text: String, font_size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", c)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l

func _on_node_hover(id: int, hovering: bool) -> void:
	if not hovering:
		if _hover_id == id:
			_hover_id = -1
			_preview.clear()
			_show_default_info()
		return
	_hover_id = id
	_preview_routes(id)
	Audio.play("holo", 0.04, -8.0)
	var n := run.map.get_map_node(id)
	var title := ""
	var body := ""
	match n["kind"]:
		RunMap.KIND_REPAIR:
			title = "Repair bay"
			body = "Patch your parts up: a pool of %d HP to hand out (%d%% of your max HP, at most %d). Wrecked parts can't be fixed." % [
				Economy.repair_pool(run.player_mech.max_hp(), float(run.mod("repair_mult", 1.0))),
				roundi(Balance.get_num("economy", "repair_pool_fraction", 0.5) * float(run.mod("repair_mult", 1.0)) * 100.0),
				int(Balance.get_num("economy", "repair_pool_max", 75))]
		RunMap.KIND_SHOP:
			title = "Autonomous bay"
			body = "Spend scraps: parts, a bigger Cargo, frame squares; sell or refine what you carry."
		RunMap.KIND_EVENT:
			title = "Unknown"
			body = "Something's out there: a choice, usually a gain with a cost. Now and then it's an autonomous bay."
		_:
			title = {RunMap.KIND_ELITE: "Elite fight", RunMap.KIND_BOSS: "Boss"}.get(n["kind"], "Fight")
			body = _enemy_names(n["enemies"]) if not (n["enemies"] as Array).is_empty() else "Hostiles unknown."
			body += {RunMap.KIND_ELITE: "\nTougher fight; more scraps and better salvage odds.", RunMap.KIND_BOSS: "\nThe last encounter: beat it to clear the mission."}.get(n["kind"], "\nWin for scraps and a salvage pick.")
	var where := ("You're here." if peeking and id == run.current_node_id else "Done.") if _path.has(id) else ("Encounter %d of %d." % [int(n["row"]) + 1, run.encounter_count()])
	if run.is_refit_row(n["row"]) and not _path.has(id):
		where += " Refit after."
	_info_title.text = title
	_info_title.add_theme_color_override("font_color", Palette.LINK if _offered.has(id) else Color("dffcf8"))
	_info_body.text = "%s\n%s%s" % [body, where, _beyond(id)]

## Every stop reachable from `ids` (them included).
func _reach(ids: Array) -> Dictionary:
	var seen := {}
	var todo := ids.duplicate()
	while not todo.is_empty():
		var id: int = todo.pop_back()
		if seen.has(id):
			continue
		seen[id] = true
		todo.append_array(run.map.get_map_node(id)["next"])
	return seen

## The links on every route from where you are, through `id`, to the end.
func _preview_routes(id: int) -> void:
	_preview.clear()
	if _path.has(id):
		return
	var start: Array = [_path[-1]] if not _path.is_empty() else run.map.nodes_in_row(0).map(func(n): return n["id"])
	var from_start := _reach(start)
	if not from_start.has(id):
		return
	var after := _reach([id])
	var before := {}
	for n_id in from_start:
		if _reach([n_id]).has(id):
			before[n_id] = true
	for n in run.map.nodes:
		for to_id in n["next"]:
			if (before.has(n["id"]) and before.has(to_id)) or (after.has(n["id"]) and after.has(to_id)):
				_preview["%d:%d" % [n["id"], to_id]] = true

## "Beyond it: 2 autonomous bays, 1 repair bay, 3 elites" (what the routes
## through a stop can still reach).
func _beyond(id: int) -> String:
	if _path.has(id) or _fogged(id):
		return ""
	var counts := {}
	for n_id in _reach([id]):
		if n_id != id and not _fogged(n_id):
			var k: String = run.map.get_map_node(n_id)["kind"]
			counts[k] = int(counts.get(k, 0)) + 1
	var parts: Array[String] = []
	for kv in [[RunMap.KIND_SHOP, "autonomous bay"], [RunMap.KIND_REPAIR, "repair bay"], [RunMap.KIND_ELITE, "elite"], [RunMap.KIND_EVENT, "unknown"]]:
		var n := int(counts.get(kv[0], 0))
		if n > 0:
			parts.append("%d %s%s" % [n, kv[1], "" if n == 1 else "s"])
	return "" if parts.is_empty() else "\nBeyond it: " + ", ".join(parts) + "."

## "Scrap Warden, 2 Rivet Brutes" from mech ids.
static func _enemy_names(ids: Array) -> String:
	var counts := {}
	var order: Array = []
	for id in ids:
		if not counts.has(id):
			order.append(id)
		counts[id] = int(counts.get(id, 0)) + 1
	var parts: Array[String] = []
	for id in order:
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/mechs/%s.json" % id))
		var name: String = d.get("name", id) if typeof(d) == TYPE_DICTIONARY else id
		parts.append(name if counts[id] == 1 else "%d %ss" % [counts[id], name])
	return ", ".join(parts)

## Peeking: Esc or the map key closes it (before anything under it sees the key).
func _input(event: InputEvent) -> void:
	if not peeking or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE or GameSettings.is_key(event, "map"):
		get_viewport().set_input_as_handled()
		closed.emit()

func _on_node_pressed(id: int) -> void:
	if peeking:
		return
	if run.orders_pending() and _orders != null:
		_orders.show_panel()
		return
	if SceneRouter.is_busy() or not run.choose_node(id):
		return
	Tutorial.event("node_chosen")
	RunState.advance() # a fight, a repair bay or an autonomous bay

func _eject() -> void:
	run.eject()
	RunState.advance()

# ---------- the routes and pins over the ground ----------

## A link from one stop to the next, following the ground.
func _route(from_id: int, to_id: int) -> PackedVector2Array:
	var a: Vector2 = _uv[from_id]
	var b: Vector2 = _uv[to_id]
	var pts := PackedVector2Array()
	for i in range(13):
		pts.append(a.lerp(b, i / 12.0))
	return _terrain.proj_line(pts, 0.03)

func _draw_map() -> void:
	if _shown <= 0.0:
		return
	var ci := _map_layer
	ci.modulate.a = _shown
	var last: int = _path[-1] if not _path.is_empty() else -1
	var offered := _offered
	for n in run.map.nodes:
		for to_id in n["next"]:
			if _fogged(n["id"]) or _fogged(to_id):
				continue
			var pts := _route(n["id"], to_id)
			var i := _path.find(n["id"])
			if i >= 0 and i + 1 < _path.size() and _path[i + 1] == to_id:
				ci.draw_polyline(pts, Color(Palette.OK, 0.35), 6.0, true)
				ci.draw_polyline(pts, Palette.OK, 2.2, true)
			elif n["id"] == last:
				var lit: bool = to_id == _hover_id or _preview.has("%d:%d" % [n["id"], to_id])
				HoloTerrain.draw_dashed(ci, pts, DASH, 5.0, -_time * 18.0, Palette.LINK if lit else Palette.HARDPOINT, 2.6 if lit else 2.0)
			elif _preview.has("%d:%d" % [n["id"], to_id]): # a route through the hovered stop
				ci.draw_polyline(pts, Color(Palette.LINK, 0.12), 6.0, true)
				HoloTerrain.draw_dashed(ci, pts, DASH, 6.0, -_time * 12.0, Color(Palette.LINK, 0.75), 1.8)
			else:
				HoloTerrain.draw_dashed(ci, pts, DASH, 6.0, 0.0, Color(GlassPanel.HOLO, 0.28), 1.2)
	# ground rings and pins
	for n in run.map.nodes:
		var id: int = n["id"]
		if _fogged(id):
			continue
		var ui: MapNodeUI = _nodes[id]
		var g := _terrain.proj(_uv[id])
		var c := Palette.OK if _path.has(id) else (Palette.LINK if id == _hover_id else (Palette.HARDPOINT if offered.has(id) else Color(GlassPanel.HOLO, 0.55)))
		var r := 0.22 if n["kind"] == RunMap.KIND_BOSS else 0.14
		ci.draw_polyline(_terrain.ground_ring(_uv[id], r), Color(c, 0.6), 1.2, true)
		if offered.has(id):
			var pulse := 0.5 + 0.5 * sin(_time * 3.0 + float(id))
			ci.draw_polyline(_terrain.ground_ring(_uv[id], r + 0.06 + pulse * 0.12), Color(c, 0.4 * (1.0 - pulse)), 1.2, true)
		ci.draw_line(g, ui.center(), Color(c, 0.25), 4.0)
		ci.draw_line(g, ui.center(), Color(c, 0.8), 1.2)
	_draw_refit_tags()

## "REFIT AFTER" chips left of the rows after which a refit is offered.
func _draw_refit_tags() -> void:
	var font := get_theme_default_font()
	for r in run.refit_rows():
		if not run.is_refit_row(r):
			continue
		var row := run.map.nodes_in_row(r)
		if row.is_empty() or _fogged(row[0]["id"]):
			continue
		var left := Vector2(INF, 0)
		for n in row:
			var c: Vector2 = _nodes[n["id"]].center()
			if c.x < left.x:
				left = c
		var chip := Rect2(left + Vector2(-128, -10), Vector2(84, 20))
		GlassPanel.draw_glass(_map_layer, chip, 1.0, Palette.REACTOR, 4.0, 0.8)
		_map_layer.draw_string(font, chip.position + Vector2(0, 14), "REFIT AFTER", HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, 10, Palette.REACTOR)
		_map_layer.draw_line(Vector2(chip.end.x, left.y), left - Vector2(26, 0), Color(Palette.REACTOR, 0.45), 1.2)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BG, true)
	# a faint floor glow under the hologram
	var c := size / 2.0 + Vector2(0, 40)
	for i in range(6):
		draw_circle(c, 420.0 - i * 60.0, Color(GlassPanel.HOLO, 0.012))

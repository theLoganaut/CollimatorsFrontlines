class_name LocationPopup
extends Control
## Info on one sector map location, on a holo glass screen projected from
## its marker on the War Table's map (a beam from the marker, then the glass
## unfolds from the beam's end): where it is, its name and description
## (placeholders in data/sectors.json for now), the rolled mission, the
## stops and mech, an optional seed (the same seed replays the same run), and
## Launch. Clicking outside the panel or Cancel closes it. open_continue()
## reuses it, centered, for a saved run: Continue, or Abandon (which ejects).

signal launch_pressed(location: Dictionary)
signal continue_pressed()
signal abandon_pressed()
signal closed()
## Launch pressed on the Daily Operation (open_daily).
signal daily_launch_pressed()

const PANEL_SIZE := Vector2(400, 330)
const PAD := 20.0
const BEAM_GAP := 40.0
const TOP_MARGIN := 57.0
const HOSTILE_TEXT := Color("ff9a6a")

var _location: Dictionary = {}
var _panel: GlassPanel
var _where: Label
var _name: Label
var _desc: Label
var _mission: Label
var _summary: Label
var _facts: Label
var _seed: LineEdit
var _primary: Button
var _secondary: Button
var _continue_mode: bool = false
var _abandon_armed: bool = false
var _from: Rect2 = Rect2()         # the marker it projects from (empty: centered)
var _anchor: Vector2 = Vector2.INF # the beam's emitter on its side (INF: centered)
var _attach: Vector2
var _beam: float = 0.0
var _vbox: VBoxContainer
var _spacer: Control
var _buttons: HBoxContainer
const CONTINUE_W := 340.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_panel = GlassPanel.new()
	_panel.tint = 0.9
	_panel.size = PANEL_SIZE
	add_child(_panel)

	var vbox := VBoxContainer.new()
	_vbox = vbox
	vbox.position = Vector2(PAD, PAD - 4.0)
	vbox.size = PANEL_SIZE - Vector2(PAD * 2.0, PAD * 2.0 - 8.0)
	vbox.add_theme_constant_override("separation", 5)
	_panel.add_child(vbox)
	_where = _label(vbox, 10, HOSTILE_TEXT)
	_name = _label(vbox, 22, Color("dffcf8"))
	_desc = _label(vbox, 13, Color("9fb9b6"))
	vbox.add_child(_rule())
	_mission = _label(vbox, 12, Palette.LINK)
	_summary = _label(vbox, 12, Palette.TEXT)
	_facts = _label(vbox, 12, Color("b9d8d4"))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 2)
	vbox.add_child(gap)
	_seed = LineEdit.new()
	_seed.placeholder_text = "Seed (optional, blank = random)"
	_seed.custom_minimum_size = Vector2(0, 32)
	_seed.max_length = 9
	_seed.add_theme_font_size_override("font_size", 12)
	_seed.add_theme_stylebox_override("normal", GlassPanel.control_style())
	_seed.add_theme_stylebox_override("focus", GlassPanel.control_style(Palette.LINK, 0.0, 0.8))
	_seed.add_theme_color_override("font_color", Palette.TEXT)
	_seed.add_theme_color_override("font_placeholder_color", Color("7f9d9a"))
	vbox.add_child(_seed)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)
	_spacer = spacer

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(row)
	_buttons = row
	_secondary = GlassPanel.button("Cancel", 14)
	_secondary.custom_minimum_size = Vector2(120, 40)
	_secondary.pressed.connect(_on_secondary)
	row.add_child(_secondary)
	_primary = GlassPanel.button("Launch", 15, true, Palette.HARDPOINT)
	_primary.custom_minimum_size = Vector2(130, 40)
	_primary.pressed.connect(_on_primary)
	row.add_child(_primary)

func _on_primary() -> void:
	if _continue_mode:
		continue_pressed.emit()
	elif _daily_mode:
		daily_launch_pressed.emit()
	else:
		launch_pressed.emit(_location)

func _on_secondary() -> void:
	if not _continue_mode:
		close()
	elif not _abandon_armed:
		_abandon_armed = true
		_secondary.text = "Click again to eject"
	else:
		abandon_pressed.emit()

## The typed seed, or -1 for a random one.
func seed_value() -> int:
	var t := _seed.text.strip_edges()
	return int(t) if t.is_valid_int() and int(t) >= 0 else -1

func _label(parent: Control, font_size: int, c: Color) -> Label:
	var l := UIKit.label("", font_size, c, true)
	parent.add_child(l)
	return l

func _rule() -> Control:
	var r := ColorRect.new()
	r.color = Color(GlassPanel.HOLO, 0.35)
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

## A location: `anchor` (global) is its marker and name on the map, `grid`
## its grid reference.
func open(location: Dictionary, mission: Dictionary, anchor: Rect2 = Rect2(), grid: String = "") -> void:
	_set_compact(false)
	_location = location
	_where.text = "HOSTILE OBJECTIVE" + ("  ·  GRID %s" % grid if grid != "" else "")
	_where.add_theme_color_override("font_color", HOSTILE_TEXT)
	_name.text = location.get("name", "")
	_desc.text = location.get("description", "")
	_desc.visible = true
	var stops: int = int(mission.get("rows", 7)) + (1 if mission.get("boss", false) else 0)
	var variant := Conditions.variant(mission)
	_mission.text = "MISSION  ·  %s%s" % [str(mission.get("name", "")).to_upper(), "" if variant.is_empty() else "  ·  " + str(variant.get("name", "")).to_upper()]
	_mission.visible = true
	_summary.text = mission.get("summary", "")
	var rules: Array[String] = []
	if not mission.get("training", false):
		rules = Conditions.describe(location, mission)
	if not rules.is_empty():
		_summary.text += "\n\n" + "\n".join(rules)
	_facts.text = "%d encounters  ·  Mech: %s (change it in the Hangar)" % [stops, Profile.mech.capitalize()]
	_continue_mode = false
	_daily_mode = false
	_primary.disabled = false
	_seed.visible = true
	_seed.text = ""
	_primary.text = "Launch"
	_secondary.text = "Cancel"
	_show(anchor)

var _daily_mode: bool = false

## Today's Daily Operation (Daily.setup): where, the mission and its
## variant, the mech; Launch uses today's one scored attempt.
func open_daily(d: Dictionary, anchor: Rect2 = Rect2()) -> void:
	var location: Dictionary = d["location"]
	var mission: Dictionary = d["mission"]
	open(location, mission, anchor)
	_daily_mode = true
	_where.text = "DAILY OPERATION  ·  %s" % d["date"]
	_where.add_theme_color_override("font_color", Palette.LINK)
	var stops: int = int(mission.get("rows", 7)) + (1 if mission.get("boss", false) else 0)
	var played := Profile.daily_played_today()
	var best := int(Profile.daily.get("best", 0))
	var lines := ["%d encounters  ·  Mech: %s (its standard loadout)  ·  seed %d" % [stops, str(d["mech"]).capitalize(), int(d["seed"])],
		"The same mission for every pilot today. One scored attempt."]
	if played:
		lines.append("Today's score: %d%s" % [int(Profile.daily.get("score", 0)), "" if str(Profile.daily.get("result", "")) != "" else " (in progress)"])
	if best > 0:
		lines.append("Your best: %d (%s)" % [best, Profile.daily.get("best_date", "")])
	_facts.text = "\n".join(lines)
	_seed.visible = false
	_primary.text = "Done for today" if played else "Launch daily"
	_primary.disabled = played

## A saved run: where it is, and Continue / Abandon.
func open_continue(summary: Dictionary) -> void:
	var loc: Dictionary = summary.get("location", {})
	var mission: Dictionary = summary.get("mission", {})
	var total: int = int(mission.get("rows", 7)) + (1 if mission.get("boss", false) else 0)
	_where.text = "MISSION IN PROGRESS"
	_where.add_theme_color_override("font_color", Palette.LINK)
	_name.text = loc.get("name", "")
	_desc.visible = false
	# the encounter it picks up at: the ones done, plus the one it's on or about to choose
	_mission.text = "%s  ·  ENCOUNTER %d / %d" % [str(mission.get("name", "")).to_upper(), mini(int(summary.get("stops", 0)) + 1, total), total]
	_summary.text = "%s  %d / %d HP" % [str(summary.get("mech", "bastion")).capitalize(), summary.get("hp", 0), summary.get("max_hp", 0)]
	_facts.text = "%d scraps  ·  seed %d" % [summary.get("scraps", 0), summary.get("seed", 0)]
	_continue_mode = true
	_abandon_armed = false
	_seed.visible = false
	_primary.text = "Continue"
	_secondary.text = "Abandon (eject)"
	_set_compact(true)
	_show(Rect2())

## A saved run's box (Logan, 2026-10-02): everything centered, the glass
## only as big as what's on it. Off: the full, left-aligned location panel.
func _set_compact(on: bool) -> void:
	var align := HORIZONTAL_ALIGNMENT_CENTER if on else HORIZONTAL_ALIGNMENT_LEFT
	for l in [_where, _name, _desc, _mission, _summary, _facts]:
		l.horizontal_alignment = align
	_spacer.visible = not on
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER if on else BoxContainer.ALIGNMENT_END
	_panel.size = Vector2(CONTINUE_W, 200.0) if on else PANEL_SIZE
	_vbox.size = _panel.size - Vector2(PAD * 2.0, PAD * 2.0 - 8.0)
	_panel.queue_redraw()
	if on:
		_refit() # the wrapped lines know their height once laid out at this width

func _refit() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not _continue_mode:
		return
	var h := _vbox.get_combined_minimum_size().y
	_panel.size = Vector2(CONTINUE_W, h + PAD * 2.0 - 8.0)
	_vbox.size = Vector2(CONTINUE_W - PAD * 2.0, h)
	_place()
	_panel.queue_redraw()

func _show(anchor: Rect2) -> void:
	visible = true
	_from = Rect2(get_global_transform().affine_inverse() * anchor.position, anchor.size)
	_place()
	modulate.a = 1.0
	_beam = 0.0
	_panel.scale = Vector2(0.04, 0.04)
	_panel.modulate.a = 0.0
	var tw := create_tween()
	if _anchor != Vector2.INF:
		tw.tween_property(self, "_beam", 1.0, 0.1)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_panel, "modulate:a", 1.0, 0.12)
	Audio.play("holo", 0.03, -4.0)

## Beside the marker (right of it, or left if there's no room), level
## with it, the beam leaving from that side; centered without a marker.
func _place() -> void:
	if _from.size == Vector2.ZERO:
		_anchor = Vector2.INF
		_panel.position = ((size - _panel.size) / 2.0).floor()
		_panel.pivot_offset = _panel.size / 2.0
		return
	var right := _from.end.x + BEAM_GAP + PANEL_SIZE.x <= size.x - 12.0
	_anchor = Vector2(_from.end.x if right else _from.position.x, _from.get_center().y)
	var x := _anchor.x + BEAM_GAP if right else _anchor.x - BEAM_GAP - PANEL_SIZE.x
	var y := clampf(_anchor.y - PANEL_SIZE.y * 0.35, TOP_MARGIN, size.y - PANEL_SIZE.y - 12.0)
	_panel.position = Vector2(x, y).floor()
	_attach = Vector2(x if right else x + PANEL_SIZE.x, clampf(_anchor.y, y + 14.0, y + PANEL_SIZE.y - 14.0))
	_panel.pivot_offset = _attach - _panel.position

func close() -> void:
	if visible:
		visible = false
		closed.emit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _panel != null and visible:
		_place()

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55 if _anchor == Vector2.INF else 0.28), true)
	if _anchor == Vector2.INF or _beam <= 0.0:
		return
	var holo := GlassPanel.HOLO
	var tip := _anchor.lerp(_attach, _beam)
	draw_circle(_anchor, 6.0, Color(holo, 0.2))
	draw_circle(_anchor, 3.0, Color(holo, 0.95))
	draw_line(_anchor, tip, Color(holo, 0.25), 6.0, true)
	draw_line(_anchor, tip, Color(holo, 0.95), 1.6, true)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		close() # a click outside the panel (the panel eats its own clicks)

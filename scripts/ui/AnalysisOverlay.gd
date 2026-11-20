class_name AnalysisOverlay
extends Control
## Analyzed parts on screen (CombatManager.analyzed; Logan, 2026-11-19).
## The analyzed part (one across all the enemies) keeps a holo outline and an "ANALYZED ×1.5"
## tag all turn. As a turn's analysis comes in, the outline traces around
## the part; when the Operator speaks (the first turn of a fight), a line
## runs from the outline to an empty stretch of screen beside the enemies,
## where his comm panel types the line ("Found a weak point.").
## Draws over the panels; never takes the mouse.

const COLOR := Color("aaf6ff")
const TRACE_TIME := 0.7
const LEAD_TIME := 0.35
const HOLD := 2.6
const PANEL_W := 330.0
const MIN_W := 240.0
const EDGE := 40.0 # from the screen's side
const SPRITE_MARGIN := 34.0 # the mech's sprite reaches past its grid
const UNDER_X := 140.0 # under the enemies: clear of the Log button

var combat: CombatManager
## MechData -> ChassisGridUI (CombatScene._grid_for).
var grid_for: Callable
## Under the enemies the panel fits between your UI: left of your heat
## box, or right of your health bar and left of End Turn.
var keep_clear: Control = null # the heat box
var health_bar: Control = null
var end_turn: Control = null
var _t: float = 0.0
var _trace: float = 1.0 # 0..1: how much of the outline is drawn
var _lead: float = 0.0  # 0..1: the line out to the Operator's panel
var _panel: Control = null
var _anchor: Vector2 = Vector2.ZERO # where the line meets the panel (local)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 120

## This turn's analysis came in: trace the outlines, and if `speak`, the
## Operator says so from beside the enemies.
func announce(speak: bool) -> void:
	_drop_panel()
	if combat == null or combat.analyzed.is_empty():
		return
	_trace = 1.0 if GameSettings.reduce_motion else 0.0
	_lead = 0.0
	if speak:
		_show_operator(Operator.analysis_line())
	queue_redraw()

func _process(delta: float) -> void:
	_t += delta
	_place_panel()
	if _trace < 1.0:
		_trace = minf(1.0, _trace + delta / TRACE_TIME)
	elif _panel != null and _lead < 1.0:
		_lead = 1.0 if GameSettings.reduce_motion else minf(1.0, _lead + delta / LEAD_TIME)
		if _lead >= 1.0:
			_start_typing()
	queue_redraw()

func _draw() -> void:
	if combat == null:
		return
	var inv := get_global_transform().affine_inverse()
	var k := 0.85 if GameSettings.reduce_motion else 0.7 + 0.3 * sin(_t * 3.0)
	var mult := Balance.get_num("analysis", "damage_mult", 1.5)
	# The line out to the Operator runs from the nearest analyzed part only,
	# so it never crosses the other enemies.
	var lead_from := Vector2.INF
	for m in combat.analyzed:
		var comp: ComponentData = combat.analyzed[m]
		if comp.destroyed or (m as MechData).is_defeated() or not grid_for.is_valid():
			continue
		var grid: ChassisGridUI = grid_for.call(m)
		if grid == null or not grid.is_visible_in_tree():
			continue
		var segs := grid.outline_segments_global(comp)
		var n := segs.size() / 2
		if n == 0:
			continue
		var shown := ceili(n * _trace)
		var top_right := Vector2(-INF, INF)
		for i in range(n):
			var a: Vector2 = inv * segs[2 * i]
			var b: Vector2 = inv * segs[2 * i + 1]
			top_right = Vector2(maxf(top_right.x, maxf(a.x, b.x)), minf(top_right.y, minf(a.y, b.y)))
			if i >= shown:
				continue
			draw_line(a, b, Color(COLOR, 0.25 * k), 6.0)
			draw_line(a, b, Color(COLOR, k), 2.0)
		if _trace >= 1.0:
			_draw_tag(top_right, "ANALYZED ×%s" % _fmt(mult))
		if _panel != null and _lead > 0.0:
			var near := _nearest(segs, inv, _anchor)
			if near.distance_to(_anchor) < lead_from.distance_to(_anchor):
				lead_from = near
	if lead_from != Vector2.INF:
		var to := lead_from.lerp(_anchor, _lead)
		draw_line(lead_from, to, Color(COLOR, 0.3), 5.0)
		draw_line(lead_from, to, Color(COLOR, 0.9), 1.5)
		draw_circle(lead_from, 3.0, COLOR)

func _draw_tag(at: Vector2, text: String) -> void:
	var f := get_theme_default_font()
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 8.0
	var r := Rect2(at + Vector2(-w + 4.0, -18.0), Vector2(w, 15.0))
	draw_rect(r, Color(0.0, 0.04, 0.05, 0.85), true)
	draw_rect(r, Color(COLOR, 0.8), false, 1.0)
	draw_string(f, r.position + Vector2(4.0, 11.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR)

static func _fmt(x: float) -> String:
	return str(int(x)) if is_equal_approx(x, roundf(x)) else str(snappedf(x, 0.01))

## The outline point closest to `to` (local coordinates).
static func _nearest(segs: PackedVector2Array, inv: Transform2D, to: Vector2) -> Vector2:
	var best: Vector2 = inv * segs[0]
	for p in segs:
		var q: Vector2 = inv * p
		if q.distance_to(to) < best.distance_to(to):
			best = q
	return best

## The comm panel (laid out each frame by _place_panel: the enemies'
## panels are still sliding in as the first turn starts).
func _show_operator(text: String) -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", GlassPanel.panel_style(GlassPanel.HOLO, 10.0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var face := OperatorPortrait.new()
	face.custom_minimum_size = Vector2(64, 64)
	row.add_child(face)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	col.add_child(UIKit.label("OPERATOR", 11, Color("8fd8d0")))
	var line := UIKit.label(text, 16, Palette.TEXT)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.visible_ratio = 0.0
	col.add_child(line)
	panel.set_meta("line", line)
	panel.set_meta("face", face)
	panel.modulate.a = 0.0
	add_child(panel)
	_panel = panel
	_place_panel()
	if GameSettings.reduce_motion:
		_lead = 1.0
		_start_typing()

## Beside the enemies, on the side their analyzed parts lean to, in the
## empty band between them and your mech; where that gap is too narrow,
## under the enemies on that side, fitted between your UI (keep_clear,
## health_bar, end_turn) and clear of the Log button.
func _place_panel() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var screen := get_viewport_rect().size
	var sum := 0.0
	var count := 0
	var lo_x := screen.x
	var hi_x := 0.0
	var low_y := 0.0
	for m in combat.enemies:
		var grid: ChassisGridUI = grid_for.call(m) if grid_for.is_valid() else null
		if grid == null or not grid.is_visible_in_tree() or (m as MechData).is_defeated():
			continue
		var r := grid.get_global_rect().grow(SPRITE_MARGIN)
		lo_x = minf(lo_x, r.position.x)
		hi_x = maxf(hi_x, r.end.x)
		low_y = maxf(low_y, r.end.y)
		if combat.analyzed.has(m):
			sum += r.get_center().x
			count += 1
	var left := count == 0 or sum / count < screen.x / 2.0
	var gap := (lo_x - EDGE) if left else (screen.x - EDGE - hi_x)
	var under := gap < MIN_W
	var w := PANEL_W if under else clampf(gap, MIN_W, PANEL_W)
	_panel.custom_minimum_size = Vector2(w, 0)
	_panel.size = Vector2(w, 0)
	var x := EDGE if left else screen.x - EDGE - w
	if under:
		if left or not _ok(health_bar) or not _ok(end_turn):
			# left of your heat box, clear of the Log button
			left = true
			x = UNDER_X
			if _ok(keep_clear):
				w = clampf(keep_clear.get_global_rect().position.x - 12.0 - UNDER_X, MIN_W, PANEL_W)
		else: # between your health bar and End Turn
			var from := health_bar.get_global_rect().end.x + 12.0
			var to := end_turn.get_global_rect().position.x - 12.0
			w = clampf(to - from, MIN_W, PANEL_W)
			x = to - w
		_panel.custom_minimum_size = Vector2(w, 0)
		_panel.size = Vector2(w, 0)
	_panel.position = Vector2(x, low_y + 8.0 if under else screen.y * 0.42)
	_anchor = _panel.position + (Vector2(w / 2.0, 0.0) if under else Vector2(w if left else 0.0, 40.0))

static func _ok(c: Control) -> bool:
	return c != null and is_instance_valid(c) and c.is_visible_in_tree()

## The line reaches the panel: it shows, types its line, holds, fades.
func _start_typing() -> void:
	var panel := _panel
	if panel == null or panel.has_meta("typing"):
		return
	panel.set_meta("typing", true)
	var line: Label = panel.get_meta("line")
	var face: OperatorPortrait = panel.get_meta("face")
	face.talking = true
	var tw := panel.create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.15)
	if GameSettings.reduce_motion:
		line.visible_ratio = 1.0
	else:
		tw.tween_property(line, "visible_ratio", 1.0, 0.03 * line.text.length())
	tw.tween_callback(func(): face.talking = false)
	tw.tween_interval(HOLD)
	tw.tween_property(panel, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func():
		if _panel == panel:
			_drop_panel())

func _drop_panel() -> void:
	if _panel != null and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null
	_lead = 0.0

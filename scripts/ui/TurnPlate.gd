class_name TurnPlate
extends PanelContainer
## Top middle of the combat screen, level with the speed and settings
## buttons (Logan, 2026-10-02): one glass plate with where the fight is
## ("SHIPYARD", in a run only), how far along the run
## is ("ENCOUNTER 3 / 14", in a run only) and whose turn it is ("TURN 2",
## "ENEMY TURN", "DEPLOYING"). Its glass is as see-through as the Log
## button's (GlassPanel.control_style).

const HEIGHT := 40.0

var _location: Label
var _dot0: Label
var _encounter: Label
var _dot: Label
var _turn: Label

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := GlassPanel.control_style(GlassPanel.HOLO)
	st.content_margin_left = 18
	st.content_margin_right = 18
	add_theme_stylebox_override("panel", st)
	custom_minimum_size = Vector2(0, HEIGHT)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_location = UIKit.label("", 13, Color("dffcf8"))
	_location.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_location)
	_dot0 = UIKit.label("·", 14, Color(GlassPanel.HOLO, 0.7))
	_dot0.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_dot0)
	_encounter = UIKit.label("", 13, Color("8fd8d0"))
	_encounter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_encounter)
	_dot = UIKit.label("·", 14, Color(GlassPanel.HOLO, 0.7))
	_dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_dot)
	_turn = UIKit.label("", 15, Color("eefcfa"))
	_turn.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_turn)
	_sync()

func _draw() -> void:
	GlassPanel.draw_frame(self, Rect2(Vector2.ZERO, size), 0.8, GlassPanel.HOLO, 6.0)

## The run's encounter (1-based) out of its total; total 0 hides it.
func set_encounter(n: int, total: int) -> void:
	_encounter.text = "ENCOUNTER %d / %d" % [n, total] if total > 0 else ""
	_sync()

## Where the fight is (the run's location); "" hides it.
func set_location(text: String) -> void:
	_location.text = text.to_upper()
	_sync()

func set_turn_number(n: int) -> void:
	set_label("Turn %d" % n)

func set_label(text: String) -> void:
	_turn.text = text.to_upper()
	_sync()

func _sync() -> void:
	_location.visible = _location.text != ""
	_encounter.visible = _encounter.text != ""
	_dot0.visible = _location.visible and (_encounter.visible or _turn.text != "")
	_dot.visible = _encounter.visible and _turn.text != ""
	reset_size()

class_name PassiveIcon
extends Control
## One passive badge (a round icon, unlike the square intent icons): a
## component's always-on effect, placed on its mech's panel when the fight
## starts. Hovering it puts that passive in the Description Box. It pulses
## whenever the passive fires, and goes dark with a red slash once its
## component is destroyed. Placeholder vector glyphs, drawn in code.

const ICON_SIZE := Vector2(24, 24)

var component: ComponentData
var mech: MechData

var _pulse: float = 0.0
## A running count shown as a stack number, like a status badge's (High
## Five: each attack this turn is a stack; Logan, 2026-10-15). 0 = none.
var count: int = 0
var numbers_below: bool = true

func set_count(n: int) -> void:
	if n != count:
		count = n
		queue_redraw()

func _ready() -> void:
	size = ICON_SIZE
	custom_minimum_size = ICON_SIZE
	pivot_offset = ICON_SIZE / 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(func(): if component != null: UIState.clear_hovered(component))
	set_process(false)

func setup(p_component: ComponentData, p_mech: MechData) -> void:
	component = p_component
	mech = p_mech
	queue_redraw()

## Appears with a little overshoot (the revealed card landing here).
func pop_in() -> void:
	visible = true
	scale = Vector2(1.8, 1.8)
	create_tween().tween_property(self, "scale", Vector2.ONE, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func pulse() -> void:
	if not visible:
		return
	_pulse = 1.0
	set_process(true)

func _process(delta: float) -> void:
	_pulse = maxf(0.0, _pulse - delta * 2.5)
	var s := 1.0 + 0.35 * sin(_pulse * PI)
	scale = Vector2(s, s)
	queue_redraw()
	if _pulse <= 0.0:
		scale = Vector2.ONE
		set_process(false)

func _on_mouse_entered() -> void:
	if component != null and UIState.dragging_card == null:
		UIState.set_hovered(component, mech, true)

func _draw() -> void:
	if component == null:
		return
	var m := ICON_SIZE / 2.0
	var r := ICON_SIZE.x / 2.0
	var off := component.destroyed
	var c: Color = Palette.TEXT_MUTED if off else Palette.category_color(component.category)
	draw_circle(m, r, Palette.PANEL_2)
	if _pulse > 0.0:
		draw_circle(m, r, Color(c, 0.45 * _pulse))
	draw_arc(m, r - 1.0, 0.0, TAU, 32, c, 2.0, true)
	match component.passive_type():
		ComponentData.PASSIVE_REDIRECT:
			_draw_redirect(m, c)
		ComponentData.PASSIVE_TURN_START_STATUS:
			_draw_bolt(m, c)
		ComponentData.PASSIVE_REDUCE_INCOMING_STATUS:
			_draw_shield_minus(m, c)
		ComponentData.PASSIVE_FACING_COVER, ComponentData.PASSIVE_ON_DAMAGED_STATUS:
			draw_colored_polygon(PackedVector2Array([m + Vector2(-6, -7), m + Vector2(6, -7), m + Vector2(6, 1), m + Vector2(0, 8), m + Vector2(-6, 1)]), c)
		ComponentData.PASSIVE_HEAT_MODS, ComponentData.PASSIVE_RECYCLE_VENT:
			# a thermometer
			draw_line(m + Vector2(0, -7), m + Vector2(0, 3), c, 3.0, true)
			draw_circle(m + Vector2(0, 5), 3.5, c)
		ComponentData.PASSIVE_TURN_START_HEAL, ComponentData.PASSIVE_SAVE:
			draw_rect(Rect2(m + Vector2(-2, -7), Vector2(4, 14)), c, true)
			draw_rect(Rect2(m + Vector2(-7, -2), Vector2(14, 4)), c, true)
		ComponentData.PASSIVE_FACING_STATUS:
			draw_polyline(PackedVector2Array([m + Vector2(-6, -2), m + Vector2(0, 5), m + Vector2(6, -2)]), c, 2.5, true)
			draw_line(m + Vector2(0, -7), m + Vector2(0, 5), c, 2.5, true)
		ComponentData.PASSIVE_FIRST_CARD_DISCOUNT, ComponentData.PASSIVE_NTH_ATTACK_TWICE:
			draw_colored_polygon(PackedVector2Array([m + Vector2(-5, -7), m + Vector2(5, 0), m + Vector2(-5, 7)]), c)
		_:
			draw_circle(m, 3.0, c)
	if off:
		draw_line(m + Vector2(-r * 0.7, r * 0.7), m + Vector2(r * 0.7, -r * 0.7), Palette.DANGER, 2.5, true)
	elif count > 0:
		var font := get_theme_default_font()
		var y := ICON_SIZE.y + 12.0 if numbers_below else -3.0
		var text := str(count)
		for o in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			draw_string(font, Vector2(0, y) + o, text, HORIZONTAL_ALIGNMENT_CENTER, ICON_SIZE.x, 12, Color(0, 0, 0, 0.85))
		draw_string(font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, ICON_SIZE.x, 12, c.lightened(0.2))

## Redirect Spike: an arrow bending down into a bar (hits get pulled to it).
func _draw_redirect(m: Vector2, c: Color) -> void:
	draw_polyline(PackedVector2Array([m + Vector2(-6, -5), m + Vector2(2, -5), m + Vector2(2, 2)]), c, 2.0, true)
	draw_colored_polygon(PackedVector2Array([m + Vector2(-2, 1), m + Vector2(6, 1), m + Vector2(2, 5)]), c)
	draw_line(m + Vector2(-6, 7), m + Vector2(6, 7), c, 2.0, true)

## Turn-start charge (Capacitor Bank): a lightning bolt.
func _draw_bolt(m: Vector2, c: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		m + Vector2(2, -8), m + Vector2(-5, 1), m + Vector2(-0.5, 1),
		m + Vector2(-2, 8), m + Vector2(5, -1), m + Vector2(0.5, -1)]), c)

## Incoming-status reduction (Insulated Core): a shield with a minus.
func _draw_shield_minus(m: Vector2, c: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		m + Vector2(-6, -7), m + Vector2(6, -7), m + Vector2(6, 1),
		m + Vector2(0, 8), m + Vector2(-6, 1)]), c)
	draw_line(m + Vector2(-3, -1.5), m + Vector2(3, -1.5), Palette.PANEL_2, 2.0)

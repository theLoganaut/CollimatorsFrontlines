class_name IntentIcon
extends Control
## One enemy intent symbol: a vague picture of what one planned action will
## do (CardData.intent()): a sword (attack), crossed swords (heavy attack),
## a shield (block), a drop (status), an up arrow (buff). The action
## currently resolving pulses. Hovering one shows the card and the part
## of your mech it's aimed at (UIState.hovered_intent). An extra warning
## icon ("overheat") means the plan takes the enemy past its max heat.
## Placeholder vector art, drawn in code.

const INTENT_OVERHEAT := "overheat"
## The enemy has nothing it can play: it spends its turn venting.
const INTENT_VENT := "vent"

const ICON_SIZE := Vector2(26, 26)
const TOOLTIPS := {
	CardData.INTENT_ATTACK: "Attack",
	CardData.INTENT_HEAVY_ATTACK: "Heavy attack",
	CardData.INTENT_BLOCK: "Block",
	CardData.INTENT_STATUS: "Status effect",
	CardData.INTENT_BUFF: "Buff",
	INTENT_OVERHEAT: "Will overheat this turn",
	INTENT_VENT: "Venting: nothing it can play, so it dumps heat this turn",
}

var kind: String = CardData.INTENT_ATTACK
var active: bool = false
## {mech, card, target} for the hover; {} for the overheat warning.
var intent: Dictionary = {}
var _t: float = 0.0

func _ready() -> void:
	size = ICON_SIZE
	custom_minimum_size = ICON_SIZE
	pivot_offset = ICON_SIZE / 2.0
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_entered.connect(func():
		if not intent.is_empty():
			UIState.set_hovered_intent(intent))
	mouse_exited.connect(func(): UIState.clear_hovered_intent(intent))
	tree_exiting.connect(func(): UIState.clear_hovered_intent(intent))

func setup(p_kind: String, p_active: bool) -> void:
	kind = p_kind
	active = p_active
	tooltip_text = TOOLTIPS.get(kind, "")
	set_process(active)
	if not active:
		scale = Vector2.ONE
	queue_redraw()

func _process(delta: float) -> void:
	_t += delta
	var s := 1.0 + 0.12 * (0.5 + 0.5 * sin(_t * 9.0))
	scale = Vector2(s, s)

func _color() -> Color:
	match kind:
		CardData.INTENT_ATTACK, CardData.INTENT_HEAVY_ATTACK: return Palette.HARDPOINT
		CardData.INTENT_BLOCK: return Palette.CHASSIS
		INTENT_OVERHEAT: return Palette.DANGER
		INTENT_VENT: return Palette.LINK
		CardData.INTENT_STATUS: return Palette.PROTOCOL
		_: return Palette.OK

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, ICON_SIZE)
	var c := _color()
	draw_rect(rect, Palette.PANEL_2, true)
	draw_rect(rect, Palette.TEXT if active else Palette.BORDER, false, 2.0 if active else 1.0)
	var m := ICON_SIZE / 2.0
	match kind:
		CardData.INTENT_ATTACK:
			_draw_sword(m, 1.0, c)
		CardData.INTENT_HEAVY_ATTACK:
			_draw_sword(m, 1.0, c)
			_draw_sword(m, -1.0, c)
		CardData.INTENT_BLOCK:
			draw_colored_polygon(PackedVector2Array([
				m + Vector2(-7, -8), m + Vector2(7, -8), m + Vector2(7, 1),
				m + Vector2(0, 9), m + Vector2(-7, 1)]), c)
		INTENT_OVERHEAT:
			# a flame
			draw_colored_polygon(PackedVector2Array([
				m + Vector2(0, -9), m + Vector2(6, 0), m + Vector2(5, 6), m + Vector2(0, 9),
				m + Vector2(-5, 6), m + Vector2(-6, 0), m + Vector2(-2, -3)]), c)
			draw_circle(m + Vector2(0, 4), 3.0, Palette.PANEL_2)
		INTENT_VENT:
			# three rising wisps
			for dx in [-5.0, 0.0, 5.0]:
				draw_polyline(PackedVector2Array([m + Vector2(dx, 8), m + Vector2(dx - 2, 3), m + Vector2(dx + 2, -2), m + Vector2(dx, -8)]), c, 2.0, true)
		CardData.INTENT_STATUS:
			draw_circle(m + Vector2(0, 3), 5.5, c)
			draw_colored_polygon(PackedVector2Array([
				m + Vector2(-4.8, 0.5), m + Vector2(0, -9), m + Vector2(4.8, 0.5)]), c)
		_:
			draw_colored_polygon(PackedVector2Array([
				m + Vector2(0, -9), m + Vector2(8, 0), m + Vector2(3, 0), m + Vector2(3, 8),
				m + Vector2(-3, 8), m + Vector2(-3, 0), m + Vector2(-8, 0)]), c)

## A sword on a diagonal, blade toward the top; `flip` = -1 mirrors it.
func _draw_sword(m: Vector2, flip: float, c: Color) -> void:
	draw_sword(self, m, flip, c)

## The same sword on any CanvasItem, at any scale (the location map's fight nodes use it).
static func draw_sword(ci: CanvasItem, m: Vector2, flip: float, c: Color, k: float = 1.0) -> void:
	var tip := m + Vector2(7 * flip, -8) * k
	var hilt := m + Vector2(-5 * flip, 6) * k
	ci.draw_line(hilt, tip, c, 3.0 * k, true)
	var dir := (tip - hilt).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var guard := hilt + dir * 3.0 * k
	ci.draw_line(guard - perp * 4.5 * k, guard + perp * 4.5 * k, c, 2.5 * k, true)
	ci.draw_circle(hilt - dir * 2.5 * k, 2.0 * k, c)

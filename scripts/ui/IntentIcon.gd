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
## A part is charging an attack: it fires next enemy turn unless that part
## is Disabled, Frozen or destroyed first. What it is stays hidden (Decided).
const INTENT_CHARGE := "charge"

const ICON_SIZE := Vector2(26, 26)
const TITLES := {INTENT_OVERHEAT: "Overheating", INTENT_VENT: "Venting", INTENT_CHARGE: "Charging"}
const TOOLTIPS := {
	CardData.INTENT_ATTACK: "Attack",
	CardData.INTENT_HEAVY_ATTACK: "Heavy attack",
	CardData.INTENT_BLOCK: "Block",
	CardData.INTENT_STATUS: "Status effect",
	CardData.INTENT_BUFF: "Buff",
	INTENT_OVERHEAT: "What it plans this turn will take it over its max heat: it overheats, the backlash damages its own parts, and its turn ends there.",
	INTENT_VENT: "It has nothing it can play, so it spends this turn dumping heat.",
	INTENT_CHARGE: "Charging something big. It fires for free at +50% as its next turn starts, unless you Disable, Freeze or destroy the charging part first.",
}

var kind: String = CardData.INTENT_ATTACK
var active: bool = false
## {mech, card, target} for the hover; {} for the overheat warning.
var intent: Dictionary = {}
## Phase 6 marks: cancelled by the player this turn (struck out), its part
## Shocked (hits a third weaker), a charged attack about to fire, a step
## added with Heat the player freed, and which part is charging.
var cancelled: bool = false
var weakened: bool = false
var charged: bool = false
var added: bool = false
var charging_part: String = ""
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
	# A card's intent explains itself in the Description Box (UIState.hovered_intent);
	# the overheat and vent icons have no card, so they say what they mean there too.
	if intent.is_empty() and TOOLTIPS.has(kind):
		var text: String = TOOLTIPS[kind]
		if kind == INTENT_CHARGE and charging_part != "":
			text = "%s: %s" % [charging_part, text]
		UIState.describe_on_hover(self, func(): return [TITLES.get(kind, "Intent"), text])
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
		INTENT_CHARGE: return Palette.WARNING
		CardData.INTENT_STATUS: return Palette.PROTOCOL
		_: return Palette.OK

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, ICON_SIZE)
	var c := _color()
	draw_rect(rect, Palette.PANEL_2, true)
	draw_rect(rect, Palette.TEXT if active else Palette.BORDER, false, 2.0 if active else 1.0)
	if charged:
		draw_rect(rect.grow(2.0), Palette.DANGER, false, 2.0)
	var m := ICON_SIZE / 2.0
	match kind:
		INTENT_CHARGE:
			# a lightning bolt
			draw_colored_polygon(PackedVector2Array([
				m + Vector2(2, -10), m + Vector2(-6, 2), m + Vector2(-1, 2), m + Vector2(-3, 10),
				m + Vector2(6, -2), m + Vector2(1, -2)]), c)
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

	if weakened and not cancelled:
		# a small down arrow: Shock takes a third off its hits
		var p := Vector2(ICON_SIZE.x - 6, ICON_SIZE.y - 7)
		draw_colored_polygon(PackedVector2Array([p + Vector2(-3, -3), p + Vector2(3, -3), p + Vector2(0, 2)]), Palette.PROTOCOL)
	if added:
		var q := Vector2(5, 5)
		draw_line(q - Vector2(3, 0), q + Vector2(3, 0), Palette.TEXT, 1.5)
		draw_line(q - Vector2(0, 3), q + Vector2(0, 3), Palette.TEXT, 1.5)
	if cancelled:
		draw_rect(rect, Color(Palette.PANEL_2, 0.6), true)
		draw_line(Vector2(3, 3), ICON_SIZE - Vector2(3, 3), Palette.DANGER, 2.5, true)

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

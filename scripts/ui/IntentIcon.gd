class_name IntentIcon
extends Control
## One enemy intent symbol: a vague picture of what one planned action will
## do (CardData.intent()): a minigun (attack), a missile salvo (heavy attack),
## a shield (guard), a skull (afflict: a status on you), a plus (recover /
## buff itself), a charging battery (charge). None reuses a status glyph
## (Shock's bolt, Acid's drop, Jam's arrow), so the intent row and the badge
## row never look alike (2026-11-09). The action
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
	CardData.INTENT_BLOCK: "Guard",
	CardData.INTENT_STATUS: "Afflict",
	CardData.INTENT_BUFF: "Recover",
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
## What the card being aimed at this enemy would do to this step
## (CombatAttack.preview_plan): "stop", "maybe_stop", "weaken" or "".
var preview: String = ""
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

## Training shows this intent as if hovered (its card in the Description Box).
func set_spotlit(on: bool) -> void:
	if intent.is_empty():
		return
	if on:
		UIState.set_hovered_intent(intent)
	else:
		UIState.clear_hovered_intent(intent)

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

func set_preview(mark: String) -> void:
	if mark != preview:
		preview = mark
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
		INTENT_VENT: return Palette.TEXT # steam
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
			# a battery two-thirds full: something is charging
			var body := Rect2(m + Vector2(-9, -5), Vector2(16, 10))
			draw_rect(body, c, false, 2.0)
			draw_rect(Rect2(m + Vector2(7, -2.5), Vector2(2.5, 5)), c, true)
			for i in range(2):
				draw_rect(Rect2(body.position + Vector2(2.5 + i * 4.5, 2.5), Vector2(3, 5)), c, true)
		CardData.INTENT_ATTACK:
			# a minigun: housing, three barrels, a collar, tracers
			draw_rect(Rect2(m + Vector2(-10, -4.5), Vector2(6, 9)), c, true)
			for y in [-3.0, 0.0, 3.0]:
				draw_line(m + Vector2(-4, y), m + Vector2(6, y), c, 2.0)
			draw_rect(Rect2(m + Vector2(2, -5), Vector2(2, 10)), c, true)
			for t in [[8.0, -3.0], [9.5, 1.5]]:
				draw_line(m + Vector2(t[0], t[1]), m + Vector2(t[0] + 2.5, t[1]), c.lightened(0.4), 1.5)
		CardData.INTENT_HEAVY_ATTACK:
			# a salvo diving at you: one big missile, a small one above and below
			var d := Vector2(1, 0.8).normalized()
			_draw_missile(m + Vector2(-1, 0), d, 1.0, c)
			_draw_missile(m + Vector2(2, -7.5), d, 0.6, c)
			_draw_missile(m + Vector2(-5, 7), d, 0.6, c)
		CardData.INTENT_BLOCK:
			draw_colored_polygon(PackedVector2Array([
				m + Vector2(-8, -9), m + Vector2(8, -9), m + Vector2(8, 1),
				m + Vector2(0, 10), m + Vector2(-8, 1)]), c)
			# a rib down the middle, so it reads as a shield and not a badge
			draw_line(m + Vector2(0, -6), m + Vector2(0, 6), c.lightened(0.45), 2.0)
		INTENT_OVERHEAT:
			# a warning: a red-hot box, a hazard triangle with a flame in it
			draw_rect(rect, Color(Palette.DANGER, 0.35), true)
			draw_rect(rect, Palette.DANGER, false, 2.0)
			var tri := PackedVector2Array([m + Vector2(0, -10), m + Vector2(10, 8), m + Vector2(-10, 8)])
			draw_colored_polygon(tri, Palette.DANGER)
			draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Palette.WARNING, 1.5, true)
			Palette.draw_status_glyph(self, m + Vector2(0, 2.5), 5.0, "burn", Palette.LINK)
		INTENT_VENT:
			# a vent grille blasting a plume up and away, mushrooming at its end
			var g := Rect2(m + Vector2(-11, 3), Vector2(8, 8))
			draw_rect(g, c, false, 1.5)
			for i in range(3):
				var y := g.position.y + 2.0 + i * 2.0
				draw_line(Vector2(g.position.x + 1.5, y), Vector2(g.end.x - 1.5, y), c, 1.0)
			var d := Vector2(1, -1).normalized()
			var pp := Vector2(-d.y, d.x)
			var start := m + Vector2(-5, 3)
			var head := start + d * 10.0
			draw_colored_polygon(PackedVector2Array([start + pp * 1.2, head + pp * 2.5, head - pp * 2.5, start - pp * 1.2]), c)
			for p in [[0.0, 0.0, 3.6], [0.0, 4.0, 2.8], [0.0, -4.0, 2.8], [2.5, 0.0, 3.0], [-1.5, 3.5, 2.2], [-1.5, -3.5, 2.2]]:
				draw_circle(head + d * p[0] + pp * p[1], p[2], c)
		CardData.INTENT_STATUS:
			# a skull: it puts something nasty on your parts
			var bg := Palette.PANEL_2
			draw_circle(m + Vector2(0, -2), 7.5, c)
			draw_rect(Rect2(m + Vector2(-4.5, 2), Vector2(9, 7)), c, true)
			draw_circle(m + Vector2(-3, -2), 2.4, bg)
			draw_circle(m + Vector2(3, -2), 2.4, bg)
			draw_colored_polygon(PackedVector2Array([m + Vector2(0, 1), m + Vector2(-1.3, 3.5), m + Vector2(1.3, 3.5)]), bg)
			for x in [-1.5, 1.5]:
				draw_line(m + Vector2(x, 6), m + Vector2(x, 9), bg, 1.0)
		_:
			# a plus: it patches, vents or boosts itself
			draw_rect(Rect2(m + Vector2(-3, -9), Vector2(6, 18)), c, true)
			draw_rect(Rect2(m + Vector2(-9, -3), Vector2(18, 6)), c, true)

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
	_draw_preview(rect)

## The aimed card's effect on this step: a bright ring with the mark it would
## get, undimmed so it reads as "would", not as already struck out.
func _draw_preview(rect: Rect2) -> void:
	match preview:
		"stop":
			draw_rect(rect.grow(2.0), Palette.DANGER, false, 2.0)
			draw_line(Vector2(3, 3), ICON_SIZE - Vector2(3, 3), Palette.DANGER, 2.5, true)
		"maybe_stop":
			# a broken slash: the roll decides
			draw_rect(rect.grow(2.0), Palette.WARNING, false, 2.0)
			draw_line(Vector2(3, 3), Vector2(10, 10), Palette.WARNING, 2.5, true)
			draw_line(ICON_SIZE - Vector2(10, 10), ICON_SIZE - Vector2(3, 3), Palette.WARNING, 2.5, true)
		"weaken":
			draw_rect(rect.grow(2.0), Palette.PROTOCOL, false, 2.0)
			var p := Vector2(ICON_SIZE.x - 6, ICON_SIZE.y - 7)
			draw_colored_polygon(PackedVector2Array([p + Vector2(-4, -4), p + Vector2(4, -4), p + Vector2(0, 3)]), Palette.PROTOCOL)

## A missile centered at `at`, flying along `d`, `k` its size.
func _draw_missile(at: Vector2, d: Vector2, k: float, c: Color) -> void:
	var pp := Vector2(-d.y, d.x)
	var tail := at - d * 6.0 * k
	var nose := at + d * 5.0 * k
	var r := 2.3 * k
	draw_colored_polygon(PackedVector2Array([tail + pp * r, nose + pp * r, nose + d * 3.5 * k,
		nose - pp * r, tail - pp * r]), c)
	for side in [1.0, -1.0]:
		draw_colored_polygon(PackedVector2Array([tail + d * 3.0 * k + pp * r * side,
			tail + pp * (r + 2.5 * k) * side - d * 1.0 * k, tail + pp * r * side]), c)
	draw_colored_polygon(PackedVector2Array([tail + pp * r * 0.8, tail - pp * r * 0.8, tail - d * 4.5 * k]), Palette.LINK)

## A sword on a diagonal, blade toward the top; `flip` = -1 mirrors it.
func _draw_sword(m: Vector2, flip: float, c: Color) -> void:
	draw_sword(self, m, flip, c)

## The same sword on any CanvasItem, at any scale (the location map's fight nodes use it).
static func draw_sword(ci: CanvasItem, m: Vector2, flip: float, c: Color, k: float = 1.0) -> void:
	var tip := m + Vector2(8 * flip, -9) * k
	var hilt := m + Vector2(-6 * flip, 7) * k
	var dir := (tip - hilt).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var guard := hilt + dir * 4.0 * k
	var shoulder := tip - dir * 3.5 * k
	# a filled, pointed blade (a plain line reads as a stick at this size)
	ci.draw_colored_polygon(PackedVector2Array([guard + perp * 2.0 * k, shoulder + perp * 2.0 * k, tip,
		shoulder - perp * 2.0 * k, guard - perp * 2.0 * k]), c)
	ci.draw_line(guard - perp * 5.0 * k, guard + perp * 5.0 * k, c, 2.5 * k, true)
	ci.draw_line(hilt, guard, c, 2.5 * k, true)
	ci.draw_circle(hilt - dir * 0.5 * k, 1.8 * k, c)

class_name MapNodeUI
extends Control
## One stop on the location map: a round holo glass badge with a sword (a fight, with a
## pip per enemy underneath), crossed swords in red (an elite), a big double
## ring (the boss), a "?" (event), a cross (repair bay) or a scrap
## (autonomous bay). Nodes the pilot can go to next pulse and take clicks;
## finished nodes show a check; the rest are dim.

signal pressed(node_id: int)
signal hover_changed(node_id: int, hovering: bool)

enum State { LOCKED, AVAILABLE, CLEARED }

const RADIUS := 21.0
const SIZE := Vector2(56, 64)

var node_id: int = -1
var kind: String = RunMap.KIND_FIGHT
var enemy_count: int = 0
var state: State = State.LOCKED

var _hover: bool = false
var _t: float = 0.0

func _ready() -> void:
	size = SIZE
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): _set_hover(true))
	mouse_exited.connect(func(): _set_hover(false))
	gui_input.connect(_on_gui_input)

func setup(p_id: int, p_kind: String, p_enemy_count: int, p_state: State) -> void:
	node_id = p_id
	kind = p_kind
	enemy_count = p_enemy_count
	state = p_state
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if state == State.AVAILABLE else Control.CURSOR_ARROW
	set_process(state == State.AVAILABLE)
	queue_redraw()

## Where edges attach: the badge's center, in the parent's coordinates.
func center() -> Vector2:
	return position + Vector2(SIZE.x / 2.0, RADIUS + 2.0) * scale

func _set_hover(h: bool) -> void:
	_hover = h
	hover_changed.emit(node_id, h)
	queue_redraw()

func _on_gui_input(event: InputEvent) -> void:
	if state == State.AVAILABLE and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		pressed.emit(node_id)

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var c := Vector2(SIZE.x / 2.0, RADIUS + 2.0)
	var ring: Color
	var glyph: Color
	var accent := Palette.HARDPOINT
	match kind:
		RunMap.KIND_REPAIR: accent = Palette.OK
		RunMap.KIND_SHOP: accent = Palette.SCRAPS
		RunMap.KIND_EVENT: accent = Palette.LINK
		RunMap.KIND_ELITE: accent = Palette.DANGER
		RunMap.KIND_BOSS: accent = Palette.PROTOTYPE
	match state:
		State.AVAILABLE:
			ring = Palette.LINK if _hover else accent
			glyph = accent
			var pulse := 0.5 + 0.5 * sin(_t * 4.0)
			draw_circle(c, RADIUS + 5.0 + pulse * 4.0, Color(ring, 0.18))
		State.CLEARED:
			ring = Palette.OK
			glyph = Color(Palette.TEXT_MUTED, 0.8)
		_:
			ring = Color(GlassPanel.HOLO, 0.45)
			glyph = Color(Color("9fb9b6"), 0.6)
	# holo glass: smoked, with a wash of the ring's colour and a soft halo
	draw_circle(c, RADIUS + 3.0, Color(ring, 0.10))
	draw_circle(c, RADIUS, Color(0.02, 0.06, 0.08, 0.86))
	draw_circle(c, RADIUS, Color(ring, 0.10))
	draw_arc(c, RADIUS, 0.0, TAU, 40, ring, 3.0 if state == State.AVAILABLE else 2.0, true)
	if kind == RunMap.KIND_BOSS or kind == RunMap.KIND_ELITE:
		draw_arc(c, RADIUS - 5.0, 0.0, TAU, 40, ring, 1.5, true)
	match kind:
		RunMap.KIND_REPAIR: # a cross
			draw_rect(Rect2(c + Vector2(-3.5, -10), Vector2(7, 20)), glyph, true)
			draw_rect(Rect2(c + Vector2(-10, -3.5), Vector2(20, 7)), glyph, true)
		RunMap.KIND_SHOP: # a scrap
			draw_rect(Rect2(c + Vector2(-8, -8), Vector2(16, 16)), glyph, false, 2.5)
			draw_rect(Rect2(c + Vector2(-3.5, -3.5), Vector2(7, 7)), glyph, true)
			for k in [-4.0, 4.0]:
				draw_line(c + Vector2(k, -8), c + Vector2(k, -12), glyph, 2.0)
				draw_line(c + Vector2(k, 8), c + Vector2(k, 12), glyph, 2.0)
				draw_line(c + Vector2(-8, k), c + Vector2(-12, k), glyph, 2.0)
				draw_line(c + Vector2(8, k), c + Vector2(12, k), glyph, 2.0)
		RunMap.KIND_EVENT:
			var font := get_theme_default_font()
			draw_string(font, c + Vector2(-6, 9), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, glyph)
		RunMap.KIND_ELITE, RunMap.KIND_BOSS:
			IntentIcon.draw_sword(self, c + Vector2(0, 1), 1.0, glyph, 1.0)
			IntentIcon.draw_sword(self, c + Vector2(0, 1), -1.0, glyph, 1.0)
		_:
			IntentIcon.draw_sword(self, c + Vector2(0, 1), 1.0, glyph, 1.25)
	if state == State.CLEARED:
		draw_polyline(PackedVector2Array([c + Vector2(7, 8), c + Vector2(11, 12), c + Vector2(18, 3)]), Palette.OK, 3.0, true)
	# one pip per Scrap Warden
	var pip_y := RADIUS * 2.0 + 9.0
	var gap := 9.0
	var x0 := SIZE.x / 2.0 - gap * float(enemy_count - 1) / 2.0
	for i in range(enemy_count):
		draw_circle(Vector2(x0 + gap * i, pip_y), 3.0, glyph if state != State.LOCKED else Color(Palette.TEXT_MUTED, 0.5))

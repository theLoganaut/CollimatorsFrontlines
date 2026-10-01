class_name GlassPanel
extends Control
## A holo glass screen, the look of the War Room's labels and the Hangar's
## panels: smoked glass with a faint teal wash, scanlines, a thin edge and
## brighter corner brackets. Children sit on top of it. draw_glass() paints
## the same glass onto any canvas (HoloLabel unfolds it).

const HOLO := Palette.REACTOR
const SMOKE := Color(0.02, 0.06, 0.08, 0.72)
const BRACKET := 8.0

var accent: Color = HOLO
## How strong the teal wash is (labels glow more than big panels).
var tint: float = 0.6

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _draw() -> void:
	draw_glass(self, Rect2(Vector2.ZERO, size), 1.0, accent, BRACKET, tint)

static func draw_glass(ci: CanvasItem, r: Rect2, a: float = 1.0, accent: Color = HOLO, bracket: float = BRACKET, p_tint: float = 1.0) -> void:
	ci.draw_rect(r, Color(SMOKE, SMOKE.a * a), true)
	var top := Color(accent, 0.20 * p_tint * a)
	var bottom := Color(accent, 0.07 * p_tint * a)
	ci.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))
	var y := r.position.y + 2.0
	while y < r.end.y:
		ci.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(accent, 0.05 * a), 1.0)
		y += 3.0
	draw_frame(ci, r, a, accent, bracket)

## Just the glass's edge and corner brackets (over art that shouldn't be smoked).
static func draw_frame(ci: CanvasItem, r: Rect2, a: float = 1.0, accent: Color = HOLO, bracket: float = BRACKET) -> void:
	ci.draw_rect(r, Color(accent, 0.5 * a), false, 1.0)
	for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if corner.x == r.position.x else -1.0
		var sy := 1.0 if corner.y == r.position.y else -1.0
		ci.draw_line(corner, corner + Vector2(bracket * sx, 0), Color(accent, a), 2.0)
		ci.draw_line(corner, corner + Vector2(0, bracket * sy), Color(accent, a), 2.0)

## A flat style for controls sitting on the glass (search box, chips, buttons).
static func control_style(border: Color = HOLO, fill: float = 0.0, border_a: float = 0.45) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(border, fill) if fill > 0.0 else Color(0, 0, 0, 0.35)
	s.border_color = Color(border, border_a)
	s.set_border_width_all(1)
	s.set_corner_radius_all(2)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s

## A panel style for containers that can't draw the full glass (pop-ups,
## banners): smoked glass with a thin accent edge.
static func panel_style(accent: Color = HOLO, margin: float = 12.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.02, 0.06, 0.08, 0.9)
	s.border_color = Color(accent, 0.75)
	s.set_border_width_all(1)
	s.set_corner_radius_all(2)
	s.shadow_color = Color(accent, 0.15)
	s.shadow_size = 6
	s.set_content_margin_all(margin)
	return s

## A button on the glass: dark with a teal edge; `on` fills it (a selected
## tab or chip).
static func button(text: String, font_size: int = 12, on: bool = false, accent: Color = HOLO) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	b.pressed.connect(func(): Audio.play("ui", 0.03))
	style_button(b, on, accent)
	return b

static func style_button(b: Button, on: bool, accent: Color = HOLO) -> void:
	var normal := control_style(accent, 0.28 if on else 0.0, 0.9 if on else 0.45)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", control_style(Palette.LINK, 0.12 if not on else 0.28, 0.9))
	b.add_theme_stylebox_override("pressed", control_style(accent, 0.35, 1.0))
	b.add_theme_stylebox_override("disabled", control_style(Palette.TEXT_MUTED, 0.0, 0.3))
	var fg := Color("dffcf8") if on else Color("b9d8d4")
	for key in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(key, fg)
	b.add_theme_color_override("font_disabled_color", Palette.TEXT_MUTED)

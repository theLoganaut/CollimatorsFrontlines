class_name Palette
extends RefCounted
## The dark palette from Refit Bay, as recorded on the UI & Screens Notion
## page. Placeholder art throughout, but these are the real category/status
## colors so the grid reads the same way Refit Bay's own grid does.

const BG := Color("0a0d12")
const PANEL := Color("12161d")
const PANEL_2 := Color("171b23")
const BORDER := Color("252b36")
const TEXT := Color("e8ebf0")
const TEXT_MUTED := Color("8189a0")

const HARDPOINT := Color("e5622f")
const REACTOR := Color("3fc4b8")
const PROTOCOL := Color("a486e0")
const CHASSIS := Color("6f93bd")

const DANGER := Color("d3402a")
const WARNING := Color("d0a12b")
const LINK := Color("f5cc45")
const OK := Color("2f9f96")

## Rarity (UI & Screens, from Refit Bay).
const SURPLUS := Color("8291a8")
const SALVAGED := Color("d69544")
const PROTOTYPE := Color("ea5c9c")
const SCRAPS := Color("f5cc45")

static func rarity_color(rarity: String) -> Color:
	match rarity:
		"salvaged": return SALVAGED
		"prototype": return PROTOTYPE
		_: return SURPLUS

static func category_color(category: String) -> Color:
	match category:
		ComponentData.CATEGORY_HARDPOINT:
			return HARDPOINT
		ComponentData.CATEGORY_REACTOR:
			return REACTOR
		ComponentData.CATEGORY_PROTOCOL:
			return PROTOCOL
		_:
			return CHASSIS

# ---------- statuses ----------

## Set by GameSettings: statuses use the colorblind-safe set and shapes.
static var colorblind := false

const STATUS_COLORS := {
	"shock": Color("6fb7ff"), "acid": Color("8fd14f"), "burn": Color("ff8a3d"),
	"disabled": Color("9aa3b5"), "offline": Color("d3402a"), "freeze": Color("bfefff"),
	"coolant": Color("3fc4b8"), "jam": Color("a486e0"),
}
## Okabe-Ito, the colorblind-safe set, each status also getting its own shape.
const STATUS_COLORS_SAFE := {
	"shock": Color("56b4e9"), "acid": Color("f0e442"), "burn": Color("e69f00"),
	"disabled": Color("bbbbbb"), "offline": Color("d55e00"), "freeze": Color("ffffff"),
	"coolant": Color("009e73"), "jam": Color("cc79a7"),
}
const STATUS_SHAPES := {
	"shock": "triangle", "acid": "diamond", "burn": "square", "disabled": "bar",
	"offline": "cross", "freeze": "ring", "coolant": "circle", "jam": "hexagon",
}

static func status_color(status: String) -> Color:
	return (STATUS_COLORS_SAFE if colorblind else STATUS_COLORS).get(status, Color.WHITE)

## One status marker of radius `r` at `c`: a dot, or in colorblind mode the
## status's own shape.
static func draw_status(ci: CanvasItem, c: Vector2, r: float, status: String) -> void:
	var col := status_color(status)
	var edge := Color(0, 0, 0, 0.7)
	if not colorblind:
		ci.draw_circle(c, r, col)
		ci.draw_arc(c, r, 0.0, TAU, 12, edge, 1.0, true)
		return
	match STATUS_SHAPES.get(status, "circle"):
		"triangle": _poly(ci, c, r * 1.15, 3, -PI / 2.0, col, edge)
		"diamond": _poly(ci, c, r * 1.15, 4, 0.0, col, edge)
		"square": _poly(ci, c, r * 1.2, 4, PI / 4.0, col, edge)
		"hexagon": _poly(ci, c, r * 1.05, 6, 0.0, col, edge)
		"bar":
			ci.draw_rect(Rect2(c - Vector2(r, r * 0.45), Vector2(r * 2.0, r * 0.9)), col, true)
			ci.draw_rect(Rect2(c - Vector2(r, r * 0.45), Vector2(r * 2.0, r * 0.9)), edge, false, 1.0)
		"cross":
			ci.draw_line(c - Vector2(r, r), c + Vector2(r, r), edge, r * 0.9)
			ci.draw_line(c + Vector2(-r, r), c + Vector2(r, -r), edge, r * 0.9)
			ci.draw_line(c - Vector2(r, r), c + Vector2(r, r), col, r * 0.55)
			ci.draw_line(c + Vector2(-r, r), c + Vector2(r, -r), col, r * 0.55)
		"ring":
			ci.draw_arc(c, r * 0.8, 0.0, TAU, 16, edge, r * 0.8, true)
			ci.draw_arc(c, r * 0.8, 0.0, TAU, 16, col, r * 0.5, true)
		_:
			ci.draw_circle(c, r, col)
			ci.draw_arc(c, r, 0.0, TAU, 12, edge, 1.0, true)

static func _poly(ci: CanvasItem, c: Vector2, r: float, sides: int, start: float, col: Color, edge: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(sides):
		var a := start + TAU * i / sides
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	ci.draw_colored_polygon(pts, col)
	pts.append(pts[0])
	ci.draw_polyline(pts, edge, 1.0, true)

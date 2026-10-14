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
	"coolant": Color("3fc4b8"), "jam": Color("a486e0"), "absorb": Color("5fd38a"),
}
## Okabe-Ito, the colorblind-safe set, each status also getting its own shape.
const STATUS_COLORS_SAFE := {
	"shock": Color("56b4e9"), "acid": Color("f0e442"), "burn": Color("e69f00"),
	"disabled": Color("bbbbbb"), "offline": Color("d55e00"), "freeze": Color("ffffff"),
	"coolant": Color("009e73"), "jam": Color("cc79a7"), "absorb": Color("7ad9a8"),
}

static func status_color(status: String) -> Color:
	return (STATUS_COLORS_SAFE if colorblind else STATUS_COLORS).get(status, Color.WHITE)

## One status marker of radius `r` at `c` (Logan, 2026-10-13: code-drawn
## glyphs): a dark chip edged in the status's color with its symbol on it.
## Bolt Shock, drop Acid, flame Burn, bubble Absorb, shield Deflect,
## circle-slash Disabled, power Offline, snowflake Freeze, down / up arrow
## Coolant / Jam (cards cost less / more), cloud Smoke. Each shape is its
## own, so colorblind mode only swaps the colors.
static func draw_status(ci: CanvasItem, c: Vector2, r: float, status: String) -> void:
	var col := status_color(status)
	ci.draw_circle(c, r, Color(0.02, 0.03, 0.05, 0.92))
	ci.draw_arc(c, r, 0.0, TAU, 20, col, maxf(1.0, r * 0.14), true)
	draw_status_glyph(ci, c, r * 0.68, status, col.lightened(0.25))

## Just the symbol, `g` = its half-size.
static func draw_status_glyph(ci: CanvasItem, c: Vector2, g: float, status: String, col: Color) -> void:
	var w := maxf(1.2, g * 0.3)
	match status:
		"shock":
			ci.draw_polyline(_pts(c, g, [[0.25, -1.0], [-0.35, 0.05], [0.3, 0.0], [-0.25, 1.0]]), col, w, true)
		"acid":
			ci.draw_circle(c + Vector2(0, g * 0.3), g * 0.6, col)
			ci.draw_colored_polygon(_pts(c, g, [[0.0, -1.0], [0.52, 0.1], [-0.52, 0.1]]), col)
		"burn":
			ci.draw_colored_polygon(_pts(c, g, [[0.0, -1.0], [0.45, -0.25], [0.7, 0.35], [0.4, 0.9], [-0.4, 0.9], [-0.7, 0.35], [-0.35, -0.1], [-0.1, 0.15]]), col)
		"absorb":
			ci.draw_arc(c, g * 0.85, 0.0, TAU, 18, col, w, true)
			ci.draw_circle(c + Vector2(-g * 0.3, -g * 0.3), g * 0.2, col)
		"deflect":
			var shield := _pts(c, g, [[-0.8, -0.85], [0.8, -0.85], [0.8, 0.1], [0.0, 1.0], [-0.8, 0.1], [-0.8, -0.85]])
			ci.draw_polyline(shield, col, w, true)
		"disabled":
			ci.draw_arc(c, g * 0.85, 0.0, TAU, 18, col, w, true)
			ci.draw_line(c + Vector2(-0.6, 0.6) * g, c + Vector2(0.6, -0.6) * g, col, w, true)
		"offline":
			ci.draw_arc(c, g * 0.8, -PI / 2.0 + 0.6, 1.5 * PI - 0.6, 16, col, w, true)
			ci.draw_line(c + Vector2(0, -g), c + Vector2(0, -g * 0.1), col, w, true)
		"freeze":
			for i in range(3):
				var d := Vector2.from_angle(PI / 2.0 + i * PI / 3.0) * g
				ci.draw_line(c - d, c + d, col, w * 0.85, true)
		"coolant":
			ci.draw_line(c + Vector2(0, -g), c + Vector2(0, g * 0.6), col, w, true)
			ci.draw_polyline(_pts(c, g, [[-0.6, 0.2], [0.0, 0.9], [0.6, 0.2]]), col, w, true)
		"jam":
			ci.draw_line(c + Vector2(0, g), c + Vector2(0, -g * 0.6), col, w, true)
			ci.draw_polyline(_pts(c, g, [[-0.6, -0.2], [0.0, -0.9], [0.6, -0.2]]), col, w, true)
		"smoke":
			for p in [[-0.45, 0.2, 0.42], [0.1, -0.15, 0.52], [0.5, 0.25, 0.38]]:
				ci.draw_circle(c + Vector2(p[0], p[1]) * g, g * p[2], col)
		"destroyed":
			ci.draw_line(c + Vector2(-0.7, -0.7) * g, c + Vector2(0.7, 0.7) * g, col, w, true)
			ci.draw_line(c + Vector2(-0.7, 0.7) * g, c + Vector2(0.7, -0.7) * g, col, w, true)
		_:
			ci.draw_circle(c, g * 0.5, col)

static func _pts(c: Vector2, g: float, xy: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in xy:
		out.append(c + Vector2(p[0], p[1]) * g)
	return out


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
## Bolt Shock, drop Acid, fire Burn, bubble Absorb, shield Deflect,
## circle-slash Disabled, unplugged plug Offline, snowflake Freeze, hollow
## drop Coolant, jammed pistol Jam, cloud Smoke (Logan, 2026-11-09). Each shape is its
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
			# a filled lightning bolt
			ci.draw_colored_polygon(_pts(c, g, [[0.3, -1.0], [-0.6, 0.15], [-0.05, 0.15], [-0.35, 1.0], [0.6, -0.2], [0.05, -0.2]]), col)
		"acid":
			ci.draw_circle(c + Vector2(0, g * 0.3), g * 0.6, col)
			ci.draw_colored_polygon(_pts(c, g, [[0.0, -1.0], [0.52, 0.1], [-0.52, 0.1]]), col)
		"burn":
			# a fire: three tongues over a round base, a hot core
			ci.draw_colored_polygon(_pts(c, g, [[0.0, -1.0], [0.2, -0.55], [0.42, -0.8], [0.45, -0.35], [0.68, -0.5],
				[0.75, 0.05], [0.75, 0.45], [0.55, 0.8], [0.25, 0.98], [-0.25, 0.98], [-0.55, 0.8], [-0.75, 0.45],
				[-0.7, 0.0], [-0.5, -0.45], [-0.38, -0.15], [-0.22, -0.65]]), col)
			ci.draw_colored_polygon(_pts(c, g, [[0.0, -0.1], [0.32, 0.35], [0.3, 0.65], [0.0, 0.85], [-0.3, 0.65], [-0.32, 0.35]]), col.lightened(0.55))
		"absorb":
			# a bubble: tinted inside, so it isn't just another ring
			ci.draw_circle(c, g * 0.85, Color(col, 0.35))
			ci.draw_arc(c, g * 0.85, 0.0, TAU, 18, col, w, true)
			ci.draw_circle(c + Vector2(-g * 0.3, -g * 0.3), g * 0.22, col)
		"deflect":
			var shield := _pts(c, g, [[-0.8, -0.85], [0.8, -0.85], [0.8, 0.1], [0.0, 1.0], [-0.8, 0.1], [-0.8, -0.85]])
			ci.draw_polyline(shield, col, w, true)
		"disabled":
			ci.draw_arc(c, g * 0.85, 0.0, TAU, 18, col, w, true)
			ci.draw_line(c + Vector2(-0.6, 0.6) * g, c + Vector2(0.6, -0.6) * g, col, w, true)
		"offline":
			# unplugged: a plug pulled out of its socket
			ci.draw_line(c + Vector2(-1.0, 0.0) * g, c + Vector2(-0.6, 0.0) * g, col, w, true)
			ci.draw_rect(Rect2(c + Vector2(-0.6, -0.45) * g, Vector2(0.5, 0.9) * g), col, true)
			for y in [-0.25, 0.25]:
				ci.draw_line(c + Vector2(-0.1, y) * g, c + Vector2(0.2, y) * g, col, maxf(1.0, w * 0.7), true)
			ci.draw_rect(Rect2(c + Vector2(0.55, -0.7) * g, Vector2(0.4, 1.4) * g), col, false, maxf(1.0, w * 0.7))
		"freeze":
			# a snowflake: six arms, each with a pair of branches
			for i in range(6):
				var d := Vector2.from_angle(PI / 2.0 + i * PI / 3.0)
				ci.draw_line(c, c + d * g, col, w * 0.8, true)
				var p := c + d * g * 0.55
				for t in [0.8, -0.8]:
					ci.draw_line(p, p + d.rotated(t) * g * 0.38, col, w * 0.65, true)
		"coolant":
			# a coolant drop: hollow, with a cooling down-arrow in it (Acid's is solid)
			var drop := _pts(c, g, [[0.0, -1.0], [0.45, -0.3], [0.68, 0.2], [0.62, 0.6], [0.35, 0.9], [0.0, 1.0],
				[-0.35, 0.9], [-0.62, 0.6], [-0.68, 0.2], [-0.45, -0.3], [0.0, -1.0]])
			ci.draw_polyline(drop, col, w * 0.85, true)
			ci.draw_line(c + Vector2(0, -0.2) * g, c + Vector2(0, 0.6) * g, col, w * 0.8, true)
			ci.draw_polyline(_pts(c, g, [[-0.3, 0.3], [0.0, 0.65], [0.3, 0.3]]), col, w * 0.8, true)
		"jam":
			# a jammed gun: a pistol with a spent case stuck upright in its port
			ci.draw_rect(Rect2(c + Vector2(-0.95, -0.35) * g, Vector2(1.9, 0.5) * g), col, true)
			ci.draw_colored_polygon(_pts(c, g, [[-0.9, 0.15], [-0.4, 0.15], [-0.5, 0.95], [-0.95, 0.95]]), col)
			ci.draw_rect(Rect2(c + Vector2(-0.05, -0.95) * g, Vector2(0.3, 0.55) * g), col.lightened(0.3), true)
			ci.draw_line(c + Vector2(0.45, -0.95) * g, c + Vector2(0.85, -0.55) * g, col, maxf(1.0, w * 0.7), true)
			ci.draw_line(c + Vector2(0.85, -0.95) * g, c + Vector2(0.45, -0.55) * g, col, maxf(1.0, w * 0.7), true)
		"smoke":
			# a cloud: puffs over a flat base (round puffs alone read as a blob)
			for p in [[-0.5, 0.25, 0.38], [0.05, -0.1, 0.5], [0.55, 0.3, 0.33]]:
				ci.draw_circle(c + Vector2(p[0], p[1]) * g, g * p[2], col)
			ci.draw_rect(Rect2(c + Vector2(-0.5, 0.25) * g, Vector2(1.05, 0.38) * g), col, true)
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


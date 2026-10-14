extends SceneTree
## Draws the studio intro's keyboard_mouse piece (what the stone turns into)
## as vector shapes, flat white with dark lines like the vessels and stone,
## and centres it on the stage in layout.json. MOUSE = false leaves the mouse
## out and centres the keyboard alone.
## Godot --headless --path . -s tools/intro_keyboard.gd

const DIR := "res://assets/intro/trismeg/"
const FILL := "#f3f3f8"
const INK := "#0b0a12"
const LINE := 3.0
const MOUSE := true

const SIZE := Vector2i(409, 83)
# the board: a little narrower at the back, seen from just above
const BACK := [26.0, 290.0, 20.0]   # left x, right x, y
const FRONT := [12.0, 304.0, 72.0]
const DECK_INSET := 9.0
const KEY_GAP := 2.6
# key widths per row (units; each row is 15), back row first
const ROWS := [
	[15.0 / 14, 15.0 / 14, 15.0 / 14, 15.0 / 14, 15.0 / 14, 15.0 / 14, 15.0 / 14, 15.0 / 14, 15.0 / 14, 15.0 / 14, 15.0 / 14, 15.0 / 14, 15.0 / 14, 15.0 / 14],
	[1.5, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1.5],
	[1.75, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2.25],
	[2.25, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2.75],
	[1.25, 1.25, 1.25, 6.25, 1.25, 1.25, 1.25, 1.25],
]

func _initialize() -> void:
	var body := _keyboard()
	var right := FRONT[1]
	if MOUSE:
		body += _mouse(Vector2(372, 47))
		right = 398.0
	var svg := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\">%s</svg>" % [SIZE.x, SIZE.y, body]
	var img := Image.new()
	img.load_svg_from_string(svg, 1.0)
	img.save_png(ProjectSettings.globalize_path(DIR + "keyboard_mouse.png"))
	# centre what was drawn under the stage's centre line
	var path := ProjectSettings.globalize_path(DIR + "layout.json")
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var piece: Dictionary = layout.pieces.keyboard_mouse
	piece.size = [SIZE.x, SIZE.y]
	piece.pivot_in_image = [snappedf((FRONT[0] + right) / 2.0, 0.1), piece.pivot_in_image[1]]
	piece.pivot_screen = [960.0, piece.pivot_screen[1]]
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(layout, "  ", false))
	print("saved keyboard_mouse.png (mouse: %s)" % MOUSE)
	quit()

## A point on the board: u across (0..1), v from back (0) to front (1).
func _at(u: float, v: float, inset: float = 0.0) -> Vector2:
	var y := lerpf(BACK[2] + inset, FRONT[2] - inset, v)
	var t := (y - BACK[2]) / (FRONT[2] - BACK[2])
	var left := lerpf(BACK[0], FRONT[0], t) + inset
	var right := lerpf(BACK[1], FRONT[1], t) - inset
	return Vector2(lerpf(left, right, u), y)

func _keyboard() -> String:
	var s := ""
	# the case, its front lip, then the dark deck the keys sit in
	s += _poly([_at(0, 0), _at(1, 0), _at(1, 1), _at(0, 1)], FILL, INK, LINE)
	s += _line(_at(0, 0.9), _at(1, 0.9), INK, 1.6)
	var deck := [_at(0, 0, DECK_INSET * 0.6), _at(1, 0, DECK_INSET * 0.6), _at(1, 0.8, DECK_INSET * 0.6), _at(0, 0.8, DECK_INSET * 0.6)]
	s += _poly(deck, INK, INK, 2.0)
	# keys, row by row, following the board's taper
	var top: float = deck[0].y + 1.2
	var bottom: float = deck[2].y - 1.2
	var row_h: float = (bottom - top) / ROWS.size()
	for r in ROWS.size():
		var y0: float = top + r * row_h + KEY_GAP / 2.0
		var y1: float = top + (r + 1) * row_h - KEY_GAP / 2.0
		var units := 0.0
		for w in ROWS[r]:
			var x0 := units / 15.0
			units += w
			var x1 := units / 15.0
			s += _key(x0, x1, y0, y1)
	return s

func _key(u0: float, u1: float, y0: float, y1: float) -> String:
	var v0 := (y0 - BACK[2]) / (FRONT[2] - BACK[2])
	var v1 := (y1 - BACK[2]) / (FRONT[2] - BACK[2])
	var inset := DECK_INSET * 0.6 + 1.2
	var a := _span(u0, v0, inset) + Vector2(KEY_GAP / 2.0, 0)
	var b := _span(u1, v0, inset) - Vector2(KEY_GAP / 2.0, 0)
	var c := _span(u1, v1, inset) - Vector2(KEY_GAP / 2.0, 0)
	var d := _span(u0, v1, inset) + Vector2(KEY_GAP / 2.0, 0)
	return _poly([a, b, c, d], FILL, FILL, 1.0)  # the thin stroke rounds the corners

## Like _at, but v is the board's own depth and the inset is sideways only.
func _span(u: float, v: float, inset: float) -> Vector2:
	var y := lerpf(BACK[2], FRONT[2], v)
	var left := lerpf(BACK[0], FRONT[0], v) + inset
	var right := lerpf(BACK[1], FRONT[1], v) - inset
	return Vector2(lerpf(left, right, u), y)

## A mouse seen from above and a little in front: a rounded body, wider at
## the palm, two buttons, a scroll wheel. Centre c.
func _mouse(c: Vector2) -> String:
	var s := ""
	var body := "M %s %s C %s %s %s %s %s %s C %s %s %s %s %s %s C %s %s %s %s %s %s C %s %s %s %s %s %s Z" % [
		c.x, c.y - 31,
		c.x + 16, c.y - 31, c.x + 24, c.y - 14, c.x + 24, c.y + 4,
		c.x + 24, c.y + 22, c.x + 14, c.y + 31, c.x, c.y + 31,
		c.x - 14, c.y + 31, c.x - 24, c.y + 22, c.x - 24, c.y + 4,
		c.x - 24, c.y - 14, c.x - 16, c.y - 31, c.x, c.y - 31]
	s += "<path d=\"%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"%s\"/>" % [body, FILL, INK, LINE]
	# where the buttons end and the palm begins
	s += "<path d=\"M %s %s Q %s %s %s %s\" fill=\"none\" stroke=\"%s\" stroke-width=\"1.8\" stroke-linecap=\"round\"/>" % [
		c.x - 23, c.y - 5, c.x, c.y + 3, c.x + 23, c.y - 5, INK]
	# the split between the buttons, broken by the wheel
	s += _line(Vector2(c.x, c.y - 30), Vector2(c.x, c.y - 23), INK, 1.8)
	s += _line(Vector2(c.x, c.y - 10), Vector2(c.x, c.y - 1), INK, 1.8)
	s += "<rect x=\"%s\" y=\"%s\" width=\"6\" height=\"12\" rx=\"3\" fill=\"%s\" stroke=\"%s\" stroke-width=\"1.8\"/>" % [c.x - 3, c.y - 23, FILL, INK]
	s += _line(Vector2(c.x - 1.6, c.y - 18), Vector2(c.x + 1.6, c.y - 18), INK, 1.2)
	s += _line(Vector2(c.x - 1.6, c.y - 15), Vector2(c.x + 1.6, c.y - 15), INK, 1.2)
	return s

func _poly(pts: Array, fill: String, stroke: String, width: float) -> String:
	var d := "M %s %s" % [pts[0].x, pts[0].y]
	for i in range(1, pts.size()):
		d += " L %s %s" % [pts[i].x, pts[i].y]
	return "<path d=\"%s Z\" fill=\"%s\" stroke=\"%s\" stroke-width=\"%s\" stroke-linejoin=\"round\"/>" % [d, fill, stroke, width]

func _line(a: Vector2, b: Vector2, colour: String, width: float) -> String:
	return "<path d=\"M %s %s L %s %s\" stroke=\"%s\" stroke-width=\"%s\" stroke-linecap=\"round\"/>" % [a.x, a.y, b.x, b.y, colour, width]

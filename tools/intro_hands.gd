extends SceneTree
## Draws the studio intro's hands (hand_<side>_front / _thumb) as vector
## shapes and saves them over the PNGs in assets/intro/trismeg, at the same
## sizes and pivots layout.json gives, so the animation is unchanged.
## Coordinates below are the left hand's, relative to the wrist pivot; the
## pinch point on the neck is (118, 13). The right hand is its mirror.
## Godot --headless --path . -s tools/intro_hands.gd

const DIR := "res://assets/intro/trismeg/"
const FILL := "#f3f3f8"
const INK := "#0b0a12"
const LINE := 4.0    # outline, matching the robe and vessels
const CREASE := 1.8  # inner lines between fingers

# Fingers are stroked centrelines (SVG path data) with their widths, back to
# front; all of them and the back of the hand merge into one silhouette.
# CREASES are the only inner lines: where one finger rests on the next, drawn
# from the tips in, stopping short of the knuckles so it stays one hand.
const FINGERS := [
	{"d": "M 50 22 C 64 25 75 27 81 32", "w": 10.0},   # little, curled
	{"d": "M 54 10 C 70 13 84 15 91 20", "w": 11.0},   # ring, curled
	{"d": "M 56 -3 C 72 -1 90 1 98 8", "w": 12.0},     # middle, curled
	{"d": "M 52 -15 C 84 -20 110 -14 120 7", "w": 12.0},  # index, over the neck
]
const CREASES := [
	"M 99 1 C 92 -3 84 -6 76 -7",   # index on middle
	"M 95 13 C 88 9 80 7 73 6",     # middle on ring
	"M 88 26 C 82 22 75 20 69 19",  # ring on little
]
const THUMB := {"d": "M 70 -20 C 98 -24 124 -14 136 0", "w": 10.0}

# The back of the hand: an even taper from the wrist to the knuckles, the top
# edge rising gently; its knuckle end stays under the fingers.
const PALM := "M -16 -18 C 10 -19 32 -21 52 -21 L 57 -12 L 56 12 L 52 26 C 34 25 12 23 -16 21 Z"

func _initialize() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "layout.json"))
	for side in ["left", "right"]:
		_save(layout, "hand_%s_front" % side, _front(), side == "right")
		_save(layout, "hand_%s_thumb" % side, _thumb(), side == "right")
	var path := ProjectSettings.globalize_path(DIR + "layout.json")
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(layout, "  ", false))
	quit()

func _save(layout: Dictionary, id: String, body: String, mirror: bool) -> void:
	var info: Dictionary = layout.pieces[id]
	var size := Vector2(info.size[0], info.size[1])
	var pivot := Vector2(info.pivot_in_image[0], info.pivot_in_image[1])
	# the viewBox puts the wrist where the pivot sits in the image
	var x0 := -pivot.x
	if mirror:
		body = "<g transform=\"scale(-1,1)\">%s</g>" % body
	var svg := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" viewBox=\"%s %s %d %d\">%s</svg>" \
			% [size.x, size.y, x0, -pivot.y, size.x, size.y, body]
	var img := Image.new()
	img.load_svg_from_string(svg, 1.0)
	img.save_png(ProjectSettings.globalize_path(DIR + info.file))
	print("saved ", info.file)

func _front() -> String:
	var ink := _path(PALM, INK, LINE * 2, INK)
	var fill := _path(PALM, FILL, 0, FILL)
	for f in FINGERS:
		ink += _stroke(f.d, INK, f.w + LINE * 2)
		fill += _stroke(f.d, FILL, f.w)
	var out := ink + fill
	for d in CREASES:
		out += _stroke(d, INK, CREASE)
	return out

func _thumb() -> String:
	return _stroke(THUMB.d, INK, THUMB.w + LINE * 2) + _stroke(THUMB.d, FILL, THUMB.w)

func _stroke(d: String, colour: String, width: float) -> String:
	return "<path d=\"%s\" fill=\"none\" stroke=\"%s\" stroke-width=\"%s\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>" % [d, colour, width]

func _path(d: String, fill_colour: String, width: float, stroke_colour: String) -> String:
	return "<path d=\"%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"%s\" stroke-linejoin=\"round\"/>" % [d, fill_colour, stroke_colour, width]

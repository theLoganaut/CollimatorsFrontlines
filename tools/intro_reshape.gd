extends SceneTree
## Reshapes pieces of the studio intro, starting from the originals kept in
## assets/intro/trismeg/_preview/:
## - robe: sloped shoulders, a soft drape between the arms, sleeves that hang
##   to a soft point. The new robe is the original plus the ADD shapes, minus
##   the CUT shapes, in robe image pixels (700×647) for the left half; the
##   right half is the mirror about x = 350.
## - cuffs: the new robe cut out under each cuff piece, so the wrists still
##   disappear into the sleeves (no line at the wrist).
## - vial_left: a straight test tube, the width of its neck down to a round
##   bottom.
## Godot --headless --path . -s tools/intro_reshape.gd

const DIR := "res://assets/intro/trismeg/"
const FILL := Color("#f3f3f8")

# The underside of the forearms: a soft drape meeting at the middle instead
# of a sharp V, rounding down into the top of each sleeve's opening.
const ADD := [
	"M 140 400 L 350 400 L 350 446 C 300 449 250 458 214 468 C 202 472 198 480 197 492 L 140 492 Z",
]
const CUT := [
	# shoulders slope from the hood down to the arm
	"M 193 240 C 170 275 110 320 74 352 C 45 380 22 420 12 455 L 0 455 L 0 236 Z",
]
# Each sleeve's opening is drawn whole: inside SLEEVE_AREA the robe is exactly
# SLEEVE. It reaches out over the hand to just before the knuckles (the wrist
# is at x 150, the knuckles at about x 200), then hangs in one smooth curve
# to a soft point.
const SLEEVE_AREA := "M 30 492 L 240 492 L 240 647 L 0 647 L 0 540 L 30 540 Z"
const SLEEVE := "M 30 492 L 197 492 C 198 515 198 532 196 548 C 190 582 158 618 90 645 C 76 645 60 640 44 630 C 18 612 4.5 582 4.5 540 L 30 540 Z"
# Each cuff is the robe drawn again over the hand, so the back of the hand
# stays inside the sleeve, as far right as the sleeve reaches. (The intro
# draws the vessel again over it, so the cuff hiding a vessel doesn't show.)
const CUFF_RIGHT := 215
const CUFF_BOTTOM := 572

# The test tube, in vial image pixels (65×193): neck edges at x 19 and 46.
# The original neck's outline runs x 18.9–21.8 and 42.9–45.8.
const TUBE_FROM := 18  # rows above this stay as drawn (the rim)
const TUBE := "M 20.35 10 L 20.35 176 A 12 12 0 0 0 44.35 176 L 44.35 10"
const INK := "#0b0a12"
const VIAL_LINE := 2.9

func _initialize() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "layout.json"))
	var robe := Image.load_from_file(ProjectSettings.globalize_path(DIR + "_preview/robe_original.png"))
	robe.convert(Image.FORMAT_RGBA8)
	var size := robe.get_size()
	var add := _mask(ADD, size)
	var cut := _mask(CUT, size)
	var area := _mask([SLEEVE_AREA], size)
	var sleeve := _mask([SLEEVE], size)
	for y in size.y:
		for x in size.x:
			var a := maxf(robe.get_pixel(x, y).a, add.get_pixel(x, y).a)
			a = minf(a, 1.0 - cut.get_pixel(x, y).a)
			if area.get_pixel(x, y).a > 0.5:
				a = sleeve.get_pixel(x, y).a
			robe.set_pixel(x, y, Color(FILL, a))
	robe.save_png(ProjectSettings.globalize_path(DIR + "robe.png"))
	# each cuff: the new robe under the cuff piece's rectangle
	var robe_info: Dictionary = layout.pieces.robe
	var robe_origin := _v(robe_info.pivot_screen) - _v(robe_info.pivot_in_image)
	for side in ["left", "right"]:
		var info: Dictionary = layout.pieces["cuff_" + side]
		var wrist := _v(info.pivot_screen) - robe_origin
		var top := int(round(wrist.y - float(info.pivot_in_image[1])))
		var left: int = 65 if side == "left" else size.x - CUFF_RIGHT
		var right: int = CUFF_RIGHT if side == "left" else size.x - 65
		var cuff := robe.get_region(Rect2i(left, top, right - left, CUFF_BOTTOM - top))
		cuff.save_png(ProjectSettings.globalize_path(DIR + info.file))
		info.size = [right - left, CUFF_BOTTOM - top]
		info.pivot_in_image = [snappedf(wrist.x - left, 0.1), info.pivot_in_image[1]]
	FileAccess.open(ProjectSettings.globalize_path(DIR + "layout.json"), FileAccess.WRITE).store_string(JSON.stringify(layout, "  ", false))
	_vial(layout)
	print("saved robe, cuffs and vial")
	quit()

func _vial(layout: Dictionary) -> void:
	var info: Dictionary = layout.pieces.vial_left
	var vial := Image.load_from_file(ProjectSettings.globalize_path(DIR + "_preview/vial_left_original.png"))
	vial.convert(Image.FORMAT_RGBA8)
	var size := vial.get_size()
	var svg := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\"><path d=\"%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"%s\"/></svg>" \
			% [size.x, size.y, TUBE, "#" + FILL.to_html(false), INK, VIAL_LINE]
	var tube := Image.new()
	tube.load_svg_from_string(svg, 1.0)
	tube.convert(Image.FORMAT_RGBA8)
	for y in range(TUBE_FROM, size.y):
		for x in size.x:
			vial.set_pixel(x, y, tube.get_pixel(x, y))
	vial.save_png(ProjectSettings.globalize_path(DIR + info.file))

## The shapes (left half, mirrored for the right) as an alpha mask.
func _mask(shapes: Array, size: Vector2i) -> Image:
	var body := ""
	for d in shapes:
		body += "<path d=\"%s\" fill=\"#fff\"/>" % d
		body += "<path d=\"%s\" fill=\"#fff\" transform=\"translate(%d,0) scale(-1,1)\"/>" % [d, size.x]
	var svg := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\">%s</svg>" % [size.x, size.y, body]
	var img := Image.new()
	img.load_svg_from_string(svg, 1.0)
	img.convert(Image.FORMAT_RGBA8)
	return img

func _v(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))

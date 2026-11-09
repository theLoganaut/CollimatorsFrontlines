extends Node
## Dev tool: every enemy intent icon and status badge at board size, saved
## as a PNG (and a ×3 nearest-neighbour copy beside it) to judge how they
## read small (at the window's stretch on this screen, as the game shows them). Needs a window (not --headless):
##   Godot --path . res://tools/IconSheet.tscn -- <out.png> [--colorblind]

const COL := 48.0
const PAD := 16.0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "user://icon_sheet.png"
	for a in args:
		if a == "--colorblind":
			Palette.colorblind = true
		elif not a.begins_with("--"):
			out = a
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Palette.BG
	bg.size = Vector2(COL * 8 + PAD * 2, 400)
	root.add_child(bg)

	var kinds := [CardData.INTENT_ATTACK, CardData.INTENT_HEAVY_ATTACK, CardData.INTENT_BLOCK,
		CardData.INTENT_STATUS, CardData.INTENT_BUFF, IntentIcon.INTENT_CHARGE,
		IntentIcon.INTENT_VENT, IntentIcon.INTENT_OVERHEAT]
	var names := ["attack", "heavy", "guard", "afflict", "recover", "charge", "vent", "overheat"]
	for i in range(kinds.size()):
		_label(root, names[i], Vector2(PAD + i * COL, 4))
		# plain, active, then the marks: cancelled, Shocked, charged, previewed stop
		var states := [{}, {"active": true}, {"cancelled": true}, {"weakened": true}, {"charged": true}, {"preview": "maybe_stop"}]
		for j in range(states.size()):
			var st: Dictionary = states[j]
			var icon := IntentIcon.new()
			icon.position = Vector2(PAD + i * COL + 6, 22 + j * 34)
			icon.cancelled = st.get("cancelled", false)
			icon.weakened = st.get("weakened", false)
			icon.charged = st.get("charged", false)
			root.add_child(icon)
			icon.setup(kinds[i], st.get("active", false))
			icon.set_preview(st.get("preview", ""))

	var statuses := ["shock", "acid", "burn", "absorb", "deflect", "disabled", "offline", "freeze", "coolant", "jam", "smoke"]
	for i in range(statuses.size()):
		var x := PAD + (i % 6) * 64.0
		var y := 240.0 + (i / 6) * 76.0
		var b := PassiveRow.StatusBadge.new()
		b.status = statuses[i]
		b.stacks = 2
		b.position = Vector2(x + 12, y)
		root.add_child(b)
		_label(root, statuses[i], Vector2(x, y + 40))

	for _f in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	# the window is stretched (canvas_items), so this is the size it shows at on this screen
	var k: float = img.get_width() / get_viewport().get_visible_rect().size.x
	img = img.get_region(Rect2i(Vector2i.ZERO, Vector2i(bg.size * k)))
	img.save_png(out)
	var big := img.duplicate() as Image
	big.resize(img.get_width() * 2, img.get_height() * 2, Image.INTERPOLATE_NEAREST)
	big.save_png(out.get_basename() + "_x2.png")
	print("saved ", out)
	get_tree().quit()

func _label(parent: Control, text: String, pos: Vector2) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	parent.add_child(l)

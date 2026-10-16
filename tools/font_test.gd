extends Node
## Dev tool: renders the default font in each style the game uses (plain,
## colored, bold, link, outlined) on a glass-dark panel and saves a PNG, to
## check font settings (MSDF, hinting) for artifacts. Needs a window:
##   Godot --path . res://tools/FontTest.tscn -- <out.png>

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if not args.is_empty() else "user://font_test.png"
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.06, 0.07)
	bg.size = Vector2(1152, 720)
	add_child(bg)
	var y := 20.0
	for bb in ["Plain: Lose that much Heat.",
			"[color=#ffd84a]Colored[/color]: Lose that much Heat.",
			"[color=#ffd84a][b]Vent[/b][/color]  Bold: Lose that much Heat.",
			"[color=#7fe0a0][url=Absorb]Absorb[/url][/color] Link: Gain Absorb 5.",
			"[b]Bold only[/b] and [i]italic[/i]",
			"[color=#ffd84a][outline_size=2][outline_color=#ffd84a]Vent[/outline_color][/outline_size][/color]  Outline as bold: Lose that much Heat."]:
		for fs in [11, 13, 16]:
			var l := RichTextLabel.new()
			l.bbcode_enabled = true
			l.fit_content = true
			l.size = Vector2(520, 30)
			l.position = Vector2(20, y)
			l.add_theme_font_size_override("normal_font_size", fs)
			l.add_theme_font_size_override("bold_font_size", fs)
			l.text = bb
			add_child(l)
			y += fs + 12.0
	var outl := Label.new()
	outl.text = "Outlined label 199 / 199 HP"
	outl.position = Vector2(600, 20)
	outl.add_theme_constant_override("outline_size", 3)
	outl.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(outl)
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()

class_name UIKit
extends RefCounted
## Small builders shared by the run screens (reward, refit, repair bay,
## autonomous bay, debrief) so buttons, panels and headers look the same.

static func label(text: String, font_size: int = 14, color: Color = Palette.TEXT, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Card or passive text with its statuses and keywords tinted, each
## opening its rule on hover (StatusGlossary.annotate, HoloHint). It passes clicks
## on to what it sits in.
static func rich_label(text: String, font_size: int = 12, color: Color = Palette.TEXT) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.add_theme_font_size_override("normal_font_size", font_size)
	l.add_theme_color_override("default_color", color)
	l.text = StatusGlossary.annotate(text)
	# Statuses and keywords are links: hovering one opens its rule at once,
	# in a holo window just below it (HoloHint).
	l.meta_underlined = false
	l.meta_hover_started.connect(func(meta):
		var e := StatusGlossary.lookup(str(meta))
		if not e.is_empty():
			HoloHint.open(l, [e], [], false, l.get_global_mouse_position())
		var st := StatusGlossary.status_id(str(meta))
		if st != "":
			UIState.set_hovered_status(l, st, null)) # light the parts holding it, on every mech
	l.meta_hover_ended.connect(func(_meta):
		HoloHint.close(l)
		UIState.clear_hovered_status(l))
	l.tree_exiting.connect(func(): UIState.clear_hovered_status(l))
	return l

static func style(bg: Color, border: Color = Palette.BORDER, border_w: int = 1, radius: int = 4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	return s

static func panel(bg: Color = Palette.PANEL, border: Color = Palette.BORDER, border_w: int = 1) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", style(bg, border, border_w, 6))
	return p

## A flat button; `accent` fills it (primary actions), otherwise it's panel-colored.
static func button(text: String, accent: Color = Color.TRANSPARENT, min_size: Vector2 = Vector2(120, 44), font_size: int = 15) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = min_size
	b.pressed.connect(func(): Audio.play("ui", 0.03))
	b.add_theme_font_size_override("font_size", font_size)
	var filled := accent.a > 0.0
	var bg: Color = accent if filled else Palette.PANEL_2
	var fg: Color = Palette.BG if filled else Palette.TEXT
	b.add_theme_stylebox_override("normal", style(bg))
	b.add_theme_stylebox_override("hover", style(bg.lightened(0.12), Palette.LINK if not filled else Palette.BORDER))
	b.add_theme_stylebox_override("pressed", style(bg.darkened(0.1)))
	b.add_theme_stylebox_override("disabled", style(Palette.PANEL, Palette.BORDER))
	for key in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(key, fg)
	b.add_theme_color_override("font_disabled_color", Palette.TEXT_MUTED)
	return b

## The glass strip across the top of a screen (TopBar): its title, then
## the row the screen adds its read-outs and buttons to.
static func top_bar(parent: Control, title: String) -> HBoxContainer:
	return TopBar.make(parent, title).row

## A "◀  War Room" button for a top bar.
static func back_button(text: String = "◀  War Room") -> Button:
	var b := GlassPanel.button(text, 13)
	b.custom_minimum_size = Vector2(130, TopBar.CHIP_H)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b

static func spacer(horizontal: bool = true) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if horizontal:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c

## "123 scraps" in the chip color.
static func scraps_label(amount: int, font_size: int = 14) -> Label:
	var l := label("%d scraps" % amount, font_size, Palette.SCRAPS)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l

## "seed 12345  [Copy]": the run's seed and a button that copies it (a seed
## typed into the War Table pop-up replays the same run).
static func seed_row(seed_value: int, font_size: int = 10, color: Color = Color("7f9d9a")) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(label("seed %d" % seed_value, font_size, color))
	var b := Button.new()
	b.text = "Copy"
	b.focus_mode = Control.FOCUS_NONE
	b.flat = true
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", Palette.LINK)
	b.tooltip_text = "Copy the seed. Type it into a location's seed field on the War Table to replay this mission."
	b.pressed.connect(func():
		DisplayServer.clipboard_set(str(seed_value))
		b.text = "Copied"
		Audio.play("ui"))
	row.add_child(b)
	return row

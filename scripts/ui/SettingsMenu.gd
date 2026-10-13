class_name SettingsMenu
extends Control
## The settings / pause menu: game speed, screen shake, details-with-Shift,
## fullscreen, VSync, colorblind-safe statuses, reduce motion,
## a volume slider per audio bus, plus Resume / Restart fight / Quit.
## During a run, "Save playtest report" writes the run so far
## (PlaytestReport); "Open reports folder" shows where they go.
## "Keys and controls" opens a second page (its Gamepad button swaps to the
## gamepad's buttons and cursor speed): every key, the rebindable ones
## as buttons (click, then press the new key; Esc cancels; taking another
## action's key swaps the two), and Reset. Esc or the
## Settings button toggles it; the game is paused while it's open.
## Restart and Quit need a second click to confirm (the viewer has no
## dialog boxes, and both throw away the current fight).
##
## The restart row depends on the screen (set_restart_action): "Restart
## fight" in a standalone fight, "Eject" during a run (a run only ever ends
## in an eject), hidden in the War Room.
##
## Holo glass like the rest of the UI (Logan, 2026-10-02: it still looked
## like a prototype): a GlassPanel screen, teal section headers, glass
## buttons and chips (GlassPanel.style_button), holo switches for the
## toggles and teal sliders. Resume is the lit button; Eject and Quit are
## edged red.

signal restart_requested()

const PANEL_SIZE := Vector2(660, 560)
const ROW_H := 40.0

const TITLE_COLOR := Color("eefcfa")
const HEADER_COLOR := Color("8fd8d0")

var _panel: GlassPanel
var _choices: Dictionary = {} # setting key -> {buttons, values}
var _sliders: Dictionary = {} # setting key -> {slider, label}
var _toggles: Dictionary = {} # setting key -> HoloSwitch
var _restart_btn: Button
var _quit_btn: Button
var _confirming: String = "" # "restart" / "quit" / ""
var _controls: GlassPanel
var _key_buttons: Dictionary = {} # action -> Button
var _listening: String = "" # the action waiting for its new key
var _restart_text: String = "Restart fight"
## Saves a mid-run playtest report (only during a run).
var _report_btn: Button
var _restart_confirm_text: String = "Click again to restart"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	top_level = true # covers the whole screen whatever its parent's size or position
	_build()
	GameSettings.changed.connect(_sync)
	get_viewport().size_changed.connect(_fit_screen)
	_fit_screen()

func _fit_screen() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size

func open() -> void:
	_confirming = ""
	if _report_btn != null:
		_report_btn.visible = RunState.is_active()
		_report_btn.text = "Save playtest report"
	_show_controls(false)
	_sync()
	_fit_screen()
	visible = true
	get_tree().paused = true

## A playtest report of the run so far (PlaytestReport.snapshot).
func _save_report() -> void:
	if not RunState.is_active():
		return
	var path := PlaytestReport.write(PlaytestReport.snapshot(RunState.run), RunState.run.player_mech.id)
	Audio.play("ui" if path != "" else "denied", 0.0)
	_report_btn.text = "Saved" if path != "" else "Couldn't save"
	_report_btn.tooltip_text = path

func close() -> void:
	visible = false
	get_tree().paused = false

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _controls != null and _controls.visible:
			_show_controls(false)
		else:
			toggle()
		get_viewport().set_input_as_handled()

## While a key button is listening, the next key press is its new key.
func _input(event: InputEvent) -> void:
	if _listening == "" or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	var action := _listening
	_listening = ""
	if event.keycode != KEY_ESCAPE:
		if GameSettings.bind_key(action, event.keycode):
			Audio.play("ui")
		else:
			Audio.play("denied", 0.0)
	_sync_keys()

func _show_controls(on: bool) -> void:
	_listening = ""
	if _controls == null:
		_build_controls()
	_controls.visible = on
	_panel.visible = not on
	_sync_keys()

func _build_controls() -> void:
	_controls = GlassPanel.new()
	_controls.tint = 0.8
	_controls.size = PANEL_SIZE
	_controls.position = _panel.position
	_controls.visible = false
	add_child(_controls)
	var outer := VBoxContainer.new()
	outer.position = Vector2(24, 20)
	outer.size = Vector2(PANEL_SIZE.x - 48, PANEL_SIZE.y - 40)
	outer.add_theme_constant_override("separation", 4)
	_controls.add_child(outer)
	outer.add_child(_title("Keys and controls"))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 32)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(cols)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	left.add_child(_header("CLICK A KEY, THEN PRESS THE NEW ONE"))
	for a in GameSettings.KEY_ACTIONS:
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 34
		row.add_child(_row_label(a[1]))
		var b := GlassPanel.button("", 13)
		b.custom_minimum_size = Vector2(110, 30)
		var action: String = a[0]
		b.pressed.connect(func():
			_listening = action
			_sync_keys())
		row.add_child(b)
		_key_buttons[action] = b
		left.add_child(row)
	right.add_child(_header("FIXED"))
	for f in [["1–9", "Play a card (left to right)"], ["Space", "Fire at the target"], ["Esc", "Cancel, or open this menu"],
			["Shift / Space (hold)", "Fast-forward the enemy turn"], ["Shift (hold)", "Show details, if set to need it"],
			["Right-click", "Rotate a held part / cancel"], ["Mouse wheel", "Scroll the combat log"]]:
		right.add_child(_fixed_row(f[0], f[1]))
	var pad := VBoxContainer.new()
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pad.visible = false
	outer.add_child(pad)
	pad.add_child(_header("GAMEPAD (the stick drives the cursor; buttons follow your keys)"))
	for f in [["Left stick", "Move the cursor (D-pad: slowly)"], ["A", "Click (hold to drag)"],
			["B / Start", "Back, cancel, this menu"], ["Y", "End turn"],
			["LB / RB", "Combat: pick a card (A plays, D-pad aims)"], ["LB / RB", "Elsewhere: undo / rotate a part"],
			["Back", "Show / hide the combat log"], ["Right stick", "Scroll"], ["RT (hold)", "Fast-forward (as Shift)"]]:
		var row := _fixed_row(f[0], f[1])
		row.custom_minimum_size.y = 30
		pad.add_child(row)
	pad.add_child(_choice_row("Cursor speed", ["Slow", "Normal", "Fast"], "pad_cursor_speed", GameSettings.PAD_SPEEDS, GlassPanel.HOLO))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	outer.add_child(actions)
	var back := _action_button("Back")
	back.pressed.connect(func():
		Audio.play("ui")
		_show_controls(false))
	actions.add_child(back)
	var reset := _action_button("Reset keys")
	reset.pressed.connect(func():
		GameSettings.reset_keys()
		Audio.play("ui")
		_sync_keys())
	actions.add_child(reset)
	var switch := _action_button("Gamepad")
	switch.pressed.connect(func():
		Audio.play("ui")
		pad.visible = not pad.visible
		cols.visible = not pad.visible
		reset.visible = cols.visible
		switch.text = "Keyboard" if pad.visible else "Gamepad")
	actions.add_child(switch)

## "Key   what it does", for the fixed keys and the gamepad list.
func _fixed_row(key_text: String, what: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 34
	var k := _row_label(key_text)
	k.add_theme_color_override("font_color", Palette.LINK)
	k.size_flags_horizontal = Control.SIZE_FILL
	k.custom_minimum_size.x = 132
	row.add_child(k)
	var d := _row_label(what)
	d.add_theme_font_size_override("font_size", 13)
	d.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	row.add_child(d)
	return row

func _sync_keys() -> void:
	for action in _key_buttons:
		_key_buttons[action].text = "Press a key…" if action == _listening else GameSettings.key_label(action)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6), true)
	# a dark backing under the glass, so the fight behind doesn't show through the text
	if _panel != null:
		draw_rect(Rect2(_panel.position, PANEL_SIZE), Color(0.01, 0.025, 0.03, 0.88), true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _panel != null:
		_panel.position = (size - PANEL_SIZE) / 2.0
		if _controls != null:
			_controls.position = _panel.position
		queue_redraw()

func _build() -> void:
	_panel = GlassPanel.new()
	_panel.tint = 0.8
	_panel.size = PANEL_SIZE
	_panel.position = (size - PANEL_SIZE) / 2.0
	add_child(_panel)

	var outer := VBoxContainer.new()
	outer.position = Vector2(24, 20)
	outer.size = Vector2(PANEL_SIZE.x - 48, PANEL_SIZE.y - 40)
	outer.add_theme_constant_override("separation", 6)
	_panel.add_child(outer)

	outer.add_child(_title("Settings"))

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 32)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(cols)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 2)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 2)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)

	left.add_child(_header("GAME"))
	left.add_child(_choice_row("Speed", ["1×", "1.5×", "2×"], "speed", GameSettings.SPEEDS, GlassPanel.HOLO))
	left.add_child(_toggle_row("Screen shake", "screen_shake"))
	left.add_child(_toggle_row("Details only with Shift held", "describe_on_shift"))
	left.add_child(_header("DISPLAY"))
	left.add_child(_toggle_row("Fullscreen", "fullscreen"))
	left.add_child(_toggle_row("VSync", "vsync"))
	left.add_child(_header("ACCESSIBILITY"))
	left.add_child(_toggle_row("Colorblind-safe statuses", "colorblind"))
	left.add_child(_toggle_row("Reduce motion", "reduce_motion"))

	right.add_child(_header("AUDIO"))
	right.add_child(_slider_row("Master", "master_volume"))
	right.add_child(_slider_row("Effects", "sfx_volume"))
	right.add_child(_slider_row("Music", "music_volume"))
	right.add_child(_slider_row("Ambience", "ambience_volume"))
	right.add_child(_header("CONTROLS"))
	var keys_btn := _action_button("Keys and controls")
	keys_btn.pressed.connect(func():
		Audio.play("ui")
		_show_controls(true))
	right.add_child(keys_btn)
	right.add_child(_header("PLAYTESTING"))
	_report_btn = _action_button("Save playtest report")
	_report_btn.tooltip_text = "Writes this mission so far (every fight, replayable) to a file you can send in."
	_report_btn.pressed.connect(_save_report)
	right.add_child(_report_btn)
	var folder_btn := _action_button("Open reports folder")
	folder_btn.pressed.connect(func():
		Audio.play("ui")
		OS.shell_open(PlaytestReport.folder()))
	right.add_child(folder_btn)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	outer.add_child(actions)
	var resume := _action_button("Resume", true)
	resume.pressed.connect(close)
	actions.add_child(resume)
	_restart_btn = _action_button("Restart fight", false, Palette.DANGER)
	_restart_btn.pressed.connect(_on_restart)
	actions.add_child(_restart_btn)
	_quit_btn = _action_button("Quit game", false, Palette.DANGER)
	_quit_btn.pressed.connect(_on_quit)
	actions.add_child(_quit_btn)

## A row of buttons, one per value of a setting (speed, UI scale).
func _choice_row(text: String, labels: Array, key: String, values: Array, on_color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = ROW_H
	row.add_child(_row_label(text))
	var buttons: Array[Button] = []
	for i in range(values.size()):
		var b := GlassPanel.button(labels[i], 13)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(56, 30)
		b.pressed.connect(func():
			GameSettings.set_value(key, values[i])
			_sync())
		row.add_child(b)
		buttons.append(b)
	_choices[key] = {"buttons": buttons, "values": values, "color": on_color}
	return row

## A 0–100% slider for a volume setting (stored 0–1).
func _slider_row(text: String, key: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.custom_minimum_size.y = ROW_H + 12
	var top := HBoxContainer.new()
	top.add_child(_row_label(text))
	var pct := Label.new()
	pct.add_theme_font_size_override("font_size", 13)
	pct.add_theme_color_override("font_color", HEADER_COLOR)
	top.add_child(pct)
	box.add_child(top)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.focus_mode = Control.FOCUS_NONE
	_style_slider(slider)
	slider.value_changed.connect(func(v: float):
		GameSettings.set_value(key, v / 100.0)
		pct.text = "%d%%" % int(v))
	slider.drag_ended.connect(func(_changed: bool): Audio.play("ui"))
	box.add_child(slider)
	_sliders[key] = {"slider": slider, "label": pct}
	return box

## The screen's title, with a teal rule under it.
func _title(text: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", TITLE_COLOR)
	box.add_child(l)
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 1)
	rule.color = Color(GlassPanel.HOLO, 0.45)
	box.add_child(rule)
	return box

## A section header: small teal capitals with a faint rule running on.
func _header(text: String) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 28
	row.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = text
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	l.size_flags_vertical = Control.SIZE_FILL
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", HEADER_COLOR)
	row.add_child(l)
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 1)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_END
	rule.color = Color(GlassPanel.HOLO, 0.18)
	row.add_child(rule)
	return row

func _row_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Palette.TEXT)
	return l

func _toggle_row(text: String, key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = ROW_H
	row.add_child(_row_label(text))
	var check := HoloSwitch.new()
	check.toggled.connect(func(on: bool):
		Audio.play("ui", 0.03)
		GameSettings.set_value(key, on))
	row.add_child(check)
	_toggles[key] = check
	return row

## A glass button across its column (`primary` lit; `accent` edges it).
func _action_button(text: String, primary: bool = false, accent: Color = GlassPanel.HOLO) -> Button:
	var b := GlassPanel.button(text, 15, primary, accent)
	b.custom_minimum_size.y = 38
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b

## Teal track, a brighter fill up to the grabber, a small square grabber.
func _style_slider(slider: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0.45)
	track.border_color = Color(GlassPanel.HOLO, 0.4)
	track.set_border_width_all(1)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	slider.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(GlassPanel.HOLO, 0.55)
	slider.add_theme_stylebox_override("grabber_area", fill)
	var fill_hi := StyleBoxFlat.new()
	fill_hi.bg_color = Color(Palette.LINK, 0.55)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill_hi)
	slider.add_theme_icon_override("grabber", _grabber(Color("dffcf8"), GlassPanel.HOLO))
	slider.add_theme_icon_override("grabber_highlight", _grabber(Color("fff6d6"), Palette.LINK))

static func _grabber(fill: Color, edge: Color) -> ImageTexture:
	var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in range(1, 13):
		for y in range(1, 13):
			var on_edge := x == 1 or x == 12 or y == 1 or y == 12
			img.set_pixel(x, y, edge if on_edge else fill)
	return ImageTexture.create_from_image(img)

## `text` = "" hides the restart row.
func set_restart_action(text: String, confirm_text: String = "") -> void:
	_restart_text = text
	_restart_confirm_text = confirm_text if confirm_text != "" else "Click again to confirm"
	_restart_btn.visible = text != ""
	_sync()

## Reflect the current settings (without re-triggering their handlers).
func _sync() -> void:
	for key in _choices.keys():
		var c: Dictionary = _choices[key]
		for i in range(c["buttons"].size()):
			var on := is_equal_approx(float(GameSettings.get(key)), float(c["values"][i]))
			c["buttons"][i].set_pressed_no_signal(on)
			GlassPanel.style_button(c["buttons"][i], on, c["color"])
	for key in _sliders.keys():
		var v := roundf(float(GameSettings.get(key)) * 100.0)
		_sliders[key]["slider"].set_value_no_signal(v)
		_sliders[key]["label"].text = "%d%%" % int(v)
	for key in _toggles.keys():
		_toggles[key].set_pressed_no_signal(bool(GameSettings.get(key)))
		_toggles[key].queue_redraw()
	_restart_btn.text = _restart_confirm_text if _confirming == "restart" else _restart_text
	_quit_btn.text = "Click again to quit" if _confirming == "quit" else "Quit game"

func _on_restart() -> void:
	if _confirming != "restart":
		_confirming = "restart"
		_sync()
		return
	close()
	restart_requested.emit()

func _on_quit() -> void:
	if _confirming != "quit":
		_confirming = "quit"
		_sync()
		return
	get_tree().quit()

## An on/off switch in the holo style: a glass track with a square knob,
## lit teal when on.
class HoloSwitch extends Button:
	const TRACK := Vector2(44, 20)

	func _init() -> void:
		toggle_mode = true
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(TRACK.x + 4, 28)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		toggled.connect(func(_on: bool): queue_redraw())

	func _draw() -> void:
		var r := Rect2(Vector2(size.x - TRACK.x - 2, (size.y - TRACK.y) / 2.0), TRACK)
		var accent: Color = Palette.LINK if is_hovered() else GlassPanel.HOLO
		draw_rect(r, Color(GlassPanel.HOLO, 0.32) if button_pressed else Color(0, 0, 0, 0.45), true)
		draw_rect(r, Color(accent, 0.95 if button_pressed or is_hovered() else 0.45), false, 1.0)
		var k := TRACK.y - 6.0
		var kx := r.end.x - k - 3.0 if button_pressed else r.position.x + 3.0
		draw_rect(Rect2(kx, r.position.y + 3.0, k, k), Color("dffcf8") if button_pressed else Color(Palette.TEXT_MUTED, 0.8), true)

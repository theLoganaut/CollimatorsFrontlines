class_name SettingsMenu
extends Control
## The settings / pause menu: game speed, screen shake, details-with-Shift,
## fullscreen, VSync, colorblind-safe statuses, reduce motion,
## a volume slider per audio bus, plus Resume / Restart fight / Quit.
## "Keys and controls" opens a second page: every key, the rebindable ones
## as buttons (click, then press the new key; Esc cancels; taking another
## action's key swaps the two), and Reset. Esc or the
## Settings button toggles it; the game is paused while it's open.
## Restart and Quit need a second click to confirm (the viewer has no
## dialog boxes, and both throw away the current fight).
##
## The restart row depends on the screen (set_restart_action): "Restart
## fight" in a standalone fight, "Eject" during a run (a run only ever ends
## in an eject), hidden in the War Room.

signal restart_requested()

const PANEL_SIZE := Vector2(660, 560)
const ROW_H := 40.0

var _panel: Panel
var _choices: Dictionary = {} # setting key -> {buttons, values}
var _sliders: Dictionary = {} # setting key -> {slider, label}
var _toggles: Dictionary = {} # setting key -> CheckButton
var _restart_btn: Button
var _quit_btn: Button
var _confirming: String = "" # "restart" / "quit" / ""
var _controls: Panel
var _key_buttons: Dictionary = {} # action -> Button
var _listening: String = "" # the action waiting for its new key
var _restart_text: String = "Restart fight"
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
	_show_controls(false)
	_sync()
	_fit_screen()
	visible = true
	get_tree().paused = true

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
	_controls = Panel.new()
	_controls.add_theme_stylebox_override("panel", _panel.get_theme_stylebox("panel"))
	_controls.size = PANEL_SIZE
	_controls.position = _panel.position
	_controls.visible = false
	add_child(_controls)
	var outer := VBoxContainer.new()
	outer.position = Vector2(24, 20)
	outer.size = Vector2(PANEL_SIZE.x - 48, PANEL_SIZE.y - 40)
	outer.add_theme_constant_override("separation", 4)
	_controls.add_child(outer)
	var title := Label.new()
	title.text = "Keys and controls"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Palette.TEXT)
	outer.add_child(title)
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
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(96, 30)
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
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 34
		var k := _row_label(f[0])
		k.add_theme_color_override("font_color", Palette.LINK)
		k.size_flags_horizontal = Control.SIZE_FILL
		k.custom_minimum_size.x = 132
		row.add_child(k)
		var d := _row_label(f[1])
		d.add_theme_font_size_override("font_size", 13)
		d.add_theme_color_override("font_color", Palette.TEXT_MUTED)
		row.add_child(d)
		right.add_child(row)
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

func _sync_keys() -> void:
	for action in _key_buttons:
		_key_buttons[action].text = "Press a key…" if action == _listening else GameSettings.key_label(action)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6), true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _panel != null:
		_panel.position = (size - PANEL_SIZE) / 2.0
		if _controls != null:
			_controls.position = _panel.position

func _build() -> void:
	_panel = Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.PANEL
	style.border_color = Palette.BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.size = PANEL_SIZE
	_panel.position = (size - PANEL_SIZE) / 2.0
	add_child(_panel)

	var outer := VBoxContainer.new()
	outer.position = Vector2(24, 20)
	outer.size = Vector2(PANEL_SIZE.x - 48, PANEL_SIZE.y - 40)
	outer.add_theme_constant_override("separation", 6)
	_panel.add_child(outer)

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Palette.TEXT)
	outer.add_child(title)

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
	left.add_child(_choice_row("Speed", ["1×", "1.5×", "2×"], "speed", GameSettings.SPEEDS, Palette.HARDPOINT))
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

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	outer.add_child(actions)
	var resume := _action_button("Resume")
	resume.pressed.connect(close)
	actions.add_child(resume)
	_restart_btn = _action_button("Restart fight")
	_restart_btn.pressed.connect(_on_restart)
	actions.add_child(_restart_btn)
	_quit_btn = _action_button("Quit game")
	_quit_btn.pressed.connect(_on_quit)
	actions.add_child(_quit_btn)

## A row of buttons, one per value of a setting (speed, UI scale).
func _choice_row(text: String, labels: Array, key: String, values: Array, on_color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = ROW_H
	row.add_child(_row_label(text))
	var buttons: Array[Button] = []
	for i in range(values.size()):
		var b := Button.new()
		b.text = labels[i]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(52, 32)
		b.pressed.connect(func():
			GameSettings.set_value(key, values[i])
			Audio.play("ui")
			_sync())
		var on := StyleBoxFlat.new()
		on.bg_color = on_color
		on.set_corner_radius_all(4)
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_color_override("font_pressed_color", Palette.BG)
		row.add_child(b)
		buttons.append(b)
	_choices[key] = {"buttons": buttons, "values": values}
	return row

## A 0–100% slider for a volume setting (stored 0–1).
func _slider_row(text: String, key: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.custom_minimum_size.y = ROW_H + 12
	var top := HBoxContainer.new()
	top.add_child(_row_label(text))
	var pct := Label.new()
	pct.add_theme_font_size_override("font_size", 13)
	pct.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	top.add_child(pct)
	box.add_child(top)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(v: float):
		GameSettings.set_value(key, v / 100.0)
		pct.text = "%d%%" % int(v))
	slider.drag_ended.connect(func(_changed: bool): Audio.play("ui"))
	box.add_child(slider)
	_sliders[key] = {"slider": slider, "label": pct}
	return box

func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.y = 26
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	return l

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
	var check := CheckButton.new()
	check.focus_mode = Control.FOCUS_NONE
	check.toggled.connect(func(on: bool): GameSettings.set_value(key, on))
	row.add_child(check)
	_toggles[key] = check
	return row

func _action_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 38
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b

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
			c["buttons"][i].set_pressed_no_signal(is_equal_approx(float(GameSettings.get(key)), float(c["values"][i])))
	for key in _sliders.keys():
		var v := roundf(float(GameSettings.get(key)) * 100.0)
		_sliders[key]["slider"].set_value_no_signal(v)
		_sliders[key]["label"].text = "%d%%" % int(v)
	for key in _toggles.keys():
		_toggles[key].set_pressed_no_signal(bool(GameSettings.get(key)))
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

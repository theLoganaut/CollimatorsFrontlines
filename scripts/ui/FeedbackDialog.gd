class_name FeedbackDialog
extends CanvasLayer
## The "Send feedback" form (the Feedback button beside the location name
## on every screen, Settings, or F8): a note box and Send. Takes a
## screenshot of the game as it was and notes where the pilot is (and, in a
## fight, its replay so far; Feedback.context), then posts the note and
## Feedback.bundle to the feedback webhook. The game pauses while it's open.

const PANEL_SIZE := Vector2(560, 410)

static var _open: FeedbackDialog = null

var _panel: GlassPanel
var _note: TextEdit
var _status: Label
var _send: Button
var _cancel: Button
var _http: HTTPRequest
var _shot: Image
var _report: Dictionary = {}
var _screen: String = ""
var _ctx: Dictionary = {}
var _was_paused: bool = false
var _sending: bool = false

## Opens the form over whatever is showing (once at a time). Close the
## settings menu first, so the screenshot shows the game.
static func open(tree: SceneTree) -> void:
	if _open != null and is_instance_valid(_open):
		return
	await tree.process_frame
	await tree.process_frame
	var d := FeedbackDialog.new()
	d._shot = tree.root.get_viewport().get_texture().get_image()
	d._screen = tree.current_scene.scene_file_path.get_file().get_basename() if tree.current_scene != null else ""
	if RunState.is_active():
		d._report = PlaytestReport.snapshot(RunState.run)
	d._ctx = Feedback.context(d._screen)
	_open = d
	tree.root.add_child(d)

## The Feedback button every screen puts right of its location name
## (Logan, 2026-10-15: there at all times). Opens this form.
static func button(height: float = TopBar.CHIP_H) -> Button:
	var b := GlassPanel.button("Feedback", 12, false, Palette.LINK)
	b.custom_minimum_size = Vector2(92, height)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "Send us a bug, something confusing, or an idea (%s). Where you are goes with it." % GameSettings.key_label("feedback")
	b.pressed.connect(func():
		Audio.play("ui")
		open(b.get_tree()))
	return b

func _ready() -> void:
	layer = 250
	process_mode = Node.PROCESS_MODE_ALWAYS
	_was_paused = get_tree().paused
	get_tree().paused = true
	CrashLog.crumb("feedback form opened")
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_panel = GlassPanel.new()
	_panel.tint = 0.9
	_panel.size = PANEL_SIZE
	add_child(_panel)
	var v := VBoxContainer.new()
	v.position = Vector2(24, 20)
	v.size = PANEL_SIZE - Vector2(48, 40)
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)
	v.add_child(UIKit.label("SEND FEEDBACK", 13, Color("b9d8d4")))
	v.add_child(UIKit.label("A bug, something confusing, an idea: anything helps.", 15, Color("eefcfa"), true))
	_note = TextEdit.new()
	_note.placeholder_text = "What happened?"
	_note.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_note.custom_minimum_size = Vector2(0, 150)
	_note.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_note.add_theme_font_size_override("font_size", 14)
	v.add_child(_note)
	v.add_child(UIKit.label("From: " + str(_ctx.get("where", "?")), 12, Color("8fd8d0"), true))
	var sent := "a screenshot, this fight's replay so far, your run, recent crash reports and the game's logs" if not (_ctx.get("fight", {}) as Dictionary).is_empty() \
		else ("a screenshot, your run so far, recent crash reports and the game's logs" if RunState.is_active() else "a screenshot, recent crash reports and the game's logs")
	v.add_child(UIKit.label("Sent with it: %s." % sent, 11, Palette.TEXT_MUTED, true))
	_status = UIKit.label("", 12, Palette.WARNING, true)
	v.add_child(_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	row.add_child(UIKit.spacer())
	_cancel = GlassPanel.button("Cancel", 13)
	_cancel.custom_minimum_size = Vector2(110, 38)
	_cancel.pressed.connect(close)
	row.add_child(_cancel)
	_send = GlassPanel.button("Send", 14, true, Palette.LINK)
	_send.custom_minimum_size = Vector2(130, 38)
	_send.pressed.connect(_on_send)
	row.add_child(_send)
	_http = HTTPRequest.new()
	_http.timeout = 60.0
	_http.request_completed.connect(_on_sent)
	add_child(_http)
	if not Feedback.enabled():
		_send.disabled = true
		_status.text = "Feedback isn't set up in this build."
	get_viewport().size_changed.connect(_center)
	_center()
	_note.grab_focus.call_deferred()

func _center() -> void:
	_panel.position = ((get_viewport().get_visible_rect().size - PANEL_SIZE) / 2.0).floor()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and not _sending:
		get_viewport().set_input_as_handled()
		close()

func _on_send() -> void:
	if _sending or not Feedback.enabled():
		return
	_sending = true
	_send.disabled = true
	_cancel.disabled = true
	_note.editable = false
	_status.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	_status.text = "Sending…"
	await get_tree().process_frame # let "Sending…" show before the zip is built
	var b := Feedback.bundle(_note.text, _shot, _report, _ctx)
	var mp := Feedback.multipart(Feedback.message(_note.text, str(_ctx.get("where", _screen))), b["name"], b["bytes"])
	var err := _http.request_raw(Feedback.webhook_url(), ["Content-Type: " + mp["content_type"]], HTTPClient.METHOD_POST, mp["body"])
	if err != OK:
		_failed("couldn't start (%s)" % error_string(err))

func _on_sent(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300:
		CrashLog.crumb("feedback sent")
		Audio.play("ui")
		_status.add_theme_color_override("font_color", Palette.OK)
		_status.text = "Sent. Thanks, pilot."
		await get_tree().create_timer(1.4, true, false, true).timeout
		close()
	elif result != HTTPRequest.RESULT_SUCCESS:
		_failed("no connection")
	else:
		_failed("the server said %d" % code)

func _failed(why: String) -> void:
	CrashLog.crumb("feedback failed: %s" % why)
	Audio.play("denied")
	_sending = false
	_send.disabled = false
	_cancel.disabled = false
	_note.editable = true
	_status.add_theme_color_override("font_color", Palette.WARNING)
	_status.text = "Couldn't send it (%s). Check your connection and try again." % why

func close() -> void:
	if _sending:
		return
	get_tree().paused = _was_paused
	_open = null
	queue_free()

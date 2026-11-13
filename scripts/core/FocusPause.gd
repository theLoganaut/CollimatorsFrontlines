extends Node
## Autoload. Pauses the game while it isn't in front: the window loses focus
## (alt-tab, the Steam Deck's Steam / ... menus, the Deck going to sleep) or
## the Steam overlay opens. The tree pauses, the sound goes quiet and the
## frame rate drops (battery on the Deck); all three come back as they were
## when the game is in front again. A pause the game was already in (the
## settings menu, the feedback dialog) is left alone.
##
## A controller that goes away while it's in use (Gamepad.disconnected) also
## pauses, with a "Controller disconnected" screen over everything until the
## player presses a key, clicks or presses a button on a pad.

const BACKGROUND_FPS := 15

var _paused_by_us: bool = false
var _was_muted: bool = false
var _fps: int = 0
var _away: bool = false
var _overlay: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var steam: Object = SteamService.api()
	if steam != null and steam.has_signal("overlay_toggled"):
		steam.overlay_toggled.connect(_on_overlay)
	Gamepad.disconnected.connect(_on_pad_lost)

var _lost_layer: CanvasLayer = null
var _lost_paused: bool = false

## The pad in use went away: pause behind a notice until any key, click or button.
func _on_pad_lost() -> void:
	if _lost_layer != null or DisplayServer.get_name() == "headless":
		return
	_lost_layer = CanvasLayer.new()
	_lost_layer.layer = 128
	_lost_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_lost_layer.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	dim.add_child(box)
	var title := UIKit.label("CONTROLLER DISCONNECTED", 26, Palette.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var line := UIKit.label("The game is paused. Reconnect it and press any button, or press a key or click to carry on.", 14, Palette.TEXT_MUTED)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(line)
	add_child(_lost_layer)
	_lost_paused = not get_tree().paused
	get_tree().paused = true
	Audio.play("ui", 0.0)

func _input(event: InputEvent) -> void:
	if _lost_layer == null:
		return
	var kind_ok: bool = event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton
	var press: bool = kind_ok and event.is_pressed() and not event.is_echo()
	get_viewport().set_input_as_handled() # nothing reaches the game behind the notice
	if not press:
		return
	_lost_layer.queue_free()
	_lost_layer = null
	if _lost_paused:
		get_tree().paused = false
	_lost_paused = false

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			_away = true
			_update()
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED:
			_away = false
			_update()

func _on_overlay(active: bool, _user_initiated = null, _app_id = null) -> void:
	_overlay = active
	_update()

## Whether the game is paused because it's in the background.
func is_away() -> bool:
	return _paused_by_us

func _update() -> void:
	var away := _away or _overlay
	if away == _paused_by_us or Engine.is_editor_hint() or DisplayServer.get_name() == "headless":
		return
	if OS.has_feature("movie") or Engine.get_write_movie_path() != "":
		return # render_replay.sh: the window is never in front
	var tree := get_tree()
	if away:
		if tree.paused:
			return # already paused (a menu): leave it to that menu
		_paused_by_us = true
		tree.paused = true
		_was_muted = AudioServer.is_bus_mute(0)
		AudioServer.set_bus_mute(0, true)
		_fps = Engine.max_fps
		Engine.max_fps = BACKGROUND_FPS
		CrashLog.crumb("Paused: game in the background")
	else:
		_paused_by_us = false
		tree.paused = false
		AudioServer.set_bus_mute(0, _was_muted)
		Engine.max_fps = _fps
		CrashLog.crumb("Resumed: game in front")

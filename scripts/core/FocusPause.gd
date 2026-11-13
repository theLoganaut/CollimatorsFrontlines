extends Node
## Autoload. Pauses the game while it isn't in front: the window loses focus
## (alt-tab, the Steam Deck's Steam / ... menus, the Deck going to sleep) or
## the Steam overlay opens. The tree pauses, the sound goes quiet and the
## frame rate drops (battery on the Deck); all three come back as they were
## when the game is in front again. A pause the game was already in (the
## settings menu, the feedback dialog) is left alone.

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

extends Node
## Autoload. Player settings, saved to user://settings.cfg and applied on
## load and on every change. They belong to the machine, not the pilot, so
## they aren't in the profile: a new profile keeps them (Claude, 2026-09-30).
## Game speed works through Engine.time_scale, so every animation, tween
## and timer (the enemy crosshair trace, HP countdowns, hit effects) speeds
## up together.
##
## Audio has a bus each for sound effects, music and ambience under Master
## (made here at startup, so no bus layout file is needed); each slider is
## 0 (off) to 1. Colorblind
## mode swaps the status colors for a colorblind-safe set and draws each
## status as its own shape (Palette.status_color / status_shape). Reduce
## motion stops screen shake, rain, the holograms' flicker and sway, and
## the crosshair's spin (read where each one moves).

signal changed()

const PATH := "user://settings.cfg"
## Rebindable keys (Logan, 2026-09-30): [action, what it does, default].
## Number keys 1–9 (play a card) and Esc (cancel / settings) stay fixed.
const KEY_ACTIONS := [
	["end_turn", "End turn", KEY_E],
	["fast_forward", "Fast enemy turns (toggle)", KEY_F],
	["log", "Show / hide the combat log", KEY_L],
	["map", "Show / hide the location map (in a fight or at a stop)", KEY_M],
	["next_target", "Next target (Shift: previous)", KEY_TAB],
	["fire", "Fire at the target", KEY_ENTER],
	["rotate", "Rotate a held part", KEY_R],
	["undo", "Undo a move (with Ctrl / Cmd)", KEY_Z],
]
## Keys that can't be bound (they already mean something fixed).
const RESERVED_KEYS := [KEY_ESCAPE, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9,
	KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_5, KEY_KP_6, KEY_KP_7, KEY_KP_8, KEY_KP_9, KEY_SHIFT, KEY_CTRL, KEY_META, KEY_ALT]
const SPEEDS := [1.0, 1.5, 2.0]
const BUSES := ["SFX", "Music", "Ambience"]

var speed: float = 1.0
var fullscreen: bool = true
var vsync: bool = true
var screen_shake: bool = true
## The combat log starts closed; its button opens it (remembered).
var log_open: bool = false
## The description box shows while hovering; with this on, only while Shift is held too.
var describe_on_shift: bool = false
var master_volume: float = 1.0
var sfx_volume: float = 0.7
var music_volume: float = 0.5
var ambience_volume: float = 0.5
var colorblind: bool = false
var reduce_motion: bool = false
## Gamepad cursor speed (Gamepad): one of PAD_SPEEDS.
var pad_cursor_speed: float = 1.0
const PAD_SPEEDS := [0.6, 1.0, 1.5]
## action -> keycode (only the ones changed from KEY_ACTIONS' defaults).
var keys: Dictionary = {}

## The key bound to `action`.
func key(action: String) -> int:
	if keys.has(action):
		return int(keys[action])
	for a in KEY_ACTIONS:
		if a[0] == action:
			return a[2]
	return KEY_NONE

## Whether a pressed key event is `action`'s key (Enter on the keypad counts
## as Enter).
func is_key(event: InputEventKey, action: String) -> bool:
	var k := key(action)
	return event.keycode == k or (k == KEY_ENTER and event.keycode == KEY_KP_ENTER)

func key_label(action: String) -> String:
	return OS.get_keycode_string(key(action))

## Binds `action` to `keycode`; an action already on that key takes this
## one's old key (a swap). Returns false for a reserved key.
func bind_key(action: String, keycode: int) -> bool:
	if RESERVED_KEYS.has(keycode) or keycode == KEY_NONE:
		return false
	var old := key(action)
	for a in KEY_ACTIONS:
		if a[0] != action and key(a[0]) == keycode:
			keys[a[0]] = old
	keys[action] = keycode
	_save()
	changed.emit()
	return true

func reset_keys() -> void:
	keys = {}
	_save()
	changed.emit()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	_load()
	apply()

func set_value(key: String, value) -> void:
	if get(key) == value:
		return
	set(key, value)
	apply()
	_save()
	changed.emit()

## The volume setting (0 to 1) of a bus: "Master", "SFX", "Music", "Ambience".
func volume(bus: String) -> float:
	match bus:
		"Master": return master_volume
		"SFX": return sfx_volume
		"Music": return music_volume
		"Ambience": return ambience_volume
	return 1.0

func apply() -> void:
	Engine.time_scale = speed
	Palette.colorblind = colorblind
	for bus in ["Master"] + BUSES:
		var i := AudioServer.get_bus_index(bus)
		if i >= 0:
			var v := volume(bus)
			AudioServer.set_bus_mute(i, v <= 0.0)
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
	if DisplayServer.get_name() == "headless":
		return
	var win := get_window()
	if fullscreen and win.mode != Window.MODE_FULLSCREEN:
		win.mode = Window.MODE_FULLSCREEN
	elif not fullscreen and win.mode == Window.MODE_FULLSCREEN:
		win.mode = Window.MODE_WINDOWED
		win.move_to_center()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	speed = float(cfg.get_value("game", "speed", speed))
	if not SPEEDS.has(speed):
		speed = 1.0
	screen_shake = bool(cfg.get_value("game", "screen_shake", screen_shake))
	log_open = bool(cfg.get_value("game", "log_open", log_open))
	describe_on_shift = bool(cfg.get_value("game", "describe_on_shift", describe_on_shift))
	master_volume = clampf(float(cfg.get_value("audio", "master_volume", master_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx_volume", sfx_volume)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value("audio", "music_volume", music_volume)), 0.0, 1.0)
	ambience_volume = clampf(float(cfg.get_value("audio", "ambience_volume", ambience_volume)), 0.0, 1.0)
	fullscreen = bool(cfg.get_value("display", "fullscreen", fullscreen))
	vsync = bool(cfg.get_value("display", "vsync", vsync))
	colorblind = bool(cfg.get_value("accessibility", "colorblind", colorblind))
	reduce_motion = bool(cfg.get_value("accessibility", "reduce_motion", reduce_motion))
	pad_cursor_speed = float(cfg.get_value("game", "pad_cursor_speed", pad_cursor_speed))
	if not PAD_SPEEDS.has(pad_cursor_speed):
		pad_cursor_speed = 1.0
	keys = {}
	for a in KEY_ACTIONS:
		if cfg.has_section_key("keys", a[0]):
			keys[a[0]] = int(cfg.get_value("keys", a[0]))

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "speed", speed)
	cfg.set_value("game", "screen_shake", screen_shake)
	cfg.set_value("game", "log_open", log_open)
	cfg.set_value("game", "describe_on_shift", describe_on_shift)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "ambience_volume", ambience_volume)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "vsync", vsync)
	cfg.set_value("accessibility", "colorblind", colorblind)
	cfg.set_value("accessibility", "reduce_motion", reduce_motion)
	cfg.set_value("game", "pad_cursor_speed", pad_cursor_speed)
	for a in keys:
		cfg.set_value("keys", a, keys[a])
	cfg.save(PATH)

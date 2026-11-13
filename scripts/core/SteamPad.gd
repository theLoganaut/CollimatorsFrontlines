class_name SteamPad
extends RefCounted
## Steam Input with In-Game Actions (Valve's full controller support): the
## game's actions are named in steam_input/game_actions_5441720.vdf (the
## Action Manifest, shipped next to the game), the player binds them to any
## controller in Steam's configurator, and this reads them every frame.
## Gamepad turns each action into the pad id the screens already handle
## (a JoyButton; JOY_BUTTON_MAX = fast-forward), so nothing past Gamepad
## knows which path the input took. Button prompts ask `glyph` / `origin_name`
## for the button an action is bound to on this controller (Steam's own
## pictures and names, for every controller Steam knows).
##
## Live only with Steam running, a controller Steam Input handles, and the
## game's actions bound on it (the click action has a button). Otherwise the
## controller reaches Godot as an ordinary gamepad (Steam's Gamepad template)
## and Gamepad reads it directly, as before.

const MANIFEST := "game_actions_5441720.vdf"
const ACTION_SET := "Play"
## Steam action -> the pad id Gamepad and the screens use for it.
const DIGITAL := {
	"click": JOY_BUTTON_A, "back": JOY_BUTTON_B, "menu": JOY_BUTTON_START, "end_turn": JOY_BUTTON_Y,
	"inspect": JOY_BUTTON_X, "prev": JOY_BUTTON_LEFT_SHOULDER, "next": JOY_BUTTON_RIGHT_SHOULDER,
	"log": JOY_BUTTON_BACK, "map": JOY_BUTTON_RIGHT_STICK, "fast_forward": JOY_BUTTON_MAX,
	"nudge_up": JOY_BUTTON_DPAD_UP, "nudge_down": JOY_BUTTON_DPAD_DOWN,
	"nudge_left": JOY_BUTTON_DPAD_LEFT, "nudge_right": JOY_BUTTON_DPAD_RIGHT,
}
## Seconds between looks at which controllers are connected, besides Steam's
## connect / disconnect events (GodotSteam prints a line on every look).
const CHECK_EVERY := 5.0

var _steam: Object = null
var _set: int = 0
var _digital: Dictionary = {} # action name -> action handle
var _analog: Dictionary = {}
var _jb_action: Dictionary = {} # pad id -> action name
## The controller in use (Steam's input handle), 0 for none.
var handle: int = 0
var _bound: bool = false
var _down: Dictionary = {} # pad id -> held
var _check_t: float = 0.0
var _glyphs: Dictionary = {} # origin -> Texture2D (null: none)

## Where Steam reads the manifest: the project folder in the editor, next
## to the executable in a build (tools/steam_release.sh copies it there).
static func manifest_path() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://steam_input/" + MANIFEST)
	return OS.get_executable_path().get_base_dir().path_join(MANIFEST)

## Starts Steam Input (`steam`: the GodotSteam singleton, or null). False
## when there's no Steam.
func start(steam: Object) -> bool:
	if steam == null or not steam.has_method("inputInit") or DisplayServer.get_name() == "headless":
		return false # (headless tools and tests: no controllers)
	if not steam.inputInit(false):
		CrashLog.crumb("Steam Input: init failed")
		return false
	_steam = steam
	var path := manifest_path()
	if FileAccess.file_exists(path):
		steam.setInputActionManifestFilePath(path)
	else:
		CrashLog.crumb("Steam Input: no action manifest at %s" % path)
	_set = steam.getActionSetHandle(ACTION_SET)
	for a in DIGITAL:
		_digital[a] = steam.getDigitalActionHandle(a)
		_jb_action[DIGITAL[a]] = a
	for a in ["cursor", "scroll"]:
		_analog[a] = steam.getAnalogActionHandle(a)
	steam.enableDeviceCallbacks()
	for sig in ["input_device_connected", "input_device_disconnected", "input_configuration_loaded"]:
		if steam.has_signal(sig):
			steam.connect(sig, _on_device)
	_check(true)
	CrashLog.crumb("Steam Input: manifest %s, %d controller(s), actions %s" % [
		"found" if FileAccess.file_exists(path) else "MISSING", steam.getConnectedControllers().size(), "bound" if _bound else "not bound"])
	return true

## A controller came or went, or its configuration loaded: look again.
func _on_device(_a = null, _b = null, _c = null) -> void:
	_check(false)

## Lets go of Steam Input before the game quits (Steam's callbacks must not
## reach a freed object).
func stop() -> void:
	if _steam == null:
		return
	for sig in ["input_device_connected", "input_device_disconnected", "input_configuration_loaded"]:
		if _steam.has_signal(sig) and _steam.is_connected(sig, _on_device):
			_steam.disconnect(sig, _on_device)
	_steam.inputShutdown()
	_steam = null
	handle = 0

## Steam Input is driving the pad: a controller with the game's actions bound.
func live() -> bool:
	return _steam != null and handle != 0 and _bound

## Call every frame. Returns the pad ids whose state changed, as
## [[id, pressed], ...], and keeps `handle` on a connected controller
## (a controller that goes away sets it to 0: Gamepad pauses).
func poll(delta: float) -> Array:
	var out: Array = []
	if _steam == null:
		return out
	_check_t -= delta
	if _check_t <= 0.0:
		_check(false)
	if not live():
		return out
	_steam.activateActionSet(handle, _set)
	for a in _digital:
		var d: Dictionary = _steam.getDigitalActionData(handle, _digital[a])
		var jb: int = DIGITAL[a]
		var on: bool = bool(d.get("state", false))
		if on != bool(_down.get(jb, false)):
			_down[jb] = on
			out.append([jb, on])
	return out

## Whether the action behind pad id `jb` is held.
func held(jb: int) -> bool:
	return live() and bool(_down.get(jb, false))

## An analog action ("cursor", "scroll") as Godot's stick axes (y down).
func stick(action: String) -> Vector2:
	if not live():
		return Vector2.ZERO
	var d: Dictionary = _steam.getAnalogActionData(handle, _analog[action])
	return Vector2(float(d.get("x", 0.0)), -float(d.get("y", 0.0)))

## The controller's first button bound to pad id `jb`'s action, or 0.
func origin(jb: int) -> int:
	if not live() or not _jb_action.has(jb):
		return 0
	var origins: Array = _steam.getDigitalActionOrigins(handle, _set, _digital[_jb_action[jb]])
	return int(origins[0]) if not origins.is_empty() else 0

## Steam's picture of the button bound to pad id `jb` (null: none).
func glyph(jb: int) -> Texture2D:
	var o := origin(jb)
	if o == 0:
		return null
	if not _glyphs.has(o):
		var tex: Texture2D = null
		var size: int = ClassDB.class_get_integer_constant(_steam.get_class(), "INPUT_GLYPH_SIZE_MEDIUM")
		var path: String = _steam.getGlyphPNGForActionOrigin(o, size, 0)
		if path != "":
			var img := Image.load_from_file(path)
			if img != null and not img.is_empty():
				tex = ImageTexture.create_from_image(img)
		_glyphs[o] = tex
	return _glyphs[o]

## Steam's name for the button bound to pad id `jb` ("" when none).
func origin_name(jb: int) -> String:
	var o := origin(jb)
	return str(_steam.getStringForActionOrigin(o)) if o != 0 else ""

## Picks the controller to read (the first connected) and whether the game's
## actions are bound on it.
func _check(first: bool) -> void:
	_check_t = CHECK_EVERY
	var pads: Array = _steam.getConnectedControllers()
	var was := handle
	if not pads.has(handle):
		handle = int(pads[0]) if not pads.is_empty() else 0
		_down.clear()
		_glyphs.clear()
	if handle != 0:
		_steam.activateActionSet(handle, _set)
		_bound = not _steam.getDigitalActionOrigins(handle, _set, _digital["click"]).is_empty()
	else:
		_bound = false
	if handle != was and not first:
		CrashLog.crumb("Steam Input: controller %s (actions %s)" % [handle if handle != 0 else "gone", "bound" if _bound else "not bound"])

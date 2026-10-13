extends Node
## Autoload. Steamworks through the GodotSteam GDExtension (addons/godotsteam,
## Steamworks SDK 1.65). Starts Steam with the game's App ID (project setting
## steam/initialization/app_data/app_id, 5441720) and keeps its callbacks
## running. Steam is optional: without the extension (tests, --script tools)
## or without a running Steam client, `available` stays false and the game
## plays on as normal.

const APP_ID_SETTING := "steam/initialization/app_data/app_id"
const DEFAULT_APP_ID := 5441720

## Steam initialised and the user logged on.
var available: bool = false
var app_id: int = DEFAULT_APP_ID
var user_id: int = 0
var user_name: String = ""
## Why Steam isn't available ("" when it is), for logs and crash reports.
var status: String = ""

var _steam: Object = null

func _ready() -> void:
	app_id = int(ProjectSettings.get_setting(APP_ID_SETTING, DEFAULT_APP_ID))
	if not Engine.has_singleton("Steam"):
		status = "GodotSteam extension not loaded"
		return
	_steam = Engine.get_singleton("Steam")
	# embed_callbacks = true: GodotSteam runs Steam's callbacks every frame itself.
	var result: Dictionary = _steam.steamInitEx(app_id, true)
	if int(result.get("status", -1)) != 0:
		status = "Steam init failed: %s" % result.get("verbal", "unknown")
		push_warning(status)
		CrashLog.crumb(status)
		return
	available = _steam.loggedOn()
	user_id = _steam.getSteamID()
	user_name = _steam.getPersonaName()
	status = "" if available else "Steam user not logged on"
	CrashLog.crumb("Steam: app %d, %s" % [app_id, user_name if available else status])

## The GodotSteam singleton, or null when Steam isn't available.
func api() -> Object:
	return _steam if available else null

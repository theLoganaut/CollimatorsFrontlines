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
## Steam Cloud syncs the saves (Auto-Cloud, tools/steam/STEAMWORKS.md): on
## for this account and this app. Set at launch; logged in the crash trail.
var cloud_on: bool = false

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
	if available:
		cloud_on = _steam.isCloudEnabledForAccount() and _steam.isCloudEnabledForApp()
		CrashLog.crumb("Steam Cloud: %s (account %s, app %s)" % ["on" if cloud_on else "off",
			_steam.isCloudEnabledForAccount(), _steam.isCloudEnabledForApp()])
	# achievements earned before Steam knew about them (or offline) catch up
	unlock_achievements(Profile.achievements.keys())
	if available:
		get_tree().scene_changed.connect(update_presence)
		update_presence()

## The GodotSteam singleton, or null when Steam isn't available.
func api() -> Object:
	return _steam if available else null

## Rich Presence: what friends see in their Steam list. The tokens
## (#Base, #Mission, #Fight) are in tools/steam/rich_presence.vdf, uploaded
## in Steamworks (Community → Rich Presence); %fight%, %mission% and
## %location% fill them in. Called on every screen change.
func update_presence() -> void:
	var steam := api()
	if steam == null:
		return
	var run: RunData = RunState.run if RunState.is_active() else null
	if run == null:
		steam.setRichPresence("steam_display", "#Base")
		return
	steam.setRichPresence("location", str(run.location.get("name", "")))
	steam.setRichPresence("mission", run.mission_name())
	var scene := get_tree().current_scene
	if scene != null and scene.scene_file_path == RunState.PHASE_SCENES[RunData.PHASE_FIGHT]:
		var kind: String = run.current_node().get("kind", RunMap.KIND_FIGHT)
		steam.setRichPresence("fight", {RunMap.KIND_ELITE: "Elite fight", RunMap.KIND_BOSS: "Boss fight"}.get(kind, "Fight"))
		steam.setRichPresence("steam_display", "#Fight")
	else:
		steam.setRichPresence("steam_display", "#Mission")

## Marks achievements earned on Steam (ids = data/achievements.json ids,
## the API names in Steamworks). Already-earned ones are a no-op; nothing
## happens without Steam.
func unlock_achievements(ids: Array) -> void:
	var steam := api()
	if steam == null or ids.is_empty():
		return
	for id in ids:
		if not steam.setAchievement(str(id)):
			push_warning("Steam: no achievement '%s' in Steamworks" % id)
	steam.storeStats()

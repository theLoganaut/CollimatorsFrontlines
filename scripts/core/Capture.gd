extends Node
## Autoload. Moments worth sharing, for players and for us:
## - The screenshot key (GameSettings "screenshot", F9) saves the screen as
##   it is to user://screenshots/ and, with Steam up, adds it to the
##   player's Steam screenshot library tagged with where they were.
## - Steam Game Recording markers (the Timeline API): menus vs playing,
##   one game phase per fight, and a marker on each highlight (a kill, a big
##   hit, an overheat, a boss phase, the result) so a player recording in
##   the background can jump straight to it and Steam offers it as a clip.
##   Steam ignores all of it unless the player records.
## Rendering a recorded fight to video for trailers is tools/render_replay.sh.

const DIR := "user://screenshots"
## A hit this big (after combat scaling) is a highlight.
const BIG_HIT := 25
## Markers are placed this far back, so the clip opens on the wind-up.
const LEAD := -2.0

enum Clip { NONE = 1, STANDARD = 2, FEATURED = 3 }
enum Mode { PLAYING = 1, STAGING = 2, MENUS = 3, LOADING = 4 }

var _flash: ColorRect
var _note: Label
var _layer: CanvasLayer
var _in_phase: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 128
	add_child(_layer)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_flash)
	_note = Label.new()
	_note.add_theme_font_size_override("font_size", 16)
	_note.add_theme_color_override("font_outline_color", Color.BLACK)
	_note.add_theme_constant_override("outline_size", 5)
	_note.modulate.a = 0.0
	_note.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_note.position = Vector2(20, -44)
	_note.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_layer.add_child(_note)
	get_tree().scene_changed.connect(_on_scene_changed)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and GameSettings.is_key(event, "screenshot"):
		get_viewport().set_input_as_handled()
		shot()

# ---------- screenshots ----------

static func folder() -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	return ProjectSettings.globalize_path(DIR)

## Saves the screen (before the flash) and, with Steam, adds it to the
## player's library. Returns the file's path ("" if it couldn't).
func shot() -> String:
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return ""
	var where := _where()
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "").replace("-", "").replace(" ", "_")
	var path := "%s/%s.png" % [folder(), stamp]
	if img.save_png(path) != OK:
		_show("Couldn't save the screenshot")
		return ""
	CrashLog.crumb("screenshot: %s" % path.get_file())
	var steam := SteamService.api()
	if steam != null:
		var handle: int = steam.addScreenshotToLibrary(path, "", img.get_width(), img.get_height())
		if handle != 0 and where != "":
			steam.setLocation(handle, where)
	Audio.play("ui", 0.0)
	_flash.color.a = 0.0 if GameSettings.reduce_motion else 0.35
	create_tween().tween_property(_flash, "color:a", 0.0, 0.25)
	_show("Screenshot saved%s" % (" (Steam library too)" if steam != null else ""))
	return path

func _show(text: String) -> void:
	_note.text = text
	_note.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(1.6)
	t.tween_property(_note, "modulate:a", 0.0, 0.5)

## "Shipyard · Assault · encounter 3 / 8 · fight, turn 4", or the screen.
func _where() -> String:
	var scene := get_tree().current_scene
	var screen := scene.scene_file_path.get_file().get_basename() if scene != null else ""
	return str(Feedback.context(screen).get("where", "")).replace("  ·  ", " · ")

# ---------- Steam Game Recording (Timeline) ----------

func _on_scene_changed() -> void:
	var scene := get_tree().current_scene
	var fight := scene != null and scene.scene_file_path == SceneRouter.COMBAT
	if not fight:
		end_fight()
	set_mode(Mode.PLAYING if RunState.is_active() or fight else Mode.MENUS)

func set_mode(mode: Mode) -> void:
	var steam := SteamService.api()
	if steam != null:
		steam.setTimelineGameMode(mode)

## A marker on the recording. `icon` is one of Steam's (steam_combat,
## steam_death, steam_explosion, steam_crown, steam_trophy...); higher
## `priority` wins when markers crowd together.
func mark(title: String, description: String = "", icon: String = "steam_marker", priority: int = 0, clip: Clip = Clip.NONE) -> void:
	var steam := SteamService.api()
	if steam != null:
		steam.addInstantaneousTimelineEvent(title, description, icon, priority, LEAD, clip)

## A fight starts: its own phase in the recording, named for what's fought.
func start_fight(enemies: String, kind: String, replay: bool) -> void:
	var steam := SteamService.api()
	if steam == null:
		return
	end_fight()
	steam.startGamePhase()
	_in_phase = true
	steam.setGamePhaseAttribute("Fight", enemies, 2)
	steam.setGamePhaseAttribute("Kind", "Replay" if replay else kind, 1)
	steam.addGamePhaseTag(kind, {"Boss fight": "steam_crown", "Elite fight": "steam_star"}.get(kind, "steam_combat"), "Fights", 1)
	steam.setTimelineGameMode(Mode.PLAYING)

func end_fight() -> void:
	var steam := SteamService.api()
	if steam != null and _in_phase:
		steam.endGamePhase()
	_in_phase = false

## Hooks a fight's highlights to markers (CombatScene calls it once the
## fight is set up). `kind` is the map stop's (RunMap.KIND_*, "" outside a run).
func watch_fight(combat: CombatManager, player: MechData, kind: String, replay: bool) -> void:
	if SteamService.api() == null:
		return
	var label: String = {RunMap.KIND_BOSS: "Boss fight", RunMap.KIND_ELITE: "Elite fight"}.get(kind, "Fight")
	var names: Array[String] = []
	for m in combat.enemies:
		names.append(m.title if m.title != "" else m.name)
	start_fight(", ".join(names), label, replay)
	var down := {} # enemies already marked as down
	var check_kills := func():
		for m in combat.enemies:
			if m.is_defeated() and not down.has(m):
				down[m] = true
				mark("%s down" % (m.title if m.title != "" else m.name), "retreated" if m.retreated else "",
					"steam_death", 2, Clip.FEATURED if m.tier == "boss" else Clip.STANDARD)
	combat.hit_landed.connect(func(mech: MechData, comp: ComponentData, dmg: int):
		if mech != player and dmg >= BIG_HIT:
			mark("%d damage" % dmg, "%s's %s" % [mech.name, comp.name], "steam_explosion", 1, Clip.STANDARD)
		check_kills.call())
	combat.component_destroyed.connect(func(mech: MechData, comp: ComponentData):
		if mech == player:
			mark("Lost %s" % comp.name, "", "steam_caution", 0)
		check_kills.call())
	combat.enemy_retreated.connect(func(_m: MechData): check_kills.call())
	combat.overheated.connect(func(mech: MechData, backlash: int):
		if mech == player:
			mark("Overheat", "%d backlash" % backlash, "steam_caution", 1, Clip.STANDARD))
	combat.boss_phase_changed.connect(func(mech: MechData):
		mark("%s: phase 2" % (mech.title if mech.title != "" else mech.name), "", "steam_crown", 2, Clip.FEATURED))
	combat.game_over.connect(func(result):
		check_kills.call()
		var won: bool = result == CombatManager.Result.WIN
		mark("Victory" if won else "Defeat", ", ".join(names), "steam_trophy" if won else "steam_death", 3,
			Clip.FEATURED if won and kind == RunMap.KIND_BOSS else Clip.STANDARD)
		end_fight())

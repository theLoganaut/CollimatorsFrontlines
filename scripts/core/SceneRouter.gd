extends CanvasLayer
## Autoload. Moves between the game's screens (War Room → location map →
## combat and back) with a fade through black. An optional caption
## ("PILOT EJECTED", "SECTOR CLEARED") holds on the black between screens.
## Input is blocked while a transition runs, and a second go() during one
## is ignored.

const WAR_ROOM := "res://scenes/WarRoom.tscn"
const LOCATION_MAP := "res://scenes/LocationMap.tscn"
const COMBAT := "res://scenes/CombatScene.tscn"
const HANGAR := "res://scenes/HangarScreen.tscn"
const DIRECTIVES := "res://scenes/DirectivesScreen.tscn"
const PILOT_LOG := "res://scenes/PilotLogScreen.tscn"
const MEMORIAL_WALL := "res://scenes/MemorialWallScreen.tscn"
const INFO_BAY := "res://scenes/InfoBayScreen.tscn"
const LIVERY_BAY := "res://scenes/LiveryBayScreen.tscn"

const FADE_OUT := 0.45
const FADE_IN := 0.4
const CAPTION_HOLD := 1.4

var _black: ColorRect
var _caption: Label
var _busy: bool = false

func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.modulate.a = 0.0
	add_child(_black)
	_caption = Label.new()
	_caption.set_anchors_preset(Control.PRESET_FULL_RECT)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 36)
	_caption.add_theme_color_override("font_color", Palette.TEXT)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.modulate.a = 0.0
	add_child(_caption)

func is_busy() -> bool:
	return _busy

func go(scene_path: String, caption: String = "", caption_color: Color = Palette.TEXT) -> void:
	if _busy:
		return
	_busy = true
	get_tree().paused = false
	_black.mouse_filter = Control.MOUSE_FILTER_STOP
	await _fade(_black, 1.0, FADE_OUT)
	if caption != "":
		_caption.text = caption
		_caption.add_theme_color_override("font_color", caption_color)
		await _fade(_caption, 1.0, 0.3)
		await get_tree().create_timer(CAPTION_HOLD, true, false, true).timeout
	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame
	await get_tree().process_frame # let the new screen lay itself out behind the black
	if caption != "":
		await _fade(_caption, 0.0, 0.25)
	await _fade(_black, 0.0, FADE_IN)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false

## Fades ignore game speed: a transition takes the same time at 1× and 2×.
func _fade(node: CanvasItem, to: float, seconds: float) -> void:
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(node, "modulate:a", to, seconds)
	await tw.finished

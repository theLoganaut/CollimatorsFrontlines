class_name HubScreen
extends Control
## Base for the War Room's stations (Directives, Pilot Log, Memorial Wall,
## Info Bay, Livery Bay): a top bar with the station's name, the Chips
## balance and a way back, over the background. Subclasses override
## screen_title(), _build() and _layout(screen).

const TOP_BAR_H := TopBar.HEIGHT
const MARGIN := 28.0

var top_row: HBoxContainer
var chips_label: Label

func screen_title() -> String:
	return ""

func _build() -> void:
	pass

func _layout(_screen: Vector2) -> void:
	pass

func _ready() -> void:
	UIState.reset()
	get_tree().paused = false
	Audio.music("hub")
	Audio.ambience("hub")
	top_row = UIKit.top_bar(self, screen_title())
	top_row.add_child(UIKit.spacer())
	chips_label = UIKit.label("", 14, Palette.SCRAPS)
	top_row.add_child(TopBar.chip(chips_label, Palette.SCRAPS))
	var back := UIKit.back_button()
	back.pressed.connect(func(): SceneRouter.go(SceneRouter.WAR_ROOM))
	top_row.add_child(back)
	_build()
	refresh_chips()
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()

func refresh_chips() -> void:
	chips_label.text = "%s Chips" % _thousands(Profile.chips)

func _on_resize() -> void:
	var screen: Vector2 = get_viewport_rect().size
	size = screen
	_layout(screen)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BG, true)

## A panel with a little padding (a card on a station's screen).
static func card(border: Color = Palette.BORDER) -> PanelContainer:
	var p := PanelContainer.new()
	var st := UIKit.style(Palette.PANEL, border, 1, 6)
	st.content_margin_left = 14
	st.content_margin_right = 14
	st.content_margin_top = 10
	st.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", st)
	return p

static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out

class_name HubScreen
extends Control
## Base for the War Room's stations (Directives, Pilot Log, Memorial Wall,
## Info Bay, Livery Bay): a top bar with the station's name, the Chips
## balance and a way back, over the background. Subclasses override
## screen_title(), _build() and _layout(screen).

const TOP_BAR_H := TopBar.HEIGHT
const MARGIN := 28.0
const BACKDROP_DIM := 0.6

var top_row: HBoxContainer
var chips_label: Label
var _backdrop: Texture2D = null
var _backdrop_layer: Control = null

func screen_title() -> String:
	return ""

## The station's own art (assets/warroom/screens/<name>.png), drawn dimmed
## behind the screen; "" = the plain background.
func backdrop_name() -> String:
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
	var path := "res://assets/warroom/screens/%s.png" % backdrop_name()
	_backdrop = load(path) if backdrop_name() != "" and ResourceLoader.exists(path) else null
	if _backdrop != null: # its own layer, so the pixel art scales crisp without touching the text
		_backdrop_layer = Control.new()
		_backdrop_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_backdrop_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_backdrop_layer.draw.connect(_draw_backdrop)
		add_child(_backdrop_layer)
	top_row = UIKit.top_bar(self, screen_title())
	top_row.add_child(FeedbackDialog.button())
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
	if _backdrop_layer != null:
		_backdrop_layer.size = screen
		_backdrop_layer.queue_redraw()
	_layout(screen)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BG, true)

func _draw_backdrop() -> void:
	var k := maxf(size.x / _backdrop.get_width(), size.y / _backdrop.get_height())
	var s := _backdrop.get_size() * k
	_backdrop_layer.draw_texture_rect(_backdrop, Rect2((size - s) / 2.0, s), false)
	_backdrop_layer.draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.02, 0.03, BACKDROP_DIM), true)

## A card on a station's screen: holo glass like the Hangar's panels
## (GlassPanel.draw_glass), its edge in `border` (the default border = teal).
static func card(border: Color = Palette.BORDER) -> PanelContainer:
	var p := PanelContainer.new()
	var st := StyleBoxEmpty.new()
	st.content_margin_left = 14
	st.content_margin_right = 14
	st.content_margin_top = 10
	st.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", st)
	var accent: Color = GlassPanel.HOLO if border == Palette.BORDER else border
	p.draw.connect(func(): GlassPanel.draw_glass(p, Rect2(Vector2.ZERO, p.size), 1.0, accent, 6.0, 0.6))
	return p

## A button on a station's glass (GlassPanel.style_button), sized like
## UIKit.button: dark with a teal edge, or lit in `accent` for an action.
static func glass_button(text: String, accent: Color = Color.TRANSPARENT, min_size: Vector2 = Vector2(120, 44), font_size: int = 15) -> Button:
	var lit := accent.a > 0.0
	var b := GlassPanel.button(text, font_size, lit, accent if lit else GlassPanel.HOLO)
	b.custom_minimum_size = min_size
	return b

## A dropdown on the glass.
static func glass_option(sel: OptionButton) -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		sel.add_theme_stylebox_override(state, GlassPanel.control_style(Palette.LINK if state == "hover" else GlassPanel.HOLO))

static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out

class_name RunScreen
extends Control
## Base for the between-fight screens (reward, refit, repair bay,
## autonomous bay): a top bar with the screen's title, scraps, the Bastion's
## HP and settings (whose menu offers Eject), a background, and a guard
## that sends the player to the right screen if the run is elsewhere.
## Subclasses override screen_phase(), screen_title(), _build(), _layout().

const TOP_BAR_H := TopBar.HEIGHT

var run: RunData
var settings_menu: SettingsMenu
var top_row: HBoxContainer
var _scraps_label: Label
var _hp_label: Label

func screen_phase() -> String:
	return ""

func screen_title() -> String:
	return ""

func _build() -> void:
	pass

func _layout(_screen: Vector2) -> void:
	pass

## Controls the training coach can ring on this screen (by name).
func _tutorial_targets() -> Dictionary:
	return {}

func _ready() -> void:
	UIState.reset()
	get_tree().paused = false
	if not RunState.is_active() or RunState.run.phase != screen_phase():
		RunState.advance.call_deferred()
		return
	run = RunState.run
	Audio.music("map")
	Audio.ambience(Audio.location_ambience(run.location))
	top_row = UIKit.top_bar(self, screen_title())
	top_row.add_child(UIKit.label(run.location.get("name", "").to_upper(), 12, Color("7f9d9a")))
	top_row.add_child(UIKit.spacer())
	_scraps_label = UIKit.scraps_label(run.scraps, 14)
	top_row.add_child(TopBar.chip(_scraps_label, Palette.SCRAPS))
	_hp_label = UIKit.label("", 13)
	top_row.add_child(TopBar.chip(_hp_label))
	# The location map, to look ahead from any stop (Logan, 2026-10-02).
	var mb := MapButton.new()
	mb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mb.pressed.connect(func(): LocationMapScreen.peek(self))
	top_row.add_child(mb)
	var sb := SettingsButton.new()
	sb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_row.add_child(sb)
	_build()
	settings_menu = SettingsMenu.new()
	settings_menu.z_index = 400
	add_child(settings_menu)
	settings_menu.set_restart_action("Eject (ends the mission)", "Click again to eject")
	settings_menu.restart_requested.connect(_eject)
	sb.pressed.connect(settings_menu.open)
	refresh_header()
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()
	Tutorial.reached(screen_phase(), _tutorial_targets())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and run != null and GameSettings.is_key(event, "map"):
		get_viewport().set_input_as_handled()
		LocationMapScreen.peek(self)

func _on_resize() -> void:
	var screen: Vector2 = get_viewport_rect().size
	size = screen
	settings_menu.size = screen
	_layout(screen)
	queue_redraw()

func refresh_header() -> void:
	_scraps_label.text = "%d scraps" % run.scraps
	var m := run.player_mech
	_hp_label.text = "%s  %d / %d HP" % [m.name, m.current_hp(), m.max_hp()]
	_hp_label.add_theme_color_override("font_color", Palette.WARNING if m.current_hp() < m.max_hp() else Palette.TEXT)

func _eject() -> void:
	run.eject()
	RunState.advance()

## Art behind the screen (drawn to cover it, dimmed), or null for plain.
func backdrop() -> Texture2D:
	return null

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BG, true)
	var tex := backdrop()
	if tex != null:
		var k := maxf(size.x / tex.get_width(), size.y / tex.get_height())
		var s := tex.get_size() * k
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		draw_texture_rect(tex, Rect2((size - s) / 2.0, s), false)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.02, 0.03, 0.62), true)

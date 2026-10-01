class_name TurnPanel
extends Control
## Turn number stacked above the End Turn button (UI & Screens, far right),
## then the Vent button (the turn spent venting instead of playing cards)
## and how many cards are left this turn (each card plays once a turn).

signal end_turn_pressed()
signal vent_pressed()

const PANEL_SIZE := Vector2(140, 150)

var _turn_label: Label
var _end_turn_button: Button
var _vent_button: Button
var _cards_label: Label
var _enabled: bool = false
var _can_vent: bool = false
var _pulse: Tween

func _ready() -> void:
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS

	_turn_label = Label.new()
	_turn_label.position = Vector2(0, 0)
	_turn_label.size = Vector2(PANEL_SIZE.x, 30)
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_label.add_theme_font_size_override("font_size", 14)
	_turn_label.add_theme_color_override("font_color", Color("dffcf8"))
	_turn_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_turn_label)

	_end_turn_button = Button.new()
	_end_turn_button.text = "End Turn"
	_end_turn_button.position = Vector2(0, 36)
	_end_turn_button.size = Vector2(PANEL_SIZE.x, 44)
	_end_turn_button.focus_mode = Control.FOCUS_NONE
	_end_turn_button.add_theme_font_size_override("font_size", 17)
	GlassPanel.style_button(_end_turn_button, true, Palette.HARDPOINT) # lit holo glass, brighter than most
	_end_turn_button.add_theme_stylebox_override("normal", GlassPanel.control_style(Palette.HARDPOINT, 0.5, 1.0))
	_end_turn_button.pressed.connect(func(): end_turn_pressed.emit())
	add_child(_end_turn_button)

	_vent_button = Button.new()
	_vent_button.text = "Vent"
	_vent_button.position = Vector2(0, 86)
	_vent_button.size = Vector2(PANEL_SIZE.x, 32)
	_vent_button.focus_mode = Control.FOCUS_NONE
	_vent_button.add_theme_font_size_override("font_size", 14)
	GlassPanel.style_button(_vent_button, false, Palette.LINK)
	_vent_button.pressed.connect(func(): vent_pressed.emit())
	add_child(_vent_button)

	_cards_label = Label.new()
	_cards_label.position = Vector2(0, 122)
	_cards_label.size = Vector2(PANEL_SIZE.x, 22)
	_cards_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cards_label.add_theme_font_size_override("font_size", 12)
	_cards_label.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	_cards_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cards_label)
	_set_tooltips()
	GameSettings.changed.connect(_set_tooltips)
	_apply()

## Tooltips naming the current key bindings (GameSettings.KEY_ACTIONS).
func _set_tooltips() -> void:
	_end_turn_button.tooltip_text = "End your turn (%s).\nKeys: 1–9 play the cards left to right (attacks: %s picks the target, %s fires, Esc cancels).\nHold Shift or Space to fast-forward the enemy turn, or press %s to keep it fast. Every key is in Settings → Controls." % [
		GameSettings.key_label("end_turn"), GameSettings.key_label("next_target"), GameSettings.key_label("fire"), GameSettings.key_label("fast_forward")]
	_vent_button.tooltip_text = "Spend this turn venting: the turn ends and your heat drops by %d%%.\nOnly before you've played a card this turn. (%s)" % [int(round(Balance.get_num("heat", "vent_action_share", 0.8) * 100.0)), GameSettings.key_label("vent")]

func set_turn_number(n: int) -> void:
	_turn_label.text = "Turn %d" % n

func set_label(text: String) -> void:
	_turn_label.text = text

func set_enabled(is_enabled: bool) -> void:
	_enabled = is_enabled
	_apply()

## Cards left this turn, whether Vent is allowed right now, and how many
## of the cards left can be played without overheating. With none playable
## End Turn pulses: there's nothing else to do (Logan, 2026-09-30).
func set_card_state(cards_left: int, can_vent: bool, playable: int = -1) -> void:
	_can_vent = can_vent
	if playable < 0:
		playable = cards_left
	if cards_left == 0:
		_cards_label.text = "Out of cards this turn"
	elif playable == 0:
		_cards_label.text = "Nothing playable left"
	else:
		_cards_label.text = "%d card%s left this turn" % [cards_left, "" if cards_left == 1 else "s"]
	_cards_label.add_theme_color_override("font_color", Palette.WARNING if playable == 0 else Palette.TEXT_MUTED)
	_set_pulse(playable == 0 and _enabled)
	_apply()

func _apply() -> void:
	if _end_turn_button == null:
		return
	_end_turn_button.disabled = not _enabled
	_vent_button.disabled = not (_enabled and _can_vent)
	if not _enabled:
		_set_pulse(false)

func _set_pulse(on: bool) -> void:
	if on == (_pulse != null):
		return
	if _pulse != null:
		_pulse.kill()
		_pulse = null
		_end_turn_button.modulate = Color.WHITE
		return
	_pulse = create_tween().set_loops()
	_pulse.tween_property(_end_turn_button, "modulate", Color(1.35, 1.35, 1.35), 0.6)
	_pulse.tween_property(_end_turn_button, "modulate", Color.WHITE, 0.6)

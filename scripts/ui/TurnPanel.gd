class_name TurnPanel
extends Control
## The End Turn button (UI & Screens, far right). The encounter and turn
## count are on the TurnPlate at the top (Logan, 2026-10-02), and there's
## no "cards left" line (clutter): with nothing playable left, End Turn pulses.
## No Vent button (Logan, 2026-10-02: redundant): ending a turn without
## playing a card is the Vent action (CombatScene).

signal end_turn_pressed()

const PANEL_SIZE := Vector2(140, 44)

var _end_turn_button: Button
var _enabled: bool = false
var _pulse: Tween

func _ready() -> void:
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS

	_end_turn_button = Button.new()
	_end_turn_button.text = "End Turn"
	_end_turn_button.position = Vector2.ZERO
	_end_turn_button.size = Vector2(PANEL_SIZE.x, 44)
	_end_turn_button.focus_mode = Control.FOCUS_NONE
	_end_turn_button.add_theme_font_size_override("font_size", 17)
	GlassPanel.style_button(_end_turn_button, true, Palette.HARDPOINT) # lit holo glass, brighter than most
	_end_turn_button.add_theme_stylebox_override("normal", GlassPanel.control_style(Palette.HARDPOINT, 0.5, 1.0))
	_end_turn_button.pressed.connect(func(): end_turn_pressed.emit())
	add_child(_end_turn_button)

	UIState.describe_on_hover(_end_turn_button, _describe_end_turn)
	_apply()

## What End Turn does, for the Description Box (naming the current key
## bindings, GameSettings.KEY_ACTIONS).
func _describe_end_turn() -> Array:
	return ["End Turn (%s)" % GameSettings.key_label("end_turn"),
		"The enemy acts, then your heat vents and your cards come back. End a turn without playing a card and you vent %d%% of your heat instead.\n\nKeys: 1–9 play the cards left to right (attacks: %s picks the target, %s fires, Esc cancels). Hold Shift or Space to fast-forward the enemy turn, or press %s to keep it fast. Every key is in Settings → Controls." % [
		int(round(Balance.get_num("heat", "vent_action_share", 0.8) * 100.0)),
		GameSettings.key_label("next_target"), GameSettings.key_label("fire"), GameSettings.key_label("fast_forward")]]

func set_enabled(is_enabled: bool) -> void:
	_enabled = is_enabled
	_apply()

## Cards left this turn and how many of them can be played without
## overheating (`can_vent` is unused now that there's no Vent button). With
## none playable End Turn pulses: there's nothing else to do (Logan, 2026-09-30).
func set_card_state(cards_left: int, _can_vent: bool, playable: int = -1) -> void:
	if playable < 0:
		playable = cards_left
	_set_pulse(playable == 0 and _enabled)
	_apply()

func _apply() -> void:
	if _end_turn_button == null:
		return
	_end_turn_button.disabled = not _enabled
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

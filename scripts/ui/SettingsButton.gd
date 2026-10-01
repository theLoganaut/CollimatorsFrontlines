class_name SettingsButton
extends Control
## Settings button, top-right corner. Opens the settings menu.

signal pressed()

const BUTTON_SIZE := Vector2(40, 40)

func _ready() -> void:
	custom_minimum_size = BUTTON_SIZE
	size = BUTTON_SIZE
	var btn := Button.new()
	btn.text = "⚙"
	btn.size = BUTTON_SIZE
	btn.tooltip_text = "Settings (Esc)"
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(func(): pressed.emit())
	GlassPanel.style_button(btn, false)
	add_child(btn)

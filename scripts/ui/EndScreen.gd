class_name EndScreen
extends Control
## The win/lose screen with one action button (Combat Slice §5.8):
## Restart in a standalone fight; during a run, Continue after a win and
## Eject after a loss (CombatScene picks the text and what it does). Under
## the title, the fight in one glance (Logan, 2026-09-30): turns, damage
## dealt and taken, biggest hit, parts lost and parts broken.

signal action_pressed()

## Holo glass like the rest of the UI (Logan, 2026-10-02): a glass panel
## over the dimmed fight, teal for a win and red for a loss, its title,
## a rule, the recap and one lit button.
const PANEL_SIZE := Vector2(560, 236)

var _panel: GlassPanel
var _backing: ColorRect
var _title_label: Label
var _rule: ColorRect
var _action_btn: Button
var _recap: Label

## CombatScene sizes it to the screen (see CombatScene._layout).
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_backing = ColorRect.new() # a dark backing under the glass so the fight doesn't show through
	_backing.color = Color(0.01, 0.025, 0.03, 0.6)
	_backing.size = PANEL_SIZE
	_backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backing)
	_panel = GlassPanel.new()
	_panel.tint = 0.9
	_panel.size = PANEL_SIZE
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_panel)
	var box := VBoxContainer.new()
	box.position = Vector2(28, 24)
	box.size = PANEL_SIZE - Vector2(56, 48)
	box.add_theme_constant_override("separation", 12)
	_panel.add_child(box)

	_title_label = UIKit.label("", 34, Palette.OK)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title_label)
	_rule = ColorRect.new()
	_rule.custom_minimum_size = Vector2(0, 1)
	box.add_child(_rule)
	_recap = UIKit.label("", 14, Color("b9d8d4"))
	_recap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_recap)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	_action_btn = GlassPanel.button("Restart", 16, true)
	_action_btn.custom_minimum_size = Vector2(200, 44)
	_action_btn.pressed.connect(func(): action_pressed.emit())
	row.add_child(_action_btn)
	resized.connect(_center)
	_center()

func _center() -> void:
	_panel.position = ((size - PANEL_SIZE) / 2.0).floor()
	_panel.pivot_offset = PANEL_SIZE / 2.0
	_backing.position = _panel.position

## `stats`: the fight's RunStats (CombatManager.stats); null shows none.
func show_result(result: int, action_text: String = "Restart", stats: RunStats = null) -> void: # CombatManager.Result
	var won := result == CombatManager.Result.WIN
	var accent: Color = GlassPanel.HOLO if won else Palette.DANGER
	_action_btn.text = action_text
	GlassPanel.style_button(_action_btn, true, accent)
	_recap.text = recap(stats) if stats != null else ""
	_title_label.text = "VICTORY" if won else "DEFEAT"
	_title_label.add_theme_color_override("font_color", Color("dffcf8") if won else Color("ffb4a6"))
	_rule.color = Color(accent, 0.5)
	_panel.accent = accent
	_panel.queue_redraw()
	_center()
	visible = true
	modulate.a = 0.0
	_panel.scale = Vector2(0.92, 0.92)
	var tw := create_tween()
	tw.tween_interval(0.5) # let the final hit land first
	tw.tween_property(self, "modulate:a", 1.0, 0.35)
	tw.parallel().tween_property(_panel, "scale", Vector2.ONE, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

static func recap(stats: RunStats) -> String:
	var line1 := "%d turn%s  ·  %d dealt  ·  %d taken  ·  biggest hit %d" % [
		stats.get_stat("turns_taken"), "" if stats.get_stat("turns_taken") == 1 else "s",
		stats.get_stat("damage_dealt"), stats.get_stat("damage_taken"), stats.get_stat("biggest_hit")]
	var line2 := "%d enemy part%s broken  ·  %d of yours lost" % [
		stats.get_stat("enemy_parts_destroyed"), "" if stats.get_stat("enemy_parts_destroyed") == 1 else "s", stats.get_stat("parts_lost")]
	if stats.get_stat("overheats") > 0:
		line2 += "  ·  %d overheat%s" % [stats.get_stat("overheats"), "" if stats.get_stat("overheats") == 1 else "s"]
	return line1 + "\n" + line2

func hide_screen() -> void:
	visible = false

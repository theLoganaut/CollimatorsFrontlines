class_name EndScreen
extends Control
## Simple win/lose screen with one action button (Combat Slice §5.8):
## Restart in a standalone fight; during a run, Continue after a win and
## Eject after a loss (CombatScene picks the text and what it does). Under
## the title, the fight in one glance (Logan, 2026-09-30): turns, damage
## dealt and taken, biggest hit, parts lost and parts broken.

signal action_pressed()

var _title_label: Label
var _action_btn: Button
var _recap: Label

## CombatScene sizes it to the screen (see CombatScene._layout).
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var bg := ColorRect.new()
	bg.color = Color(Palette.BG, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_title_label = Label.new()
	_title_label.set_anchors_preset(Control.PRESET_CENTER)
	_title_label.position = Vector2(-200, -80)
	_title_label.size = Vector2(400, 60)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 40)
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_label)

	_recap = Label.new()
	_recap.set_anchors_preset(Control.PRESET_CENTER)
	_recap.position = Vector2(-260, -14)
	_recap.size = Vector2(520, 50)
	_recap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_recap.add_theme_font_size_override("font_size", 15)
	_recap.add_theme_color_override("font_color", Color("9fb9b6"))
	_recap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_recap)

	_action_btn = Button.new()
	_action_btn.text = "Restart"
	_action_btn.custom_minimum_size = Vector2(160, 48)
	_action_btn.set_anchors_preset(Control.PRESET_CENTER)
	_action_btn.position = Vector2(-80, 46)
	_action_btn.focus_mode = Control.FOCUS_NONE
	_action_btn.pressed.connect(func(): action_pressed.emit())
	add_child(_action_btn)

## `stats`: the fight's RunStats (CombatManager.stats); null shows none.
func show_result(result: int, action_text: String = "Restart", stats: RunStats = null) -> void: # CombatManager.Result
	_action_btn.text = action_text
	_recap.text = recap(stats) if stats != null else ""
	if result == CombatManager.Result.WIN:
		_title_label.text = "VICTORY"
		_title_label.add_theme_color_override("font_color", Palette.OK)
	else:
		_title_label.text = "DEFEAT"
		_title_label.add_theme_color_override("font_color", Palette.DANGER)
	visible = true
	modulate.a = 0.0
	_title_label.pivot_offset = _title_label.size / 2.0
	_title_label.scale = Vector2(1.8, 1.8)
	var tw := create_tween()
	tw.tween_interval(0.5) # let the final hit land first
	tw.tween_property(self, "modulate:a", 1.0, 0.4)
	tw.parallel().tween_property(_title_label, "scale", Vector2.ONE, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

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

class_name CardUI
extends Control
## One card: hover scale + z-raise, and the drag source (Combat Slice §4.4,
## UI & Screens card face: Cost | Dmg, Name, Effect text, Image).
##
## Dragging is manual (top_level + z_index), not Godot's built-in drag-and-
## drop: on press, the card becomes top_level and follows the mouse in
## _process(). A valid drop target (ComponentCellUI / PlayField) claims the
## release via its own _gui_input and calls UIState.end_drag() itself. As a
## robust fallback — since a plain Control anywhere (a panel, a label) can
## silently swallow the release event without claiming it — this card also
## polls Input.is_mouse_button_pressed() every frame; once the button is up
## and nothing has claimed the drag, it snaps back on its own. That poll
## can't race the event-driven handlers: input dispatch always completes
## before _process runs in the same frame.

const BASE_SIZE := Vector2(120, 158)
const HOVER_SCALE := 1.18

var card: CardData
var hand_tray: Control # HandTray — relayout() is called after every drag ends

var _hovering: bool = false
var _dragging: bool = false
var _grab_offset: Vector2 = Vector2.ZERO
var _category: String = ComponentData.CATEGORY_HARDPOINT

var _cost_label: Label
var _dmg_label: Label
var _name_label: Label
var _effect_label: Label

func _ready() -> void:
	custom_minimum_size = BASE_SIZE
	size = BASE_SIZE
	pivot_offset = BASE_SIZE / 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)
	set_process(false)
	_build_children()
	_refresh()

func setup(p_card: CardData, p_category: String, p_hand_tray: Control) -> void:
	card = p_card
	_category = p_category
	hand_tray = p_hand_tray
	if is_inside_tree():
		_refresh()

func _build_children() -> void:
	_cost_label = Label.new()
	_cost_label.position = Vector2(6, 4)
	_cost_label.add_theme_font_size_override("font_size", 13)
	_cost_label.add_theme_color_override("font_color", Palette.TEXT)
	_cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cost_label)

	_dmg_label = Label.new()
	_dmg_label.add_theme_font_size_override("font_size", 12)
	_dmg_label.add_theme_color_override("font_color", Palette.HARDPOINT)
	_dmg_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dmg_label.size = Vector2(64, 20)
	_dmg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_dmg_label.position = Vector2(BASE_SIZE.x - 70, 4)
	add_child(_dmg_label)

	_name_label = Label.new()
	_name_label.position = Vector2(6, 26)
	_name_label.size = Vector2(BASE_SIZE.x - 12, 34)
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.add_theme_color_override("font_color", Palette.TEXT)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)

	_effect_label = Label.new()
	_effect_label.position = Vector2(6, 60)
	_effect_label.size = Vector2(BASE_SIZE.x - 12, BASE_SIZE.y - 66)
	_effect_label.add_theme_font_size_override("font_size", 11)
	_effect_label.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	_effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_effect_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_effect_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_effect_label)

func _refresh() -> void:
	if card == null:
		return
	_cost_label.text = str(card.heat_cost)
	_dmg_label.text = card.damage_label()
	_name_label.text = card.name
	var lines: Array[String] = []
	for s in card.statuses:
		lines.append("%s ×%d → %s" % [s.status.capitalize(), s.stacks, _target_label(s.target)])
	if card.effect_text != "":
		lines.append(card.effect_text)
	_effect_label.text = "\n".join(lines)
	queue_redraw()

func _target_label(target: String) -> String:
	match target:
		StatusEffectData.TARGET_ENEMY: return "target"
		StatusEffectData.TARGET_ALL_ENEMIES: return "all enemies"
		StatusEffectData.TARGET_SELF: return "this component"
		StatusEffectData.TARGET_LINKED: return "linked"
		StatusEffectData.TARGET_OWN_MECH: return "own mech"
		_: return target

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Palette.PANEL_2, true)
	draw_rect(rect, Palette.category_color(_category), false, 2.0)

func _on_mouse_entered() -> void:
	_hovering = true
	_apply_hover_visual()

func _on_mouse_exited() -> void:
	_hovering = false
	_apply_hover_visual()

func _apply_hover_visual() -> void:
	var target_scale: float = HOVER_SCALE if _hovering else 1.0
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(target_scale, target_scale), 0.1)
	z_index = 10 if _hovering else 0

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not _dragging and UIState.dragging_card == null:
			_start_drag(event.position)
			get_viewport().set_input_as_handled()

func _start_drag(local_pos: Vector2) -> void:
	_dragging = true
	_grab_offset = local_pos * scale
	scale = Vector2.ONE
	z_index = 100
	top_level = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIState.begin_drag(self, card)
	set_process(true)

func _process(_delta: float) -> void:
	if not _dragging:
		set_process(false)
		return
	global_position = get_global_mouse_position() - _grab_offset
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if UIState.dragging_card_ui == self:
			UIState.end_drag() # nothing claimed the drop this frame -> snap back
		_finish_drag_visual()

func _finish_drag_visual() -> void:
	_dragging = false
	top_level = false
	z_index = 0
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)
	if hand_tray != null and hand_tray.has_method("relayout"):
		hand_tray.relayout()

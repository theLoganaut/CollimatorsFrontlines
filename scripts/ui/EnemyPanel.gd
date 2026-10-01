class_name EnemyPanel
extends Control
## One enemy slot (UI & Screens sketch): a name bar centered above the mech
## image → the mech image with its part grid laid over it → a health bar
## exactly as wide as the image, with the heat box to the image's left,
## bottom-aligned with the health bar → its passive badges → its intents.
## The grid is faint at rest and fully visible while the mouse is on it, an
## attack card's crosshair is over this panel, or its passives are being
## revealed (see ChassisGridUI).
##
## The panel's origin is the heat box's left edge; IMAGE_X is where the
## mech image (and so the "unit") starts. Place panels by image center
## using image_center_offset().
##
## The image shows the enemy's sprite (MechArt). Elites are drawn bigger than
## regulars and bosses bigger still, and everything under the image (health
## bar, passives, intents) follows its size.

const IMAGE_SIZE := Vector2(180, 160) # a regular's
const TIER_SCALE := {"elite": 1.15, "boss": 1.3}
const HEAT_BOX_SIZE := Vector2(44, 32)
const HEAT_GAP := 6.0
const IMAGE_X := HEAT_BOX_SIZE.x + HEAT_GAP
const NAME_BAR_H := 24.0
const IMAGE_Y := NAME_BAR_H + 6.0
const HP_BAR_H := 20.0
const INTENT_GAP := 12.0 # room for the little order chevrons between icons
const CELL_SIZE := 28.0

var mech: MechData
var display_name: String = ""
## This enemy's image size (IMAGE_SIZE scaled by its tier) and the rows under it.
var image_size: Vector2 = IMAGE_SIZE
var hp_bar_y: float
var passive_y: float
var intent_y: float # what this enemy plans to do next turn, in order, below it
var panel_size: Vector2
var grid: ChassisGridUI

var _name_bar: Panel
var _name_style: StyleBoxFlat
var _name_label: Label
var _image_rect: ColorRect
var _sprite: TextureRect
var _heat_box: HeatBox
var _health_bar: HealthBar
var _defeated_label: Label
var _intent_row: Control
var passive_row: PassiveRow
var defeat_played: bool = false

func image_center_offset() -> Vector2:
	return Vector2(IMAGE_X + image_size.x / 2.0, IMAGE_Y + image_size.y / 2.0)

## Where this enemy's feet are from the panel's origin: the lowest pixel of
## its sprite (the image's bottom without art), centered. The sprite is
## square and fills the image's height.
func feet_offset() -> Vector2:
	var bottom := image_size.y
	if _sprite != null:
		bottom -= MechArt.bottom_inset(_sprite.texture) * image_size.y
	return Vector2(IMAGE_X + image_size.x / 2.0, IMAGE_Y + bottom)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS

func setup(p_mech: MechData, p_display_name: String) -> void:
	mech = p_mech
	display_name = p_display_name
	image_size = (IMAGE_SIZE * float(TIER_SCALE.get(mech.tier, 1.0))).round()
	hp_bar_y = IMAGE_Y + image_size.y + 8.0
	passive_y = hp_bar_y + HP_BAR_H + 6.0
	intent_y = passive_y + PassiveIcon.ICON_SIZE.y + 6.0
	panel_size = Vector2(IMAGE_X + image_size.x, intent_y + IntentIcon.ICON_SIZE.y)
	custom_minimum_size = panel_size
	size = panel_size
	_build_children()
	refresh()

func _build_children() -> void:
	_name_style = StyleBoxFlat.new() # a strip of holo glass, red-edged: it's hostile
	_name_style.bg_color = Color(0.03, 0.03, 0.04, 0.8)
	_name_style.border_color = Color(Palette.HARDPOINT, 0.55)
	_name_style.set_border_width_all(1)
	_name_style.shadow_color = Color(Palette.HARDPOINT, 0.12)
	_name_style.shadow_size = 5
	_name_bar = Panel.new()
	_name_bar.position = Vector2(IMAGE_X, 0)
	_name_bar.size = Vector2(image_size.x, NAME_BAR_H)
	_name_bar.add_theme_stylebox_override("panel", _name_style)
	_name_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_bar)

	_name_label = Label.new()
	_name_label.position = _name_bar.position
	_name_label.size = _name_bar.size
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.add_theme_color_override("font_color", Color("fff1e8"))
	_name_label.text = display_name
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)

	var image_pos := Vector2(IMAGE_X, IMAGE_Y)
	_image_rect = ColorRect.new()
	_image_rect.position = image_pos
	_image_rect.size = image_size
	_image_rect.color = Palette.PANEL_2
	_image_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_image_rect)
	var tex := MechArt.enemy(mech.id)
	if tex != null:
		_image_rect.color = Color.TRANSPARENT # the sprite stands on the field
		_sprite = MechArt.sprite(tex, image_size)
		_image_rect.add_child(_sprite)

	grid = ChassisGridUI.new()
	# Bigger frames (elites 5×5, bosses 6×6) get smaller cells to fit the image.
	var frame := 0
	for c in mech.cells:
		frame = maxi(frame, maxi(c.x, c.y) + 1)
	var cell := minf(CELL_SIZE, floorf((image_size.y - 12.0) / float(maxi(frame, 1))) - 3.0)
	grid.setup(mech, cell)
	grid.position = image_pos + (image_size - grid.size) / 2.0
	grid.aim_area = self
	grid.backdrop = _sprite
	add_child(grid)

	_health_bar = HealthBar.new()
	_health_bar.position = Vector2(IMAGE_X, hp_bar_y)
	_health_bar.size = Vector2(image_size.x, HP_BAR_H)
	_health_bar.threshold = mech.defeat_hp_threshold()
	_health_bar.tooltip_text = "Destroyed at %d HP, or when all its hardpoints are." % mech.defeat_hp_threshold()
	add_child(_health_bar)

	_heat_box = HeatBox.new()
	add_child(_heat_box)
	_heat_box.custom_minimum_size = HEAT_BOX_SIZE
	_heat_box.size = HEAT_BOX_SIZE
	_heat_box.position = Vector2(0, hp_bar_y + HP_BAR_H - HEAT_BOX_SIZE.y) # bottoms aligned

	passive_row = PassiveRow.new()
	passive_row.position = Vector2(IMAGE_X, passive_y)
	add_child(passive_row)
	passive_row.setup(mech, image_size.x)

	_intent_row = Control.new()
	_intent_row.position = Vector2(IMAGE_X, intent_y)
	_intent_row.size = Vector2(image_size.x, IntentIcon.ICON_SIZE.y)
	_intent_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intent_row.draw.connect(_draw_intent_chevrons)
	add_child(_intent_row)

	_defeated_label = Label.new()
	_defeated_label.position = image_pos
	_defeated_label.size = image_size
	_defeated_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_defeated_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_defeated_label.add_theme_font_size_override("font_size", 20)
	_defeated_label.add_theme_color_override("font_color", Palette.DANGER)
	_defeated_label.text = "DESTROYED"
	_defeated_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_defeated_label.visible = false
	add_child(_defeated_label)

func refresh() -> void:
	if mech == null:
		return
	_heat_box.set_heat(mech.current_heat, mech.heat_capacity())
	_health_bar.set_hp(mech.current_hp(), mech.max_hp())
	grid.refresh_all()
	passive_row.refresh()
	_defeated_label.visible = mech.is_defeated()

## Shows the upcoming actions ([{card, active, target}], in order) as
## icons centered under the mech image, plus a flame when the plan will
## overheat it. Hovering an icon shows what it'll do and to which part.
## `venting`: it has nothing to play and spends its turn venting (shown
## as its one intent).
func set_intents(actions: Array, overheat: bool = false, venting: bool = false) -> void:
	for child in _intent_row.get_children():
		_intent_row.remove_child(child)
		child.queue_free()
	if actions.is_empty() and venting:
		var v := IntentIcon.new()
		v.position = Vector2((image_size.x - IntentIcon.ICON_SIZE.x) / 2.0, 0)
		_intent_row.add_child(v)
		v.setup(IntentIcon.INTENT_VENT, false)
		_intent_row.queue_redraw()
		return
	var n := actions.size() + (1 if overheat and not actions.is_empty() else 0)
	var step := IntentIcon.ICON_SIZE.x + INTENT_GAP
	var x0 := (image_size.x - (n * IntentIcon.ICON_SIZE.x + (n - 1) * INTENT_GAP)) / 2.0
	for i in range(actions.size()):
		var icon := IntentIcon.new()
		icon.position = Vector2(x0 + i * step, 0)
		icon.intent = {"mech": mech, "card": actions[i]["card"], "target": actions[i].get("target", null)}
		_intent_row.add_child(icon)
		icon.setup(actions[i]["card"].intent(), actions[i]["active"])
	if n > actions.size():
		var warn := IntentIcon.new()
		warn.position = Vector2(x0 + actions.size() * step, 0)
		_intent_row.add_child(warn)
		warn.setup(IntentIcon.INTENT_OVERHEAT, false)
	_intent_row.queue_redraw()

func _draw_intent_chevrons() -> void:
	var icons := _intent_row.get_children()
	for i in range(icons.size() - 1):
		if (icons[i + 1] as IntentIcon).kind == IntentIcon.INTENT_OVERHEAT:
			continue
		var x: float = icons[i].position.x + IntentIcon.ICON_SIZE.x + INTENT_GAP / 2.0
		var y := IntentIcon.ICON_SIZE.y / 2.0
		_intent_row.draw_polyline(PackedVector2Array([Vector2(x - 2, y - 4), Vector2(x + 2, y), Vector2(x - 2, y + 4)]), Palette.TEXT_MUTED, 1.5, true)

func image_global_rect() -> Rect2:
	return _image_rect.get_global_rect()

## Defeated: the sprite flashes white, then sinks a little and dims with
## the grid while DESTROYED punches in (CombatScene adds the blasts).
func play_defeated() -> void:
	defeat_played = true
	_defeated_label.visible = true
	_defeated_label.pivot_offset = _defeated_label.size / 2.0
	_defeated_label.scale = Vector2(2.2, 2.2)
	_image_rect.modulate = Color(2.6, 2.6, 2.6)
	var tw := create_tween()
	tw.tween_property(_image_rect, "modulate", Color(1.4, 0.8, 0.6), 0.18)
	tw.set_parallel(true)
	tw.tween_property(_defeated_label, "scale", Vector2.ONE, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_image_rect, "modulate", Color(1, 1, 1, 0.45), 0.7).set_delay(0.25)
	tw.tween_property(_image_rect, "position:y", _image_rect.position.y + 10.0, 0.7).set_delay(0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(grid, "self_modulate:a", 0.45, 0.4)

## Highlights the name bar while this enemy is taking its turn.
func set_acting(acting: bool) -> void:
	_name_style.border_color = Palette.HARDPOINT if acting else Color(Palette.HARDPOINT, 0.55)
	_name_style.set_border_width_all(2 if acting else 1)
	_name_bar.queue_redraw()

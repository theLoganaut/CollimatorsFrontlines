class_name PlayerMechPanel
extends Control
## The player's mech (UI & Screens sketch): a health bar exactly as wide as
## the mech image, above it; a large heat box to the image's left, its top
## aligned with the health bar's top; then the mech image with its grid laid
## over it, faint like the enemies' until it matters (see ChassisGridUI).
## It's a third larger than it first was — it's the closest thing to the
## camera — and CombatScene places it so the image runs slightly off the
## bottom of the screen. Its passive badges sit
## in a row just above the health bar (outside the panel's rect).
##
## The panel's origin is the heat box's left edge; IMAGE_X is where the
## mech image (and so the "unit") starts.

const IMAGE_SIZE := Vector2(293, 253)
const HEAT_BOX_SIZE := Vector2(66, 48)
const HEAT_GAP := 8.0
const IMAGE_X := HEAT_BOX_SIZE.x + HEAT_GAP
const HP_BAR_H := 24.0
const IMAGE_Y := HP_BAR_H + 8.0
const PANEL_SIZE := Vector2(IMAGE_X + IMAGE_SIZE.x, IMAGE_Y + IMAGE_SIZE.y)
const CELL_SIZE := 35.0
const PASSIVE_GAP := 6.0 # between the passive row and the health bar

var mech: MechData
var combat: CombatManager = null # set by CombatScene: card costs for the heat preview
var grid: ChassisGridUI
var passive_row: PassiveRow

var _heat_box: HeatBox
var _heat_caption: Label
var _health_bar: HealthBar
var _image_rect: ColorRect

func _ready() -> void:
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS

func setup(p_mech: MechData) -> void:
	mech = p_mech
	_build_children()
	refresh()

func _build_children() -> void:
	_health_bar = HealthBar.new()
	_health_bar.font_size = 13
	_health_bar.position = Vector2(IMAGE_X, 0)
	_health_bar.size = Vector2(IMAGE_SIZE.x, HP_BAR_H)
	_health_bar.threshold = mech.defeat_hp_threshold()
	add_child(_health_bar)

	passive_row = PassiveRow.new()
	passive_row.position = Vector2(IMAGE_X, -PassiveIcon.ICON_SIZE.y - PASSIVE_GAP)
	add_child(passive_row)
	passive_row.setup(mech, IMAGE_SIZE.x)

	_heat_box = HeatBox.new()
	_heat_box.font_size = 24
	_heat_box.show_forecast = true
	add_child(_heat_box)
	_heat_box.custom_minimum_size = HEAT_BOX_SIZE
	_heat_box.size = HEAT_BOX_SIZE
	_heat_box.position = Vector2(0, 0) # top aligned with the health bar's top

	# Heat preview caption under the heat box: "+4" or "OVERHEAT −24 HP".
	_heat_caption = Label.new()
	_heat_caption.position = Vector2(-20, HEAT_BOX_SIZE.y + 4)
	_heat_caption.size = Vector2(HEAT_BOX_SIZE.x + 40, 34)
	_heat_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heat_caption.add_theme_font_size_override("font_size", 12)
	_heat_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_heat_caption)
	UIState.hovered_card_changed.connect(_refresh_preview.unbind(1))
	UIState.drag_started.connect(_refresh_preview.unbind(1))
	UIState.drag_ended.connect(_refresh_preview)

	var image_pos := Vector2(IMAGE_X, IMAGE_Y)
	_image_rect = ColorRect.new()
	_image_rect.position = image_pos
	_image_rect.size = IMAGE_SIZE
	_image_rect.color = Palette.PANEL_2
	_image_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_image_rect)
	# The mech seen from behind (MechArt). Mechs without art keep the
	# placeholder, painted in the worn livery.
	var tex := MechArt.player_back(mech.id)
	var livery := Meta.livery(Profile.livery)
	var sprite: TextureRect = null
	if tex != null:
		_image_rect.color = Color.TRANSPARENT
		sprite = MechArt.sprite(tex, IMAGE_SIZE)
		_image_rect.add_child(sprite)
	elif not livery.is_empty() and livery.get("id", "") != "standard_issue":
		_image_rect.draw.connect(func(): Meta.paint_livery(_image_rect, Rect2(Vector2.ZERO, IMAGE_SIZE), livery, 0.6))

	grid = ChassisGridUI.new()
	grid.setup(mech, CELL_SIZE)
	grid.backdrop = sprite
	grid.position = image_pos + (IMAGE_SIZE - grid.size) / 2.0
	add_child(grid)

func refresh() -> void:
	if mech == null:
		return
	_heat_box.vent_at_max = mech.vent_at_max # Rain lowers it
	_heat_box.set_heat(mech.current_heat, mech.heat_capacity())
	_health_bar.set_hp(mech.current_hp(), mech.max_hp())
	grid.refresh_all()
	passive_row.refresh()
	_refresh_preview()

## Heat preview for the card being dragged, or else hovered, in the hand.
func _refresh_preview() -> void:
	var card: CardData = UIState.dragging_card if UIState.dragging_card != null else UIState.hovered_card
	if card == null or UIState.input_locked:
		_heat_box.set_preview(-1)
		_heat_caption.text = ""
		return
	var cost: int = combat.effective_cost(card) if combat != null else card.heat_cost
	var projected := maxi(0, mech.current_heat + cost)
	_heat_box.set_preview(projected)
	if HeatRules.is_overheated(projected, mech.heat_capacity()) and mech.heat_check_timing == MechData.HEAT_CHECK_END_OF_TURN:
		_heat_caption.text = "OVER MAX\nvent before turn end"
		_heat_caption.add_theme_color_override("font_color", Palette.WARNING)
	elif HeatRules.is_overheated(projected, mech.heat_capacity()):
		_heat_caption.text = "OVERHEAT\n−%d HP" % HeatRules.backlash_for(mech)
		_heat_caption.add_theme_color_override("font_color", Palette.DANGER)
	else:
		_heat_caption.text = ("+%d heat" % cost) if cost >= 0 else ("vent %d" % -cost)
		_heat_caption.add_theme_color_override("font_color", Palette.WARNING)

## The mech image's rect in global coordinates (the enemy crosshair wanders over it).
func image_global_rect() -> Rect2:
	return _image_rect.get_global_rect()

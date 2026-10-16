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

## The hovered or dragged card would overheat the mech (CombatScene pulses the screen red).
signal overheat_warning(on: bool)

var mech: MechData
var combat: CombatManager = null # set by CombatScene: card costs for the heat preview
var grid: ChassisGridUI
var passive_row: PassiveRow

var _heat_box: HeatBox
var _health_bar: HealthBar
var _image_rect: ColorRect
var _warning: bool = false

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


	_heat_box = HeatBox.new()
	_heat_box.font_size = 24
	add_child(_heat_box)
	_heat_box.custom_minimum_size = HEAT_BOX_SIZE
	_heat_box.size = HEAT_BOX_SIZE
	_heat_box.position = Vector2(0, 0) # top aligned with the health bar's top

	# No text under the box (Logan, 2026-10-02: clutter): the box itself turns
	# amber for a card's heat, red for an overheat, and what an overheat
	# would cost shows on the health bar.
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

	# The badge row last, over the grid: its overflow opens over the health
	# bar (which steps aside meanwhile) and the top of the image.
	passive_row = PassiveRow.new()
	passive_row.numbers_below = false # the row sits over the health bar: stacks show above it
	passive_row.part_statuses = true # Shock on your weapon, Burn, Disabled...: a badge each, as for enemies
	passive_row.position = Vector2(IMAGE_X, -PassiveIcon.ICON_SIZE.y - PASSIVE_GAP)
	add_child(passive_row)
	passive_row.setup(mech, IMAGE_SIZE.x)
	passive_row.expanded_changed.connect(func(on: bool): _health_bar.visible = not on)

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
		_health_bar.set_preview_loss(0)
		_set_warning(false)
		return
	var cost: int = combat.effective_cost(card) if combat != null else card.heat_cost
	var projected := maxi(0, mech.current_heat + cost)
	_heat_box.set_preview(projected)
	_health_bar.set_preview_loss(0)
	_set_warning(false)
	# (Redline checks heat at the end of its turn: over max mid-turn isn't an overheat yet.)
	if HeatRules.is_overheated(projected, mech.heat_capacity()) and mech.heat_check_timing != MechData.HEAT_CHECK_END_OF_TURN:
		_health_bar.set_preview_loss(HeatRules.backlash_for(mech))
		_set_warning(true)

## A hovered part's HP lit on the health bar (0 clears it).
func highlight_hp(amount: int) -> void:
	_health_bar.set_highlight(amount)

## The primed protocol's badge on the passive row: [title, text] for its
## hover, or [] to hide it.
func set_protocol(info: Array) -> void:
	passive_row.set_protocol(info)

func _set_warning(on: bool) -> void:
	if on != _warning:
		_warning = on
		overheat_warning.emit(on)

## The heat box in global coordinates: kept clear by a card's keyword hint
## (HoloHint.keep_clear).
func heat_rect() -> Rect2:
	return _heat_box.get_global_rect().grow(4.0)

## The mech image's rect in global coordinates (the enemy crosshair wanders over it).
func image_global_rect() -> Rect2:
	return _image_rect.get_global_rect()

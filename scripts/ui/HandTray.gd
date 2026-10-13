class_name HandTray
extends Control
## Fanned left group / player mech gap / fanned right group (Combat Slice
## §5, UI & Screens). Cards split evenly in hand order (the mech's parts in
## order), the extra card on the left. Each group starts just outside the player mech
## (left_gap / right_gap from the tray's center, set by CombatScene, since
## the heat box makes the mech's left side wider) and splays outward, the
## outer cards dropping lower and rotating further, running off the bottom
## edge.
##
## The tray itself ignores the mouse so it never blocks the player mech's
## grid behind it; only its cards take input.

const CARD_STEP_X := 72.0 # preferred spacing; squeezed if a group would run off the side
const MIN_CARD_STEP_X := 28.0
const SIDE_MARGIN := 16.0
const CARD_ROTATION_STEP_DEG := 4.0
const CARD_ARC_DROP := 16.0

var mech: MechData
var combat: CombatManager = null # for card costs, playability and one-use cards
var left_gap: float = 220.0
var right_gap: float = 160.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func setup(p_mech: MechData, p_combat: CombatManager = null) -> void:
	mech = p_mech
	combat = p_combat
	for child in get_children():
		child.queue_free()
	# Spent cards leave the fan (hidden, not freed) and come back next turn.
	var cards: Array[CardData] = combat.hand_cards(true) if combat != null else mech.all_playable_cards()
	for card in cards:
		var card_ui := CardUI.new()
		add_child(card_ui)
		var owner_component := mech.get_component(card.owner_component_id)
		var category := owner_component.category if owner_component != null else ComponentData.CATEGORY_HARDPOINT
		card_ui.setup(card, category, self, owner_component)
	relayout()
	refresh_heat()

## Removes every hand card whose granting component is gone (Combat Rules:
## a destroyed component's cards leave the hand, and the fan re-splits).
## Safe to call after any damage — does nothing if no card needs to go.
func prune_destroyed() -> void:
	if mech == null:
		return
	var changed := false
	for child in get_children():
		if not (child is CardUI) or child.card == null or child.is_queued_for_deletion():
			continue
		var owner_component := mech.get_component(child.card.owner_component_id)
		var used_up: bool = child.card.one_use and combat != null and not combat.bonus_cards.has(child.card)
		if owner_component == null or owner_component.destroyed or used_up:
			if child == UIState.dragging_card_ui:
				UIState.end_drag()
			child.queue_free()
			changed = true
	if changed:
		call_deferred("relayout") # wait for queue_free()'d children to actually leave

## Each card's cost right now (Coolant, Jam, Overclock Shunt), whether it
## would overheat the mech, whether its part can act at all, and whether
## it's been played this fight.
func refresh_heat() -> void:
	if mech == null:
		return
	var changed := false
	for child in get_children():
		if child is CardUI and child.card != null:
			var cost: int = combat.effective_cost(child.card) if combat != null else child.card.heat_cost
			var comp := mech.get_component(child.card.owner_component_id)
			var usable := comp != null and comp.is_usable()
			var spent: bool = combat != null and combat.is_spent(child.card)
			var over := HeatRules.is_overheated(mech.current_heat + cost, mech.heat_capacity())
			child.set_state(cost, over, not usable, spent)
			child.set_protocol_glow(combat != null and combat.primed.any(func(p): return CombatProtocols.affects(p, child.card)))
			if spent != child.gone:
				child.set_gone(spent)
				changed = true
	if changed:
		relayout()

## Repositions the current set of CardUI children into the fan. Does not
## add or remove any card — see setup() / prune_destroyed(). Sides and
## number keys come from the whole hand, played cards included, so playing
## one never moves a card to the other side or renumbers the rest; only the
## cards still in hand are laid out.
func relayout() -> void:
	var cards := _cards()
	var n_left := (cards.size() + 1) / 2
	var left: Array[CardUI] = cards.slice(0, n_left).filter(func(c): return not c.gone)
	var right: Array[CardUI] = cards.slice(n_left).filter(func(c): return not c.gone)
	var center_x := size.x / 2.0
	_layout_side(left, center_x - left_gap, -1.0)
	_layout_side(right, center_x + right_gap, 1.0)
	var ordered := ordered_cards()
	for i in range(ordered.size()):
		ordered[i].hotkey = i + 1 if i < 9 else 0
		ordered[i].queue_redraw()

## Lifts the cards `component` grants (its part is hovered on your mech);
## null drops them back.
func set_linked_part(component: ComponentData) -> void:
	for c in _cards():
		c.set_linked(component != null and c.card.owner_component_id == component.id)

## The fan's card for `card`, or null.
func card_ui_for(card: CardData) -> CardUI:
	for c in _cards():
		if c.card == card:
			return c
	return null

func _cards() -> Array[CardUI]:
	var cards: Array[CardUI] = []
	for child in get_children():
		if child is CardUI and child.card != null and not child.is_queued_for_deletion():
			cards.append(child)
	return cards

## The hand's cards as they read on screen, left to right (the left fan's
## inner card is nearest the mech), played ones included: number keys 1–9
## play them in this order.
func ordered_cards() -> Array[CardUI]:
	var cards := _cards()
	var n_left := (cards.size() + 1) / 2
	var left: Array[CardUI] = cards.slice(0, n_left)
	left.reverse()
	left.append_array(cards.slice(n_left))
	return left

## `inner_x`: x of the group's edge nearest the mech. Card 0 is the inner one.
func _layout_side(group: Array[CardUI], inner_x: float, dir: float) -> void:
	var n := group.size()
	# Room from the group's inner edge to the screen side, minus one full card
	# and how far the outermost card's top corner swings out when rotated
	# (it pivots on its bottom-center).
	var outer_rot := deg_to_rad(CARD_ROTATION_STEP_DEG * float(n))
	var swing := CardUI.BASE_SIZE.y * sin(outer_rot) - CardUI.BASE_SIZE.x / 2.0 * (1.0 - cos(outer_rot))
	var room: float = (inner_x - SIDE_MARGIN if dir < 0.0 else size.x - SIDE_MARGIN - inner_x) - CardUI.BASE_SIZE.x - swing
	var step: float = CARD_STEP_X
	if n > 1:
		step = clampf(room / float(n - 1), MIN_CARD_STEP_X, CARD_STEP_X)
	for i in range(n):
		var card_ui: CardUI = group[i]
		var center_x: float = inner_x + dir * (CardUI.BASE_SIZE.x / 2.0 + float(i) * step)
		var outer_frac: float = float(i) / maxf(float(n - 1), 1.0)
		card_ui.rest_position = Vector2(center_x - CardUI.BASE_SIZE.x / 2.0, CARD_ARC_DROP * outer_frac)
		card_ui.rest_rotation = dir * CARD_ROTATION_STEP_DEG * float(i + 1)
		# Keep each card's left edge (cost + name) readable: in the left
		# group the inner cards sit on top, in the right group the outer ones.
		card_ui.rest_z = (n - i) if dir < 0.0 else i
		if card_ui == UIState.dragging_card_ui:
			continue # a card being dragged positions itself; don't fight it
		card_ui.apply_rest()

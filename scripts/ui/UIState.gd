extends Node
## Autoload. Cross-widget UI state: the card currently being dragged (manual
## drag via top_level + z_index, no Godot built-in DnD — see CardUI.gd) and
## what's hovered right now, for the Description Box (shown only while
## something is hovered, Logan 2026-09-30).

signal drag_started(card: CardData)
signal drag_ended()
signal hover_changed(component: ComponentData, mech: MechData)
signal hovered_card_changed(card: CardData)
## An enemy intent icon is hovered ({mech, card, target} or {} when none).
signal intent_hover_changed(intent: Dictionary)

var dragging_card: CardData = null
var dragging_card_ui: Control = null
## 0 while an attack card is still near the hand, 1 once it's been dragged
## far enough to have fully turned into the targeting crosshair.
var drag_fade: float = 0.0
## Set by CombatScene: func(card, global_pos, drag_distance) -> bool (played).
var drop_handler: Callable
## True while the enemy turn plays out — cards can't be picked up.
var input_locked: bool = false

var hovered_component: ComponentData = null
var hovered_mech: MechData = null
## True when the hover came from a passive icon: the Description Box then
## describes that passive rather than the component as a whole.
var hovered_passive: bool = false
var hovered_card: CardData = null
var hovered_intent: Dictionary = {}

func is_dragging_attack_card() -> bool:
	return dragging_card != null and dragging_card.is_attack()

func begin_drag(card_ui: Control, card: CardData) -> void:
	dragging_card = card
	dragging_card_ui = card_ui
	drag_fade = 0.0
	drag_started.emit(card)

func end_drag() -> void:
	dragging_card = null
	dragging_card_ui = null
	drag_fade = 0.0
	drag_ended.emit()

func set_hovered(component: ComponentData, mech: MechData, as_passive: bool = false) -> void:
	if hovered_component == component and hovered_passive == as_passive:
		return
	hovered_component = component
	hovered_mech = mech
	hovered_passive = as_passive
	hover_changed.emit(component, mech)

## The pointer left `component` (a grid cell or passive badge): nothing is
## hovered now, unless something else already took over.
func clear_hovered(component: ComponentData) -> void:
	if hovered_component != component:
		return
	hovered_component = null
	hovered_mech = null
	hovered_passive = false
	hover_changed.emit(null, null)

func set_hovered_card(card: CardData) -> void:
	if hovered_card == card:
		return
	hovered_card = card
	hovered_card_changed.emit(card)

func clear_hovered_card(card: CardData) -> void:
	if hovered_card == card:
		hovered_card = null
		hovered_card_changed.emit(null)

func set_hovered_intent(intent: Dictionary) -> void:
	hovered_intent = intent
	intent_hover_changed.emit(intent)

func clear_hovered_intent(intent: Dictionary) -> void:
	if hovered_intent == intent:
		hovered_intent = {}
		intent_hover_changed.emit({})

func reset() -> void:
	hovered_intent = {}
	dragging_card = null
	dragging_card_ui = null
	drag_fade = 0.0
	input_locked = false
	hovered_component = null
	hovered_mech = null
	hovered_passive = false
	hovered_card = null
	hover_changed.emit(null, null)

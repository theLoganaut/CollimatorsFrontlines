extends Node
## Autoload. Cross-widget UI state: the card currently being dragged (manual
## drag via top_level + z_index, no Godot built-in DnD — see CardUI.gd) and
## whichever component is currently hovered, for the Description Box
## (UI & Screens: "Hover a component (yours or an enemy's)").

signal drag_started(card: CardData)
signal drag_ended()
signal hover_changed(component: ComponentData, mech: MechData)

var dragging_card: CardData = null
var dragging_card_ui: Control = null

var hovered_component: ComponentData = null
var hovered_mech: MechData = null

func is_dragging_attack_card() -> bool:
	return dragging_card != null and dragging_card.is_attack()

func begin_drag(card_ui: Control, card: CardData) -> void:
	dragging_card = card
	dragging_card_ui = card_ui
	drag_started.emit(card)

func end_drag() -> void:
	dragging_card = null
	dragging_card_ui = null
	drag_ended.emit()

func set_hovered(component: ComponentData, mech: MechData) -> void:
	if hovered_component == component:
		return
	hovered_component = component
	hovered_mech = mech
	hover_changed.emit(component, mech)

func clear_hovered(component: ComponentData) -> void:
	# only clear if the thing that stopped being hovered is still the current one
	# (prevents a stale mouse_exited from a previous cell clearing a newer hover)
	if hovered_component == component:
		hovered_component = null
		hovered_mech = null
		hover_changed.emit(null, null)

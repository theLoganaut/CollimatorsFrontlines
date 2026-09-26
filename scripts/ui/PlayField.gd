class_name PlayField
extends Control
## Background catch-all covering the whole combat screen, added first (so
## every other interactive element sits on top of it in the same viewport).
## A self card released here — meaning "anywhere outside the hand" that
## isn't a more specific drop target — resolves (Combat Rules §4.4). An
## attack card released here has nowhere valid to land, so it's a no-op:
## the drag simply ends via CardUI's own fallback and the card snaps back.

signal self_card_dropped(card: CardData)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BG, true)

func _on_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed):
		return
	if UIState.dragging_card == null:
		return
	var card := UIState.dragging_card
	if not card.is_attack():
		self_card_dropped.emit(card)
		get_viewport().set_input_as_handled()
	# an attack card with nowhere valid to land is left alone — CardUI's own
	# per-frame fallback notices the button is up and snaps it back.

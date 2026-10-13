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
## Something else on the combat screen is hovered that the Description Box
## explains (End Turn, Vent, a health bar...): {title, text} or {} when none.
signal hint_changed(hint: Dictionary)
## A status is hovered (a status badge, or a status word in card text):
## every part holding it lights up. `mech` null = on every mech; "" = none.
signal status_hover_changed(status: String, mech: MechData)

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
var hint: Dictionary = {}
var hovered_status: String = ""
var hovered_status_mech: MechData = null
var _status_owner: int = 0

## Hovering `control` lights the parts holding `status` (on `mech`, or every mech).
func set_hovered_status(control: Object, status: String, mech: MechData) -> void:
	_status_owner = control.get_instance_id()
	hovered_status = status
	hovered_status_mech = mech
	status_hover_changed.emit(status, mech)

func clear_hovered_status(control: Object) -> void:
	if _status_owner != control.get_instance_id() or hovered_status == "":
		return
	hovered_status = ""
	hovered_status_mech = null
	status_hover_changed.emit("", null)

## Hovering `control` explains it in the Description Box (Logan,
## 2026-10-02: not a tooltip): `describe` returns [title, text], called on
## each hover so it can name the current key bindings or numbers.
func describe_on_hover(control: Control, describe: Callable) -> void:
	control.mouse_entered.connect(func():
		var d: Array = describe.call()
		if d.size() < 2:
			return
		hint = {"title": d[0], "text": d[1], "owner": control.get_instance_id()}
		hint_changed.emit(hint))
	var leave := func():
		if hint.get("owner", 0) == control.get_instance_id():
			hint = {}
			hint_changed.emit(hint)
	control.mouse_exited.connect(leave)
	control.tree_exiting.connect(leave) # rebuilt under the mouse

func is_dragging_attack_card() -> bool:
	return dragging_card != null and dragging_card.is_attack()

func begin_drag(card_ui: Control, card: CardData) -> void:
	dragging_card = card
	dragging_card_ui = card_ui
	drag_fade = 0.0
	CrashLog.crumb("drag card: %s" % card.name)
	drag_started.emit(card)

func end_drag() -> void:
	CrashLog.crumb("drop card")
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
	CrashLog.crumb("hover part: %s › %s (%s%s)" % [mech.name if mech != null else "?", component.name if component != null else "none",
		component.library_id if component != null else "", ", passive" if as_passive else ""])
	hover_changed.emit(component, mech)

## The pointer left `component` (a grid cell or passive badge): nothing is
## hovered now, unless something else already took over.
func clear_hovered(component: ComponentData) -> void:
	if hovered_component != component:
		return
	hovered_component = null
	hovered_mech = null
	hovered_passive = false
	CrashLog.crumb("hover off part")
	hover_changed.emit(null, null)

func set_hovered_card(card: CardData) -> void:
	if hovered_card == card:
		return
	hovered_card = card
	CrashLog.crumb("hover card: %s" % (card.name if card != null else "none"))
	hovered_card_changed.emit(card)

func clear_hovered_card(card: CardData) -> void:
	if hovered_card == card:
		hovered_card = null
		hovered_card_changed.emit(null)

func set_hovered_intent(intent: Dictionary) -> void:
	hovered_intent = intent
	var mech = intent.get("mech")
	var card = intent.get("card")
	CrashLog.crumb("hover intent: %s › %s" % [mech.name if mech is MechData else "?", card.name if card is CardData else "?"])
	intent_hover_changed.emit(intent)

func clear_hovered_intent(intent: Dictionary) -> void:
	if hovered_intent == intent:
		hovered_intent = {}
		intent_hover_changed.emit({})

func reset() -> void:
	hovered_intent = {}
	hovered_status = ""
	hovered_status_mech = null
	dragging_card = null
	dragging_card_ui = null
	drag_fade = 0.0
	input_locked = false
	hovered_component = null
	hovered_mech = null
	hovered_passive = false
	hovered_card = null
	hover_changed.emit(null, null)

class_name MechData
extends RefCounted
## A mech: a chassis (grid + weight class + max heat) plus its installed
## components. Chassis page: a chassis carries no HP of its own — mech HP is
## the sum of installed components' HP.

const HEAT_CHECK_LIVE := "live"
const HEAT_CHECK_END_OF_TURN := "end_of_turn"

var id: String
var name: String
var weight_class: String
var cells: Array[Vector2i] = []   # chassis cells
var max_heat: int
var heat_check_timing: String
var components: Array[ComponentData] = []

var current_heat: int = 0
var mech_statuses: Array[StatusInstance] = []  # Absorb / Deflect / Smoke (mech-scoped)

func max_hp() -> int:
	var total := 0
	for c in components:
		total += c.max_hp
	return total

func current_hp() -> int:
	var total := 0
	for c in components:
		total += c.current_hp
	return total

func is_defeated() -> bool:
	for c in components:
		if not c.destroyed:
			return false
	return true

func get_component(component_id: String) -> ComponentData:
	for c in components:
		if c.id == component_id:
			return c
	return null

func non_destroyed_components() -> Array[ComponentData]:
	var out: Array[ComponentData] = []
	for c in components:
		if not c.destroyed:
			out.append(c)
	return out

## All cards from non-destroyed components, in component order.
func all_playable_cards() -> Array[CardData]:
	var out: Array[CardData] = []
	for c in non_destroyed_components():
		for card in c.cards:
			out.append(card)
	return out

func is_overheated() -> bool:
	return current_heat > max_heat

func get_mech_status(status_name: String) -> StatusInstance:
	for s in mech_statuses:
		if s.status == status_name:
			return s
	return null

func mech_status_stacks(status_name: String) -> int:
	var s := get_mech_status(status_name)
	return s.stacks if s != null else 0

func add_mech_status(status_name: String, stacks: int) -> int:
	if stacks <= 0:
		return mech_status_stacks(status_name)
	var s := get_mech_status(status_name)
	if s == null:
		s = StatusInstance.new(status_name, 0)
		mech_statuses.append(s)
	s.stacks += stacks
	return s.stacks

func remove_mech_status(status_name: String, amount: int) -> void:
	var s := get_mech_status(status_name)
	if s == null:
		return
	s.stacks -= amount
	if s.stacks <= 0:
		mech_statuses.erase(s)

func clear_mech_status(status_name: String) -> void:
	var s := get_mech_status(status_name)
	if s != null:
		mech_statuses.erase(s)

func clone() -> MechData:
	var m := MechData.new()
	m.id = id
	m.name = name
	m.weight_class = weight_class
	m.cells = cells.duplicate()
	m.max_heat = max_heat
	m.heat_check_timing = heat_check_timing
	m.components = []
	for c in components:
		m.components.append(c.clone())
	m.current_heat = current_heat
	m.mech_statuses = []
	for s in mech_statuses:
		m.mech_statuses.append(s.clone())
	return m

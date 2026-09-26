class_name ComponentData
extends RefCounted
## One installed component: a shaped piece with HP and the cards it grants.
## Components & Cards: category is "hardpoint" / "reactor" / "protocol".
## `cells` is the component's own shape (not assumed contiguous — Combat
## Slice §2 flags Targeting Computer specifically); `placed_cells` is that
## shape rotated and offset into the owning mech's grid space, computed by
## DataLoader.

const CATEGORY_HARDPOINT := "hardpoint"
const CATEGORY_REACTOR := "reactor"
const CATEGORY_PROTOCOL := "protocol"

var id: String
var name: String
var category: String
var max_hp: int
var current_hp: int
var cells: Array[Vector2i] = []          # local shape, unrotated
var offset: Vector2i = Vector2i.ZERO
var rotation_steps: int = 0
var placed_cells: Array[Vector2i] = []   # in the owning mech's grid space
var cards: Array[CardData] = []

var destroyed: bool = false
var statuses: Array[StatusInstance] = [] # Shock / Acid / Disabled / Offline / Coolant / Jam / Burn / Freeze

func is_destroyed() -> bool:
	return destroyed

func has_cards() -> bool:
	return cards.size() > 0

func leftmost_column() -> int:
	var m := 999999
	for c in placed_cells:
		m = mini(m, c.y)
	return m

func topmost_row() -> int:
	var m := 999999
	for c in placed_cells:
		m = mini(m, c.x)
	return m

## Deals damage to this component, floors at 0, marks it destroyed at 0.
## Returns the amount actually applied (after flooring against remaining HP).
func apply_damage(amount: int) -> int:
	if destroyed or amount <= 0:
		return 0
	var applied: int = mini(amount, current_hp)
	current_hp -= applied
	if current_hp <= 0:
		current_hp = 0
		destroyed = true
	return applied

## Heals up to max_hp; can't revive a destroyed component (Statuses & Links: Absorb clarification).
func heal(amount: int) -> int:
	if destroyed or amount <= 0:
		return 0
	var applied: int = mini(amount, max_hp - current_hp)
	current_hp += applied
	return applied

func get_status(status_name: String) -> StatusInstance:
	for s in statuses:
		if s.status == status_name:
			return s
	return null

func status_stacks(status_name: String) -> int:
	var s := get_status(status_name)
	return s.stacks if s != null else 0

## Adds stacks of a component-scoped status, creating it if absent. Returns the new total.
func add_status(status_name: String, stacks: int) -> int:
	if stacks <= 0:
		return status_stacks(status_name)
	var s := get_status(status_name)
	if s == null:
		s = StatusInstance.new(status_name, 0)
		statuses.append(s)
	s.stacks += stacks
	return s.stacks

## Removes up to `amount` stacks; drops the entry once it hits 0.
func remove_status(status_name: String, amount: int) -> void:
	var s := get_status(status_name)
	if s == null:
		return
	s.stacks -= amount
	if s.stacks <= 0:
		statuses.erase(s)

func clone() -> ComponentData:
	var c := ComponentData.new()
	c.id = id
	c.name = name
	c.category = category
	c.max_hp = max_hp
	c.current_hp = current_hp
	c.cells = cells.duplicate()
	c.offset = offset
	c.rotation_steps = rotation_steps
	c.placed_cells = placed_cells.duplicate()
	c.cards = []
	for card in cards:
		c.cards.append(card.clone())
	c.destroyed = destroyed
	c.statuses = []
	for s in statuses:
		c.statuses.append(s.clone())
	return c

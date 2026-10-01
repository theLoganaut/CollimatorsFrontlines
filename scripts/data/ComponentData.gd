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

## Passive effects a component can have while it isn't destroyed, as data.
## Only effects designed in Refit Bay are implemented; `text` holds the
## Refit Bay wording shown to the player.
## {"type": PASSIVE_REDIRECT} — Redirect Spike: whenever another component
## on this mech would take damage, that damage goes to this one instead.
## {"type": PASSIVE_TURN_START_STATUS, "status", "stacks", "target"} —
## Capacitor Bank: applies a status at the start of its mech's turn.
## {"type": PASSIVE_REDUCE_INCOMING_STATUS, "statuses", "amount"} —
## Insulated Core: incoming stacks of those statuses on this mech are
## reduced by `amount` each time they're applied.
##
## Passives are always in play while their component stands; they never
## become cards in the hand (CombatScene reveals them at the fight's start).
const PASSIVE_REDIRECT := "redirect"
const PASSIVE_TURN_START_STATUS := "turn_start_status"
const PASSIVE_REDUCE_INCOMING_STATUS := "reduce_incoming_status"
## The rest (data/component_rules.json has one per reactor):
const PASSIVE_HEAT_MODS := "heat_mods"                  # {max_heat, decay} while installed
const PASSIVE_RECYCLE_VENT := "recycle_vent"            # Recycling Loops
const PASSIVE_FACING_COVER := "facing_cover"            # Plated Housing: soaks hits on the part it faces
const PASSIVE_TURN_START_HEAL := "turn_start_heal_lowest" # Nano Bots
const PASSIVE_SAVE := "save_from_destruction"           # Redundant Wiring
const PASSIVE_FACING_STATUS := "facing_turn_start_status" # Coolant Flush
const PASSIVE_ON_DAMAGED_STATUS := "on_damaged_status"  # Reactive Plating
const PASSIVE_FIRST_CARD_DISCOUNT := "first_card_discount" # Overclock Shunt
const PASSIVE_NTH_ATTACK_TWICE := "nth_attack_twice"    # High Five

var id: String          # unique on its mech (a second Voltage Spike is "voltage_spike_2")
var library_id: String = ""  # the Refit Bay part it is (ComponentLibrary id)
var name: String
var category: String
var rarity: String = ""   # surplus / salvaged / prototype (Refit Bay)
var max_hp: int
var current_hp: int
var cells: Array[Vector2i] = []          # local shape, unrotated
var offset: Vector2i = Vector2i.ZERO
var rotation_steps: int = 0
var placed_cells: Array[Vector2i] = []   # in the owning mech's grid space
var cards: Array[CardData] = []
var passive: Dictionary = {} # see PASSIVE_*; {} = none

var destroyed: bool = false
var statuses: Array[StatusInstance] = [] # Shock / Acid / Disabled / Offline / Coolant / Jam / Burn / Freeze

## Renames this instance (and re-points its cards at it), so two copies of
## the same part can sit on one mech.
func set_instance_id(new_id: String) -> void:
	id = new_id
	for card in cards:
		card.owner_component_id = new_id

## Places it in some grid: rotation steps and offset, recomputing placed_cells.
func place(steps: int, p_offset: Vector2i) -> void:
	rotation_steps = steps
	offset = p_offset
	placed_cells = GridUtils.place_cells(cells, steps, p_offset)

func is_destroyed() -> bool:
	return destroyed

func passive_type() -> String:
	return passive.get("type", "")

func has_passive() -> bool:
	return passive_type() != ""

## Player-facing description of the passive ("" if none).
func passive_text() -> String:
	return passive.get("text", "")

## Can act: standing, not Disabled, not Offline (Statuses & Links).
func is_usable() -> bool:
	return not destroyed and status_stacks("disabled") <= 0 and status_stacks("offline") <= 0

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
	c.library_id = library_id
	c.name = name
	c.category = category
	c.rarity = rarity
	c.max_hp = max_hp
	c.current_hp = current_hp
	c.cells = cells.duplicate()
	c.offset = offset
	c.rotation_steps = rotation_steps
	c.placed_cells = placed_cells.duplicate()
	c.cards = []
	for card in cards:
		c.cards.append(card.clone())
	c.passive = passive.duplicate()
	c.destroyed = destroyed
	c.statuses = []
	for s in statuses:
		c.statuses.append(s.clone())
	return c

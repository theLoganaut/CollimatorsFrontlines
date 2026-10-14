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
## Enemies: "regular" / "elite" / "boss", the AI's style ("careful" never
## overheats; "reckless" will), and a boss's pilot title ("Collimator Vasquez").
var tier: String = ""
var ai_profile: String = "careful"
var title: String = ""
## How this enemy plays (EnemyAI's profile keys: heat, cards, targets,
## slip, protocols, guard, phase2). {} = the defaults.
var ai: Dictionary = {}
## A boss's lines: {"intro", "phase2", "defeat"}.
var lines: Dictionary = {}
## A boss past its phase change (sticky once reached).
var phase2_reached: bool = false
var cells: Array[Vector2i] = []   # chassis cells
var max_heat: int
## Share of heat vented at max heat; < 0 = balance.json heat.vent_at_max
## (Overclocked Core lowers it for a run).
var vent_at_max: float = -1.0
## Heat added at the start of each of this mech's turns (Special
## Requisition, a run mod).
var turn_heat: int = 0
## Left the fight with nothing left to play (Logan, 2026-10-13); defeated.
var retreated: bool = false
var heat_check_timing: String
var components: Array[ComponentData] = []

var current_heat: int = 0
## Redirect Spike in a squad (Logan, 2026-10-13: "cover yourself OR an
## ally"): an ally's Spike covering this mech (`covered_by`, on
## `covered_by_mech`), and whether this mech's own Spike is away covering an
## ally. Set each round by CombatManager._assign_spikes.
var covered_by: ComponentData = null
var covered_by_mech: MechData = null
var spike_away: bool = false
var mech_statuses: Array[StatusInstance] = []  # Absorb / Deflect / Smoke (mech-scoped)

## A boss with phase-2 overrides switches once it falls to half its HP
## (balance.json enemy_ai.boss_phase_at), and stays switched.
func in_phase2() -> bool:
	if phase2_reached:
		return true
	if not ai.has("phase2") or max_hp() <= 0:
		return false
	if current_hp() <= max_hp() * Balance.get_num("enemy_ai", "boss_phase_at", 0.5):
		phase2_reached = true
	return phase2_reached

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

## Share of max HP at or below which this mech is destroyed, whatever's
## left standing (Combat Rules). 0 = no threshold (only the hardpoint rule).
## Set per mech from its data (`defeat_hp_fraction` in the mech JSON).
var defeat_hp_fraction: float = 0.0

## A mech is destroyed (Logan, 2026-09-27), for players and enemies alike,
## once either:
## - every one of its hardpoints is destroyed (it can't fight back), or
## - its total HP falls to defeat_hp_threshold() — so damage to reactors and
##   protocols still counts toward the kill.
## - it retreated: nothing left it could ever play (CombatManager; counts
##   as a kill).
func is_defeated() -> bool:
	return retreated or all_hardpoints_destroyed() or current_hp() <= defeat_hp_threshold()

## Whether any part could still give it a card this fight: standing, with
## cards, and not Offline (Offline lasts the fight; Disabled wears off).
func has_cards_left() -> bool:
	return components.any(func(c): return not c.destroyed and c.has_cards() and c.status_stacks("offline") <= 0)

func defeat_hp_threshold() -> int:
	if defeat_hp_fraction <= 0.0:
		return 0
	return int(floor(max_hp() * defeat_hp_fraction))

## Every hardpoint destroyed. A mech with no hardpoints at all needs every
## component destroyed instead.
func all_hardpoints_destroyed() -> bool:
	var has_hardpoint := false
	for c in components:
		if c.category == ComponentData.CATEGORY_HARDPOINT:
			has_hardpoint = true
			if not c.destroyed:
				return false
	if has_hardpoint:
		return true
	for c in components:
		if not c.destroyed:
			return false
	return true

## The living part that damage aimed at `target` lands on instead, if any:
## a Plated Housing facing it first, else a Redirect Spike (never the
## target itself).
func cover_for(target: ComponentData) -> ComponentData:
	if target == null:
		return null
	for c in living_passives(ComponentData.PASSIVE_FACING_COVER):
		if c != target and Links.facing(self, c).has(target):
			return c
	if covered_by != null and not covered_by.destroyed:
		return covered_by
	if spike_away:
		return null
	for c in living_passives(ComponentData.PASSIVE_REDIRECT):
		if c != target:
			return c
	return null

## Overheat backlash multiplier from heat passives (Pressure Regulator).
func backlash_mult() -> float:
	var m := 1.0
	for c in living_passives(ComponentData.PASSIVE_HEAT_MODS):
		m *= float(c.passive.get("backlash_mult", 1.0))
	return m

## Standing parts with a passive of `type`.
func living_passives(type: String) -> Array[ComponentData]:
	var out: Array[ComponentData] = []
	for c in components:
		if not c.destroyed and c.passive_type() == type:
			out.append(c)
	return out

## Max heat including living Thermal Core / Overpressure Valve bonuses.
func heat_capacity() -> int:
	var cap := max_heat
	for c in living_passives(ComponentData.PASSIVE_HEAT_MODS):
		cap += int(c.passive.get("max_heat", 0))
	return cap

## Extra heat vented when this mech's heat disperses (Coolant Loop +1,
## Overpressure Valve −1).
func decay_bonus() -> int:
	var d := 0
	for c in living_passives(ComponentData.PASSIVE_HEAT_MODS):
		d += int(c.passive.get("decay", 0))
	return d

## The living part whose passive cuts incoming stacks of `status_name`
## (Insulated Core), if any.
func incoming_status_reducer(status_name: String) -> ComponentData:
	for c in components:
		if c.destroyed or c.passive_type() != ComponentData.PASSIVE_REDUCE_INCOMING_STATUS:
			continue
		if status_name in c.passive.get("statuses", []):
			return c
	return null

## Every component with a passive, destroyed ones included (for the UI).
func passive_components() -> Array[ComponentData]:
	var out: Array[ComponentData] = []
	for c in components:
		if c.has_passive():
			out.append(c)
	return out

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
	m.tier = tier
	m.ai_profile = ai_profile
	m.title = title
	m.ai = ai.duplicate(true)
	m.lines = lines.duplicate()
	m.phase2_reached = phase2_reached
	m.retreated = retreated
	m.cells = cells.duplicate()
	m.max_heat = max_heat
	m.vent_at_max = vent_at_max
	m.turn_heat = turn_heat
	m.defeat_hp_fraction = defeat_hp_fraction
	m.heat_check_timing = heat_check_timing
	m.components = []
	for c in components:
		m.components.append(c.clone())
	m.current_heat = current_heat
	m.mech_statuses = []
	for s in mech_statuses:
		m.mech_statuses.append(s.clone())
	return m

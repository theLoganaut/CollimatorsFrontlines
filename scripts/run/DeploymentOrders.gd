class_name DeploymentOrders
extends RefCounted
## Deployment orders (Logan, 2026-09-29): right after Launch the Operator
## offers three, one boost, one tradeoff and one gamble (anything random is
## a gamble), in a shuffled order that never says which is which. The pilot
## takes one before the first stop. Names and text are data/orders.json, the
## numbers balance.json "orders".
##
## Taking an order applies what it can at once (scraps, Cargo, lasting run
## effects in RunData.mods, a new map for the ones that change it) and
## queues the steps that need the pilot: pick a Salvaged part, place frame
## squares, choose a component to strip out or transmute. The offer and
## the queue live in RunData.orders and are saved with the run, so a reload
## can't reroll them.
##
## Every order that hands out parts opens the run with a refit (Logan,
## 2026-09-29), so a new part is never stuck waiting for a later one. For
## that refit Cargo is 5×5, so every part fits (orders "cargo_size" holds
## its real size; what's left outside it when the refit ends is scrapped,
## RunData.finish_refit). Scramble and Transmute put the old part's
## replacement in that Cargo and leave the swap in orders "swaps" for the
## refit to animate (SwapFx).

const PATH := "res://data/orders.json"
const KINDS := ["boost", "tradeoff", "gamble"]

const STEP_PICK := "pick"           # {category ("" until chosen), options, rarity}
const STEP_CELLS := "cells"         # {left}
const STEP_REMOVE := "remove"       # choose an installed component to strip out
const STEP_TRANSMUTE := "transmute" # choose an installed component to transmute

## Orders that hand out parts: the run opens with a refit.
const PART_ORDERS := ["requisition", "blind_drop", "hot_insertion", "spare_parts", "prototype_contract", "scramble", "transmute",
	"special_requisition", "mystery_crate"]
const OPENING_CARGO := 5

static var _defs: Array = []

static func all() -> Array:
	if _defs.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_defs = parsed.get("orders", []) if typeof(parsed) == TYPE_DICTIONARY else []
	return _defs

static func def(id: String) -> Dictionary:
	for o in all():
		if o["id"] == id:
			return o
	return {}

## balance.json orders.<id>.<key>.
static func num(id: String, key: String, fallback: float) -> float:
	return float(Balance.section("orders").get(id, {}).get(key, fallback))

static func title(id: String) -> String:
	return def(id).get("name", id)

## The order's text with its numbers filled in.
static func text(id: String) -> String:
	var vals := {}
	var nums: Dictionary = Balance.section("orders").get(id, {})
	for k in nums:
		var v = nums[k]
		vals[k] = str(int(v)) if typeof(v) == TYPE_FLOAT and v == floorf(v) else str(v)
	return str(def(id).get("text", "")).format(vals)

## Rolls the three offers onto the run (one of each kind, shuffled).
static func offer(run: RunData) -> void:
	var picks: Array = []
	for kind in KINDS:
		var pool := all().filter(func(o): return o["kind"] == kind)
		if not pool.is_empty():
			picks.append(pool[run.rng.randi() % pool.size()]["id"])
	for i in range(picks.size() - 1, 0, -1):
		var j := run.rng.randi_range(0, i)
		var t = picks[i]
		picks[i] = picks[j]
		picks[j] = t
	run.orders = {"offer": picks, "chosen": "", "steps": []}

static func current_step(run: RunData) -> Dictionary:
	var steps: Array = run.orders.get("steps", [])
	return steps[0] if not steps.is_empty() else {}

static func _pop_step(run: RunData) -> void:
	(run.orders["steps"] as Array).pop_front()

## Takes one of the offers. Returns what happened, for the Operator to say
## ("" if it can't be taken).
static func choose(run: RunData, id: String) -> String:
	if run.orders.is_empty() or run.orders.get("chosen", "") != "" or not (run.orders.get("offer", []) as Array).has(id):
		return ""
	run.orders["chosen"] = id
	var steps: Array = run.orders["steps"]
	var notes: Array[String] = []
	var n := func(key: String, fallback: float = 0.0) -> float: return num(id, key, fallback)
	if PART_ORDERS.has(id):
		_open_cargo(run)
	match id:
		"supply_drop":
			run.add_scraps(int(n.call("scraps")))
		"requisition":
			steps.append(_pick_step(str(Balance.section("orders").get(id, {}).get("rarity", "salvaged"))))
		"extra_cell":
			steps.append({"type": STEP_CELLS, "left": int(n.call("cells", 1))})
		"expanded_cargo":
			for i in range(int(n.call("rows", 1))):
				run.cargo.grow_rows()
		"field_repair":
			run.mods["repair_mult"] = n.call("repair_mult", 1.2)
		"cold_start":
			run.mods["cold_start_fights"] = int(n.call("fights", 2))
			run.mods["cold_start_stacks"] = int(n.call("stacks", 2))
		"wider_picks":
			run.mods["wider_fights"] = int(n.call("fights", 3))
			run.mods["wider_options"] = int(n.call("options", 4))
		"friendly_merchant":
			run.mods["free_parts"] = int(n.call("free_parts", 1))
		"stripped_frame":
			run.add_scraps(int(n.call("scraps")))
			steps.append({"type": STEP_REMOVE})
		"modular_chassis":
			for c in run.player_mech.components: # only the parts launched with (Logan)
				c.max_hp = maxi(1, c.max_hp + int(n.call("part_hp", -10)))
				c.current_hp = mini(c.current_hp, c.max_hp)
			steps.append({"type": STEP_CELLS, "left": int(n.call("cells", 2))})
		"overclocked_core":
			run.mods["max_heat"] = int(n.call("max_heat", 3))
			run.mods["vent_at_max"] = n.call("vent_at_max", 0.8)
		"hot_start":
			run.mods["max_heat"] = int(n.call("max_heat", 2))
			run.mods["start_heat"] = int(n.call("start_heat", 3))
		"salvage_rights":
			run.mods["scraps_mult"] = n.call("scraps_mult", 1.5)
			run.mods["map_odds"] = {"repair_chance": 0.0}
		"hunters_route":
			run.mods["elite_rolls"] = int(n.call("elite_rolls", 3))
			run.mods["map_odds"] = {
				"elite_chance": Balance.get_num("map", "elite_chance", 0.1) * n.call("elite_chance_mult", 2.0),
				"elite_min_row": int(n.call("elite_min_row", 1)),
			}
		"loan_shark":
			run.add_scraps(int(n.call("scraps")))
			run.mods["unpaid_fights"] = int(n.call("unpaid_fights", 3))
		"blind_drop":
			run.add_scraps(int(n.call("scraps")))
			run.mods["fog"] = int(n.call("sight_rows", 2))
			steps.append(_pick_step(str(Balance.section("orders").get(id, {}).get("rarity", "prototype"))))
		"hot_insertion":
			for i in range(int(n.call("picks", 2))):
				steps.append(_pick_step(str(Balance.section("orders").get(id, {}).get("rarity", "salvaged"))))
			run.mods["strong_fights"] = int(n.call("strong_fights", 2))
		"heavy_hauler":
			for i in range(int(n.call("rows", 2))):
				run.cargo.grow_rows()
			for i in range(int(n.call("cols", 1))):
				run.cargo.grow_cols()
			run.mods["max_heat"] = int(n.call("max_heat", -1))
		"spare_parts":
			for i in range(int(n.call("parts", 2))):
				var pid := Economy.roll_part(Economy.CATEGORIES[run.rng.randi() % 3], run.rng, [], 1, run.player_mech.weight_class, "surplus")
				if pid != "":
					notes.append(stow(run, run.new_part(pid)))
		"prototype_contract":
			var pid := Economy.roll_part(Economy.CATEGORIES[run.rng.randi() % 3], run.rng, [], 1, run.player_mech.weight_class, "prototype")
			for c in run.player_mech.components:
				c.current_hp = maxi(1, ceili(c.max_hp * n.call("hp_share", 0.6)))
			if pid != "":
				notes.append(stow(run, run.new_part(pid)))
		"scramble":
			notes.append(_scramble(run))
		# 2026-09-30 drafts (Claude, for Logan to vet): only effects the orders above already use
		"heat_sinks":
			run.mods["max_heat"] = int(n.call("max_heat", 1))
		"wide_cargo":
			for i in range(int(n.call("cols", 1))):
				run.cargo.grow_cols()
		"black_market":
			run.mods["free_parts"] = int(n.call("free_parts", 2))
			run.mods["scraps_mult"] = n.call("scraps_mult", 0.75)
		"heavy_plating":
			for c in run.player_mech.components: # only the parts launched with, like Modular Chassis
				c.max_hp += int(n.call("part_hp", 12))
				c.current_hp += int(n.call("part_hp", 12))
			run.mods["vent_at_max"] = n.call("vent_at_max", 0.9)
		"forced_march":
			run.add_scraps(int(n.call("scraps")))
			run.mods["map_odds"] = {"repair_chance": Balance.get_num("map", "repair_chance", 0.15) * n.call("repair_chance_mult", 0.5)}
		"special_requisition":
			steps.append(_pick_step("prototype"))
			run.mods["turn_heat"] = int(n.call("turn_heat", 2))
		"mystery_crate":
			for i in range(int(n.call("parts", 2))):
				var pid := Economy.roll_part(Economy.CATEGORIES[run.rng.randi() % 3], run.rng, [], 1, run.player_mech.weight_class, "")
				if pid != "":
					notes.append(stow(run, run.new_part(pid)))
		"coin_flip":
			if run.rng.randf() < n.call("chance", 0.5):
				run.add_scraps(int(n.call("scraps")))
				notes.append("Heads: +%d scraps." % int(n.call("scraps")))
			else:
				for c in run.player_mech.components:
					c.current_hp = maxi(1, ceili(c.max_hp * n.call("hp_share", 0.7)))
				notes.append("Tails: your parts start at %d%% HP." % int(round(n.call("hp_share", 0.7) * 100.0)))
		"unmapped_route":
			var odds := {}
			for key in ["repair_chance", "shop_chance", "event_chance", "elite_chance"]:
				odds[key] = Balance.get_num("map", key, 0.12) * run.rng.randf_range(n.call("odds_min", 0.5), n.call("odds_max", 2.0))
			run.mods["map_odds"] = odds
		"transmute":
			steps.append({"type": STEP_TRANSMUTE})
	run.apply_mech_mods()
	if run.mods.has("map_odds"):
		run.build_map()
	_maybe_open_refit(run)
	return "  ·  ".join(notes.filter(func(s): return s != ""))

## Cargo grows to 5×5 until the opening refit ends.
static func _open_cargo(run: RunData) -> void:
	if not run.orders.has("cargo_size"):
		run.orders["cargo_size"] = [run.cargo.rows, run.cargo.cols]
	run.cargo.rows = maxi(run.cargo.rows, OPENING_CARGO)
	run.cargo.cols = maxi(run.cargo.cols, OPENING_CARGO)

## Once a parts order has nothing left for the pilot, the run opens with a refit.
static func _maybe_open_refit(run: RunData) -> void:
	if PART_ORDERS.has(run.orders.get("chosen", "")) and (run.orders.get("steps", []) as Array).is_empty():
		run.phase = RunData.PHASE_REFIT

static func _pick_step(rarity: String) -> Dictionary:
	return {"type": STEP_PICK, "rarity": rarity, "category": "", "options": []}

## A new part goes into Cargo, or onto the workbench if Cargo is full
## (it waits there for the next refit or autonomous bay). `acquired`:
## counts toward the run's parts acquired (a swapped-in part doesn't).
static func stow(run: RunData, comp: ComponentData, acquired: bool = true) -> String:
	if acquired:
		run.stats.add("parts_acquired")
	if run.cargo.add(comp):
		return "%s stowed in Cargo." % comp.name
	if run.bench.add(comp):
		return "%s is waiting on the workbench (Cargo was full)." % comp.name
	return "No room for %s; left behind." % comp.name

# ---------- the steps that need the pilot ----------

## A pick step: choose the category (rolls its options once).
static func pick_category(run: RunData, category: String) -> Array:
	var step := current_step(run)
	if step.get("type", "") != STEP_PICK:
		return []
	if step["category"] == "":
		step["category"] = category
		step["options"] = Economy.roll_options(category, run.rng, 1, run.player_mech.weight_class, step["rarity"])
	return step["options"]

## A pick step: take one of its options. Returns the note ("" if not an option).
static func pick_part(run: RunData, component_id: String) -> String:
	var step := current_step(run)
	if step.get("type", "") != STEP_PICK or not (step.get("options", []) as Array).has(component_id):
		return ""
	_pop_step(run)
	var note := stow(run, run.new_part(component_id))
	_maybe_open_refit(run)
	return note

## A cells step: add a free frame square.
static func add_cell(run: RunData, cell: Vector2i) -> bool:
	var step := current_step(run)
	if step.get("type", "") != STEP_CELLS or not run.add_frame_cell(cell):
		return false
	step["left"] = int(step["left"]) - 1
	if step["left"] <= 0:
		_pop_step(run)
	return true

## Whether `comp` can be chosen for a remove / transmute step (the last
## working hardpoint can't be stripped out).
static func can_choose_part(run: RunData, comp: ComponentData) -> bool:
	var step := current_step(run)
	if not run.player_mech.components.has(comp) or comp.destroyed:
		return false
	match step.get("type", ""):
		STEP_TRANSMUTE:
			return true
		STEP_REMOVE:
			if comp.category != ComponentData.CATEGORY_HARDPOINT:
				return true
			return run.player_mech.components.any(func(c): return c != comp and not c.destroyed and c.category == ComponentData.CATEGORY_HARDPOINT)
	return false

## A remove or transmute step: acts on `comp`. Returns the note ("" if it can't).
static func choose_part(run: RunData, comp: ComponentData) -> String:
	if not can_choose_part(run, comp):
		return ""
	var type: String = current_step(run)["type"]
	_pop_step(run)
	if type == STEP_REMOVE:
		run.player_mech.components.erase(comp)
		return "%s stripped out." % comp.name
	var note := _swap_all(run, [comp])
	_maybe_open_refit(run)
	return note

## Scramble: every installed part swapped.
static func _scramble(run: RunData) -> String:
	return _swap_all(run, run.player_mech.components.filter(func(c): return not c.destroyed))

## Swaps each of `parts` for a random part of its category one rarity up.
## The old part comes off the chassis and its replacement goes into Cargo
## (5×5 for the opening refit); orders "swaps" keeps what the refit shows:
## [{old, rotation, offset, new (the new part's id)}].
static func _swap_all(run: RunData, parts: Array) -> String:
	var mech := run.player_mech
	var swaps: Array = run.orders.get("swaps", [])
	var notes: Array[String] = []
	for old in parts:
		var id := Economy.roll_part(old.category, run.rng, [old.library_id], 1, mech.weight_class, Economy.rarity_above(old.rarity))
		if id == "":
			continue
		mech.components.erase(old)
		var comp := run.new_part(id)
		stow(run, comp, false)
		swaps.append({"old": old.library_id, "rotation": old.rotation_steps, "offset": [old.offset.x, old.offset.y], "new": comp.id})
		notes.append("%s → %s" % [old.name, comp.name])
	run.orders["swaps"] = swaps
	return "  ·  ".join(notes)

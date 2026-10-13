class_name RunParts
extends RefCounted
## A run's parts, for RunData: new parts, moving them between the chassis,
## Cargo and the 6×6 workbench, scrapping what's left behind, and refits.
## Static and stateless: the parts live on the run passed in.

## A fresh copy of a Refit Bay part with an id unique on this run.
static func new_part(run: RunData, library_id: String) -> ComponentData:
	var comp := ComponentLibrary.make(library_id)
	var id := library_id
	var n := 2
	while id_in_use(run, id):
		id = "%s_%d" % [library_id, n]
		n += 1
	comp.set_instance_id(id)
	return comp

static func id_in_use(run: RunData, id: String) -> bool:
	for c in run.player_mech.components + run.cargo.items + run.bench.items:
		if c.id == id:
			return true
	return false

static func discard_from_cargo(run: RunData, comp: ComponentData) -> void:
	run.cargo.remove(comp)

static func chassis_cells(run: RunData) -> Dictionary:
	return GridUtils.cells_to_set(run.player_mech.cells)

static func mech_occupied(run: RunData, except: ComponentData = null) -> Dictionary:
	var set := {}
	for c in run.player_mech.components:
		if c == except:
			continue
		for cell in c.placed_cells:
			set[cell] = true
	return set

static func can_install(run: RunData, comp: ComponentData, steps: int, offset: Vector2i) -> bool:
	return fits_class(run, comp) and GridUtils.can_place(comp.cells, steps, offset, chassis_cells(run), mech_occupied(run, comp))

## Whether a part's weight class fits this run's mech (General fits all).
static func fits_class(run: RunData, comp: ComponentData) -> bool:
	return ComponentLibrary.fits_class(comp.library_id, run.player_mech.weight_class)

## Refit: moves a part (from Cargo, or elsewhere on the mech) onto the chassis.
static func install(run: RunData, comp: ComponentData, steps: int, offset: Vector2i) -> bool:
	if run.phase != RunData.PHASE_REFIT or not can_install(run, comp, steps, offset):
		return false
	run.cargo.remove(comp)
	comp.place(steps, offset)
	if not run.player_mech.components.has(comp):
		run.player_mech.components.append(comp)
	return true

## Refit: moves a part (from the mech, or elsewhere in Cargo) into Cargo.
static func stow(run: RunData, comp: ComponentData, steps: int, offset: Vector2i) -> bool:
	if run.phase != RunData.PHASE_REFIT or not run.cargo.can_place(comp, steps, offset):
		return false
	run.player_mech.components.erase(comp)
	return run.cargo.place(comp, steps, offset)

## Whether parts can be moved around here: Cargo and the workbench at a
## refit or an autonomous bay; the chassis at a refit, and at an autonomous
## bay too while economy.shop_refit is on (a trial, 2026-10-02).
static func can_rearrange(run: RunData, to: String) -> bool:
	if to == RunData.MECH:
		if run.phase == RunData.PHASE_SHOP:
			return bool(Balance.section("economy").get("shop_refit", false))
		return run.phase == RunData.PHASE_REFIT
	return run.phase == RunData.PHASE_REFIT or run.phase == RunData.PHASE_SHOP

## Whether `comp` fits at `offset` (turned `steps`) on the chassis, in Cargo
## or on the workbench.
static func can_move(run: RunData, comp: ComponentData, to: String, steps: int, offset: Vector2i) -> bool:
	if not can_rearrange(run, to) or comp.destroyed:
		return false
	match to:
		RunData.MECH: return can_install(run, comp, steps, offset)
		RunData.CARGO: return run.cargo.can_place(comp, steps, offset)
		RunData.BENCH: return run.bench.can_place(comp, steps, offset)
	return false

## Moves a part (from anywhere it is) onto the chassis, into Cargo or onto
## the workbench.
static func move_part(run: RunData, comp: ComponentData, to: String, steps: int, offset: Vector2i) -> bool:
	if not can_move(run, comp, to, steps, offset):
		return false
	run.player_mech.components.erase(comp)
	run.cargo.remove(comp)
	run.bench.remove(comp)
	match to:
		RunData.MECH:
			comp.place(steps, offset)
			run.player_mech.components.append(comp)
		RunData.CARGO:
			run.cargo.place(comp, steps, offset)
		RunData.BENCH:
			run.bench.place(comp, steps, offset)
	return true

## Scraps for the parts on the workbench (what leaving would pay).
static func bench_value(run: RunData) -> int:
	var total := 0
	for c in run.bench.items:
		total += Economy.scrap_value(c)
	return total

## Leaving a refit or autonomous bay: every part left on the workbench is
## scrapped for scraps. Returns {"names": [...], "scraps": n}.
static func scrap_bench(run: RunData) -> Dictionary:
	var names: Array[String] = []
	var total := bench_value(run)
	for c in run.bench.items:
		names.append(c.name)
	run.bench.items.clear()
	if total > 0:
		run.add_scraps(total)
		run.stats.add("parts_scrapped", names.size())
	return {"names": names, "scraps": total}

## Destroyed parts are gone for the run: a refit clears their wrecks off
## the chassis. Returns the names scrapped.
static func scrap_destroyed(run: RunData) -> Array[String]:
	var names: Array[String] = []
	for c in run.player_mech.components.duplicate():
		if c.destroyed:
			names.append(c.name)
			run.player_mech.components.erase(c)
	return names

## A refit can only end with at least one working hardpoint installed.
static func can_finish_refit(run: RunData) -> bool:
	for c in run.player_mech.components:
		if c.category == ComponentData.CATEGORY_HARDPOINT and not c.destroyed:
			return true
	return false

## The opening refit (a deployment order that hands out parts): Cargo's
## real size while it's 5×5, else ZERO.
static func opening_cargo_size(run: RunData) -> Vector2i:
	var s: Array = run.orders.get("cargo_size", [])
	return Vector2i(int(s[0]), int(s[1])) if s.size() == 2 else Vector2i.ZERO

## Parts in the opening refit's Cargo outside its real size (scrapped when
## the refit ends).
static func cargo_overflow(run: RunData) -> Array[ComponentData]:
	var out: Array[ComponentData] = []
	var real := opening_cargo_size(run)
	if real == Vector2i.ZERO:
		return out
	for c in run.cargo.items:
		if c.placed_cells.any(func(cell): return cell.x >= real.x or cell.y >= real.y):
			out.append(c)
	return out

## Parts scrapped by leaving now (the workbench, plus the opening refit's
## Cargo overflow), and what they pay.
## Every part leaving now would scrap: the workbench's, then any outside
## the opening refit's real Cargo.
static func leave_scrap_parts(run: RunData) -> Array[ComponentData]:
	var out: Array[ComponentData] = []
	out.append_array(run.bench.items)
	out.append_array(cargo_overflow(run))
	return out

static func leave_scrap_count(run: RunData) -> int:
	return run.bench.items.size() + cargo_overflow(run).size()

static func leave_scrap_value(run: RunData) -> int:
	var total := bench_value(run)
	for c in cargo_overflow(run):
		total += Economy.scrap_value(c)
	return total

## Ends the opening refit's big Cargo: what sits outside the real size is
## scrapped, and Cargo shrinks back.
static func close_opening_cargo(run: RunData) -> void:
	var real := opening_cargo_size(run)
	if real == Vector2i.ZERO:
		return
	var over := cargo_overflow(run)
	var total := 0
	for c in over:
		total += Economy.scrap_value(c)
		run.cargo.remove(c)
	if total > 0:
		run.add_scraps(total)
		run.stats.add("parts_scrapped", over.size())
	run.cargo.rows = real.x
	run.cargo.cols = real.y
	run.orders.erase("cargo_size")

static func finish_refit(run: RunData) -> bool:
	if run.phase != RunData.PHASE_REFIT or not can_finish_refit(run):
		return false
	close_opening_cargo(run)
	scrap_bench(run)
	run.stats.add("refits")
	run.phase = RunData.PHASE_MAP
	return true

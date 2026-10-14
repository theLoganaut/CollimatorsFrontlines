extends WorkshopScreen
## Refit (offered only after stops 2, 4 and 6 — Logan, 2026-09-27), in the
## field refit bay (assets/run/refit_bay.png): the chassis on the left, Cargo
## and the 6×6 workbench on the right (WorkshopScreen). Drag parts between
## all three, R or right-click to rotate while dragging; a ghost shows where
## the part would land, green if it fits. Destroyed parts are scrapped when
## the refit opens (they're gone for the run). Done needs at least one
## working hardpoint installed, and scraps whatever is left on the bench.
## The opening refit after a deployment order that hands out parts has a
## 5×5 Cargo (the squares past its real size shaded amber, scrapped at the
## end), and first plays Scramble / Transmute's swaps (SwapFx): each old
## part lifts off the chassis, becomes an orb, and its replacement comes out
## into Cargo.

const CHASSIS_MAX := Vector2(306, 420)
const CHASSIS_CELL := 46.0

var _mech_title: Label
var _mech_grid: PackingGrid
var _mech_info: Label

func screen_phase() -> String:
	return RunData.PHASE_REFIT

func screen_title() -> String:
	return "Refit"

func bay_art() -> String:
	return "res://assets/run/refit_bay.png"

func pad_center() -> Vector2:
	return Vector2(310, 304)

func leave_text() -> String:
	return "Finish refit"

var _scrapped: Array[String] = []

func _build_left() -> void:
	_scrapped = run.scrap_destroyed()
	_mech_title = UIKit.label("CHASSIS  ·  %s  ·  %s" % [run.player_mech.name.to_upper(), run.player_mech.weight_class.to_upper()], 11, Color("b9d8d4"))
	_mech_title.position = Vector2(12, 10)
	_left.add_child(_mech_title)
	_mech_grid = _add_grid(_left, RunData.MECH)
	_mech_info = UIKit.label("", 11, Color("9fb9b6"), true)
	_mech_info.size = Vector2(LEFT.size.x - 24, 60)
	_left.add_child(_mech_info)
	var hint := UIKit.label("Click a part to pick it up, then click where it goes (or drag it).\n%s or right-click rotates it while held." % GameSettings.key_label("rotate"), 11, Color("7f9d9a"), true)
	hint.position = Vector2(12, LEFT.size.y - 52)
	hint.size = Vector2(LEFT.size.x - 24, 40)
	_left.add_child(hint)

func _after_build() -> void:
	var swaps: Array = run.orders.get("swaps", [])
	if not swaps.is_empty() and not run.orders.get("swaps_shown", false):
		_play_swaps.call_deferred(swaps)
		return
	if run.opening_cargo_size() != Vector2i.ZERO:
		_say_opening()
	elif not _scrapped.is_empty():
		_say("Scrapped the wreck%s of %s." % ["s" if _scrapped.size() > 1 else "", ", ".join(_scrapped)], Color("9fb9b6"))
	elif run.can_finish_refit():
		_say("Hover a part to inspect it.")

static func _bounds_of(cells: Array[Vector2i]) -> Vector2i:
	var b := Vector2i.ZERO
	for c in cells:
		b = Vector2i(maxi(b.x, c.x + 1), maxi(b.y, c.y + 1))
	return b

func _refresh_extra() -> void:
	var m := run.player_mech
	var b := _bounds_of(m.cells)
	var cell := minf(CHASSIS_CELL, minf((CHASSIS_MAX.x + PackingGrid.GAP) / b.y, (CHASSIS_MAX.y + PackingGrid.GAP) / b.x) - PackingGrid.GAP)
	_mech_grid.setup(run.chassis_cells(), b, floorf(cell))
	_mech_grid.set_parts(m.components)
	_mech_grid.position = Vector2(floorf((LEFT.size.x - _mech_grid.size.x) / 2.0), 34)
	var hardpoints := m.components.filter(func(c): return c.category == ComponentData.CATEGORY_HARDPOINT and not c.destroyed).size()
	var used := 0
	for c in m.components:
		used += c.cells.size()
	_mech_info.position = Vector2(12, _mech_grid.position.y + _mech_grid.size.y + 10.0)
	_mech_info.text = "%d / %d HP  ·  %d / %d cells  ·  %d hardpoint%s\nmax heat %d" % [m.current_hp(), m.max_hp(), used, m.cells.size(), hardpoints, "" if hardpoints == 1 else "s", m.heat_capacity()]
	if hardpoints == 0:
		_say("Install at least one working hardpoint to finish the refit.", Palette.WARNING)

func _can_leave() -> bool:
	return run.can_finish_refit()

func _say_opening() -> void:
	_say("Fit your new parts before you drop. Cargo is 5×5 for this refit only: anything left on the amber squares is scrapped.", Palette.OK)

## The swaps, staggered: each new part stays hidden until its orb sets it down.
func _play_swaps(swaps: Array) -> void:
	_busy = true
	var fresh := {} # swap index -> the new part
	for i in range(swaps.size()):
		for c in run.cargo.items + run.bench.items + run.player_mech.components:
			if c.id == str(swaps[i]["new"]):
				fresh[i] = c
				_hidden_parts.append(c)
	_refresh()
	await get_tree().process_frame
	_say("Transmuting…", Palette.LINK)
	var last: SwapFx = null
	var n := 0
	for i in range(swaps.size()):
		if not fresh.has(i):
			continue
		var s: Dictionary = swaps[i]
		var comp: ComponentData = fresh[i]
		var old := ComponentLibrary.make(str(s["old"]))
		if old == null:
			continue
		old.place(int(s["rotation"]), Vector2i(int(s["offset"][0]), int(s["offset"][1])))
		var to_grid: PackingGrid = _bench_grid if run.bench.items.has(comp) else _cargo_grid
		var fx := SwapFx.new()
		_stage.add_child(fx)
		fx.setup(old, old.rotation_steps, _mech_grid.cell_size, comp, to_grid.cell_size)
		fx.finished.connect(func():
			_hidden_parts.erase(comp)
			_refresh())
		fx.play(_centre_on(_mech_grid, old.placed_cells), _centre_on(to_grid, comp.placed_cells), 0.6 + n * 0.45) # after the screen fades in
		last = fx
		n += 1
	if last != null:
		await last.finished
	_hidden_parts.clear()
	run.orders["swaps_shown"] = true
	SaveGame.save(run)
	_busy = false
	_refresh()
	_say_opening()

## The middle of `cells` on `grid`, in the stage's coordinates.
func _centre_on(grid: PackingGrid, cells: Array[Vector2i]) -> Vector2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in cells:
		var p := grid.cell_pos(c)
		lo = lo.min(p)
		hi = hi.max(p + Vector2(grid.cell_size, grid.cell_size))
	return grid.global_position - _stage.global_position + (lo + hi) / 2.0

func _tutorial_targets() -> Dictionary:
	return {"mech": _mech_grid, "cargo": _cargo_grid, "keep_clear": [_mech_grid, _cargo_grid, _leave]}

func _on_leave() -> void:
	if SceneRouter.is_busy() or not _confirm_leave():
		return
	Tutorial.event("refit_done")
	if not run.finish_refit():
		return
	RunState.advance()

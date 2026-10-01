class_name RunShop
extends RefCounted
## Autonomous bays, for RunData: the stock, buying, selling, refining, Cargo
## upgrades and frame squares. Static and stateless: the run passed in holds
## the bay's state (`run.shop`) and the scraps.

## An autonomous bay's stock (shop rework, 2026-09-30, numbers Proposed):
## economy.shop_offers parts of each category, each with its own rarity
## roll, no repeats. Saved in `shop`, so a reload doesn't reroll it.
static func stock_shop(run: RunData) -> void:
	run.shop = {"parts": roll_stock(run), "upgrade_bought": false, "refined": false}

static func roll_stock(run: RunData) -> Array:
	var parts: Array = []
	var per := maxi(1, Balance.get_int("economy", "shop_offers", 2))
	for cat in Economy.CATEGORIES:
		var taken: Array = []
		for i in range(per):
			var id := Economy.roll_part(cat, run.rng, taken, 1, run.player_mech.weight_class)
			if id != "":
				taken.append(id)
			parts.append(id if id != "" else RunData.NO_STOCK)
	return parts

## Selling a part from Cargo or the workbench pays what scrapping it would.
static func can_sell(run: RunData, comp: ComponentData) -> bool:
	return run.phase == RunData.PHASE_SHOP and comp != null and (run.cargo.items.has(comp) or run.bench.items.has(comp))

static func sell_part(run: RunData, comp: ComponentData) -> int:
	if not can_sell(run, comp):
		return 0
	var value := Economy.scrap_value(comp)
	if run.cargo.items.has(comp):
		run.cargo.remove(comp)
	else:
		run.bench.remove(comp)
	run.add_scraps(value)
	return value

## Refining (once a visit): a part in Cargo or on the bench becomes a random
## part of its type one rarity up. The price is by its current rarity; -1
## when it can't be refined (Prototype, or no part one rarity up).
static func refine_price(_run: RunData, comp: ComponentData) -> int:
	if comp == null:
		return -1
	var rar := str(ComponentLibrary.definition(comp.library_id).get("rarity", "surplus"))
	return int(Balance.get_dict("economy", "refine_prices").get(rar, -1))

static func can_refine(run: RunData, comp: ComponentData) -> bool:
	return can_sell(run, comp) and not run.shop.get("refined", false) and refine_price(run, comp) >= 0 and run.scraps >= refine_price(run, comp)

## Returns the new part, or null (can't, or nothing one rarity up, or no room).
static func refine_part(run: RunData, comp: ComponentData) -> ComponentData:
	if not can_refine(run, comp):
		return null
	var def := ComponentLibrary.definition(comp.library_id)
	var target := Economy.rarity_above(str(def.get("rarity", "surplus")))
	var id := Economy.roll_part(comp.category, run.rng, [comp.library_id], 1, run.player_mech.weight_class, target)
	if id == "" or str(ComponentLibrary.definition(id).get("rarity", "")) != target:
		return null
	var in_cargo := run.cargo.items.has(comp)
	var home = run.cargo if in_cargo else run.bench
	home.remove(comp)
	var fresh := run.new_part(id)
	if not home.add(fresh) and not (run.bench if in_cargo else run.cargo).add(fresh):
		home.add(comp) # no room for the new shape: put the old part back
		return null
	var price := refine_price(run, comp)
	run.scraps -= price
	run.stats.add("scraps_spent", price)
	run.shop["refined"] = true
	return fresh

## Buys the shop's part in `slot` onto the workbench (into Cargo if the
## bench is full). Returns the new part, or null (sold out, not enough
## scraps, or no room anywhere).
static func buy_part(run: RunData, slot: int) -> ComponentData:
	if run.phase != RunData.PHASE_SHOP or slot < 0 or slot >= run.shop["parts"].size():
		return null
	var id: String = run.shop["parts"][slot]
	if id == "" or id == RunData.NO_STOCK or run.scraps < part_price(run, id):
		return null
	var comp := run.new_part(id)
	if not run.bench.add(comp) and not run.cargo.add(comp):
		return null
	var price := part_price(run, id)
	if int(run.mod("free_parts")) > 0:
		run._use_mod("free_parts")
	run.scraps -= price
	run.stats.add("scraps_spent", price)
	run.stats.add("parts_acquired")
	run.shop["parts"][slot] = ""
	return comp

## A shop part's price here (Friendly Merchant: free while it lasts).
static func part_price(run: RunData, id: String) -> int:
	return 0 if int(run.mod("free_parts")) > 0 else Economy.price(id)

static func cargo_upgrade_price(run: RunData) -> int:
	return Economy.cargo_upgrade_price(run.cargo_upgrades)

## +1 row (`add_row`) or +1 column of Cargo.
static func buy_cargo_upgrade(run: RunData, add_row: bool) -> bool:
	if run.phase != RunData.PHASE_SHOP or run.shop.get("upgrade_bought", true) or run.scraps < cargo_upgrade_price(run):
		return false
	run.scraps -= cargo_upgrade_price(run)
	run.stats.add("scraps_spent", cargo_upgrade_price(run))
	run.cargo_upgrades += 1
	if add_row:
		run.cargo.grow_rows()
	else:
		run.cargo.grow_cols()
	run.shop["upgrade_bought"] = true
	return true

## A frame square at an autonomous bay (Logan, 2026-09-28): 25 scraps, then
## 25 more than the last one each time (balance.json cell_price_*).
static func cell_price(run: RunData) -> int:
	return Balance.get_int("economy", "cell_price_base", 25) + Balance.get_int("economy", "cell_price_step", 25) * run.cells_bought

## The squares that can be added: empty ones touching the frame (holes in
## it included), no further than one ring around the chassis' original
## bounds (frame_ring). May sit at row or column -1.
static func cell_options(run: RunData) -> Array[Vector2i]:
	var have := run.chassis_cells()
	var ring := frame_ring(run)
	var out: Array[Vector2i] = []
	for c in run.player_mech.cells:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not have.has(n) and not out.has(n) and ring.has_point(n):
				out.append(n)
	return out

## Where frame squares may go: the original bounds grown by one ring.
static func frame_ring(run: RunData) -> Rect2i:
	return run.base_bounds.grow(1)

## Adds `cell` to the frame. A square above or left of the frame shifts the
## whole frame (and its parts) so cells stay at row/col 0 and up.
static func buy_cell(run: RunData, cell: Vector2i) -> bool:
	if run.phase != RunData.PHASE_SHOP or run.scraps < cell_price(run) or not cell_options(run).has(cell):
		return false
	var price := cell_price(run)
	run.scraps -= price
	run.stats.add("scraps_spent", price)
	run.cells_bought += 1
	return add_frame_cell(run, cell)

## Adds a square to the frame (bought, or free from a deployment order).
static func add_frame_cell(run: RunData, cell: Vector2i) -> bool:
	if not cell_options(run).has(cell):
		return false
	run.player_mech.cells.append(cell)
	var shift := Vector2i(maxi(0, -cell.x), maxi(0, -cell.y))
	if shift != Vector2i.ZERO:
		run.base_bounds.position += shift
		for i in range(run.player_mech.cells.size()):
			run.player_mech.cells[i] += shift
		for c in run.player_mech.components:
			c.place(c.rotation_steps, c.offset + shift)
	return true

static func leave_shop(run: RunData) -> void:
	if run.phase == RunData.PHASE_SHOP:
		run.scrap_bench()
		run.shop = {}
		run.mods.erase("free_parts") # Friendly Merchant: only the first bay
		run._finish_node()

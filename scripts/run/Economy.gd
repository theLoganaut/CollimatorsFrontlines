class_name Economy
extends RefCounted
## Reward rolls, scraps and prices (Logan, 2026-09-27: two-stage pick,
## Surplus 70% / Salvaged 25% / Prototype 5%, scraps spent at autonomous
## bays). The numbers live in data/balance.json ("economy"); they're
## Proposed, tuned by sim.

const CATEGORIES := ["hardpoint", "reactor", "protocol"]
const RARITIES := ["surplus", "salvaged", "prototype"]

static func _weights() -> Array:
	var w := Balance.get_dict("economy", "rarity_weights")
	return [float(w.get("surplus", 0.70)), float(w.get("salvaged", 0.25)), float(w.get("prototype", 0.05))]

static func options_per_pick() -> int:
	return Balance.get_int("economy", "options_per_pick", 3)

static func roll_rarity(rng: RandomNumberGenerator) -> String:
	var r := rng.randf()
	var acc := 0.0
	var weights := _weights()
	for i in range(RARITIES.size()):
		acc += weights[i]
		if r < acc:
			return RARITIES[i]
	return RARITIES[0]

## One part of `category`: roll a rarity, then pick among implemented parts
## of it. If that rarity has none (Refit Bay has no Prototypes yet), step
## down to the next rarity that does, then up. `exclude` avoids repeats.
## A `rarity` given skips the roll (deployment orders).
static func roll_part(category: String, rng: RandomNumberGenerator, exclude: Array = [], rolls: int = 1, weight_class: String = "", rarity: String = "") -> String:
	if rarity == "":
		rarity = roll_rarity(rng)
		for i in range(rolls - 1): # elites and bosses: keep the best of several rolls
			var again := roll_rarity(rng)
			if RARITIES.find(again) > RARITIES.find(rarity):
				rarity = again
	var start := RARITIES.find(rarity)
	var order: Array = []
	for i in range(start, -1, -1):
		order.append(RARITIES[i])
	for i in range(start + 1, RARITIES.size()):
		order.append(RARITIES[i])
	for rar in order:
		var pool := ComponentLibrary.pool(category, rar, weight_class).filter(func(id): return not exclude.has(id))
		if not pool.is_empty():
			return pool[rng.randi_range(0, pool.size() - 1)]
	return ""

## Up to options_per_pick() (or `count`) different parts of one category.
static func roll_options(category: String, rng: RandomNumberGenerator, rolls: int = 1, weight_class: String = "", rarity: String = "", count: int = -1) -> Array[String]:
	var out: Array[String] = []
	for i in range(options_per_pick() if count < 0 else count):
		var id := roll_part(category, rng, out, rolls, weight_class, rarity)
		if id != "":
			out.append(id)
	return out

## Scraps for a fight of `enemy_count` enemies; elites and bosses pay more.
static func scraps_for_fight(enemy_count: int, rng: RandomNumberGenerator, kind: String = "fight") -> int:
	var base := Balance.get_int("economy", "scraps_base", 10) + Balance.get_int("economy", "scraps_per_enemy", 5) * enemy_count \
		+ rng.randi_range(0, Balance.get_int("economy", "scraps_spread", 5))
	return int(round(base * float(Balance.get_dict("economy", "scraps_mult").get(kind, 1.0))))

static func price(component_id: String) -> int:
	var prices := Balance.get_dict("economy", "prices")
	return int(prices.get(ComponentLibrary.definition(component_id).get("rarity", "surplus"), prices.get("surplus", 40)))

## What a part fetches when it's scrapped off the workbench: a share of its
## price (balance.json economy.scrap_fraction), less for a damaged part.
## What an undamaged part sells / scraps for, by library id.
static func sell_value(component_id: String) -> int:
	return maxi(1, int(round(price(component_id) * Balance.get_num("economy", "scrap_fraction", 0.5))))

static func scrap_value(comp: ComponentData) -> int:
	var hp_share := float(comp.current_hp) / float(maxi(comp.max_hp, 1))
	return maxi(1, int(round(price(comp.library_id) * Balance.get_num("economy", "scrap_fraction", 0.5) * hp_share)))

static func cargo_upgrade_price(bought_before: int) -> int:
	return int(round(Balance.get_num("economy", "cargo_upgrade_base", 50) * pow(Balance.get_num("economy", "cargo_upgrade_growth", 1.5), bought_before)))

static func repair_pool(max_hp: int, mult: float = 1.0) -> int:
	return int(floor(max_hp * Balance.get_num("economy", "repair_pool_fraction", 0.5) * mult))

## The next rarity up (Prototype stays Prototype).
static func rarity_above(rarity: String) -> String:
	return RARITIES[mini(RARITIES.find(rarity) + 1, RARITIES.size() - 1)] if RARITIES.has(rarity) else RARITIES[1]

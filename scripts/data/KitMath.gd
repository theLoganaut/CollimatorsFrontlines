class_name KitMath
extends RefCounted
## How hard a kit hits (Logan, 2026-09-30: starting kits ~50 a turn; the
## reward screen compares offers by it): the best turn of cards it can
## afford from cold within max heat, by average damage, each card once.
## Free and venting cards always go in (a vent card's negative cost adds to
## the budget); the rest is a knapsack over heat. Ignores statuses,
## protocols and passives, so it's a yardstick, not a forecast.

static func best_turn(cards: Array, max_heat: int) -> float:
	var budget := max_heat
	var total := 0.0
	var paid: Array = []
	for c in cards:
		if c.hits <= 0 and c.heat_cost >= 0:
			continue
		if c.heat_cost <= 0:
			total += c.average_damage()
			budget -= c.heat_cost
		else:
			paid.append(c)
	budget = maxi(budget, 0)
	var dp := PackedFloat32Array()
	dp.resize(budget + 1)
	for c in paid:
		var w: int = c.heat_cost
		for h in range(budget, w - 1, -1):
			dp[h] = maxf(dp[h], dp[h - w] + c.average_damage())
	return total + (dp[budget] if budget >= 0 else 0.0)

## A mech's living parts' cards.
static func mech_turn(mech: MechData) -> float:
	var cards: Array = []
	for comp in mech.non_destroyed_components():
		cards.append_array(comp.cards)
	return best_turn(cards, mech.heat_capacity())

## The same with one more part's cards (an offered part, installed as well).
static func with_part(mech: MechData, part: ComponentData) -> float:
	var cards: Array = []
	for comp in mech.non_destroyed_components():
		cards.append_array(comp.cards)
	cards.append_array(part.cards)
	return best_turn(cards, mech.heat_capacity())

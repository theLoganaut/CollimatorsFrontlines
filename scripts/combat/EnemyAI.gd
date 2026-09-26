class_name EnemyAI
extends RefCounted
## v1 enemy AI (Combat Slice §3): walk a Warden's non-destroyed components
## left-to-right by leftmost column (tie -> topmost row); each one with
## cards plays one random affordable card at a random non-destroyed player
## component. Components with no cards are skipped. Never overheats, since
## it only ever considers cards it can afford.

## Components that act this turn, in walk order. Components with no cards
## are left out entirely (they're skipped, not "acted on and did nothing").
static func act_order(mech: MechData) -> Array[ComponentData]:
	var acting := mech.non_destroyed_components().filter(func(c): return c.has_cards())
	acting.sort_custom(func(a, b):
		if a.leftmost_column() != b.leftmost_column():
			return a.leftmost_column() < b.leftmost_column()
		return a.topmost_row() < b.topmost_row()
	)
	return acting

static func affordable_cards(component: ComponentData, mech: MechData) -> Array[CardData]:
	var out: Array[CardData] = []
	for c in component.cards:
		if mech.current_heat + c.heat_cost <= mech.max_heat:
			out.append(c)
	return out

static func choose_card(component: ComponentData, mech: MechData, rng: RandomNumberGenerator) -> CardData:
	var pool := affordable_cards(component, mech)
	if pool.is_empty():
		return null
	return pool[rng.randi() % pool.size()]

static func choose_target(defender_mech: MechData, rng: RandomNumberGenerator) -> ComponentData:
	var pool := defender_mech.non_destroyed_components()
	if pool.is_empty():
		return null
	return pool[rng.randi() % pool.size()]

## Runs one Warden's full turn against the player mech. Returns a small log
## (list of dictionaries) the UI/tests can inspect. Stops early if the
## player mech is fully destroyed mid-turn.
static func run_turn(warden: MechData, player_mech: MechData, rng: RandomNumberGenerator) -> Array:
	var log := []
	for component in act_order(warden):
		if player_mech.is_defeated():
			break
		var card := choose_card(component, warden, rng)
		if card == null:
			continue # can't afford anything right now — skipped, not "no-opped"
		var target := EnemyAI.choose_target(player_mech, rng)
		if target == null:
			break
		warden.current_heat += card.heat_cost
		var result := CardResolver.resolve_attack_card(card, warden, component, player_mech, target, rng)
		log.append({
			"component": component.id,
			"card": card.id,
			"target": target.id,
			"damage": result["total_damage"],
			"target_destroyed": result["target_destroyed"],
		})
	return log

class_name CombatManager
extends RefCounted
## The round state machine (Combat Slice §4.1) and win/lose check. Owns one
## seeded RNG for the whole fight so tests and bug repros are deterministic.
## Pure/headless: no scene tree dependency, so it's fully unit-testable
## (tests/TestCombatManager.gd) and the UI layer is just a thin wrapper
## around this + its signals.

enum Phase { PLAYER_TURN, ENEMY_TURN, GAME_OVER }
enum Result { NONE, WIN, LOSE }

signal component_damaged(mech: MechData, component: ComponentData, amount: int)
signal component_destroyed(mech: MechData, component: ComponentData)
signal card_played(mech: MechData, card: CardData)
signal overheated(mech: MechData, backlash: int)
signal turn_changed(phase: Phase, turn_number: int)
signal enemy_action(log_entry: Dictionary)
signal game_over(result: Result)

var player_mech: MechData
var enemies: Array[MechData] = []
var rng: RandomNumberGenerator
var phase: Phase = Phase.PLAYER_TURN
var turn_number: int = 1
var result: Result = Result.NONE

func _init(p_player: MechData, p_enemies: Array[MechData], seed_value: int = -1) -> void:
	player_mech = p_player
	enemies = p_enemies
	rng = RandomNumberGenerator.new()
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()

func start_combat() -> void:
	turn_number = 1
	result = Result.NONE
	phase = Phase.PLAYER_TURN
	_start_player_turn()

func is_player_turn() -> bool:
	return phase == Phase.PLAYER_TURN and result == Result.NONE

func is_game_over() -> bool:
	return phase == Phase.GAME_OVER

func living_enemies() -> Array[MechData]:
	return enemies.filter(func(m): return not m.is_defeated())

## Plays an attack card from the player's hand at one enemy component.
## Combat Slice §4.4: precise targeting only, all hits/damage/statuses go
## to this one component.
func play_attack_card(card: CardData, target_mech: MechData, target_component: ComponentData) -> Dictionary:
	if not is_player_turn():
		return {"ok": false, "reason": "not_player_turn"}
	if target_component == null or target_component.destroyed:
		return {"ok": false, "reason": "target_destroyed"}
	var attacker_component := player_mech.get_component(card.owner_component_id)
	if attacker_component == null or attacker_component.destroyed:
		return {"ok": false, "reason": "source_destroyed"}

	player_mech.current_heat += card.heat_cost
	var res := CardResolver.resolve_attack_card(card, player_mech, attacker_component, target_mech, target_component, rng)
	card_played.emit(player_mech, card)
	component_damaged.emit(target_mech, target_component, res["total_damage"])
	if target_component.destroyed:
		component_destroyed.emit(target_mech, target_component)

	if _check_player_overheat():
		return {"ok": true, "result": res, "overheated": true}
	_check_game_over()
	return {"ok": true, "result": res, "overheated": false}

## Plays a self card (Extension / Spike Setup / Lock On / Insulated Core).
func play_self_card(card: CardData) -> Dictionary:
	if not is_player_turn():
		return {"ok": false, "reason": "not_player_turn"}
	var owner_component := player_mech.get_component(card.owner_component_id)
	if owner_component == null or owner_component.destroyed:
		return {"ok": false, "reason": "source_destroyed"}

	player_mech.current_heat += card.heat_cost
	CardResolver.resolve_self_card(card, player_mech, owner_component)
	card_played.emit(player_mech, card)

	if _check_player_overheat():
		return {"ok": true, "overheated": true}
	return {"ok": true, "overheated": false}

## Live overheat check (Bastion's heat-check timing is "live" — §2, §4.3).
## Returns true if the mech overheated (and the turn was therefore forced
## to end, or the game ended).
func _check_player_overheat() -> bool:
	if not HeatRules.is_overheated(player_mech.current_heat, player_mech.max_heat):
		return false
	var backlash := HeatRules.apply_overheat_backlash(player_mech, rng)
	overheated.emit(player_mech, backlash)
	if _check_game_over():
		return true
	end_player_turn()
	return true

## End Turn button (or the forced end from an overheat). Runs round
## structure steps 3-6 then loops back into step 1 for the next player turn.
func end_player_turn() -> void:
	if phase != Phase.PLAYER_TURN or result != Result.NONE:
		return

	# Step 3: end-of-turn decay on the player's own components.
	CardResolver.decay_end_of_turn_statuses(player_mech)

	phase = Phase.ENEMY_TURN
	turn_changed.emit(phase, turn_number)

	# Step 4: player heat disperses, each living Warden's Absorb clears.
	player_mech.current_heat = HeatRules.heat_after_vent(player_mech.current_heat, player_mech.max_heat)
	for w in enemies:
		w.clear_mech_status("absorb")

	# Step 5: Warden 1 -> 2 -> 3, each acting fully before the next.
	for w in enemies:
		if player_mech.is_defeated():
			break
		if w.is_defeated():
			continue
		var log := EnemyAI.run_turn(w, player_mech, rng)
		for entry in log:
			enemy_action.emit(entry)

	if _check_game_over():
		return

	# Step 6: end-of-turn decay on every Warden's components.
	for w in enemies:
		CardResolver.decay_end_of_turn_statuses(w)

	turn_number += 1
	_start_player_turn()

## Step 1 of the next player turn: enemy heat disperses, Bastion's Absorb clears.
func _start_player_turn() -> void:
	for w in enemies:
		if not w.is_defeated():
			w.current_heat = HeatRules.heat_after_vent(w.current_heat, w.max_heat)
	player_mech.clear_mech_status("absorb")
	phase = Phase.PLAYER_TURN
	turn_changed.emit(phase, turn_number)

func _check_game_over() -> bool:
	if player_mech.is_defeated():
		_end_game(Result.LOSE)
		return true
	for w in enemies:
		if not w.is_defeated():
			return false
	_end_game(Result.WIN)
	return true

func _end_game(r: Result) -> void:
	result = r
	phase = Phase.GAME_OVER
	game_over.emit(r)

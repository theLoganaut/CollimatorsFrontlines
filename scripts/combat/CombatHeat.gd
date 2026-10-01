class_name CombatHeat
extends RefCounted
## Heat during a fight, for CombatManager: the live overheat check, the
## Overheat Fuse, backlash, and each mech's dispersal (ratio venting, the
## Vent action's flat share, decay bonuses, Smoke). Static and stateless:
## the fight's state lives on the CombatManager passed in.

## Live overheat check (Bastion's heat-check timing is "live" — §2, §4.3).
## Returns true if the mech overheated (and the turn was therefore forced
## to end, or the game ended). A mech that checks at the end of its turn
## (Redline) can run over its max mid-turn; see end_player_turn.
static func check_player_overheat(cm: CombatManager) -> bool:
	var p := cm.player_mech
	if p.heat_check_timing == MechData.HEAT_CHECK_END_OF_TURN:
		return false
	if not HeatRules.is_overheated(p.current_heat, p.heat_capacity()):
		return false
	if burn_fuse(cm, p):
		return false
	backlash(cm, p)
	if cm._check_game_over():
		return true
	cm.end_player_turn()
	return true

## Overheat Fuse: the first overheat doesn't happen; the fuse burns out and
## heat drops to max. Returns whether a fuse took it.
static func burn_fuse(cm: CombatManager, mech: MechData) -> bool:
	var fuses := mech.living_passives("overheat_fuse")
	if fuses.is_empty():
		return false
	var f: ComponentData = fuses[0]
	f.apply_damage(f.current_hp)
	mech.current_heat = mech.heat_capacity()
	cm.passive_triggered.emit(mech, f)
	cm.component_destroyed.emit(mech, f)
	return true

static func backlash(cm: CombatManager, mech: MechData) -> void:
	var alive_before := mech.non_destroyed_components()
	var amount := HeatRules.apply_overheat_backlash(mech, cm.rng)
	if mech == cm.player_mech:
		cm.stats.add("overheats")
		cm.stats.add("damage_taken", amount)
	cm.overheated.emit(mech, amount)
	for c in alive_before:
		if c.destroyed:
			cm.component_destroyed.emit(mech, c)
	CombatAttack.check_boss_phase(cm, mech)

## A mech's heat disperses (ratio venting), plus its decay bonus (Coolant
## Loop / Overpressure Valve), minus Smoke (each point vented clears a
## stack of Smoke first).
static func vent(cm: CombatManager, mech: MechData) -> void:
	var vented := HeatRules.amount_vented(mech.current_heat, mech.heat_capacity(), mech.vent_at_max)
	var vent_action := cm.venting.has(mech)
	if vent_action:
		cm.venting.erase(mech)
		vented = maxi(vented, HeatRules.vent_action_amount(mech.current_heat))
	vented = clampi(vented + mech.decay_bonus(), 0, mech.current_heat)
	var smoke := mech.mech_status_stacks("smoke")
	if smoke > 0 and vented > 0:
		var blocked := mini(smoke, vented)
		mech.remove_mech_status("smoke", blocked)
		vented -= blocked
	mech.current_heat -= vented
	if vent_action:
		cm.mech_vented.emit(mech, vented)

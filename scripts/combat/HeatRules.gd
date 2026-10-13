class_name HeatRules
extends RefCounted
## Pure heat math: ratio venting (Combat Slice §4.2, capped at 80%) and overheat backlash
## (§4.3). Every worked example in Combat Rules / Combat Slice §4.2 is
## reproduced in tests/TestHeatRules.gd.

## Ratio venting: the share vented is the heat %, scaled so that at max heat
## (or over it) `vent_at_max` of the heat vents (80%; Logan, 2026-09-28:
## "it shouldn't vent the full 100% at max heat"), rounded down:
## vented = floor(heat * min(heat, maxHeat) * vent_at_max / maxHeat).
## Returns the amount vented (not the remaining heat). `vent_at_max` < 0
## uses the balance.json value (a mech can carry its own, MechData.vent_at_max).
##
## With heat.full_reset on (a trial, 2026-10-02) all of it vents.
static func amount_vented(current_heat: int, max_heat: int, vent_at_max: float = -1.0) -> int:
	if max_heat <= 0 or current_heat <= 0:
		return 0
	if full_reset():
		return current_heat
	var share := vent_at_max if vent_at_max >= 0.0 else Balance.get_num("heat", "vent_at_max", 0.8)
	var pct := int(round(share * 100.0))
	# Integer division truncates toward zero, which is floor() for non-negative operands.
	var ratio_vented: int = (current_heat * mini(current_heat, max_heat) * pct) / (max_heat * 100)
	return mini(current_heat, ratio_vented)

## Whether every dispersal clears a mech's heat (balance.json heat.full_reset).
static func full_reset() -> bool:
	return bool(Balance.section("heat").get("full_reset", false))

## The Vent action's dispersal: a flat share of the heat (heat.vent_action_share,
## the same 80% the ratio reaches at max heat), rounded down.
static func vent_action_amount(current_heat: int) -> int:
	if current_heat <= 0:
		return 0
	var pct := int(round(Balance.get_num("heat", "vent_action_share", 0.8) * 100.0))
	return mini(current_heat, (current_heat * pct) / 100)

## Returns the mech's heat after venting.
static func heat_after_vent(current_heat: int, max_heat: int) -> int:
	return current_heat - amount_vented(current_heat, max_heat)

static func is_overheated(current_heat: int, max_heat: int) -> bool:
	return current_heat > max_heat

## floor(15% of max HP) — the overheat backlash total (Combat Slice §4.3).
static func overheat_backlash_total(max_hp: int) -> int:
	return (max_hp * 15) / 100

## What an overheat costs this mech now (Pressure Regulator raises it).
static func backlash_for(mech: MechData) -> int:
	return int(overheat_backlash_total(mech.max_hp()) * mech.backlash_mult())

## Deals the backlash total 1 point at a time to random non-destroyed
## components (re-picked fresh after every point, so a component that dies
## partway through redirects the rest). Ignores Deflect and Absorb — it
## goes straight through ComponentData.apply_damage(). Returns the total
## damage actually applied (may be less than the nominal total if every
## component runs out of HP first).
static func apply_overheat_backlash(mech: MechData, rng: RandomNumberGenerator) -> int:
	var total := backlash_for(mech)
	var applied := 0
	for i in range(total):
		var eligible := mech.non_destroyed_components()
		if eligible.is_empty():
			break
		var target: ComponentData = eligible[rng.randi() % eligible.size()]
		applied += target.apply_damage(1)
	return applied

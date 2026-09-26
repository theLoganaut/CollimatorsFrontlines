class_name HeatRules
extends RefCounted
## Pure heat math: ratio venting (Combat Slice §4.2) and overheat backlash
## (§4.3). Every worked example in Combat Rules / Combat Slice §4.2 is
## reproduced in tests/TestHeatRules.gd.

## vented = min(heat, floor(heat*heat/maxHeat)) — the share vented equals the
## mech's current heat %, rounded down; at >=100% heat everything vents.
## Returns the amount vented (not the remaining heat).
static func amount_vented(current_heat: int, max_heat: int) -> int:
	if max_heat <= 0 or current_heat <= 0:
		return 0
	# Integer division truncates toward zero, which is floor() for non-negative operands.
	var ratio_vented: int = (current_heat * current_heat) / max_heat
	return mini(current_heat, ratio_vented)

## Returns the mech's heat after venting.
static func heat_after_vent(current_heat: int, max_heat: int) -> int:
	return current_heat - amount_vented(current_heat, max_heat)

static func is_overheated(current_heat: int, max_heat: int) -> bool:
	return current_heat > max_heat

## floor(15% of max HP) — the overheat backlash total (Combat Slice §4.3).
static func overheat_backlash_total(max_hp: int) -> int:
	return (max_hp * 15) / 100

## Deals the backlash total 1 point at a time to random non-destroyed
## components (re-picked fresh after every point, so a component that dies
## partway through redirects the rest). Ignores Deflect and Absorb — it
## goes straight through ComponentData.apply_damage(). Returns the total
## damage actually applied (may be less than the nominal total if every
## component runs out of HP first).
static func apply_overheat_backlash(mech: MechData, rng: RandomNumberGenerator) -> int:
	var total := overheat_backlash_total(mech.max_hp())
	var applied := 0
	for i in range(total):
		var eligible := mech.non_destroyed_components()
		if eligible.is_empty():
			break
		var target: ComponentData = eligible[rng.randi() % eligible.size()]
		applied += target.apply_damage(1)
	return applied

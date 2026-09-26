class_name TestHeatRules
extends RefCounted
## Reproduces every worked heat example in Combat Rules / Combat Slice §4.2-4.3.

static func run_all(t: TestContext) -> void:
	t.group("HeatRules: ratio venting (Bastion, max heat 14)")
	t.assert_eq(HeatRules.heat_after_vent(3, 14), 3, "3 -> 3 (nothing vents)")
	t.assert_eq(HeatRules.heat_after_vent(5, 14), 4, "5 -> 4")
	t.assert_eq(HeatRules.heat_after_vent(7, 14), 4, "7 -> 4")
	t.assert_eq(HeatRules.heat_after_vent(10, 14), 3, "10 -> 3")
	t.assert_eq(HeatRules.heat_after_vent(12, 14), 2, "12 -> 2")
	t.assert_eq(HeatRules.heat_after_vent(13, 14), 1, "13 -> 1")
	t.assert_eq(HeatRules.heat_after_vent(14, 14), 0, "14 -> 0")
	t.assert_eq(HeatRules.heat_after_vent(17, 14), 0, "17 (overheated) -> 0, vents 100%")
	t.assert_eq(HeatRules.heat_after_vent(0, 14), 0, "0 heat stays 0")

	t.group("HeatRules: generic ratio example")
	t.assert_eq(HeatRules.amount_vented(9, 10), 8, "9/10 vents 8")
	t.assert_eq(HeatRules.heat_after_vent(9, 10), 1, "9/10 stays at 1")

	t.group("HeatRules: overheat state")
	t.assert_true(not HeatRules.is_overheated(14, 14), "at exactly max heat is not overheated")
	t.assert_true(HeatRules.is_overheated(15, 14), "one over max heat is overheated")

	t.group("HeatRules: overheat backlash total")
	t.assert_eq(HeatRules.overheat_backlash_total(162), 24, "floor(15% of Bastion's 162 max HP) = 24")
	t.assert_eq(HeatRules.overheat_backlash_total(140), 21, "floor(15% of 140) = 21")

	t.group("HeatRules: overheat backlash application")
	var comp_a := TestFixtures.make_component("a", 100)
	var comp_b := TestFixtures.make_component("b", 100)
	var mech := TestFixtures.make_mech("test", 14, [comp_a, comp_b])
	var r := TestFixtures.rng(42)
	var applied := HeatRules.apply_overheat_backlash(mech, r)
	t.assert_eq(applied, 30, "backlash total applied (15% of 200 max HP) = 30")
	t.assert_eq(comp_a.current_hp + comp_b.current_hp, 170, "200 total HP - 30 backlash = 170 remaining")
	t.assert_true(comp_a.current_hp >= 0 and comp_b.current_hp >= 0, "no component goes negative")

	t.group("HeatRules: backlash ignores Deflect/Absorb (goes straight through)")
	var comp_c := TestFixtures.make_component("c", 50)
	var shielded_mech := TestFixtures.make_mech("shielded", 14, [comp_c])
	shielded_mech.add_mech_status("deflect", 999)
	shielded_mech.add_mech_status("absorb", 999)
	var applied2 := HeatRules.apply_overheat_backlash(shielded_mech, TestFixtures.rng(1))
	t.assert_eq(applied2, HeatRules.overheat_backlash_total(50), "Deflect/Absorb don't reduce backlash at all")
	t.assert_eq(shielded_mech.mech_status_stacks("deflect"), 999, "Deflect stacks untouched by backlash")
	t.assert_eq(shielded_mech.mech_status_stacks("absorb"), 999, "Absorb stacks untouched by backlash")

	t.group("HeatRules: backlash stops once every component is destroyed")
	# 15% of max HP can never fully destroy a component starting at full health
	# (0.15*H < H for any H>0) — so this starts it already weakened: max 20,
	# currently at 2 HP. Backlash total = floor(0.15*20) = 3 nominal points,
	# but only 2 are needed to destroy it, and the 3rd has nothing left to hit.
	var tiny := TestFixtures.make_component("tiny", 20)
	tiny.current_hp = 2
	var tiny_mech := TestFixtures.make_mech("tiny_mech", 14, [tiny])
	var applied3 := HeatRules.apply_overheat_backlash(tiny_mech, TestFixtures.rng(7))
	t.assert_eq(applied3, 2, "backlash stops once its only target is destroyed, wasting the 3rd nominal point")
	t.assert_true(tiny.destroyed, "the only component is destroyed")

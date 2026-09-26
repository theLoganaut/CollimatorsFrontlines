class_name TestCardResolver
extends RefCounted
## Covers the per-hit damage pipeline order, each status's slice
## clarification, wasted hits, self cards, and status targets.

static func run_all(t: TestContext) -> void:
	t.group("CardResolver: roll_damage bounds")
	var fixed_card := TestFixtures.make_card("fixed", "src", 0, 1, 5, 5)
	t.assert_eq(CardResolver.roll_damage(fixed_card, TestFixtures.rng(1)), 5, "a min==max card always rolls that value")
	var ranged_card := TestFixtures.make_card("ranged", "src", 0, 1, 1, 100)
	for seed_value in range(1, 21):
		var roll := CardResolver.roll_damage(ranged_card, TestFixtures.rng(seed_value))
		t.assert_true(roll >= 1 and roll <= 100, "roll #%d within [1,100]" % seed_value)

	t.group("CardResolver: Shock (2/3 damage, flat while any stacks remain)")
	var shocked := TestFixtures.make_component("shocked", 100)
	t.assert_eq(CardResolver.apply_shock(9, shocked), 9, "no Shock -> unchanged")
	shocked.add_status("shock", 1)
	t.assert_eq(CardResolver.apply_shock(9, shocked), 6, "Shock: 9 -> floor(9*2/3) = 6")
	t.assert_eq(CardResolver.apply_shock(10, shocked), 6, "Shock: 10 -> floor(10*2/3) = 6")
	shocked.add_status("shock", 1) # 2 stacks now
	t.assert_eq(CardResolver.apply_shock(9, shocked), 6, "2 stacks of Shock is still just 2/3 (duration, not magnitude)")

	t.group("CardResolver: Absorb (heals the hit component, consumes all stacks)")
	var absorb_defender := TestFixtures.make_mech("d1", 14, [])
	var absorb_target := TestFixtures.make_component("t1", 50)
	absorb_target.current_hp = 40 # 10 HP of room to heal into
	absorb_defender.add_mech_status("absorb", 5)
	var after_absorb := CardResolver.apply_absorb(8, absorb_defender, absorb_target)
	t.assert_eq(after_absorb, 3, "8 damage - 5 absorbed = 3 through")
	t.assert_eq(absorb_target.current_hp, 45, "component healed by the 5 prevented")
	t.assert_eq(absorb_defender.mech_status_stacks("absorb"), 0, "all Absorb stacks consumed when triggered")

	var absorb_defender2 := TestFixtures.make_mech("d2", 14, [])
	var absorb_target2 := TestFixtures.make_component("t2", 50)
	absorb_target2.current_hp = 48 # only 2 HP of room
	absorb_defender2.add_mech_status("absorb", 10)
	var after_absorb2 := CardResolver.apply_absorb(4, absorb_defender2, absorb_target2)
	t.assert_eq(after_absorb2, 0, "4 damage fully absorbed by 10 stacks")
	t.assert_eq(absorb_target2.current_hp, 50, "heal capped at the component's own max HP")
	t.assert_eq(absorb_defender2.mech_status_stacks("absorb"), 0, "still loses ALL 10 stacks even though only 4 were needed")

	t.group("CardResolver: Deflect (per-hit, ceil(stacks/2) consumed — audit's anti-stuck fix)")
	var deflect_defender := TestFixtures.make_mech("d3", 14, [])
	deflect_defender.add_mech_status("deflect", 3)
	var after_deflect1 := CardResolver.apply_deflect(10, deflect_defender)
	t.assert_eq(after_deflect1, 7, "10 damage - 3 deflected = 7")
	t.assert_eq(deflect_defender.mech_status_stacks("deflect"), 1, "ceil(3/2) = 2 consumed, 1 left")
	var after_deflect2 := CardResolver.apply_deflect(5, deflect_defender)
	t.assert_eq(after_deflect2, 4, "5 damage - 1 deflected = 4")
	t.assert_eq(deflect_defender.mech_status_stacks("deflect"), 0, "a single stack is fully used up on the hit it reduces (not stuck forever)")

	t.group("CardResolver: full per-hit pipeline order (Shock -> Absorb -> Deflect)")
	var attacker := TestFixtures.make_component("atk", 100)
	attacker.add_status("shock", 1)
	var defender_mech := TestFixtures.make_mech("def", 14, [])
	defender_mech.add_mech_status("absorb", 2)
	defender_mech.add_mech_status("deflect", 3)
	var defender_component := TestFixtures.make_component("def_c", 100)
	defender_component.current_hp = 90
	var big_card := TestFixtures.make_card("big", "atk", 0, 1, 12, 12)
	var hit_result := CardResolver.resolve_hit(big_card, attacker, defender_mech, defender_component, TestFixtures.rng(1))
	# 12 -> Shock floor(12*2/3)=8 -> Absorb (2 stacks) -> 6, heal +2 -> Deflect (3 stacks) -> prevented 3 -> 3 applied
	t.assert_eq(hit_result["damage_dealt"], 3, "12 base damage nets to 3 after Shock->Absorb->Deflect in that order")
	t.assert_eq(defender_component.current_hp, 89, "90 HP + 2 healed by Absorb - 3 applied = 89")
	t.assert_eq(defender_mech.mech_status_stacks("absorb"), 0, "Absorb consumed")
	t.assert_eq(defender_mech.mech_status_stacks("deflect"), 1, "Deflect: ceil(3/2)=2 consumed, 1 left")

	t.group("CardResolver: wasted hits after target destroyed, no spill-over")
	var frail := TestFixtures.make_component("frail", 5)
	var multi_hit_card := TestFixtures.make_card("triple", "atk2", 0, 3, 10, 10)
	var atk2 := TestFixtures.make_component("atk2", 100)
	var multi_defender_mech := TestFixtures.make_mech("md", 14, [])
	var res := CardResolver.resolve_attack_card(multi_hit_card, TestFixtures.make_mech("am", 14, [atk2]), atk2, multi_defender_mech, frail, TestFixtures.rng(1))
	t.assert_eq(res["total_damage"], 5, "only the first hit's damage (capped at 5 HP) counts")
	t.assert_eq(res["hits_landed"], 1, "1 of 3 hits landed, the rest were wasted")
	t.assert_true(res["target_destroyed"], "target destroyed by the first hit")
	t.assert_eq(frail.current_hp, 0, "HP floors at 0, doesn't go negative")

	t.group("CardResolver: status targets")
	var shock_status: Array[StatusEffectData] = [StatusEffectData.new("shock", 2, StatusEffectData.TARGET_ENEMY)]
	var enemy_card := TestFixtures.make_card("shocker", "p", 0, 1, 1, 1, shock_status)
	var enemy_target := TestFixtures.make_component("et", 100)
	var enemy_mech := TestFixtures.make_mech("em", 14, [enemy_target])
	var player_component := TestFixtures.make_component("pc", 100)
	var player_mech := TestFixtures.make_mech("pm", 14, [player_component])
	CardResolver.resolve_attack_card(enemy_card, player_mech, player_component, enemy_mech, enemy_target, TestFixtures.rng(1))
	t.assert_eq(enemy_target.status_stacks("shock"), 2, "TARGET_ENEMY status lands on the dropped-on component")

	var all_enemies_status: Array[StatusEffectData] = [StatusEffectData.new("shock", 1, StatusEffectData.TARGET_ALL_ENEMIES)]
	var aoe_card := TestFixtures.make_card("aoe", "p", 0, 1, 1, 1, all_enemies_status)
	var e1 := TestFixtures.make_component("e1", 10)
	var e2 := TestFixtures.make_component("e2", 10)
	var e3_destroyed := TestFixtures.make_component("e3", 10)
	e3_destroyed.destroyed = true
	var aoe_mech := TestFixtures.make_mech("aoe_m", 14, [e1, e2, e3_destroyed])
	CardResolver.resolve_attack_card(aoe_card, player_mech, player_component, aoe_mech, e1, TestFixtures.rng(1))
	t.assert_eq(e1.status_stacks("shock"), 1, "TARGET_ALL_ENEMIES hits e1")
	t.assert_eq(e2.status_stacks("shock"), 1, "TARGET_ALL_ENEMIES hits e2")
	t.assert_eq(e3_destroyed.status_stacks("shock"), 0, "TARGET_ALL_ENEMIES skips a destroyed component")

	var self_status: Array[StatusEffectData] = [StatusEffectData.new("shock", 1, StatusEffectData.TARGET_SELF)]
	var self_card := TestFixtures.make_card("self_shock", "sc", 0, 1, 1, 1, self_status)
	var self_component := TestFixtures.make_component("sc", 100)
	var self_mech := TestFixtures.make_mech("sm", 14, [self_component])
	var some_target := TestFixtures.make_component("st", 10)
	var some_target_mech := TestFixtures.make_mech("stm", 14, [some_target])
	CardResolver.resolve_attack_card(self_card, self_mech, self_component, some_target_mech, some_target, TestFixtures.rng(1))
	t.assert_eq(self_component.status_stacks("shock"), 1, "TARGET_SELF lands on the component that granted the card")
	t.assert_eq(some_target.status_stacks("shock"), 0, "TARGET_SELF never touches the dropped-on target")

	var linked_status: Array[StatusEffectData] = [StatusEffectData.new("coolant", 1, StatusEffectData.TARGET_LINKED)]
	var linked_card := TestFixtures.make_card("linked", "lc", 0, 1, 1, 1, linked_status)
	var linked_component := TestFixtures.make_component("lc", 100)
	var linked_mech := TestFixtures.make_mech("lm", 14, [linked_component])
	CardResolver.resolve_attack_card(linked_card, linked_mech, linked_component, some_target_mech, some_target, TestFixtures.rng(1))
	t.assert_eq(linked_component.status_stacks("coolant"), 0, "TARGET_LINKED is a no-op (link system not built this slice)")

	t.group("CardResolver: self cards (Extension / Spike Setup)")
	var deflect_self: Array[StatusEffectData] = [StatusEffectData.new("deflect", 1, StatusEffectData.TARGET_OWN_MECH)]
	var extension_card := TestFixtures.make_card("extension", "na", 3, 0, 0, 0, deflect_self)
	var na_component := TestFixtures.make_component("na", 64)
	var bastion_stub := TestFixtures.make_mech("bastion_stub", 14, [na_component])
	CardResolver.resolve_self_card(extension_card, bastion_stub, na_component)
	t.assert_eq(bastion_stub.mech_status_stacks("deflect"), 1, "Extension grants the mech 1 Deflect")
	t.assert_eq(na_component.statuses.size(), 0, "Extension itself gains no component-scoped status")

	t.group("CardResolver: end-of-turn Shock decay")
	var decaying := TestFixtures.make_component("decaying", 100)
	decaying.add_status("shock", 2)
	var single_stack := TestFixtures.make_component("single", 100)
	single_stack.add_status("shock", 1)
	var clean := TestFixtures.make_component("clean", 100)
	var dead := TestFixtures.make_component("dead", 100)
	dead.destroyed = true
	var decay_mech := TestFixtures.make_mech("decay_m", 14, [decaying, single_stack, clean, dead])
	CardResolver.decay_end_of_turn_statuses(decay_mech)
	t.assert_eq(decaying.status_stacks("shock"), 1, "2 stacks of Shock -> 1 after one turn's decay")
	t.assert_eq(single_stack.status_stacks("shock"), 0, "1 stack decays to 0 and is removed")
	t.assert_true(single_stack.get_status("shock") == null, "the removed status entry is actually gone, not just at 0")
	t.assert_eq(clean.statuses.size(), 0, "a component with no Shock is untouched")

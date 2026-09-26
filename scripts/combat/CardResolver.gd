class_name CardResolver
extends RefCounted
## Applies a played card. Combat Rules' per-hit damage pipeline (confirmed
## order): roll -> attacker's Shock -> (target's Acid, once implemented) ->
## defender mech's Absorb -> defender mech's Deflect -> subtract from
## component HP (floor 0) -> Destroyed at 0. Win/lose is CombatManager's job.

static func roll_damage(card: CardData, rng: RandomNumberGenerator) -> int:
	if card.hits <= 0 or card.damage_max <= 0:
		return 0
	return rng.randi_range(card.damage_min, card.damage_max)

## Shock: while a component holds any Shock, its outgoing hits deal 2/3
## damage (floored). Stacks are duration (turns remaining), not magnitude —
## the reduction doesn't scale with stack count.
static func apply_shock(damage: int, attacker_component: ComponentData) -> int:
	if attacker_component.status_stacks("shock") <= 0:
		return damage
	return (damage * 2) / 3

## Acid isn't implemented this slice (nothing applies it yet) — kept as an
## explicit no-op so the pipeline's shape already has the slot Acid will
## fill later (Combat Rules damage pipeline).
static func apply_acid_incoming(damage: int, _target_component: ComponentData) -> int:
	return damage

## Absorb (mech-scoped): reduces the incoming hit by its stacks, heals the
## hit component by the amount actually prevented (capped at that
## component's own max HP; can't revive a destroyed one), and is fully
## consumed the instant it's triggered by a hit.
static func apply_absorb(damage: int, defender_mech: MechData, target_component: ComponentData) -> int:
	var stacks := defender_mech.mech_status_stacks("absorb")
	if stacks <= 0 or damage <= 0:
		return damage
	var prevented: int = mini(damage, stacks)
	defender_mech.remove_mech_status("absorb", stacks)
	target_component.heal(prevented)
	return damage - prevented

## Deflect (mech-scoped): reduces each incoming hit by its stacks (a flat
## amount, not a percentage). Each hit it actually reduces removes
## ceil(stacks/2) — so a single stack is used up on its first hit instead
## of lasting forever.
static func apply_deflect(damage: int, defender_mech: MechData) -> int:
	var stacks := defender_mech.mech_status_stacks("deflect")
	if stacks <= 0 or damage <= 0:
		return damage
	var prevented: int = mini(damage, stacks)
	var consumed: int = (stacks + 1) / 2  # ceil(stacks/2) via integer math
	defender_mech.remove_mech_status("deflect", consumed)
	return damage - prevented

## One hit of an attack card against one component. If the target is
## already destroyed (an earlier hit from the same card killed it), the hit
## is wasted with no spill-over (Combat Slice §4.4).
static func resolve_hit(card: CardData, attacker_component: ComponentData, defender_mech: MechData, target_component: ComponentData, rng: RandomNumberGenerator) -> Dictionary:
	if target_component.destroyed:
		return {"damage_dealt": 0, "wasted": true}
	var dmg := roll_damage(card, rng)
	dmg = apply_shock(dmg, attacker_component)
	dmg = apply_acid_incoming(dmg, target_component)
	dmg = apply_absorb(dmg, defender_mech, target_component)
	dmg = apply_deflect(dmg, defender_mech)
	var applied := target_component.apply_damage(dmg)
	return {"damage_dealt": applied, "wasted": false}

## Applies one of a card's declared statuses to whatever it targets.
## `playing_mech`/`playing_component` are whoever played the card;
## `enemy_mech`/`enemy_target_component` are the drop target (null for a
## self card, which only ever uses TARGET_SELF / TARGET_OWN_MECH).
static func apply_card_status(status_def: StatusEffectData, playing_mech: MechData, playing_component: ComponentData, enemy_mech: MechData, enemy_target_component: ComponentData) -> void:
	if status_def.stacks <= 0:
		return
	match status_def.target:
		StatusEffectData.TARGET_ENEMY:
			if enemy_target_component != null and not enemy_target_component.destroyed:
				enemy_target_component.add_status(status_def.status, status_def.stacks)
		StatusEffectData.TARGET_ALL_ENEMIES:
			if enemy_mech != null:
				for c in enemy_mech.non_destroyed_components():
					c.add_status(status_def.status, status_def.stacks)
		StatusEffectData.TARGET_SELF:
			playing_component.add_status(status_def.status, status_def.stacks)
		StatusEffectData.TARGET_OWN_MECH:
			playing_mech.add_mech_status(status_def.status, status_def.stacks)
		StatusEffectData.TARGET_LINKED:
			pass # link system not implemented this slice (Statuses & Links)

## Resolves an attack card: every hit against one component, then the
## card's own statuses. Precise targeting only — no spread (Combat Slice §2).
static func resolve_attack_card(card: CardData, attacker_mech: MechData, attacker_component: ComponentData, defender_mech: MechData, target_component: ComponentData, rng: RandomNumberGenerator) -> Dictionary:
	var total_damage := 0
	var hits_landed := 0
	for i in range(card.hits):
		var result := resolve_hit(card, attacker_component, defender_mech, target_component, rng)
		total_damage += int(result["damage_dealt"])
		if not result["wasted"]:
			hits_landed += 1
	for status_def in card.statuses:
		apply_card_status(status_def, attacker_mech, attacker_component, defender_mech, target_component)
	return {
		"total_damage": total_damage,
		"hits_landed": hits_landed,
		"target_destroyed": target_component.destroyed,
	}

## Resolves a self card (0 hits): just its statuses, onto the playing side.
static func resolve_self_card(card: CardData, owner_mech: MechData, owner_component: ComponentData) -> void:
	for status_def in card.statuses:
		apply_card_status(status_def, owner_mech, owner_component, null, null)

## End-of-turn status decay for the side whose turn just ended (Combat
## Rules: "loses 1 stack at the very end of the turn"). Only Shock is
## implemented this slice; Burn/Acid/Freeze would join this same list once built.
static func decay_end_of_turn_statuses(mech: MechData) -> void:
	for c in mech.non_destroyed_components():
		if c.status_stacks("shock") > 0:
			c.remove_status("shock", 1)

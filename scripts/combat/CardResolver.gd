class_name CardResolver
extends RefCounted
## Applies a played card. Combat Rules' per-hit damage pipeline (confirmed
## order): roll -> card and protocol multipliers -> attacker's Shock ->
## target's Acid -> defender mech's Absorb -> defender mech's Deflect ->
## subtract from component HP (floor 0, Redundant Wiring may save it) ->
## Destroyed at 0. Win/lose is CombatManager's job.
##
## `mods` (from primed protocols and passives, see CombatManager):
## {"mult": float, "split": bool, "bonus_first": int, "catalyze": int,
##  "reroute": status name, "flat": +damage per hit, "pierce": ignore cover,
##  Absorb and Deflect, "max_roll": every hit rolls its maximum,
##  "execute": {fraction, mult} against a part at or below that share of
##  its HP}. Missing keys = no change.

## Statuses that lose 1 stack at the end of their owning side's turn
## (Statuses & Links global rule; Coolant/Jam decay on use, Offline at the
## fight's end, Absorb/Deflect have their own rules).
const DECAYS_END_OF_TURN := ["shock", "acid", "burn", "disabled", "freeze"]
const MECH_DECAYS_END_OF_TURN := ["smoke"]
const MECH_STATUSES := ["absorb", "deflect", "smoke"]

static func roll_damage(card: CardData, rng: RandomNumberGenerator, max_roll: bool = false) -> int:
	if card.hits <= 0 or card.damage_max <= 0:
		return 0
	if max_roll:
		return card.damage_max
	return rng.randi_range(card.damage_min, card.damage_max)

## Shock: while a component holds any Shock, its outgoing hits deal 2/3
## damage (floored). Stacks are duration (turns remaining), not magnitude —
## the reduction doesn't scale with stack count.
static func apply_shock(damage: int, attacker_component: ComponentData) -> int:
	if attacker_component.status_stacks("shock") <= 0:
		return damage
	return (damage * 2) / 3

## Acid: a component holding any Acid takes 1/3 more damage (floored).
static func apply_acid_incoming(damage: int, target_component: ComponentData) -> int:
	if target_component.status_stacks("acid") <= 0 or damage <= 0:
		return damage
	return damage + damage / 3

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

## Damage straight into one part, with Redundant Wiring's one save: the
## first time a part (other than the Wiring) would be destroyed it's left
## at 1 HP instead, and the Wiring is destroyed. Returns
## {"applied", "saved_by" (the Wiring, or null)}.
static func deal_damage(mech: MechData, comp: ComponentData, amount: int) -> Dictionary:
	if comp.destroyed or amount <= 0:
		return {"applied": 0, "saved_by": null}
	if amount >= comp.current_hp and mech != null:
		for w in mech.living_passives(ComponentData.PASSIVE_SAVE):
			if w != comp:
				var applied := comp.apply_damage(comp.current_hp - 1)
				w.apply_damage(w.current_hp)
				return {"applied": applied, "saved_by": w}
		# Reinforced Bulkhead: the same save, `charges` times a fight (1 by
		# default), and it stays.
		for b in mech.living_passives("save_once_per_fight"):
			if int(b.get_meta("save_used", 0)) < int(b.passive.get("charges", 1)):
				b.set_meta("save_used", int(b.get_meta("save_used", 0)) + 1)
				return {"applied": comp.apply_damage(comp.current_hp - 1), "saved_by": b}
	return {"applied": comp.apply_damage(amount), "saved_by": null}

## The card's own damage multiplier against this target (EMP Round,
## Thrust Through), from its rule.
static func card_multiplier(card: CardData, target: ComponentData) -> float:
	var m := 1.0
	var s: Dictionary = card.rule.get("mult_if_target_status", {})
	if not s.is_empty() and target.status_stacks(s["status"]) > 0:
		if not s.get("hardpoint_only", false) or target.category == ComponentData.CATEGORY_HARDPOINT:
			m *= float(s["mult"])
	var b: Dictionary = card.rule.get("mult_if_target_below", {})
	if not b.is_empty() and target.current_hp <= target.max_hp * float(b["fraction"]):
		if not b.get("hardpoint_only", false) or target.category == ComponentData.CATEGORY_HARDPOINT:
			m *= float(b["mult"])
	return m

## One hit of an attack card against one component. If the target is
## already destroyed (an earlier hit from the same card killed it), the hit
## is wasted with no spill-over (Combat Slice §4.4). A cover part (Plated
## Housing facing it, or a Redirect Spike) takes the hit instead
## (`hit_component` says which part actually took it).
static func resolve_hit(card: CardData, attacker_component: ComponentData, defender_mech: MechData, target_component: ComponentData, rng: RandomNumberGenerator, mods: Dictionary = {}) -> Dictionary:
	if target_component.destroyed:
		return {"damage_dealt": 0, "wasted": true, "hit_component": target_component}
	var pierce: bool = mods.get("pierce", false) or card.rule.get("pierce", false)
	var hit_component := target_component
	var cover := defender_mech.cover_for(target_component) if not pierce else null
	if cover != null:
		hit_component = cover
	var dmg := roll_damage(card, rng, mods.get("max_roll", false))
	if mods.get("split", false):
		dmg /= 2
	var mult: float = float(mods.get("mult", 1.0)) * card_multiplier(card, target_component)
	var ex: Dictionary = mods.get("execute", {})
	if not ex.is_empty() and target_component.current_hp <= target_component.max_hp * float(ex.get("fraction", 0.34)):
		mult *= float(ex.get("mult", 3))
	if mult != 1.0:
		dmg = int(floor(dmg * mult))
	dmg += int(mods.get("bonus_first", 0)) + int(mods.get("flat", 0))
	dmg = apply_shock(dmg, attacker_component)
	dmg = apply_acid_incoming(dmg, hit_component)
	var before_defenses := dmg
	var hp_before := hit_component.current_hp
	if not pierce:
		dmg = apply_absorb(dmg, defender_mech, hit_component)
	var healed := hit_component.current_hp - hp_before
	if not pierce:
		dmg = apply_deflect(dmg, defender_mech)
	dmg = mini(dmg, damage_cap(defender_mech, hit_component))
	var dealt := deal_damage(defender_mech, hit_component, dmg)
	return {"damage_dealt": dealt["applied"], "wasted": false, "hit_component": hit_component,
		"blocked": before_defenses - dmg, "healed": healed, "saved_by": dealt["saved_by"]}

## The most one hit can deal to `comp` (Bulwark Frame on the parts it
## points at), or a huge number when nothing caps it.
static func damage_cap(mech: MechData, comp: ComponentData) -> int:
	var cap := 1 << 30
	for b in mech.living_passives("damage_cap_linked"):
		if b != comp and Links.linked(mech, b).has(comp):
			cap = mini(cap, int(b.passive.get("cap", cap)))
	return cap

## Adds `stacks` of a status to one part (or its mech, for mech-scoped
## statuses), after the defender's reducers (Insulated Core, Exhaust Fans).
## Returns the reducing part, or null.
static func add_status_to(mech: MechData, comp: ComponentData, status: String, stacks: int, incoming: bool) -> ComponentData:
	var reducer: ComponentData = null
	if incoming and mech != null:
		reducer = mech.incoming_status_reducer(status)
		if reducer != null:
			stacks = maxi(0, stacks - int(reducer.passive.get("amount", 0)))
	if stacks <= 0:
		return reducer
	if MECH_STATUSES.has(status):
		if mech != null:
			mech.add_mech_status(status, stacks)
	elif comp != null and not comp.destroyed:
		comp.add_status(status, stacks)
	return reducer

## Applies one of a card's declared statuses to whatever it targets.
## `playing_mech`/`playing_component` are whoever played the card;
## `enemy_mech`/`enemy_target_component` are the drop target (null for a
## self card, which only ever uses TARGET_SELF / TARGET_OWN_MECH).
## Returns the defender's component whose passive reduced the stacks
## (Insulated Core), or null.
static func apply_card_status(status_def: StatusEffectData, playing_mech: MechData, playing_component: ComponentData, enemy_mech: MechData, enemy_target_component: ComponentData) -> ComponentData:
	if status_def.stacks <= 0:
		return null
	match status_def.target:
		StatusEffectData.TARGET_ENEMY:
			if enemy_target_component == null or enemy_target_component.destroyed:
				return null
			return add_status_to(enemy_mech, enemy_target_component, status_def.status, status_def.stacks, true)
		StatusEffectData.TARGET_ALL_ENEMIES:
			if enemy_mech == null:
				return null
			var reducer: ComponentData = null
			for c in enemy_mech.non_destroyed_components():
				var r := add_status_to(enemy_mech, c, status_def.status, status_def.stacks, true)
				if r != null:
					reducer = r
			return reducer
		StatusEffectData.TARGET_SELF:
			add_status_to(playing_mech, playing_component, status_def.status, status_def.stacks, false)
		StatusEffectData.TARGET_OWN_MECH:
			if MECH_STATUSES.has(status_def.status):
				playing_mech.add_mech_status(status_def.status, status_def.stacks)
			else:
				add_status_to(playing_mech, playing_component, status_def.status, status_def.stacks, false)
		StatusEffectData.TARGET_LINKED:
			for c in Links.linked(playing_mech, playing_component):
				add_status_to(playing_mech, c, status_def.status, status_def.stacks, false)
	return null

## A card's statuses as they'll actually apply: Catalyze adds stacks,
## Reroute swaps an enemy-targeted status for another.
static func statuses_with_mods(card: CardData, mods: Dictionary) -> Array[StatusEffectData]:
	var out: Array[StatusEffectData] = []
	for s in card.statuses:
		var c := s.clone()
		c.stacks += int(mods.get("catalyze", 0))
		var swap: String = mods.get("reroute", "")
		if swap != "" and c.target in [StatusEffectData.TARGET_ENEMY, StatusEffectData.TARGET_ALL_ENEMIES]:
			c.status = swap
		out.append(c)
	return out

## Turn-start passives: Capacitor Bank's status, Nano Bots' heal, Coolant
## Flush's Coolant on the part it faces. Called at the start of the owning
## mech's turn, after that turn's Absorb clear. Returns the components that
## triggered.
## `first_turn`: the mech's first turn of the fight. Parts that point a
## status at another part (Coolant Flush) give it only then, at the start
## of combat, not every turn (Logan, 2026-09-30).
static func apply_turn_start_passives(mech: MechData, first_turn: bool = true) -> Array[ComponentData]:
	var triggered: Array[ComponentData] = []
	for c in mech.non_destroyed_components():
		match c.passive_type():
			ComponentData.PASSIVE_TURN_START_STATUS:
				var s := StatusEffectData.new(c.passive.get("status", ""), int(c.passive.get("stacks", 0)), c.passive.get("target", StatusEffectData.TARGET_OWN_MECH))
				apply_card_status(s, mech, c, null, null)
				triggered.append(c)
			ComponentData.PASSIVE_TURN_START_HEAL:
				var lowest: ComponentData = null
				for other in mech.non_destroyed_components():
					if other.current_hp < other.max_hp and (lowest == null or other.current_hp < lowest.current_hp):
						lowest = other
				if lowest != null and lowest.heal(int(c.passive.get("amount", 0))) > 0:
					triggered.append(c)
			"turn_start_heal_linked":
				var healed_any := false
				for other in Links.linked(mech, c):
					if other.heal(int(c.passive.get("amount", 0))) > 0:
						healed_any = true
				if healed_any:
					triggered.append(c)
			ComponentData.PASSIVE_FACING_STATUS:
				if not first_turn:
					continue
				var faced := Links.facing(mech, c)
				for f in faced:
					add_status_to(mech, f, c.passive.get("status", ""), int(c.passive.get("stacks", 0)), false)
				if not faced.is_empty():
					triggered.append(c)
	return triggered

## Burn at the start of its owner's turn: +1 heat per stack on any of the
## mech's living parts. Returns the heat added.
static func apply_burn(mech: MechData) -> int:
	var heat := 0
	for c in mech.non_destroyed_components():
		heat += c.status_stacks("burn")
	mech.current_heat += heat
	return heat

## Resolves a self card (0 hits): just its statuses, onto the playing side.
static func resolve_self_card(card: CardData, owner_mech: MechData, owner_component: ComponentData, mods: Dictionary = {}) -> void:
	for status_def in statuses_with_mods(card, mods):
		apply_card_status(status_def, owner_mech, owner_component, null, null)

## End-of-turn status decay for the side whose turn just ended (Combat
## Rules: "loses 1 stack at the very end of the turn").
static func decay_end_of_turn_statuses(mech: MechData) -> void:
	for c in mech.non_destroyed_components():
		for s in DECAYS_END_OF_TURN:
			if c.status_stacks(s) > 0:
				c.remove_status(s, 1)
	for s in MECH_DECAYS_END_OF_TURN:
		if mech.mech_status_stacks(s) > 0:
			mech.remove_mech_status(s, 1)

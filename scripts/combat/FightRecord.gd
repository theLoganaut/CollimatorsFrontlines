class_name FightRecord
extends RefCounted
## A fight, recorded so it can be watched again (Pilot Log) or sent in with
## a playtest report. CombatManager is deterministic for a seed, so a record
## holds only what the fight started from and what the player did:
## - every mech as it stood before the first turn (parts, HP, placement,
##   heat, statuses, frame, max heat),
## - the seed,
## - "opening": every status and heat value once the fight-start effects
##   (events, Alert, Recon intel, conditions) are on, since those go on
##   after start_combat,
## - the player's commands (CombatManager.command_log).
## replay() runs it headless; CombatScene's replay mode plays it on screen.
## Plain dictionaries throughout, so it saves as JSON.

const VERSION := 2 # 2: the card pass and Phase 6 enemy AI (2026-10-13); v1 fights replay differently

## A new record for a fight about to start: call before start_combat().
static func begin(player: MechData, enemies: Array[MechData], seed_value: int, labels: Array = [], background: Dictionary = {}) -> Dictionary:
	var foes := []
	for m in enemies:
		foes.append(mech_to_dict(m))
	return {
		"v": VERSION, "seed": seed_value, "date": Time.get_datetime_string_from_system(false, true),
		"player": mech_to_dict(player), "enemies": foes, "labels": labels.duplicate(),
		"background": background.duplicate(true), "opening": {}, "commands": [],
		"result": "", "turns": 0, "stats": {},
	}

## Once the fight-start effects are on: the statuses and heat they left.
static func set_opening(rec: Dictionary, player: MechData, enemies: Array[MechData]) -> void:
	var mechs := []
	for m in [player] + enemies:
		mechs.append(status_state(m))
	rec["opening"] = {"mechs": mechs}

## The fight is over (or left): its commands, result and counters.
static func finish(rec: Dictionary, combat: CombatManager, result: String) -> void:
	rec["commands"] = combat.command_log.duplicate(true)
	rec["result"] = result
	rec["turns"] = combat.turn_number
	rec["stats"] = combat.stats.to_dict()

## "win" / "loss" for a finished fight.
static func result_name(r: CombatManager.Result) -> String:
	match r:
		CombatManager.Result.WIN: return "win"
		CombatManager.Result.LOSE: return "loss"
	return ""

# ---------- mechs ----------

static func mech_to_dict(m: MechData) -> Dictionary:
	var parts := RunSave.parts_to_list(m.components)
	for i in range(parts.size()):
		parts[i]["statuses"] = _statuses_to_list(m.components[i].statuses)
	return {
		"id": m.id, "name": m.name, "cells": m.cells.map(func(c): return [c.x, c.y]),
		"max_heat": m.max_heat, "vent_at_max": m.vent_at_max, "heat": m.current_heat,
		"phase2": m.phase2_reached, "statuses": _statuses_to_list(m.mech_statuses), "parts": parts,
	}

## The mech a record names, as it stood: its file's AI, lines and rules,
## with the recorded parts, frame, heat and statuses. null if its file is gone.
static func mech_from_dict(d: Dictionary) -> MechData:
	var path := "res://data/mechs/%s.json" % str(d.get("id", ""))
	if not FileAccess.file_exists(path):
		return null
	var m := DataLoader.load_mech_from_file(path)
	if m == null:
		return null
	m.components = RunSave.parts_from_list(d.get("parts", []))
	var list: Array = d.get("parts", [])
	for c in m.components:
		for p in list:
			if p["id"] == c.id:
				c.statuses = _statuses_from_list(p.get("statuses", []))
	m.cells.clear()
	for c in d.get("cells", []):
		m.cells.append(Vector2i(int(c[0]), int(c[1])))
	m.max_heat = int(d.get("max_heat", m.max_heat))
	m.vent_at_max = float(d.get("vent_at_max", -1.0))
	m.current_heat = int(d.get("heat", 0))
	m.phase2_reached = bool(d.get("phase2", false))
	m.mech_statuses = _statuses_from_list(d.get("statuses", []))
	return m

## The record's mechs: {"player", "enemies"}, or {} if one can't be built
## (a mech file removed since).
static func mechs(rec: Dictionary) -> Dictionary:
	var player := mech_from_dict(rec.get("player", {}))
	var enemies: Array[MechData] = []
	for d in rec.get("enemies", []):
		var e := mech_from_dict(d)
		if e == null:
			return {}
		enemies.append(e)
	if player == null or enemies.is_empty():
		return {}
	return {"player": player, "enemies": enemies}

static func status_state(m: MechData) -> Dictionary:
	var parts := {}
	for c in m.components:
		if not c.statuses.is_empty():
			parts[c.id] = _statuses_to_list(c.statuses)
	return {"heat": m.current_heat, "statuses": _statuses_to_list(m.mech_statuses), "parts": parts}

static func apply_status_state(m: MechData, s: Dictionary) -> void:
	m.current_heat = int(s.get("heat", m.current_heat))
	m.mech_statuses = _statuses_from_list(s.get("statuses", []))
	var parts: Dictionary = s.get("parts", {})
	for c in m.components:
		c.statuses = _statuses_from_list(parts.get(c.id, []))

## Puts the recorded opening (fight-start effects) on, after start_combat.
static func apply_opening(rec: Dictionary, player: MechData, enemies: Array[MechData]) -> void:
	var list: Array = rec.get("opening", {}).get("mechs", [])
	var all: Array = [player] + enemies
	if list.size() != all.size():
		return
	for i in range(all.size()):
		apply_status_state(all[i], list[i])

static func _statuses_to_list(list: Array[StatusInstance]) -> Array:
	return list.map(func(s): return [s.status, s.stacks])

static func _statuses_from_list(list: Array) -> Array[StatusInstance]:
	var out: Array[StatusInstance] = []
	for s in list:
		out.append(StatusInstance.new(str(s[0]), int(s[1])))
	return out

# ---------- replaying ----------

## Plays a record headless from its start. Returns {"ok", "combat",
## "result", "turns", "matches"}: matches = it ended as recorded (same
## result, turns and damage). ok = false if its mechs can't be rebuilt.
static func replay(rec: Dictionary) -> Dictionary:
	var ms := mechs(rec)
	if ms.is_empty():
		return {"ok": false}
	var cm := CombatManager.new(ms["player"], ms["enemies"], int(rec["seed"]))
	cm.start_combat()
	apply_opening(rec, ms["player"], ms["enemies"])
	var refused := 0
	for cmd in rec.get("commands", []):
		if not cm.apply(cmd).get("ok", false):
			refused += 1
	var res := result_name(cm.result)
	var want: String = rec.get("result", "")
	var same := refused == 0 and cm.turn_number == int(rec.get("turns", 0)) \
		and cm.stats.get_stat("damage_dealt") == int(rec.get("stats", {}).get("damage_dealt", 0)) \
		and (res == want or (want == "ejected" and res == ""))
	return {"ok": true, "combat": cm, "result": res, "turns": cm.turn_number, "matches": same, "refused": refused}

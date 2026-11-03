extends SceneTree
## The best turn a starter kit can play (Logan, 2026-10-24: every starting kit should
## be worth about 50 damage on its optimal turn, found only after real thought).
## Brute force over the real rules (CombatManager): every order of the kit's cards
## (each once, an attack aimed at the part that is attacking or at one that isn't),
## on turn 1 from cold, then the best turn 2 after each of the top turn-1 lines, so
## self-Disables and Standby/Batch debts count. Balance scaling is on (live numbers).
##   Godot --headless --path . --script res://tools/kit_optimum.gd -- [--mech=bastion,redline,jackal] [--seeds=12] [--top=6]
const DUMMY_HP := 100000

var mechs: PackedStringArray = ["bastion", "redline", "jackal"]
var seeds := 12
var top := 6
var nodes := 0
var attack_keys := []

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mech="):
			mechs = a.get_slice("=", 1).split(",")
		elif a.begins_with("--seeds="):
			seeds = int(a.get_slice("=", 1))
		elif a.begins_with("--top="):
			top = int(a.get_slice("=", 1))
	for m in mechs:
		_kit(m)
	quit()

func _fight(mech_id: String, seed_value: int) -> CombatManager:
	var player := DataLoader.load_mech_from_file("res://data/mechs/%s.json" % mech_id)
	var foe := DataLoader.load_mech({"id": "dummy", "name": "Dummy", "cells": [[0, 0], [1, 0], [2, 0]], "max_heat": 99, "components": [
		{"id": "autocannon", "offset": [0, 0], "rotation": 0}]})
	for c in foe.components:
		c.max_hp = DUMMY_HP
		c.current_hp = DUMMY_HP
	var foes: Array[MechData] = [foe]
	var cm := CombatManager.new(player, foes, seed_value)
	cm.start_combat()
	return cm

func _hp(cm: CombatManager) -> int:
	var n := 0
	for c in cm.enemies[0].components:
		n += c.current_hp
	return n

## Every card key of the player's mech, and which are attacks.
func _keys(cm: CombatManager) -> Array:
	var keys := []
	for comp in cm.player_mech.components:
		for c in comp.cards:
			keys.append(cm.card_key(c))
	return keys

## Plays the line (strings "key" or "key>part") from a fresh fight; returns damage dealt.
func _play(mech_id: String, line: Array, seed_value: int) -> Dictionary:
	var cm := _fight(mech_id, seed_value)
	var before := _hp(cm)
	var heats := [0]
	cm.overheated.connect(func(_m, _a): heats[0] += 1)
	var turn_marks := []
	for step in line:
		if step == "END":
			turn_marks.append(before - _hp(cm))
			if not cm.apply({"type": "end_turn"}).get("ok", false):
				return {"ok": false}
			continue
		var cmd := {"type": "play", "card": str(step).get_slice(">", 0)}
		if ">" in step:
			cmd["target"] = [1, str(step).get_slice(">", 1)]
		if not cm.apply(cmd).get("ok", false) or heats[0] > 0 or cm.turn_number != 1:
			return {"ok": false} # an overheat costs the turn (and HP), so a line that overheats isn't a clean turn
	turn_marks.append(before - _hp(cm))
	if cm.player_mech.heat_check_timing == MechData.HEAT_CHECK_END_OF_TURN:
		cm.apply({"type": "end_turn"}) # Redline checks at the end of the turn
		if heats[0] > 0:
			return {"ok": false}
	return {"ok": true, "dmg": turn_marks, "heat": cm.player_mech.current_heat}

## Depth-first over the next card to play; calls `visit` with each playable line.
func _search(mech_id: String, prefix: Array, used: Array, keys: Array, out: Array) -> void:
	var base := _play(mech_id, prefix, 1)
	if not base["ok"]:
		return
	nodes += 1
	out.append([prefix.duplicate(), base])
	for k in keys:
		if k in used:
			continue
		var is_attack: bool = k in attack_keys
		for tgt in (["autocannon"] if is_attack else [""]):
			var step: String = k + (">" + tgt if tgt != "" else "")
			var line := prefix.duplicate()
			line.append(step)
			var u := used.duplicate()
			u.append(k)
			_search(mech_id, line, u, keys, out)

func _kit(mech_id: String) -> void:
	nodes = 0
	var t0 := Time.get_ticks_msec()
	var cm0 := _fight(mech_id, 1)
	var keys := _keys(cm0)
	attack_keys = keys.filter(func(k): return cm0.find_card(k).is_attack())
	var lines := []
	_search(mech_id, [], [], keys, lines)
	# average the single-turn lines over seeds, keep the best
	var scored := []
	for l in lines:
		var tot := 0.0
		for s in range(seeds):
			tot += _play(mech_id, l[0], s + 1)["dmg"][0]
		scored.append([l[0], tot / seeds])
	scored.sort_custom(func(a, b): return a[1] > b[1])
	print("== %s  (%d lines, %d ms) ==" % [mech_id, lines.size(), Time.get_ticks_msec() - t0])
	print("turn 1, best lines:")
	for i in range(mini(top, scored.size())):
		print("  %5.1f  %s" % [scored[i][1], " ".join(scored[i][0].map(func(s): return str(s).replace("autocannon", "*")))])

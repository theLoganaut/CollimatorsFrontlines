extends SceneTree
## Card value audit: what each attack card and each protocol is worth, in
## damage per Heat, measured by the real rules (CombatManager), with
## balance.json's combat scaling on (the numbers the game shows).
##   Godot --headless --path . --script res://tools/card_value.gd -- [--runs=200] [--top=12]
## Every measurement is a fresh fight: a player mech carrying only the
## parts under test (no reactors, max heat out of reach) against a dummy
## that never acts (two big parts side by side, so Chain and random-part
## hits land somewhere). Damage is the dummy's HP lost over WINDOW turns
## after one play (so repeats, Recall and Standby count); Heat is what the
## first turn's plays cost. Averaged over --runs seeds. Statuses are listed,
## not valued (only their damage counts).
## 1. Every attack card: Heat, average damage, damage per Heat, against its
##    rarity's median ("high"/"low" past 1.35×/0.75×). Cards that hit every
##    enemy are also measured against two dummies.
## 2. Every protocol played before each of the --top cards by average
##    damage: the damage it adds, and damage per Heat with it. Execute is
##    measured on a part at 40% HP, Last Stand with your parts at half HP,
##    Fan Out against two dummies; Replay is played after the card.
## Protocols that don't add damage or save Heat show as utility. (Only one
## protocol waits at a time, so there's no stacking to measure.)

const DUMMY_HP := 100000
## Turns each measurement runs, so cards that repeat on later turns
## (Release Swarm, Latch, Spillage) and Recall / Standby count in full.
const WINDOW := 4
const HIGH := 1.35
const LOW := 0.75
## Protocols that need links on the grid or a target's telegraph, so a
## lone pair of parts can't measure them.
const SKIP := ["fire_control_relay", "coordinated_strike_suite", "signal_interceptor", "thermal_transfer_bus", "payload_converter"]

var runs := 200
var top := 12

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--runs="):
			runs = int(a.get_slice("=", 1))
		elif a.begins_with("--top="):
			top = int(a.get_slice("=", 1))
	var attacks: Array = [] # [part id, card id, CardData]
	var protocols: Array[String] = []
	for id in ComponentLibrary.all_ids():
		var c := ComponentLibrary.make(id)
		if c == null:
			continue
		if c.category == ComponentData.CATEGORY_PROTOCOL:
			if not id in SKIP:
				protocols.append(id)
			continue
		for card in c.cards:
			if card.is_attack():
				attacks.append([id, card.id, card])

	# ---------- 1. attack cards ----------
	var rows: Array = []
	for a in attacks:
		var m := _measure(a[0], a[1], [], 1)
		var aoe: bool = _hits_all(a[2])
		var m2 := _measure(a[0], a[1], [], 2) if aoe else {}
		rows.append({"part": a[0], "card": a[2], "dmg": m["dmg"], "heat": m["heat"], "dph": _dph(m), "aoe": aoe, "dmg2": m2.get("dmg", 0.0),
			"rarity": ComponentLibrary.definition(a[0]).get("rarity", ""), "wc": ComponentLibrary.weight_class_of(a[0])})
	var medians := {}
	for r in ["surplus", "salvaged", "prototype"]:
		var vals := rows.filter(func(x): return x["rarity"] == r and x["heat"] > 0).map(func(x): return x["dph"])
		vals.sort()
		medians[r] = vals[vals.size() / 2] if not vals.is_empty() else 0.0
	print("== 1. Attack cards, damage per Heat (balance.json combat scaling on; %d runs each) ==" % runs)
	print("rarity medians: " + ", ".join(medians.keys().map(func(k): return "%s %.2f" % [k, medians[k]])))
	print("%-24s %-9s %-7s %-20s %4s %5s %7s %6s  %s" % ["part", "rarity", "class", "card", "heat", "hits", "dmg", "/heat", "notes"])
	rows.sort_custom(func(x, y): return x["dph"] > y["dph"])
	for r in rows:
		var card: CardData = r["card"]
		var notes := PackedStringArray()
		var med: float = medians.get(r["rarity"], 0.0)
		if r["heat"] <= 0:
			notes.append("FREE")
		elif med > 0 and r["dph"] >= med * HIGH:
			notes.append("HIGH ×%.2f" % (r["dph"] / med))
		elif med > 0 and r["dph"] <= med * LOW:
			notes.append("low ×%.2f" % (r["dph"] / med))
		if r["aoe"]:
			notes.append("all enemies: %.1f vs 2" % r["dmg2"])
		if not card.statuses.is_empty():
			notes.append("+" + ",".join(card.statuses.map(func(s): return "%s %d%s" % [s.status, s.stacks, " (self)" if s.target == StatusEffectData.TARGET_SELF else ""])))
		if card.effect_text != "":
			notes.append(card.effect_text.left(60))
		print("%-24s %-9s %-7s %-20s %4.1f %5d %7.1f %6s  %s" % [r["part"], r["rarity"], r["wc"], card.name.left(20), r["heat"], card.hits, r["dmg"],
			"free" if r["heat"] <= 0 else "%.2f" % r["dph"], " · ".join(notes)])

	# ---------- 2. protocols on the hardest-hitting cards ----------
	var by_dmg := rows.duplicate()
	by_dmg.sort_custom(func(x, y): return x["dmg"] > y["dmg"])
	var picks := by_dmg.slice(0, top)
	print("\n== 2. Protocols on the %d hardest-hitting cards ==" % picks.size())
	print("cards: " + ", ".join(picks.map(func(x): return "%s (%.0f dmg, %.0f heat)" % [x["card"].name, x["dmg"], x["heat"]])))
	var proto_rows: Array = []
	for p in protocols:
		var gain := 0.0
		var gain_pct := 0.0
		var saved := 0.0
		var dph_with := 0.0
		var dph_without := 0.0
		var best := ""
		var best_gain := -INF
		for r in picks:
			var m := _measure(r["part"], r["card"].id, [p], 2 if p == "scatter_link" else 1)
			var base_dmg: float = r["dmg2"] if p == "scatter_link" and r["aoe"] else r["dmg"]
			var g: float = m["dmg"] - base_dmg
			gain += g
			gain_pct += g / maxf(base_dmg, 1.0)
			saved += r["heat"] - m["heat"]
			dph_with += _dph(m)
			dph_without += r["dph"]
			if g > best_gain:
				best_gain = g
				best = "%s +%.0f" % [r["card"].name, g]
		var n := float(picks.size())
		var row := {"id": p, "gain": gain / n, "pct": gain_pct / n, "saved": saved / n, "with": dph_with / n, "without": dph_without / n, "best": best,
			"text": ComponentLibrary.make(p).cards[0].effect_text}
		row["kind"] = "damage" if row["pct"] > 0.02 else ("heat" if absf(row["saved"]) > 0.3 else "utility")
		proto_rows.append(row)
	proto_rows.sort_custom(func(x, y): return x["pct"] > y["pct"] if x["pct"] != y["pct"] else x["saved"] > y["saved"])
	for kind in ["damage", "heat", "utility"]:
		var group := proto_rows.filter(func(x): return x["kind"] == kind)
		if kind == "heat":
			group.sort_custom(func(x, y): return x["saved"] > y["saved"])
		print("-- %s protocols --" % kind)
		print("%-26s %-9s %9s %7s %11s %9s %9s  %-22s %s" % ["protocol", "rarity", "+dmg avg", "+dmg %", "heat saved", "/heat w/", "/heat w/o", "best on", "card text"])
		for r in group:
			print("%-26s %-9s %+9.1f %+6.0f%% %+11.1f %9.2f %9.2f  %-22s %s" % [r["id"], ComponentLibrary.definition(r["id"]).get("rarity", ""),
				r["gain"], r["pct"] * 100.0, r["saved"], r["with"], r["without"], r["best"] if kind == "damage" else "", r["text"]])

	quit()

static func _dph(m: Dictionary) -> float:
	return m["dmg"] / m["heat"] if m["heat"] > 0 else m["dmg"]

static func _hits_all(card: CardData) -> bool:
	return card.effect_text.to_lower().contains("all enemies") or card.rule.get("all_enemies", false)

## Plays `protos` (in order) then the card, or the card then Replay, in a
## fresh fight per seed; returns the averages {"dmg", "heat"}.
func _measure(part: String, card_id: String, protos: Array, dummies: int) -> Dictionary:
	var dmg := 0.0
	var heat := 0.0
	for s in range(runs):
		var r := _one(part, card_id, protos, dummies, s + 1)
		dmg += r[0]
		heat += r[1]
	return {"dmg": dmg / runs, "heat": heat / runs}

func _one(part: String, card_id: String, protos: Array, dummies: int, seed_value: int) -> Array:
	var comps := [{"id": part, "offset": [0, 0], "rotation": 0}]
	for i in range(protos.size()):
		comps.append({"id": protos[i], "offset": [0, 6 + 4 * i], "rotation": 0})
	var cells := []
	for x in range(16):
		for y in range(16):
			cells.append([x, y])
	var player := DataLoader.load_mech({"id": "test", "name": "Test", "cells": cells, "max_heat": 99, "components": comps})
	if "last_stand_protocol" in protos:
		for c in player.components:
			c.current_hp = maxi(1, c.max_hp / 2)
	var foes: Array[MechData] = []
	for d in range(dummies):
		var w := DataLoader.load_mech({"id": "dummy_%d" % d, "name": "Dummy", "cells": [[0, 0], [1, 0]], "max_heat": 99, "components": [
			{"id": "dummy_a", "name": "Dummy A", "category": "hardpoint", "hp": DUMMY_HP, "cells": [[0, 0]], "offset": [0, 0]},
			{"id": "dummy_b", "name": "Dummy B", "category": "hardpoint", "hp": DUMMY_HP, "cells": [[0, 0]], "offset": [1, 0]}]})
		if "kill_switch" in protos:
			w.components[0].current_hp = int(DUMMY_HP * 0.4)
		foes.append(w)
	var start_hp := 0
	for w in foes:
		for c in w.components:
			start_hp += c.current_hp
	var cm := CombatManager.new(player, foes, seed_value)
	cm.start_combat()
	var target := [1, "dummy_a"]
	var key := "%s/%s" % [part, card_id]
	var replay := "echo_buffer" in protos
	for p in protos:
		if p != "echo_buffer":
			_play(cm, "%s/%s" % [p, player.get_component(p).cards[0].id], [])
	_play(cm, key, target)
	if replay:
		_play(cm, "echo_buffer/%s" % player.get_component("echo_buffer").cards[0].id, [])
	var heat := player.current_heat
	for t in range(WINDOW):
		cm.apply({"type": "end_turn"})
	var end_hp := 0
	for w in foes:
		for c in w.components:
			end_hp += c.current_hp
	return [start_hp - end_hp, heat]

static func _play(cm: CombatManager, key: String, target: Array) -> void:
	var cmd := {"type": "play", "card": key}
	if not target.is_empty():
		cmd["target"] = target
	cm.apply(cmd)

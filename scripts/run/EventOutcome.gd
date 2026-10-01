class_name EventOutcome
extends RefCounted
## What an event choice does, in words, built from its outcome data (Logan,
## 2026-09-30: the pilot should know what they're getting into, costs now
## or later included, and never be surprised by a choice they took for
## free). EventScreen shows it on the button: "Option (gain, but cost)".

## Statuses that help whoever holds them.
const GOOD := ["absorb", "deflect", "coolant"]

## The button text: the choice's label plus its summary in brackets.
static func button_text(choice: Dictionary, has_alert: bool) -> String:
	var s := summary(choice.get("outcome", {}), has_alert)
	if choice.get("outcome", {}).has("goto"):
		s = "then another choice" if s == "nothing happens" else s + ", then another choice"
	return choice.get("label", "") if s == "" else "%s  (%s)" % [choice.get("label", ""), s]

## "gain, but cost", "gain", "cost", a gamble's "60%: gain · else: cost",
## or "nothing happens".
static func summary(o: Dictionary, has_alert: bool) -> String:
	if o.has("chance"):
		var p := int(round(float(o["chance"]) * 100.0))
		return "%d%%: %s  ·  else: %s" % [p, _plain(o.get("then", {}), has_alert), _plain(o.get("else", {}), has_alert)]
	return _plain(o, has_alert)

static func _plain(o: Dictionary, has_alert: bool) -> String:
	var parts := split(o, has_alert)
	var gains: Array = parts["gains"]
	var costs: Array = parts["costs"]
	if gains.is_empty() and costs.is_empty():
		return "nothing happens"
	if costs.is_empty():
		return ", ".join(gains)
	if gains.is_empty():
		return ", ".join(costs)
	return "%s, but %s" % [", ".join(gains), ", ".join(costs)]

## {"gains": [...], "costs": [...]} in plain words.
static func split(o: Dictionary, has_alert: bool) -> Dictionary:
	var gains: Array[String] = []
	var costs: Array[String] = []
	var scraps := int(o.get("scraps", 0))
	if scraps > 0:
		gains.append("+%d scraps" % scraps)
	elif scraps < 0:
		costs.append("−%d scraps" % -scraps)
	if int(o.get("repair", 0)) > 0:
		gains.append("repair %d HP" % int(o["repair"]))
	if o.has("gain_part"):
		var g: Dictionary = o["gain_part"]
		var rar := str(g.get("rarity", ""))
		gains.append("a random %s%s" % ["" if rar == "" else rar.capitalize() + " ", str(g.get("category", "part"))])
	if int(o.get("damage_random_part", 0)) > 0:
		costs.append("a random part takes %d" % int(o["damage_random_part"]))
	for nf in o.get("next_fight", []):
		var mine: bool = str(nf.get("side", "player")) == "player"
		var st := str(nf.get("status", ""))
		var text := "%s start the next fight with %s %d" % [_who(mine, str(nf.get("parts", "all"))), st.capitalize(), int(nf.get("stacks", 1))]
		if (st in GOOD) == mine:
			gains.append(text)
		else:
			costs.append(text)
	if int(o.get("alert_turns", 0)) > 0 and has_alert:
		costs.append("Alert rises")
	return {"gains": gains, "costs": costs}

static func _who(mine: bool, parts: String) -> String:
	match parts:
		"hardpoints": return "your hardpoints" if mine else "enemy hardpoints"
		"mech": return "you" if mine else "enemies"
	return "all your parts" if mine else "every enemy part"

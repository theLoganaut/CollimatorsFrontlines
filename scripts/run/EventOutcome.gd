class_name EventOutcome
extends RefCounted
## What an event choice does, in words, built from its outcome data (Logan,
## 2026-09-30: the pilot should know what they're getting into, costs now
## or later included, and never be surprised by a choice they took for
## free). EventScreen shows it on the button: "Option (gain, but cost)".

## Statuses that help whoever holds them.
const GOOD := ["absorb", "deflect", "coolant"]

## The button text: the choice's label, and on the line under it what it
## does, one short sentence per effect (Logan, 2026-10-13: "+70 Scraps.
## Hardpoints Jam 1 next fight.").
static func button_text(choice: Dictionary, has_alert: bool) -> String:
	var s := summary(choice.get("outcome", {}), has_alert)
	if choice.get("outcome", {}).has("goto"):
		s = "Then another choice." if s == NOTHING else s + " Then another choice."
	return "%s\n%s" % [choice.get("label", ""), s]

const NOTHING := "Nothing happens."

## Gains, then costs, each its own sentence; a gamble reads
## "60%: gain. Otherwise: cost."; NOTHING when it does nothing.
static func summary(o: Dictionary, has_alert: bool) -> String:
	if o.has("chance"):
		var p := int(round(float(o["chance"]) * 100.0))
		return "%d%%: %s Otherwise: %s" % [p, _plain(o.get("then", {}), has_alert), _plain(o.get("else", {}), has_alert)]
	return _plain(o, has_alert)

static func _plain(o: Dictionary, has_alert: bool) -> String:
	var parts := split(o, has_alert)
	var all: Array = parts["gains"] + parts["costs"]
	if all.is_empty():
		return NOTHING
	return ". ".join(all) + "."

static func split(o: Dictionary, has_alert: bool) -> Dictionary:
	var gains: Array[String] = []
	var costs: Array[String] = []
	var scraps := int(o.get("scraps", 0))
	if scraps > 0:
		gains.append("+%d Scraps" % scraps)
	elif scraps < 0:
		costs.append("−%d Scraps" % -scraps)
	if int(o.get("repair", 0)) > 0:
		gains.append("Repair %d HP" % int(o["repair"]))
	if o.has("gain_part"):
		var g: Dictionary = o["gain_part"]
		var rar := str(g.get("rarity", ""))
		var cat := str(g.get("category", "part"))
		gains.append("Gain random %s%s" % ["" if rar == "" else rar.capitalize() + " ", cat if cat == "part" else cat.capitalize()])
	if int(o.get("damage_random_part", 0)) > 0:
		costs.append("Random part −%d HP" % int(o["damage_random_part"]))
	for nf in o.get("next_fight", []):
		var mine: bool = str(nf.get("side", "player")) == "player"
		var st := str(nf.get("status", ""))
		var text := ("%s %s %d next fight" % [_who(mine, str(nf.get("parts", "all"))), st.capitalize(), int(nf.get("stacks", 1))]).strip_edges()
		if (st in GOOD) == mine:
			gains.append(text)
		else:
			costs.append(text)
	if int(o.get("alert_turns", 0)) > 0 and has_alert:
		costs.append("Alert rises")
	return {"gains": gains, "costs": costs}

## Who a next-fight status lands on ("" = your mech: "Deflect 5 next fight").
static func _who(mine: bool, parts: String) -> String:
	match parts:
		"hardpoints": return "Hardpoints" if mine else "Enemy hardpoints"
		"mech": return "" if mine else "Enemies"
	return "All parts" if mine else "All enemy parts"

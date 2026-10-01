class_name RunEvents
extends RefCounted
## Event stops, for RunData (data/events.json, Claude's drafts for Logan to
## vet): which event a stop holds, and what a choice does (its outcome:
## scraps, damage, repairs, parts, next-fight statuses, Alert). Static and
## stateless: the run passed in holds the event in progress (`run.event`:
## {id, step, resolved, result}) and the events it has seen.
##
## An event can be limited to `sectors` and `missions` (ids), or need the
## Alert (`requires_alert`: Rescue); a choice can need the Alert too. An
## outcome with `goto` leads on to one of the event's `steps` ({text,
## choices}) instead of ending it: that's a multi-step event. A run doesn't
## see an event twice until it has seen every one it can.

static func events() -> Array:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(RunData.EVENTS_PATH))
	return parsed.get("events", []) if typeof(parsed) == TYPE_DICTIONARY else []

static func event_def(run: RunData) -> Dictionary:
	for e in events():
		if e["id"] == run.event.get("id", ""):
			return e
	return {}

## Whether the run's mission has an Alert level (Rescue).
static func has_alert(run: RunData) -> bool:
	return not run.mission.get("alert", {}).is_empty()

## Whether an event can come up on this run (its sector, mission, Alert).
static func eligible(run: RunData, e: Dictionary) -> bool:
	if e.has("sectors") and not (e["sectors"] as Array).has(run.location.get("id", "")):
		return false
	if e.has("missions") and not (e["missions"] as Array).has(run.mission.get("id", "")):
		return false
	return not e.get("requires_alert", false) or has_alert(run)

## Picks the event for a stop: one this run can have and hasn't seen yet
## (any it can have once it has seen them all). "" if there are none.
static func pick(run: RunData) -> String:
	var pool := events().filter(func(e): return eligible(run, e))
	var fresh := pool.filter(func(e): return not run.events_seen.has(e["id"]))
	if not fresh.is_empty():
		pool = fresh
	if pool.is_empty():
		return ""
	var id: String = pool[run.rng.randi() % pool.size()]["id"]
	run.events_seen.append(id)
	return id

## What the event shows now: its opening, or the step a choice led to
## ({title, text, choices}).
static func current(run: RunData) -> Dictionary:
	var e := event_def(run)
	var step: String = run.event.get("step", "")
	if step == "" or not e.get("steps", {}).has(step):
		return e
	var s: Dictionary = e["steps"][step]
	return {"title": s.get("title", e.get("title", "")), "text": s.get("text", ""), "choices": s.get("choices", [])}

## The choices on offer now, as [{index, choice}] (Alert-only ones left out
## when the mission has no Alert).
static func visible_choices(run: RunData) -> Array:
	var out := []
	var choices: Array = current(run).get("choices", [])
	for i in range(choices.size()):
		if not choices[i].get("requires_alert", false) or has_alert(run):
			out.append({"index": i, "choice": choices[i]})
	return out

## A choice with a scrap price (negative scraps, not a gamble's) can only
## be taken with that many scraps on hand.
static func affordable(run: RunData, choice: Dictionary) -> bool:
	return run.scraps >= -mini(0, int(choice.get("outcome", {}).get("scraps", 0)))

## Plays one of the choices on offer (by its index in the step's choices).
## Returns the result text to show. A choice that leads on (`goto`) moves
## to that step instead of ending the event; its result text stays above.
static func resolve_event(run: RunData, choice: int) -> String:
	if run.phase != RunData.PHASE_EVENT or run.event.get("resolved", true):
		return ""
	if not visible_choices(run).any(func(v): return v["index"] == choice):
		return ""
	var c: Dictionary = current(run)["choices"][choice]
	if not affordable(run, c):
		return ""
	var outcome: Dictionary = c.get("outcome", {})
	var text: String = c.get("result", "")
	if outcome.has("chance"):
		var branch: Dictionary = outcome["then"] if run.rng.randf() < float(outcome["chance"]) else outcome["else"]
		text = branch.get("result", text)
		outcome = branch
	var notes := apply_outcome(run, outcome)
	var said := text if notes == "" else "%s\n%s" % [text, notes]
	var before: String = run.event.get("result", "")
	run.event["result"] = said if before == "" else "%s\n\n%s" % [before, said]
	if outcome.has("goto") and event_def(run).get("steps", {}).has(outcome["goto"]):
		run.event["step"] = outcome["goto"]
	else:
		run.event["resolved"] = true
	return said

static func apply_outcome(run: RunData, o: Dictionary) -> String:
	var notes: Array[String] = []
	if int(o.get("scraps", 0)) > 0:
		run.add_scraps(int(o["scraps"]))
		notes.append("+%d scraps" % int(o["scraps"]))
	elif int(o.get("scraps", 0)) < 0: # a cost: takes what you have, up to the amount
		var paid := mini(run.scraps, -int(o["scraps"]))
		run.scraps -= paid
		run.stats.add("scraps_spent", paid)
		notes.append("−%d scraps" % paid)
	if int(o.get("damage_random_part", 0)) > 0:
		var parts := run.player_mech.non_destroyed_components()
		if not parts.is_empty():
			var p: ComponentData = parts[run.rng.randi() % parts.size()]
			var r := CardResolver.deal_damage(run.player_mech, p, int(o["damage_random_part"]))
			run.stats.add("damage_taken", int(r["applied"]))
			notes.append("%s took %d damage" % [p.name, int(r["applied"])])
	if int(o.get("repair", 0)) > 0:
		var left := int(o["repair"])
		var healed := 0
		while left > 0:
			var lowest: ComponentData = null
			for p in run.player_mech.non_destroyed_components():
				if p.current_hp < p.max_hp and (lowest == null or float(p.current_hp) / p.max_hp < float(lowest.current_hp) / lowest.max_hp):
					lowest = p
			if lowest == null:
				break
			var h := lowest.heal(mini(left, 5))
			left -= h
			healed += h
		run.stats.add("damage_healed", healed)
		notes.append("Repaired %d HP" % healed)
	if o.has("gain_part"):
		var g: Dictionary = o["gain_part"]
		var id := Economy.roll_part(g.get("category", "hardpoint"), run.rng, [], 1, run.player_mech.weight_class, str(g.get("rarity", "")))
		if id != "":
			var comp := run.new_part(id)
			if run.cargo.add(comp):
				run.stats.add("parts_acquired")
				notes.append("%s stowed in Cargo" % comp.name)
			else:
				notes.append("No room in Cargo for %s; left behind" % comp.name)
	for e in o.get("next_fight", []):
		run.next_fight.append(e)
	if int(o.get("alert_turns", 0)) > 0 and not run.mission.get("alert", {}).is_empty():
		run.alert_turns += int(o["alert_turns"])
		notes.append("Alert rises")
	return "  ·  ".join(notes)

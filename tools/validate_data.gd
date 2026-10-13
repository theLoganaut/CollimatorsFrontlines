extends SceneTree
## Data validator: checks that every file in data/ points at things that
## exist. Run with tools/check_all.sh, or:
##   Godot --headless --path . -s tools/validate_data.gd
## Errors (exit 1): a missing part, card, enemy, status or outcome key.
## Warnings: a balance.json number no script reads, a part outside its
## mech's weight class, a Medium player mech with no Medium parts to find.

const EVENT_KEYS := ["scraps", "damage_random_part", "repair", "gain_part", "next_fight", "alert_turns", "chance", "then", "else", "result", "goto"]
const EVENT_TOP_KEYS := ["id", "title", "text", "choices", "steps", "sectors", "missions", "requires_alert"]
const CHOICE_KEYS := ["label", "result", "outcome", "requires_alert"]
const NEXT_FIGHT_KEYS := ["side", "status", "stacks", "parts"]
const NEXT_FIGHT_PARTS := ["hardpoints", "all", "mech"]
## balance.json sections read through generic code (per-order numbers fill
## orders.json text and DeploymentOrders reads them by name).
const GENERIC_SECTIONS := ["orders"]

var errors: Array[String] = []
var warnings: Array[String] = []
var _source := ""

func _initialize() -> void:
	_source = _all_source()
	_mechs()
	_sectors()
	_events()
	_directives()
	_orders()
	_rules()
	_enemy_ai()
	_balance()
	_classes()
	for w in warnings:
		print("WARN  ", w)
	for e in errors:
		print("ERROR ", e)
	print("validate_data: %d errors, %d warnings" % [errors.size(), warnings.size()])
	quit(1 if not errors.is_empty() else 0)

func _json(path: String):
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null:
		errors.append("%s doesn't parse" % path)
		return {}
	return parsed

## Every .gd file's text, to check that balance keys are read somewhere.
func _all_source() -> String:
	var out := ""
	for dir in ["res://scripts", "res://tools"]:
		out += _read_dir(dir)
	return out

func _read_dir(path: String) -> String:
	var out := ""
	var d := DirAccess.open(path)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out += FileAccess.get_file_as_string(path + "/" + f)
	for sub in d.get_directories():
		out += _read_dir(path + "/" + sub)
	return out

func _mech_ids() -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at("res://data/mechs"):
		if f.ends_with(".json"):
			out.append(f.get_basename())
	return out

func _mechs() -> void:
	for id in _mech_ids():
		var d = _json("res://data/mechs/%s.json" % id)
		if typeof(d) != TYPE_DICTIONARY:
			continue
		if str(d.get("id", "")) != id:
			errors.append("mechs/%s.json: id is \"%s\"" % [id, d.get("id", "")])
		for c in d.get("components", []):
			if not ComponentLibrary.has(str(c.get("id", ""))):
				errors.append("mechs/%s.json: no part \"%s\" in components.json" % [id, c.get("id", "")])
		var m := DataLoader.load_mech_from_file("res://data/mechs/%s.json" % id)
		if m == null:
			errors.append("mechs/%s.json doesn't load" % id)
			continue
		var cells := GridUtils.cells_to_set(m.cells)
		var taken := {}
		for comp in m.components:
			for cell in comp.placed_cells:
				if not cells.has(cell):
					errors.append("mechs/%s.json: %s sits off the frame at %s" % [id, comp.id, cell])
				if taken.has(cell):
					errors.append("mechs/%s.json: %s overlaps %s at %s" % [id, comp.id, taken[cell], cell])
				taken[cell] = comp.id

func _sectors() -> void:
	var ids := _mech_ids()
	for loc in _json("res://data/sectors.json").get("locations", []):
		var name := str(loc.get("id", "?"))
		var refs: Array = loc.get("regulars", []) + loc.get("elites", []) + [loc.get("boss", "")]
		for pool in loc.get("encounters", {}).values():
			for e in pool:
				refs += e.get("enemies", [])
		for r in refs:
			if not ids.has(str(r)):
				errors.append("sectors.json %s: no enemy \"%s\" in data/mechs" % [name, r])
		for m in loc.get("modifiers", []):
			if not Conditions.data().get("modifiers", {}).has(m):
				errors.append("sectors.json %s: no modifier \"%s\" in conditions.json" % [name, m])
	# conditions.json: variants' modifiers exist, every variant has a weight and every weight a variant
	var mods: Dictionary = Conditions.data().get("modifiers", {})
	var weights: Dictionary = Balance.section("conditions").get("variant_weights", {})
	var variant_ids := []
	for v in Conditions.data().get("variants", []):
		variant_ids.append(v["id"])
		if not weights.has(v["id"]):
			errors.append("conditions.json variant %s: no weight in balance.json conditions.variant_weights" % v["id"])
		for m in v.get("modifiers", []):
			if not mods.has(m):
				errors.append("conditions.json variant %s: no modifier \"%s\"" % [v["id"], m])
	for w in weights:
		if not variant_ids.has(w):
			errors.append("balance.json conditions.variant_weights: no variant \"%s\"" % w)

func _events() -> void:
	var sector_ids: Array = _json("res://data/sectors.json").get("locations", []).map(func(l): return l["id"])
	var mission_ids: Array = _json("res://data/missions.json").get("missions", {}).keys()
	var seen := {}
	for ev in _json("res://data/events.json").get("events", []):
		var id: String = ev.get("id", "?")
		if seen.has(id):
			errors.append("events.json: duplicate event id %s" % id)
		seen[id] = true
		for k in ev:
			if not EVENT_TOP_KEYS.has(k):
				errors.append("events.json %s: unknown key \"%s\"" % [id, k])
		for sid in ev.get("sectors", []):
			if not sector_ids.has(sid):
				errors.append("events.json %s: no sector %s" % [id, sid])
		for mid in ev.get("missions", []):
			if not mission_ids.has(mid):
				errors.append("events.json %s: no mission %s" % [id, mid])
		var steps: Dictionary = ev.get("steps", {})
		var lists := [["", ev.get("choices", [])]]
		for step_id in steps:
			lists.append([step_id, steps[step_id].get("choices", [])])
		for pair in lists:
			if (pair[1] as Array).is_empty():
				errors.append("events.json %s%s: no choices" % [id, "" if pair[0] == "" else " / " + pair[0]])
			for ch in pair[1]:
				var where := "events.json %s / %s" % [id, ch.get("label", "?")]
				for k in ch:
					if not CHOICE_KEYS.has(k):
						errors.append("%s: unknown choice key \"%s\"" % [where, k])
				_outcome(where, ch.get("outcome", {}))
				for o in [ch.get("outcome", {}), ch.get("outcome", {}).get("then", {}), ch.get("outcome", {}).get("else", {})]:
					if o.has("goto") and not steps.has(o["goto"]):
						errors.append("%s: goto %s, no such step" % [where, o["goto"]])

func _outcome(where: String, o: Dictionary) -> void:
	for k in o:
		if not EVENT_KEYS.has(k):
			errors.append("%s: unknown outcome key \"%s\"" % [where, k])
	if o.has("gain_part") and not Economy.CATEGORIES.has(str(o["gain_part"].get("category", "hardpoint"))):
		errors.append("%s: gain_part category \"%s\"" % [where, o["gain_part"].get("category")])
	for nf in o.get("next_fight", []):
		for k in nf:
			if not NEXT_FIGHT_KEYS.has(k):
				errors.append("%s: unknown next_fight key \"%s\"" % [where, k])
		if not ComponentLibrary.IMPLEMENTED_STATUSES.has(str(nf.get("status", ""))):
			errors.append("%s: next_fight status \"%s\"" % [where, nf.get("status", "")])
		if not NEXT_FIGHT_PARTS.has(str(nf.get("parts", "all"))):
			errors.append("%s: next_fight parts \"%s\"" % [where, nf.get("parts", "")])
	for branch in ["then", "else"]:
		if o.has(branch):
			_outcome(where + " (%s)" % branch, o[branch])

func _directives() -> void:
	var known := {}
	for d in RunStats.DEFS:
		known[d[0]] = true
	var re := RegEx.create_from_string("stats\\.add\\(\"([a-z_]+)\"")
	for m in re.search_all(_source):
		known[m.get_string(1)] = true
	known["clears"] = true # Meta.gd counts a cleared run itself
	var dj: Dictionary = _json("res://data/directives.json")
	var sector_ids: Array = _json("res://data/sectors.json").get("locations", []).map(func(l): return l["id"])
	var mission_ids: Array = _json("res://data/missions.json").get("missions", {}).keys()
	var seen := {}
	for d in dj.get("directives", []) + dj.get("weekly", []):
		var id := str(d.get("id", "?"))
		if seen.has(id):
			errors.append("directives.json: duplicate id %s" % id)
		seen[id] = true
		var stats: Array = d.get("stat", []) if typeof(d.get("stat")) == TYPE_ARRAY else [d.get("stat", "")]
		for st in stats:
			if not known.has(str(st)):
				errors.append("directives.json %s: no stat \"%s\" is ever counted" % [id, st])
		if d.has("location") and not sector_ids.has(d["location"]):
			errors.append("directives.json %s: no location %s" % [id, d["location"]])
		if d.has("mission") and not mission_ids.has(d["mission"]):
			errors.append("directives.json %s: no mission %s" % [id, d["mission"]])

func _orders() -> void:
	var bal: Dictionary = Balance.section("orders")
	var re := RegEx.create_from_string("\\{([a-z_]+)\\}")
	for o in _json("res://data/orders.json").get("orders", []):
		var id := str(o.get("id", ""))
		if not bal.has(id):
			errors.append("orders.json %s: no numbers in balance.json orders" % id)
			continue
		for m in re.search_all(str(o.get("text", ""))):
			if not (bal[id] as Dictionary).has(m.get_string(1)):
				errors.append("orders.json %s: text uses {%s}, not in balance.json" % [id, m.get_string(1)])

func _rules() -> void:
	var rules = _json("res://data/component_rules.json")
	var cards := {}
	for id in ComponentLibrary.all_ids():
		for c in ComponentLibrary.definition(id).get("cards", []):
			cards[str(c.get("id", ""))] = true
	for pid in rules.get("passives", {}):
		if not ComponentLibrary.has(pid):
			errors.append("component_rules.json: passive for unknown part \"%s\"" % pid)
	for cid in rules.get("cards", {}):
		if not cards.has(cid):
			errors.append("component_rules.json: rule for unknown card \"%s\"" % cid)
	for id in ComponentLibrary.all_ids():
		for c in ComponentLibrary.definition(id).get("cards", []):
			for s in c.get("statuses", []):
				var st := str(s.get("status", s.get("name", ""))).to_lower()
				if st != "" and not ComponentLibrary.IMPLEMENTED_STATUSES.has(st) and StatusGlossary.get_entry(st).is_empty():
					errors.append("components.json %s / %s: unknown status \"%s\"" % [id, c.get("id", ""), st])

## data/enemy_ai.json (Phase 6): every entry is an enemy, its rhythms use
## known themes and conditions, and its on_lost parts are on that enemy.
func _enemy_ai() -> void:
	var d = _json("res://data/enemy_ai.json")
	if typeof(d) != TYPE_DICTIONARY:
		errors.append("enemy_ai.json doesn't load")
		return
	var conds := ["player_hot", "player_shielded", "player_damaged", "player_primed", "self_hurt", "ally_hurt", "has_charge", "squad"]
	var ids := _mech_ids()
	for id in d:
		if str(id).begins_with("_"):
			continue
		if not ids.has(id):
			errors.append("enemy_ai.json: no enemy \"%s\"" % id)
			continue
		var mech = _json("res://data/mechs/%s.json" % id)
		var parts := (mech.get("components", []) as Array).map(func(c): return str(c.get("id", "")))
		var e: Dictionary = d[id]
		var lists: Array = [e.get("rhythms", []), e.get("phase2", {}).get("rhythms", [])]
		for key in e.get("on_lost", {}):
			if not parts.has(key):
				errors.append("enemy_ai.json %s: on_lost part \"%s\" isn't on it" % [id, key])
			lists.append(e["on_lost"][key].get("rhythms", []))
		for list in lists:
			for r in list:
				for t in r.get("turns", []):
					if not EnemyAI.THEMES.has(t):
						errors.append("enemy_ai.json %s: unknown theme \"%s\"" % [id, t])
				var when = r.get("when", [])
				for c in (when if when is Array else [when]):
					if not conds.has(str(c)):
						errors.append("enemy_ai.json %s: unknown condition \"%s\"" % [id, c])

func _balance() -> void:
	var data := Balance.data()
	for sec in data:
		if str(sec).begins_with("_") or GENERIC_SECTIONS.has(sec) or typeof(data[sec]) != TYPE_DICTIONARY:
			continue
		for key in data[sec]:
			if str(key).begins_with("_"):
				continue
			if not _source.contains("\"%s\"" % key):
				warnings.append("balance.json %s.%s: no script reads it" % [sec, key])

func _classes() -> void:
	for id in _mech_ids():
		var m := DataLoader.load_mech_from_file("res://data/mechs/%s.json" % id)
		if m == null:
			continue
		for comp in m.components:
			if not ComponentLibrary.fits_class(comp.library_id, m.weight_class):
				warnings.append("mechs/%s.json (%s): %s is a %s part" % [id, m.weight_class, comp.library_id, ComponentLibrary.weight_class_of(comp.library_id)])
	for wc in ["light", "medium", "heavy"]:
		var own := 0
		for cat in Economy.CATEGORIES:
			for rar in Economy.RARITIES:
				own += ComponentLibrary.pool(cat, rar, wc).filter(func(p): return ComponentLibrary.weight_class_of(p) == wc).size()
		if own == 0:
			warnings.append("no %s parts can drop for a %s mech" % [wc, wc])

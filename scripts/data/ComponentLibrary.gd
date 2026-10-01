class_name ComponentLibrary
extends RefCounted
## Every Refit Bay part, loaded from data/components.json (a verbatim Refit
## Bay export, see tools/import_refit_bay.py) plus data/component_rules.json
## (how each effect plays). Mech files and rewards name parts by id; make()
## builds a fresh ComponentData for one.
##
## Reactors are passive: their one Refit Bay card never goes in the hand.
## Its statuses and effect text become the passive's description, and the
## rules file says what the passive does.
##
## A part is "implemented" once all of its statuses are built and every
## effect text and passive it has is covered by the rules file. Only
## implemented parts can drop as rewards or be sold in shops.

const COMPONENTS_PATH := "res://data/components.json"
const RULES_PATH := "res://data/component_rules.json"

## Statuses the engine plays (every one on Statuses & Links).
const IMPLEMENTED_STATUSES := ["shock", "acid", "burn", "absorb", "deflect", "smoke", "disabled", "offline", "freeze", "coolant", "jam"]
## Passive types that take their status from the reactor's Refit Bay card.
const STATUS_PASSIVES := ["turn_start_status", "facing_turn_start_status", "on_damaged_status"]

static var _defs: Dictionary = {}   # id -> raw component dict
static var _order: Array[String] = []
static var _rules: Dictionary = {}

static func _ensure_loaded() -> void:
	if not _defs.is_empty():
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(COMPONENTS_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ComponentLibrary: failed to parse %s" % COMPONENTS_PATH)
		return
	for c in parsed.get("components", []):
		_defs[c["id"]] = c
		_order.append(c["id"])
	var rules = JSON.parse_string(FileAccess.get_file_as_string(RULES_PATH))
	_rules = rules if typeof(rules) == TYPE_DICTIONARY else {}

static func has(id: String) -> bool:
	_ensure_loaded()
	return _defs.has(id)

static func definition(id: String) -> Dictionary:
	_ensure_loaded()
	return _defs.get(id, {})

static func all_ids() -> Array[String]:
	_ensure_loaded()
	return _order.duplicate()

static func card_rule(card_id: String) -> Dictionary:
	_ensure_loaded()
	return _rules.get("cards", {}).get(card_id, {})

static func passive_rule(component_id: String) -> Dictionary:
	_ensure_loaded()
	return _rules.get("passives", {}).get(component_id, {})

static func is_implemented(id: String) -> bool:
	var d := definition(id)
	if d.is_empty():
		return false
	if d["category"] == ComponentData.CATEGORY_REACTOR and passive_rule(id).is_empty():
		return false
	for c in d["cards"]:
		for s in c["statuses"]:
			if not IMPLEMENTED_STATUSES.has(s["status"]):
				return false
		if d["category"] != ComponentData.CATEGORY_REACTOR and str(c["effect_text"]) != "" and card_rule(c["id"]).is_empty():
			return false
	return true

## Implemented parts of one category and rarity, in library order. With a
## `weight_class`, only parts that fit it (General fits every class).
static func pool(category: String, rarity: String, weight_class: String = "") -> Array[String]:
	var out: Array[String] = []
	for id in all_ids():
		var d := definition(id)
		if d["category"] == category and d["rarity"] == rarity and is_implemented(id) and fits_class(id, weight_class):
			out.append(id)
	return out

## Refit Bay: a part tagged General fits any chassis; Light / Medium /
## Heavy parts fit only that class. "" = don't check.
static func fits_class(id: String, weight_class: String) -> bool:
	if weight_class == "" or weight_class == "general":
		return true
	var wc: String = definition(id).get("weight_class", "general")
	return wc == "general" or wc == weight_class

static func weight_class_of(id: String) -> String:
	return definition(id).get("weight_class", "general")

## A fresh, unplaced part (offset 0, rotation 0, full HP).
static func make(id: String) -> ComponentData:
	var d := definition(id)
	if d.is_empty():
		push_error("ComponentLibrary: unknown component '%s'" % id)
		return null
	var dict := d.duplicate(true)
	if d["category"] == ComponentData.CATEGORY_REACTOR:
		dict["passive"] = _passive_for(d)
		dict["cards"] = []
	var c := DataLoader.load_component(dict)
	var hm := Balance.get_num("combat", "hp_mult", 1.0)
	if hm != 1.0:
		c.max_hp = maxi(1, roundi(c.max_hp * hm))
		c.current_hp = c.max_hp
	c.rarity = d.get("rarity", "")
	c.library_id = id
	for card in c.cards:
		card.rule = card_rule(card.id).duplicate(true)
		if card.rule.has("play_mode"):
			card.play_mode = card.rule["play_mode"]
		scale_card(card)
	return c

## balance.json "combat": heat_add on every card that costs heat; then
## every card's damage times damage_mult (rounded, at least 1), and a
## damage-dealing card's heat cost times heat_mult (rounded). Refit Bay
## keeps the unscaled numbers.
static func scale_card(card: CardData) -> void:
	if card.heat_cost > 0:
		card.heat_cost += Balance.get_int("combat", "heat_add", 0)
	if card.hits <= 0 or card.damage_max <= 0:
		return
	var dm := Balance.get_num("combat", "damage_mult", 1.0)
	if dm != 1.0:
		card.damage_min = maxi(1, roundi(card.damage_min * dm))
		card.damage_max = maxi(card.damage_min, roundi(card.damage_max * dm))
	var hm := Balance.get_num("combat", "heat_mult", 1.0)
	if hm != 1.0 and card.heat_cost > 0:
		card.heat_cost = maxi(1, roundi(card.heat_cost * hm))

## A reactor's passive: its rule, plus its Refit Bay card's statuses and
## text as the description ("Gain Absorb 25. Triggers automatically…").
static func _passive_for(d: Dictionary) -> Dictionary:
	var p := passive_rule(d["id"]).duplicate(true)
	if p.is_empty():
		p = {"type": "unimplemented"}
	var parts: Array[String] = []
	if not d["cards"].is_empty():
		var card: Dictionary = d["cards"][0]
		for s in card["statuses"]:
			parts.append(StatusEffectData.short_text(s["status"], DataLoader.parse_stacks(s["stacks"]), s["target"]) + ".")
			if STATUS_PASSIVES.has(p.get("type", "")):
				p["status"] = s["status"]
				p["stacks"] = DataLoader.parse_stacks(s["stacks"])
				p["target"] = s["target"]
		var effect := str(card["effect_text"])
		if effect.ends_with(":") and not parts.is_empty():
			# a lead-in ("Turn start:") goes before the statuses it introduces
			parts[0] = parts[0].substr(0, 1).to_lower() + parts[0].substr(1)
			parts.push_front(effect)
		elif effect != "":
			parts.append(effect)
	p["text"] = " ".join(parts)
	return p

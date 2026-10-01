class_name DataLoader
extends RefCounted
## Turns mech JSON into MechData/ComponentData/CardData. The JSON mirrors
## Refit Bay's own raw export shapes on purpose (damage as "a-b" / "0" / "",
## heat cost as a string that can be "" or negative) — see Combat Slice §2's
## "Data-loading notes" callout — so this parsing logic is the same logic a
## future direct Refit Bay import would need.

static func parse_cell(pair) -> Vector2i:
	return Vector2i(int(pair[0]), int(pair[1]))

static func parse_cells(arr) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for pair in arr:
		out.append(parse_cell(pair))
	return out

## "6-10" -> [6,10] · "0" / "" -> [0,0] · "16" -> [16,16]
static func parse_damage_range(raw) -> Array:
	var s := str(raw).strip_edges()
	if s == "" or s == "0":
		return [0, 0]
	if s.find("-") == -1:
		var v := int(s)
		return [v, v]
	var parts := s.split("-")
	return [int(parts[0]), int(parts[1])]

## "" -> 0 (Lock On / every current protocol) · "-3" -> -3 (vents heat) · "4" -> 4
static func parse_heat_cost(raw) -> int:
	var s := str(raw).strip_edges()
	if s == "":
		return 0
	return int(s)

## "" -> 0 · "3" -> 3
static func parse_hits(raw) -> int:
	var s := str(raw).strip_edges()
	if s == "":
		return 0
	return int(s)

static func parse_stacks(raw) -> int:
	if typeof(raw) == TYPE_STRING:
		var s: String = raw.strip_edges()
		return int(s) if s != "" else 0
	return int(raw)

## A flag status (Offline) has no stack count in Refit Bay: it counts as 1.
const FLAG_STATUSES := ["offline"]

static func parse_statuses(arr) -> Array[StatusEffectData]:
	var out: Array[StatusEffectData] = []
	for d in arr:
		var status: String = d.get("status", "")
		var stacks := parse_stacks(d.get("stacks", 0))
		if stacks <= 0 and FLAG_STATUSES.has(status):
			stacks = 1
		out.append(StatusEffectData.new(status, stacks, d.get("target", StatusEffectData.TARGET_ENEMY)))
	return out

## Attack cards are ones that deal damage, or apply a status to an enemy
## component (Combat Rules: "Attack cards ... have to be released on a
## specific enemy component"). Everything else is a self card.
static func derive_play_mode(hits: int, statuses: Array[StatusEffectData]) -> String:
	if hits > 0:
		return CardData.PLAY_MODE_ATTACK
	for s in statuses:
		if s.target == StatusEffectData.TARGET_ENEMY or s.target == StatusEffectData.TARGET_ALL_ENEMIES:
			return CardData.PLAY_MODE_ATTACK
	return CardData.PLAY_MODE_SELF

static func load_card(dict: Dictionary, owner_component_id: String) -> CardData:
	var card := CardData.new()
	card.id = dict.get("id", "")
	card.name = dict.get("name", "")
	card.heat_cost = parse_heat_cost(dict.get("heat_cost", ""))
	card.hits = parse_hits(dict.get("hits", ""))
	var dmg := parse_damage_range(dict.get("damage", ""))
	card.damage_min = dmg[0]
	card.damage_max = dmg[1]
	card.statuses = parse_statuses(dict.get("statuses", []))
	card.effect_text = dict.get("effect_text", "")
	card.play_mode = derive_play_mode(card.hits, card.statuses)
	card.hand_side = dict.get("hand_side", "left")
	card.owner_component_id = owner_component_id
	return card

## A mech file can name a library part by id with just its placement
## ({"id", "offset", "rotation"}); everything else comes from Refit Bay via
## ComponentLibrary. A full inline definition (tests) is loaded as-is.
static func load_component(dict: Dictionary) -> ComponentData:
	var part_id: String = dict.get("part", dict.get("id", "")) # "part": a repeated part's library id
	if not dict.has("cells") and ComponentLibrary.has(part_id):
		var lib := ComponentLibrary.make(part_id)
		if part_id != dict.get("id", part_id):
			lib.set_instance_id(dict["id"])
		lib.offset = parse_cell(dict.get("offset", [0, 0]))
		lib.rotation_steps = int(dict.get("rotation", 0))
		lib.placed_cells = GridUtils.place_cells(lib.cells, lib.rotation_steps, lib.offset)
		return lib
	var c := ComponentData.new()
	c.id = dict.get("id", "")
	c.name = dict.get("name", "")
	c.category = dict.get("category", "")
	c.max_hp = int(dict.get("hp", 0))
	c.current_hp = c.max_hp
	c.cells = parse_cells(dict.get("cells", []))
	c.offset = parse_cell(dict.get("offset", [0, 0]))
	c.rotation_steps = int(dict.get("rotation", 0))
	c.placed_cells = GridUtils.place_cells(c.cells, c.rotation_steps, c.offset)
	c.passive = dict.get("passive", {})
	c.library_id = c.id
	c.cards = []
	for card_dict in dict.get("cards", []):
		c.cards.append(load_card(card_dict, c.id))
	return c

static func load_mech(dict: Dictionary) -> MechData:
	var m := MechData.new()
	m.id = dict.get("id", "")
	m.name = dict.get("name", "")
	m.weight_class = dict.get("weight_class", "")
	m.tier = dict.get("tier", "")
	var ai = dict.get("ai", "careful")
	if typeof(ai) == TYPE_DICTIONARY:
		m.ai = ai
		m.ai_profile = ai.get("heat", "careful")
	else:
		m.ai = {"heat": str(ai)}
		m.ai_profile = str(ai)
	m.lines = dict.get("lines", {})
	m.title = dict.get("title", "")
	m.cells = parse_cells(dict.get("cells", []))
	m.max_heat = int(dict.get("max_heat", 0))
	m.defeat_hp_fraction = float(dict.get("defeat_hp_fraction", 0.0))
	m.heat_check_timing = dict.get("heat_check_timing", MechData.HEAT_CHECK_END_OF_TURN)
	m.components = []
	for comp_dict in dict.get("components", []):
		m.components.append(load_component(comp_dict))
	m.current_heat = 0
	return m

static func load_mech_from_json(json_text: String) -> MechData:
	var parsed = JSON.parse_string(json_text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		push_error("DataLoader: failed to parse mech JSON")
		return null
	return load_mech(parsed)

static func load_mech_from_file(path: String) -> MechData:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("DataLoader: cannot open %s (error %s)" % [path, FileAccess.get_open_error()])
		return null
	var text := f.get_as_text()
	f.close()
	return load_mech_from_json(text)

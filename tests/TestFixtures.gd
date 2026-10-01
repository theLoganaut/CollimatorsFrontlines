class_name TestFixtures
extends RefCounted
## Small synthetic components/cards/mechs for tests that need precise edge
## cases rather than real Bastion/Warden data.

static func make_component(id: String, hp: int, cards: Array[CardData] = []) -> ComponentData:
	var c := ComponentData.new()
	c.id = id
	c.name = id
	c.category = ComponentData.CATEGORY_HARDPOINT
	c.max_hp = hp
	c.current_hp = hp
	c.cells = [Vector2i(0, 0)]
	c.placed_cells = [Vector2i(0, 0)]
	c.cards = cards
	return c

static func make_mech(id: String, max_heat: int, components: Array[ComponentData]) -> MechData:
	var m := MechData.new()
	m.id = id
	m.name = id
	m.weight_class = "general"
	m.cells = [Vector2i(0, 0)]
	m.max_heat = max_heat
	m.heat_check_timing = MechData.HEAT_CHECK_LIVE
	m.components = components
	m.current_heat = 0
	return m

static func make_card(id: String, owner_id: String, heat_cost: int, hits: int, dmg_min: int, dmg_max: int, statuses: Array[StatusEffectData] = []) -> CardData:
	var card := CardData.new()
	card.id = id
	card.name = id
	card.heat_cost = heat_cost
	card.hits = hits
	card.damage_min = dmg_min
	card.damage_max = dmg_max
	card.statuses = statuses
	card.effect_text = ""
	card.play_mode = DataLoader.derive_play_mode(hits, statuses)
	card.hand_side = "left"
	card.owner_component_id = owner_id
	return card

## A seeded RandomNumberGenerator, so a test's rolls are the same every run.
static func rng(seed_value: int = 1) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r

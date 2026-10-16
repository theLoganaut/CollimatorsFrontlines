class_name CardData
extends RefCounted
## One card granted by a component. Combat Slice §2/§4.4: attack cards must
## be dropped on an enemy component cell; self cards resolve on release
## anywhere outside the hand.

const PLAY_MODE_ATTACK := "attack"
const PLAY_MODE_SELF := "self"

var id: String
var name: String
var heat_cost: int
var hits: int
var damage_min: int
var damage_max: int
var statuses: Array[StatusEffectData] = []
var effect_text: String
var play_mode: String
var hand_side: String            # "left" / "right" — only meaningful for the player's hand
var owner_component_id: String   # which component granted this card; used to pull it from
                                  # the hand when that component is destroyed (§4.4)
## Its mechanics from data/component_rules.json ({} = plays exactly as its numbers say).
var rule: Dictionary = {}
## A one-use card (Intercept's copy of an enemy attack): gone once played.
var one_use: bool = false

func protocol() -> String:
	return rule.get("protocol", "")

func is_attack() -> bool:
	return play_mode == PLAY_MODE_ATTACK

const INTENT_ATTACK := "attack"
const INTENT_HEAVY_ATTACK := "heavy_attack"
const INTENT_BLOCK := "block"
const INTENT_STATUS := "status"
const INTENT_BUFF := "buff"
## An attack whose average total damage reaches this reads as "heavy".
const HEAVY_ATTACK_AVG := 20.0

func average_damage() -> float:
	return hits * (damage_min + damage_max) / 2.0

## The vague shape of what this card does, for enemy intent icons: attack
## (heavy if it hits hard), block (Deflect/Absorb on itself), status (puts
## a status on the target without hitting), or buff (anything else).
func intent() -> String:
	if hits > 0:
		return INTENT_HEAVY_ATTACK if average_damage() >= HEAVY_ATTACK_AVG else INTENT_ATTACK
	for s in statuses:
		if s.status in ["deflect", "absorb"] and s.target in [StatusEffectData.TARGET_SELF, StatusEffectData.TARGET_OWN_MECH]:
			return INTENT_BLOCK
	for s in statuses:
		if s.target in [StatusEffectData.TARGET_ENEMY, StatusEffectData.TARGET_ALL_ENEMIES]:
			return INTENT_STATUS
	return INTENT_BUFF

## One hit's damage: "6", or "4–8" for a range.
func per_hit_label() -> String:
	return str(damage_min) if damage_min == damage_max else "%d–%d" % [damage_min, damage_max]

func damage_label() -> String:
	if hits <= 0:
		return ""
	var per_hit := per_hit_label()
	if hits == 1:
		return per_hit # a single hit is implied, no "1×"
	return "%d×%s" % [hits, per_hit]

## The card's status lines for its face, with any chance shown up front
## (Logan, 2026-09-30: "25%: Shock 1"), then a note if its hits can miss.
func status_lines() -> Array[String]:
	var out: Array[String] = []
	var chance := float(rule.get("status_chance", 1.0))
	for s in statuses:
		out.append(s.short() if chance >= 1.0 else "%d%%: %s" % [int(round(chance * 100.0)), s.short()])
	var curve: Array = rule.get("hit_chance", [])
	if not curve.is_empty() and curve.any(func(c): return float(c) < 1.0):
		if float(curve[0]) < 1.0 and curve.size() == 1:
			out.append("Each hit: %d%% to land" % int(round(float(curve[0]) * 100.0)))
		else:
			out.append("Later hits may miss")
	return out

func clone() -> CardData:
	var c := CardData.new()
	c.id = id
	c.name = name
	c.heat_cost = heat_cost
	c.hits = hits
	c.damage_min = damage_min
	c.damage_max = damage_max
	c.statuses = []
	for s in statuses:
		c.statuses.append(s.clone())
	c.effect_text = effect_text
	c.play_mode = play_mode
	c.rule = rule.duplicate(true)
	c.one_use = one_use
	c.hand_side = hand_side
	c.owner_component_id = owner_component_id
	return c

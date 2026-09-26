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

func is_attack() -> bool:
	return play_mode == PLAY_MODE_ATTACK

func damage_label() -> String:
	if hits <= 0:
		return ""
	return "%d×%d–%d" % [hits, damage_min, damage_max]

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
	c.hand_side = hand_side
	c.owner_component_id = owner_component_id
	return c

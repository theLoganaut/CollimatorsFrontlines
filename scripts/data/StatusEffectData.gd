class_name StatusEffectData
extends RefCounted
## A single status application described by a card: which status, how many
## stacks, and who it targets. See Notion "Statuses & Links" for the rules
## each status name maps to.

const TARGET_ENEMY := "enemy"       # the single component the card was dropped on
const TARGET_ALL_ENEMIES := "allEnemies"
const TARGET_SELF := "self"         # the component that granted the card
const TARGET_LINKED := "linked"     # not implemented this slice
const TARGET_OWN_MECH := "ownMech"  # the mech that played the card

var status: String
var stacks: int
var target: String

func _init(p_status: String = "", p_stacks: int = 0, p_target: String = TARGET_ENEMY) -> void:
	status = p_status
	stacks = p_stacks
	target = p_target

func clone() -> StatusEffectData:
	return StatusEffectData.new(status, stacks, target)

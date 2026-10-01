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

## A status as a card face reads it, Slay-the-Spire short: the target is
## implied for the part the card is dropped on ("Burn 3"); anything else says
## where it lands ("Gain Deflect 5", "Disabled 1 (self)"). Flag statuses
## (Offline) have no count.
static func short_text(p_status: String, p_stacks: int, t: String) -> String:
	var s := p_status.capitalize()
	if p_stacks > 0 and not DataLoader.FLAG_STATUSES.has(p_status):
		s += " %d" % p_stacks
	match t:
		TARGET_ENEMY: return s
		TARGET_ALL_ENEMIES: return "%s to all enemies" % s
		TARGET_SELF: return "%s (self)" % s
		TARGET_LINKED: return "%s (linked)" % s
		TARGET_OWN_MECH: return "Gain %s" % s
		_: return s

func short() -> String:
	return short_text(status, stacks, target)

func clone() -> StatusEffectData:
	return StatusEffectData.new(status, stacks, target)

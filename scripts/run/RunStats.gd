class_name RunStats
extends RefCounted
## Counters for the debrief (Logan, 2026-09-27: "a bunch of stats … fun for
## players to track"). CombatManager keeps one for its fight; RunData merges
## each fight's into the run's, and adds the between-fight ones (scraps,
## repairs, bays). DEFS is the debrief's list, in display order.

const DEFS := [
	["damage_dealt", "Damage dealt"],
	["damage_taken", "Damage taken"],
	["damage_blocked", "Damage blocked (Absorb / Deflect)"],
	["damage_healed", "Damage healed"],
	["biggest_hit", "Biggest single hit"],
	["best_turn_damage", "Most damage in one turn"],
	["enemies_destroyed", "Enemies destroyed"],
	["enemy_parts_destroyed", "Enemy parts destroyed"],
	["parts_lost", "Your parts lost"],
	["fights_won", "Fights won"],
	["elites_beaten", "Elites beaten"],
	["bosses_beaten", "Bosses beaten"],
	["fastest_fight", "Fastest fight (turns)"],
	["turns_taken", "Turns taken"],
	["cards_played", "Cards played"],
	["hits_landed", "Hits landed"],
	["heat_generated", "Heat generated"],
	["overheats", "Overheats"],
	["scraps_earned", "Scraps earned"],
	["scraps_spent", "Scraps spent"],
	["parts_acquired", "Parts acquired"],
	["repair_bays", "Repair bays used"],
	["autonomous_bays", "Autonomous bays visited"],
	["refits", "Refits"],
]
## What the debrief shows, in order (Logan, 2026-10-13); the rest are
## still tracked for the Pilot Log and directives.
const DEBRIEF := ["damage_dealt", "damage_taken", "biggest_hit", "best_turn_damage", "cards_played", "heat_generated",
	"enemies_destroyed", "fights_won", "fastest_fight", "turns_taken", "scraps_earned", "scraps_spent"]
const MAX_KEYS := ["biggest_hit", "best_turn_damage"]
const MIN_KEYS := ["fastest_fight"]

var values: Dictionary = {}

## A stat's name ("Damage dealt").
static func label(key: String) -> String:
	for d in DEFS:
		if d[0] == key:
			return d[1]
	return key.capitalize()

func get_stat(key: String) -> int:
	return int(values.get(key, 0))

func add(key: String, n: int = 1) -> void:
	values[key] = get_stat(key) + n

func record_max(key: String, n: int) -> void:
	if n > get_stat(key):
		values[key] = n

func record_min(key: String, n: int) -> void:
	if not values.has(key) or n < get_stat(key):
		values[key] = n

## Folds another set of counters (one fight) into these.
func merge(other: RunStats) -> void:
	for key in other.values.keys():
		var v: int = other.get_stat(key)
		if MAX_KEYS.has(key):
			record_max(key, v)
		elif MIN_KEYS.has(key):
			record_min(key, v)
		else:
			add(key, v)

func to_dict() -> Dictionary:
	return values.duplicate()

static func from_dict(d: Dictionary) -> RunStats:
	var s := RunStats.new()
	for k in d.keys():
		s.values[k] = int(d[k])
	return s

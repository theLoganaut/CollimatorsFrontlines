class_name Threat
extends RefCounted
## Threat levels (Logan, 2026-11-08 and 11-19): harder runs of a location
## for more Chips. Level 0 is the plain mission; a location's next level
## unlocks when the pilot clears it at the one before (Profile.threat).
## Each level adds its effect and keeps every one below:
## 1 Veterans: enemy parts have more HP (balance.json threat.veteran_hp_mult).
## 2 They're expecting you: elites open with an extra move (EnemyAI.apply_openers).
## 3 Captured bays: enemies may be waiting at a repair bay (ambush_roll).
## 4 On alert: bosses start in their phase 2 playbook.
## 5 Supply lines cut: fights pay fewer scraps.
## The run's mission carries its level ("threat"), so a saved run keeps it.
## Names, effect text and Operator lines are in data/threat.json.

const PATH := "res://data/threat.json"
const VETERANS := 1
const EXPECTING := 2
const CAPTURED_BAYS := 3
const ON_ALERT := 4
const SUPPLY_CUT := 5

static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = parsed if typeof(parsed) == TYPE_DICTIONARY else {"levels": []}
	return _data

static func max_level() -> int:
	return Balance.get_int("threat", "max_level", 5)

static func num(key: String, fallback: float) -> float:
	return Balance.get_num("threat", key, fallback)

# ---------- words ----------

static func level_def(n: int) -> Dictionary:
	for d in data().get("levels", []):
		if int(d.get("level", -1)) == n:
			return d
	return {}

static func level_name(n: int) -> String:
	return str(level_def(n).get("name", "Level %d" % n))

## A level's own effect, numbers filled in ("" for level 0).
static func effect(n: int) -> String:
	return str(level_def(n).get("effect", "")).format({
		"veteran_hp_pct": str(roundi((num("veteran_hp_mult", 1.1) - 1.0) * 100.0)),
		"scraps_less_pct": str(roundi((1.0 - num("scraps_mult", 0.75)) * 100.0)),
	})

static func operator_line(n: int) -> String:
	return str(level_def(n).get("operator", ""))

## Every effect on at level `n`, lowest first.
static func effects_up_to(n: int) -> Array[String]:
	var out: Array[String] = []
	for i in range(1, n + 1):
		var e := effect(i)
		if e != "":
			out.append(e)
	return out

## "+20% Chips" for level 2 ("" for 0).
static func chips_text(n: int) -> String:
	return "" if n <= 0 else "+%d%% Chips" % roundi((chips_mult(n) - 1.0) * 100.0)

## Lines for the location map: the level, then each effect on.
static func describe(mission: Dictionary) -> Array[String]:
	var lv := level(mission)
	var out: Array[String] = []
	if lv <= 0:
		return out
	out.append("Threat %d · %s (%s)" % [lv, level_name(lv), chips_text(lv)])
	out.append_array(effects_up_to(lv))
	return out

# ---------- the run's level ----------

static func level(mission: Dictionary) -> int:
	return int(mission.get("threat", 0))

## The mission at threat `n` (training and the Daily stay at 0).
static func with_level(mission: Dictionary, n: int) -> Dictionary:
	var m := mission.duplicate(true)
	if n > 0 and not m.get("training", false) and not m.has("daily"):
		m["threat"] = clampi(n, 0, max_level())
	return m

static func chips_mult(n: int) -> float:
	return 1.0 + num("chips_per_level", 0.1) * maxi(n, 0)

static func scraps_mult(mission: Dictionary) -> float:
	return num("scraps_mult", 0.75) if level(mission) >= SUPPLY_CUT else 1.0

# ---------- what it does ----------

## A fight's enemies as they're made (RunData.encounter_enemies): the level
## they carry (chevrons on their name plates), Veterans' HP, an elite's
## extra opener, a boss on alert. On the mechs themselves, so a fight
## record and the sim see the same.
static func apply_to_enemies(mission: Dictionary, enemies: Array[MechData]) -> void:
	var lv := level(mission)
	if lv <= 0:
		return
	for m in enemies:
		m.threat = lv
		if lv >= VETERANS:
			var mult := num("veteran_hp_mult", 1.1)
			for c in m.components:
				c.max_hp = maxi(1, roundi(c.max_hp * mult))
				c.current_hp = maxi(1, roundi(c.current_hp * mult))
		if lv >= EXPECTING and m.tier == "elite":
			m.threat_openers.append({"type": "threat_extra"})
		if lv >= ON_ALERT and m.tier == "boss" and (m.ai.has("phase2") or EnemyAI.design(m).has("phase2")):
			m.phase2_reached = true
			m.threat_openers.append({"type": "note", "note": "on alert, it fights its phase 2 playbook from the start"})

## Level 3 (Logan, 2026-11-19): whether enemies are waiting at the repair
## bay `node` the pilot just reached. Rolled on arrival, never shown on the
## map, never at the bay right before the boss. The chance starts at
## threat.ambush_start, rises ambush_step after each free bay, and drops to
## ambush_after after a taken one (kept in run.ambush_chance).
static func ambush_roll(run: RunData, node: Dictionary) -> bool:
	if level(run.mission) < CAPTURED_BAYS or before_boss(run.map, node):
		return false
	var chance := run.ambush_chance if run.ambush_chance >= 0.0 else num("ambush_start", 0.2)
	var roll := RandomNumberGenerator.new()
	roll.seed = hash([run.seed_value, int(node["id"]), "ambush"])
	var taken := roll.randf() < chance
	run.ambush_chance = num("ambush_after", 0.05) if taken else minf(1.0, chance + num("ambush_step", 0.15))
	return taken

## A stop that leads straight into the boss.
static func before_boss(map: RunMap, node: Dictionary) -> bool:
	for id in node.get("next", []):
		if map.get_map_node(id).get("kind", "") == RunMap.KIND_BOSS:
			return true
	return false

class_name MapGenerator
extends RefCounted
## Builds a RunMap: one row per entry in `enemy_ramp` (regular enemies per
## fight on that row), 2–4 nodes a row, plus a single boss stop on top that
## every path leads into when the mission has a boss (Logan, 2026-09-28).
## The first and last ramp rows are all fights; rows in between can hold
## repair bays, autonomous bays, events and elites, and every map has at
## least one of each (Proposed odds below). A bay never links straight into
## another of the same kind, nor an elite into an elite.
##
## Elites (with a regular escort from `elite_escort_from_row` up) and the
## boss are picked here, so the seed fixes them. A regular fight's enemies
## are picked here too when the location has no encounter pools; with
## pools (Slay-the-Spire style, Logan 2026-09-28) they're rolled when the
## pilot enters the fight (RunData.roll_encounter), since which pool it
## draws from depends on how many fights came before.
##
## Links between two rows never cross: nodes are sorted left to right, each
## links to its proportional partner in the next row (a non-decreasing
## mapping), sometimes also to the partner's right-hand neighbour, and any
## node left unreached is linked from the nearer of the two nodes whose
## partners bracket it. Two rows of the same size always get at least one
## branch, and separate lanes are then bridged until every node belongs to
## one connected map, so paths can always cross over somewhere.
##
## The numbers (row sizes, branch chance, the odds of each stop kind) are
## in data/balance.json ("map").

static func _n(key: String, fallback: float) -> float:
	return Balance.get_num("map", key, fallback)

## `opts`: {"boss": bool, "regulars": [ids], "elites": [ids], "boss_id",
## "elite_escort_from_row", "max_shops" (0 = no cap), "odds": {balance.json
## "map" keys}}. Without
## pools every enemy is a Scrap Warden. `odds` overrides the stop odds for
## this map (deployment orders); a kind at 0 odds isn't forced in either.
static func generate(rng: RandomNumberGenerator, enemy_ramp: Array, opts: Dictionary = {}) -> RunMap:
	var map := RunMap.new()
	var ramp_rows := enemy_ramp.size()
	map.row_count = ramp_rows
	var rows: Array = [] # Array of Array[int] (node ids, left to right)
	for r in range(ramp_rows):
		var count := rng.randi_range(int(_n("start_min", 3)) if r == 0 else int(_n("min_per_row", 2)), int(_n("max_per_row", 4)))
		var ids: Array[int] = []
		for i in range(count):
			var jitter := rng.randf_range(-0.22, 0.22) / float(count)
			var node := {
				"id": map.nodes.size(), "row": r, "x": (float(i) + 0.5) / float(count) + jitter,
				"next": [], "kind": RunMap.KIND_FIGHT, "enemy_count": int(enemy_ramp[r]), "enemies": [],
			}
			map.nodes.append(node)
			ids.append(node["id"])
		rows.append(ids)
	for r in range(ramp_rows - 1):
		_link_rows(map, rows[r], rows[r + 1], rng)
	_bridge_lanes(map, rows, rng)
	_assign_kinds(map, rng, not (opts.get("elites", []) as Array).is_empty() or not opts.has("elites"), opts.get("odds", {}))
	if int(opts.get("max_shops", 0)) > 0:
		_cap_kind(map, rng, enemy_ramp, RunMap.KIND_SHOP, int(opts["max_shops"]))
	if opts.get("boss", false):
		var last: Array = rows[ramp_rows - 1]
		var boss_row := ramp_rows
		# A repair bay every path goes through right before the boss (Logan,
		# 2026-09-30: "makes it easier on the player"). Takes no RNG, so maps
		# without it (older saves) come out the same.
		if opts.get("repair_before_boss", false):
			var bay := {"id": map.nodes.size(), "row": ramp_rows, "x": 0.5, "next": [], "kind": RunMap.KIND_REPAIR, "enemy_count": 0, "enemies": []}
			map.nodes.append(bay)
			for id in last:
				map.nodes[id]["next"] = [bay["id"]]
			last = [bay["id"]]
			boss_row += 1
		var boss := {"id": map.nodes.size(), "row": boss_row, "x": 0.5, "next": [], "kind": RunMap.KIND_BOSS, "enemy_count": 1, "enemies": []}
		map.nodes.append(boss)
		for id in last:
			map.nodes[id]["next"] = [boss["id"]]
		map.row_count = boss_row + 1
	_assign_enemies(map, rng, enemy_ramp, opts)
	return map

static func _assign_kinds(map: RunMap, rng: RandomNumberGenerator, elites_allowed: bool, odds: Dictionary = {}) -> void:
	var odd := func(key: String, fallback: float) -> float: return float(odds.get(key, _n(key, fallback)))
	var elite_min_row := int(odd.call("elite_min_row", 2))
	var last_ramp_row := map.row_count - 1
	var middle: Array[int] = []
	for n in map.nodes:
		if n["row"] == 0 or n["row"] == last_ramp_row:
			continue
		middle.append(n["id"])
		var roll := rng.randf()
		var kind := RunMap.KIND_FIGHT
		var repair: float = odd.call("repair_chance", 0.15)
		var shop: float = repair + odd.call("shop_chance", 0.12)
		var event: float = shop + odd.call("event_chance", 0.14)
		var elite: float = event + odd.call("elite_chance", 0.10)
		if roll < repair:
			kind = RunMap.KIND_REPAIR
		elif roll < shop:
			kind = RunMap.KIND_SHOP
		elif roll < event:
			kind = RunMap.KIND_EVENT
		elif roll < elite and elites_allowed and n["row"] >= elite_min_row:
			kind = RunMap.KIND_ELITE
		if kind != RunMap.KIND_FIGHT and not _neighbour_has_kind(map, n, kind):
			_set_kind(n, kind)
	var needed: Array = []
	for pair in [[RunMap.KIND_REPAIR, "repair_chance"], [RunMap.KIND_SHOP, "shop_chance"], [RunMap.KIND_EVENT, "event_chance"], [RunMap.KIND_ELITE, "elite_chance"]]:
		if float(odd.call(pair[1], 1.0)) > 0.0 and (pair[0] != RunMap.KIND_ELITE or elites_allowed):
			needed.append(pair[0])
	for kind in needed:
		if middle.is_empty() or middle.any(func(id): return map.nodes[id]["kind"] == kind):
			continue
		var fights := middle.filter(func(id): return map.nodes[id]["kind"] == RunMap.KIND_FIGHT \
			and not _neighbour_has_kind(map, map.nodes[id], kind) \
			and (kind != RunMap.KIND_ELITE or map.nodes[id]["row"] >= elite_min_row))
		if not fights.is_empty():
			_set_kind(map.nodes[fights[rng.randi_range(0, fights.size() - 1)]], kind)

## At most `most` stops of `kind`: the extra ones (picked at random) become
## fights. Shops are a detour you choose, Slay-the-Spire style (Logan,
## 2026-09-30: 1–3 a map); the one every map gets stays.
static func _cap_kind(map: RunMap, rng: RandomNumberGenerator, enemy_ramp: Array, kind: String, most: int) -> void:
	var ids: Array = []
	for n in map.nodes:
		if n["kind"] == kind:
			ids.append(n["id"])
	while ids.size() > most:
		var id: int = ids[rng.randi_range(0, ids.size() - 1)]
		ids.erase(id)
		_set_kind(map.nodes[id], RunMap.KIND_FIGHT)
		map.nodes[id]["enemy_count"] = int(enemy_ramp[map.nodes[id]["row"]])

## Picks elites, the boss and (without encounter pools) regular fights.
static func _assign_enemies(map: RunMap, rng: RandomNumberGenerator, enemy_ramp: Array, opts: Dictionary) -> void:
	var regulars: Array = opts.get("regulars", ["scrap_warden"])
	var elites: Array = opts.get("elites", [])
	var escort_from := int(opts.get("elite_escort_from_row", 99))
	var pools: bool = opts.get("encounter_pools", false)
	for n in map.nodes:
		var list: Array = []
		match n["kind"]:
			RunMap.KIND_FIGHT:
				if pools:
					n["enemies"] = []
					n["enemy_count"] = 0 # rolled on entry
					continue
				for i in range(int(enemy_ramp[n["row"]])):
					list.append(regulars[rng.randi() % regulars.size()])
			RunMap.KIND_ELITE:
				list.append(elites[rng.randi() % elites.size()] if not elites.is_empty() else regulars[0])
				if n["row"] >= escort_from:
					list.append(regulars[rng.randi() % regulars.size()])
			RunMap.KIND_BOSS:
				list.append(opts.get("boss_id", "anchor"))
		n["enemies"] = list
		n["enemy_count"] = list.size()

## Whether a node linked to `n` (into it or out of it) is already `kind`.
static func _neighbour_has_kind(map: RunMap, n: Dictionary, kind: String) -> bool:
	for to_id in n["next"]:
		if map.nodes[to_id]["kind"] == kind:
			return true
	for other in map.nodes:
		if other["kind"] == kind and (other["next"] as Array).has(n["id"]):
			return true
	return false

static func _set_kind(n: Dictionary, kind: String) -> void:
	n["kind"] = kind
	n["enemy_count"] = 0

static func _link_rows(map: RunMap, lower: Array[int], upper: Array[int], rng: RandomNumberGenerator) -> void:
	var n := lower.size()
	var m := upper.size()
	var partner: Array[int] = []
	for i in range(n):
		partner.append(roundi(float(i) * float(m - 1) / float(n - 1)) if n > 1 else (m - 1) / 2)
	var reached := {}
	for i in range(n):
		_add_link(map, lower[i], upper[partner[i]], reached)
		# A second link one to the right stays uncrossed as long as the next
		# node's partner isn't left of it.
		var right := partner[i] + 1
		var next_partner: int = partner[i + 1] if i + 1 < n else m - 1
		if right < m and right <= next_partner and rng.randf() < _n("branch_chance", 0.4):
			_add_link(map, lower[i], upper[right], reached)
	# Same-size rows map one to one: without a branch they'd run as parallel lanes.
	if n == m and n > 1 and not lower.any(func(id): return (map.nodes[id]["next"] as Array).size() > 1):
		var i := rng.randi_range(0, n - 2)
		_add_link(map, lower[i], upper[i + 1], reached)
	# Unreached nodes sit between two neighbours' partners: the left half of
	# such a gap links from the left node, the right half from the right one.
	for j in range(m):
		if reached.has(upper[j]):
			continue
		var left_i := 0
		for i in range(n):
			if partner[i] < j:
				left_i = i
		var right_i := mini(left_i + 1, n - 1)
		var lo: int = partner[left_i]
		var hi: int = partner[right_i]
		var from_i := left_i if (j - lo) <= (hi - j) else right_i
		_add_link(map, lower[from_i], upper[j], reached)

static func _add_link(map: RunMap, from_id: int, to_id: int, reached: Dictionary) -> void:
	var next: Array = map.nodes[from_id]["next"]
	if not next.has(to_id):
		next.append(to_id)
		next.sort()
	reached[to_id] = true

## Joins separate lanes: while the map falls into more than one connected
## piece, adds a link that crosses no other between two pieces.
static func _bridge_lanes(map: RunMap, rows: Array, rng: RandomNumberGenerator) -> void:
	for _guard in range(64):
		var comp := _components(map)
		var ids := {}
		for c in comp.values():
			ids[c] = true
		if ids.size() <= 1:
			return
		var candidates: Array = []
		for r in range(rows.size() - 1):
			var lower: Array = rows[r]
			var upper: Array = rows[r + 1]
			for a in range(lower.size()):
				for b in range(upper.size()):
					if comp[lower[a]] != comp[upper[b]] and not _crosses(map, lower, upper, a, b):
						candidates.append([lower[a], upper[b]])
		if candidates.is_empty():
			return
		var pick: Array = candidates[rng.randi_range(0, candidates.size() - 1)]
		_add_link(map, pick[0], pick[1], {})

## Node id -> the id of its connected piece (links followed both ways).
static func _components(map: RunMap) -> Dictionary:
	var parent := {}
	for n in map.nodes:
		parent[n["id"]] = n["id"]
	for n in map.nodes:
		for to in n["next"]:
			var ra: int = _root(parent, n["id"])
			var rb: int = _root(parent, to)
			if ra != rb:
				parent[ra] = rb
	var out := {}
	for n in map.nodes:
		out[n["id"]] = _root(parent, n["id"])
	return out

static func _root(parent: Dictionary, x: int) -> int:
	while parent[x] != x:
		x = parent[x]
	return x

## Whether a link from lower[a] to upper[b] would cross an existing one.
static func _crosses(map: RunMap, lower: Array, upper: Array, a: int, b: int) -> bool:
	for i in range(lower.size()):
		for to in map.nodes[lower[i]]["next"]:
			var j := upper.find(to)
			if j < 0:
				continue
			if (i < a and j > b) or (i > a and j < b):
				return true
	return false

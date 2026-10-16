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
## Layout 2 (Logan, 2026-10-16: routes were either a web where every start
## reaches everything or a forced lane, a stop apart): Slay-the-Spire style
## walkers. The map has `columns` columns; `paths` walkers start on the
## bottom row (at least start_min different spots) and climb a row at a
## time, each step to the column left, ahead or right, never crossing a link
## already laid. The stops are the cells walked on, the links the steps
## taken, so routes fork and merge all the way up. A layout with a middle row
## of one stop (everyone forced through it) is rolled again. Then a stop with
## one way on gets a second (to a stop beside its first, never crossing) at
## `walk_branch_chance`, and wherever a route would still run more than
## `max_forced` rows with one way on, it gets one: to a stop beside, or else
## to a new stop beside its lane that leads on into the row after. The mission
## picks the layout (`map_layout`, saved with the run): saves from before
## keep layout 1, the map they were made on.
##
## The numbers (row sizes, branch chance, columns, walkers, the odds of each
## stop kind) are in data/balance.json ("map").

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
	if int(opts.get("layout", 1)) >= 2:
		rows = _walk_layout(map, rng, enemy_ramp)
	for r in range(ramp_rows if rows.is_empty() else 0):
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
	if int(opts.get("layout", 1)) < 2:
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

## Layout 2: walkers climbing a grid of columns (see the top). Fills
## map.nodes and returns the rows (node ids, left to right).
static func _walk_layout(map: RunMap, rng: RandomNumberGenerator, enemy_ramp: Array) -> Array:
	var cols := int(_n("columns", 5))
	var walkers := int(_n("paths", 5))
	var starts_min := mini(int(_n("start_min", 3)), cols)
	var rows_n := enemy_ramp.size()
	var cells := {}  # Vector2i(col, row) -> true
	var steps := {}  # row -> [[from col, to col], ...]
	for _try in range(20):
		cells.clear()
		steps.clear()
		var order: Array = range(cols)
		_shuffle(order, rng)
		for w in range(walkers):
			var col: int = order[w] if w < starts_min else rng.randi_range(0, cols - 1)
			cells[Vector2i(col, 0)] = true
			for r in range(rows_n - 1):
				var row_steps: Array = steps.get(r, [])
				var options: Array = []
				for to in [col - 1, col, col + 1]:
					if to >= 0 and to < cols and not _step_crosses(row_steps, col, to):
						options.append(to)
				var nxt: int = options[rng.randi_range(0, options.size() - 1)] if not options.is_empty() else col
				if not row_steps.has([col, nxt]):
					row_steps.append([col, nxt])
				steps[r] = row_steps
				col = nxt
				cells[Vector2i(col, r + 1)] = true
		var pinched := false
		for r in range(1, rows_n - 1):
			if range(cols).filter(func(c): return cells.has(Vector2i(c, r))).size() < 2:
				pinched = true
		if not pinched:
			break
	_branch_walks(cells, steps, cols, rows_n, rng)
	var rows: Array = []
	var id_at := {}
	for r in range(rows_n):
		var ids: Array[int] = []
		for c in range(cols):
			if not cells.has(Vector2i(c, r)):
				continue
			var jitter := rng.randf_range(-0.15, 0.15) / float(cols)
			var node := {
				"id": map.nodes.size(), "row": r, "x": (float(c) + 0.5) / float(cols) + jitter,
				"next": [], "kind": RunMap.KIND_FIGHT, "enemy_count": int(enemy_ramp[r]), "enemies": [],
			}
			map.nodes.append(node)
			ids.append(node["id"])
			id_at[Vector2i(c, r)] = node["id"]
		rows.append(ids)
	for r in steps:
		for s in steps[r]:
			_add_link(map, id_at[Vector2i(s[0], r)], id_at[Vector2i(s[1], r + 1)], {})
	return rows

## Second ways on (see the top): by chance, then wherever a route would run
## more than max_forced rows with one way on, from the top down.
static func _branch_walks(cells: Dictionary, steps: Dictionary, cols: int, rows_n: int, rng: RandomNumberGenerator) -> void:
	var chance := _n("walk_branch_chance", 0.35)
	var cap := int(_n("max_forced", 2))
	for r in range(rows_n - 1):
		for c in range(cols):
			if cells.has(Vector2i(c, r)) and _outs(steps, r, c).size() == 1 and rng.randf() < chance:
				_branch(cells, steps, r, c, rng)
	var forced := {} # Vector2i -> rows in a row with one way on, from here up
	for r in range(rows_n - 2, -1, -1):
		for c in range(cols):
			if not cells.has(Vector2i(c, r)):
				continue
			var outs := _outs(steps, r, c)
			if outs.size() == 1:
				var run := 1 + int(forced.get(Vector2i(outs[0], r + 1), 0))
				if run > cap and (_branch(cells, steps, r, c, rng) or _branch_new(cells, steps, cols, rows_n, r, c, rng)):
					run = 0
				forced[Vector2i(c, r)] = run
			else:
				forced[Vector2i(c, r)] = 0

## The columns a stop at (c, r) links to.
static func _outs(steps: Dictionary, r: int, c: int) -> Array:
	return (steps.get(r, []) as Array).filter(func(s): return s[0] == c).map(func(s): return s[1])

## Adds a link from (c, r) to a stop beside its current one in the next row,
## if one is there and the link crosses none. True if it added one.
static func _branch(cells: Dictionary, steps: Dictionary, r: int, c: int, rng: RandomNumberGenerator) -> bool:
	var row_steps: Array = steps.get(r, [])
	var have := _outs(steps, r, c)
	var options: Array = []
	for to in [c - 1, c, c + 1]:
		if cells.has(Vector2i(to, r + 1)) and not have.has(to) and not _step_crosses(row_steps, c, to):
			options.append(to)
	if options.is_empty():
		return false
	row_steps.append([c, options[rng.randi_range(0, options.size() - 1)]])
	steps[r] = row_steps
	return true

## A new stop beside where (c, r) goes, linked from it and on to a stop in
## the row after (all without crossing). True if it fit.
static func _branch_new(cells: Dictionary, steps: Dictionary, cols: int, rows_n: int, r: int, c: int, rng: RandomNumberGenerator) -> bool:
	if r + 2 >= rows_n:
		return false
	var row_steps: Array = steps.get(r, [])
	var up_steps: Array = steps.get(r + 1, [])
	var sides: Array = [c - 1, c + 1]
	_shuffle(sides, rng)
	for to in sides:
		if to < 0 or to >= cols or cells.has(Vector2i(to, r + 1)) or _step_crosses(row_steps, c, to):
			continue
		var onward: Array = []
		for t2 in [to - 1, to, to + 1]:
			if cells.has(Vector2i(t2, r + 2)) and not _step_crosses(up_steps, to, t2):
				onward.append(t2)
		if onward.is_empty():
			continue
		cells[Vector2i(to, r + 1)] = true
		row_steps.append([c, to])
		steps[r] = row_steps
		up_steps.append([to, onward[rng.randi_range(0, onward.size() - 1)]])
		steps[r + 1] = up_steps
		return true
	return false

## Whether a step from column a to b crosses one already laid between the same rows.
static func _step_crosses(row_steps: Array, a: int, b: int) -> bool:
	for s in row_steps:
		if (s[0] < a and s[1] > b) or (s[0] > a and s[1] < b):
			return true
	return false

static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

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

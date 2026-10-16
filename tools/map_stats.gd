extends SceneTree
## How a map layout plays (MapGenerator): over many seeds, for each start,
## how much of the map it can still reach, how far apart the starts are in
## that, how many choices each step offers, and the longest run of forced
## steps (one way on) along any route.
##   Godot --headless --path . --script tools/map_stats.gd -- [seeds] [rows] [columns] [walkers] [branch chance]
## (columns / walkers / branch chance: try layout 2 with these instead of balance.json's)

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var seeds := int(args[0]) if args.size() > 0 else 300
	var rows := int(args[1]) if args.size() > 1 else 12
	var ramp := []
	for i in range(rows):
		ramp.append(1)
	if args.size() > 3:
		Balance.set_value("map", "columns", int(args[2]))
		Balance.set_value("map", "paths", int(args[3]))
	if args.size() > 4:
		Balance.set_value("map", "walk_branch_chance", float(args[4]))
	for layout in [1, 2]:
		var reach_sum := 0.0
		var spread_sum := 0.0
		var spread_max := 0.0
		var degree := {1: 0, 2: 0, 3: 0}
		var forced_sum := 0.0
		var forced_max := 0
		var per_row := 0.0
		var lanes := 0
		for s in range(1, seeds + 1):
			var rng := RandomNumberGenerator.new()
			rng.seed = s
			var map := MapGenerator.generate(rng, ramp, {"layout": layout})
			per_row += float(map.nodes.size()) / rows
			var lo := 1.0
			var hi := 0.0
			for start in map.nodes_in_row(0):
				var f := float(_reach(map, start["id"]).size()) / map.nodes.size()
				reach_sum += f
				lo = minf(lo, f)
				hi = maxf(hi, f)
			spread_sum += hi - lo
			spread_max = maxf(spread_max, hi - lo)
			for n in map.nodes:
				if not map.is_last_row(n["row"]):
					var d: int = mini((n["next"] as Array).size(), 3)
					degree[d] = int(degree.get(d, 0)) + 1
			var f_run := _longest_forced(map)
			forced_sum += f_run
			forced_max = maxi(forced_max, f_run)
			var pieces := {}
			for root in MapGenerator._components(map).values():
				pieces[root] = true
			if pieces.size() > 1:
				lanes += 1
		var total_deg: int = degree[1] + degree[2] + degree[3]
		print("layout %d: %.1f stops a row | a start reaches %.0f%% of the map on average, starts differ by %.0f%% (worst %.0f%%) | steps with 1 / 2 / 3 ways on: %.0f%% / %.0f%% / %.0f%% | longest forced run %.1f rows (worst %d) | maps in separate lanes: %d" % [
			layout, per_row / seeds, 100.0 * reach_sum / _starts_total(seeds, ramp, layout), 100.0 * spread_sum / seeds, 100.0 * spread_max,
			100.0 * degree[1] / total_deg, 100.0 * degree[2] / total_deg, 100.0 * degree[3] / total_deg,
			forced_sum / seeds, forced_max, lanes])
	quit()

func _starts_total(seeds: int, ramp: Array, layout: int) -> int:
	var n := 0
	for s in range(1, seeds + 1):
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		n += MapGenerator.generate(rng, ramp, {"layout": layout}).nodes_in_row(0).size()
	return n

## Every stop reachable from `id` (itself included).
func _reach(map: RunMap, id: int) -> Dictionary:
	var seen := {id: true}
	var todo := [id]
	while not todo.is_empty():
		var n: Dictionary = map.get_map_node(todo.pop_back())
		for to in n["next"]:
			if not seen.has(to):
				seen[to] = true
				todo.append(to)
	return seen

## The most rows in a row where the stop you're on has one way on.
func _longest_forced(map: RunMap) -> int:
	var best := {}
	var top := 0
	for r in range(map.row_count - 1, -1, -1):
		for n in map.nodes_in_row(r):
			var nexts: Array = n["next"]
			var run := 0
			if nexts.size() == 1:
				run = 1 + int(best.get(nexts[0], 0))
			best[n["id"]] = run
			top = maxi(top, run)
	return top

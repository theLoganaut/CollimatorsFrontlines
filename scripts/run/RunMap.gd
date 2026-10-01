class_name RunMap
extends RefCounted
## One location's encounter map (Slay the Spire style): rows of nodes from
## the bottom (row 0, the starting spots) to the top, each node linking to
## one or more nodes in the row above. Built by MapGenerator.
##
## A node is {id, row, x (0..1 across the map), next: Array[int] of node
## ids in the row above, kind, enemies: [mech ids], enemy_count}.

const KIND_FIGHT := "fight"
const KIND_REPAIR := "repair"   # repair bay: heal parts from a pool
const KIND_SHOP := "shop"       # autonomous bay: buy parts with scraps
const KIND_EVENT := "event"     # a choice with an outcome (data/events.json)
const KIND_ELITE := "elite"     # an elite fight
const KIND_BOSS := "boss"       # the boss stop at the top (Assault, Rescue)

## Stops fought through the combat screen.
static func is_fight(kind: String) -> bool:
	return kind in [KIND_FIGHT, KIND_ELITE, KIND_BOSS]

var nodes: Array[Dictionary] = []
var row_count: int = 0

func get_map_node(id: int) -> Dictionary:
	return nodes[id] if id >= 0 and id < nodes.size() else {}

func nodes_in_row(row: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in nodes:
		if n["row"] == row:
			out.append(n)
	return out

func is_last_row(row: int) -> bool:
	return row == row_count - 1

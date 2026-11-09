extends Node
## Dev tool: a playable standalone fight (no run, nothing saved) with extra
## parts bolted onto the player's mech, to try a rule by hand:
##   Godot --path . res://tools/TestFight.tscn -- [--mech=bastion] [--add=a|b,c (each: the first that fits)]
##        [--enemies=needle_drone] [--hp=N (each enemy part's HP is capped at N)]
## Default: Bastion plus a Freeze part (Lockdown Cannon, Grav Anchor or Thermal Spike Rifle) vs a
## Needle Drone, whose two acting parts show two intents: Freeze one, Shock or
## destroy the other, and watch the disrupt preview as you aim. An added part
## goes in the first free spot it fits; if none, one non-hardpoint
## part is taken out to make room. Restart (settings) deals a fresh copy.

var _mech_id := "bastion"
var _add: Array = ["lockdown_cannon|grav_anchor|thermal_spike_rifle"]
var _enemies: Array = ["needle_drone"]
var _hp := 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mech="):
			_mech_id = a.get_slice("=", 1)
		elif a.begins_with("--add="):
			_add = Array(a.get_slice("=", 1).split(",", false))
		elif a.begins_with("--enemies="):
			_enemies = Array(a.get_slice("=", 1).split(",", false))
		elif a.begins_with("--hp="):
			_hp = int(a.get_slice("=", 1))
	GameSettings.operator_tips = false
	RunState.run = null
	CombatScene.standalone_setup = _setup
	var inst: Node = load("res://scenes/CombatScene.tscn").instantiate()
	get_tree().root.add_child.call_deferred(inst)
	get_tree().set_deferred("current_scene", inst)

func _setup() -> Array:
	var m := GameData.fresh_mech("res://data/mechs/%s.json" % _mech_id)
	for alts in _add:
		var part: ComponentData = null
		for id in alts.split("|"): # "a|b": the first of them that fits
			part = _fit(m, id)
			if part != null:
				break
			for c in m.components.duplicate(): # else make room by taking out one non-hardpoint
				if c.category == ComponentData.CATEGORY_HARDPOINT:
					continue
				var at := m.components.find(c)
				m.components.erase(c)
				part = _fit(m, id)
				if part != null:
					print("test_fight: took out ", c.name, " to make room")
					break
				m.components.insert(at, c)
			if part != null:
				break
		if part == null:
			print("test_fight: no room for ", alts)
			continue
		m.components.append(part)
		print("test_fight: added ", part.name, ": ", part.cards.map(func(c): return c.name))
	var foes: Array[MechData] = []
	for e in _enemies:
		var foe := GameData.fresh_mech("res://data/mechs/%s.json" % e)
		if _hp > 0:
			for c in foe.components:
				c.current_hp = mini(c.current_hp, _hp)
		foes.append(foe)
	return [m, foes]

## `id` placed in the first free spot of `m`'s frame it fits, or null.
func _fit(m: MechData, id: String) -> ComponentData:
	var free := GridUtils.cells_to_set(m.cells)
	for c in m.components:
		for cell in c.placed_cells:
			free.erase(cell)
	for rot in range(4):
		for x in range(-4, 8):
			for y in range(-4, 8):
				var part := DataLoader.load_component({"id": id, "offset": [x, y], "rotation": rot})
				if part.placed_cells.all(func(cell): return free.has(cell)):
					var n := 2
					var iid := id
					while m.components.any(func(c): return c.id == iid):
						iid = "%s_%d" % [id, n]
						n += 1
					part.set_instance_id(iid)
					return part
	return null

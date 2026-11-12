extends SceneTree
# Runs Screenshot.tscn's warroom_right, then turns the War Room back to the middle wall
# with the Operator hidden before the shot is taken.
func _initialize() -> void:
	node_added.connect(_on_added)
	change_scene_to_file.call_deferred("res://tools/Screenshot.tscn")

func _on_added(n: Node) -> void:
	if n.get_script() and str(n.get_script().resource_path).ends_with("WarRoomScreen.gd"):
		_fix(n)

func _fix(wv: Node) -> void:
	await create_timer(2.2).timeout
	wv._pan_to(0, true)
	wv._operator.visible = false
	print("middle wall, operator hidden")

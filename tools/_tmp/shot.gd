extends SceneTree
func _initialize() -> void:
	var d := WhatsNewDialog.new()
	d._showing_next = true
	root.add_child(d)
	for i in 30: await process_frame
	root.get_viewport().get_texture().get_image().save_png("/private/tmp/claude-501/-Users-logan-collimators--frontlines/cf96351a-9f45-460a-9831-a54050666a7d/scratchpad/roadmap.png")
	print("saved")
	quit()

## Saves frames of the studio intro at set times, to check its look:
## Godot --path . --resolution 1920x1080 -s tools/intro_capture.gd -- <out dir> [seconds...]
extends SceneTree
var intro: Node
var times := [0.6, 1.8, 2.4, 2.75, 2.9, 3.1, 3.4, 4.5, 7.0]
var out := OS.get_cmdline_user_args()[0]
func _initialize() -> void:
	if OS.get_cmdline_user_args().size() > 1:
		times = Array(OS.get_cmdline_user_args().slice(1)).map(func(a): return float(a))
	intro = load("res://scenes/TrismegIntro.tscn").instantiate()
	root.add_child(intro)
func _process(_d: float) -> bool:
	if times.is_empty():
		quit()
		return true
	if intro._t >= times[0]:
		root.get_texture().get_image().save_png("%s/t_%.2f.png" % [out, intro._t])
		times.pop_front()
	return false

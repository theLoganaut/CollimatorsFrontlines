class_name SwapFx
extends Control
## Scramble / Transmute in the opening refit (Logan, 2026-09-29): the old
## part lifts off the chassis and grows a little, collapses into an orb of
## energy, the orb drifts over to Cargo, and the new part comes out of it and
## settles into its Cargo squares. Drawn with the parts' own art (PartArt);
## emits `finished` once the new part is down, then frees itself.

signal finished()

const GAP := 3.0

var old_part: ComponentData # placed in its old turn, at offset 0
var new_part: ComponentData # placed in its Cargo turn, at offset 0
var old_cell: float = 40.0
var new_cell: float = 40.0

var part_pos := Vector2.ZERO
var part_scale: float = 1.0
var part_alpha: float = 1.0
var showing_new: bool = false
var orb_pos := Vector2.ZERO
var orb_r: float = 0.0
var orb_a: float = 0.0
var _t: float = 0.0

## `old` / `new`: the parts (only their shape, turn and art are used).
func setup(old: ComponentData, old_rotation: int, p_old_cell: float, new: ComponentData, p_new_cell: float) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	old_part = old.clone()
	old_part.place(old_rotation, Vector2i.ZERO)
	new_part = new.clone()
	new_part.place(new.rotation_steps, Vector2i.ZERO)
	old_cell = p_old_cell
	new_cell = p_new_cell

## Plays from the old part's centre to the new part's centre (this control's
## coordinates), after `delay` seconds (the old part sits in place till then).
func play(from: Vector2, to: Vector2, delay: float = 0.0) -> void:
	part_pos = from
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func(): Audio.play("holo", 0.05))
	# picked up, a little bigger
	tw.tween_property(self, "part_pos", from + Vector2(0, -28), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "part_scale", 1.25, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.15)
	# into an orb of energy
	tw.tween_callback(func(): orb_pos = part_pos; Audio.play("shield", 0.05))
	tw.tween_property(self, "part_scale", 0.12, 0.3).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "part_alpha", 0.0, 0.3).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "orb_r", 20.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "orb_a", 1.0, 0.2)
	tw.tween_interval(0.25)
	# over to Cargo
	tw.tween_property(self, "orb_pos", to + Vector2(0, -28), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# the new part comes out
	tw.tween_callback(func():
		showing_new = true
		part_pos = orb_pos
		part_scale = 0.12
		Audio.play("prime", 0.05))
	tw.tween_property(self, "part_scale", 1.25, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "part_alpha", 1.0, 0.2)
	tw.parallel().tween_property(self, "orb_r", 0.0, 0.32)
	tw.parallel().tween_property(self, "orb_a", 0.0, 0.32)
	tw.tween_interval(0.2)
	# set down in its squares
	tw.tween_property(self, "part_pos", to, 0.28).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "part_scale", 1.0, 0.28)
	tw.tween_callback(func():
		Audio.play("card", 0.05)
		finished.emit()
		queue_free())

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	if orb_a > 0.0 and orb_r > 0.0:
		_draw_orb()
	if part_alpha > 0.0:
		var part := new_part if showing_new else old_part
		var cs := new_cell if showing_new else old_cell
		var dims := Vector2i.ZERO
		for c in part.placed_cells:
			dims = Vector2i(maxi(dims.x, c.x + 1), maxi(dims.y, c.y + 1))
		# scaled by hand: PartArt resets the canvas transform after each tile
		var step := (cs + GAP) * part_scale
		var half := Vector2(dims.y, dims.x) * step / 2.0
		var glow := Palette.category_color(part.category)
		for c in part.placed_cells:
			var r := Rect2(part_pos + Vector2(c.y, c.x) * step - half, Vector2(cs, cs) * part_scale)
			draw_rect(r.grow(3.0 * part_scale), Color(glow, 0.18 * part_alpha), true)
			PartArt.draw_part_cell(self, r, part, c, part_alpha)

func _draw_orb() -> void:
	var core := Color("eefcfa")
	for i in range(5):
		draw_circle(orb_pos, orb_r * (2.2 - i * 0.3), Color(GlassPanel.HOLO, 0.08 * orb_a))
	var pulse := 1.0 + 0.08 * sin(_t * 18.0)
	draw_circle(orb_pos, orb_r * pulse, Color(GlassPanel.HOLO, 0.55 * orb_a))
	draw_circle(orb_pos, orb_r * 0.55 * pulse, Color(core, 0.9 * orb_a))
	# crackling arcs around it
	for i in range(6):
		var a := _t * 5.0 + i * TAU / 6.0 + sin(_t * 11.0 + i) * 0.6
		var p1 := orb_pos + Vector2.from_angle(a) * orb_r * 0.9
		var p2 := orb_pos + Vector2.from_angle(a + 0.35) * orb_r * (1.35 + 0.25 * sin(_t * 23.0 + i))
		var p3 := orb_pos + Vector2.from_angle(a + 0.6) * orb_r * 1.1
		draw_polyline(PackedVector2Array([p1, p2, p3]), Color(Palette.LINK if i % 2 == 0 else core, 0.8 * orb_a), 1.5, true)

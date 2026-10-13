extends WorkshopScreen
## Repair bay (Logan, 2026-09-27), in the field repair station
## (assets/run/repair_bay.png), laid out like the other workshops: the
## chassis on the left, the part preview on top, the mech as a hologram on
## the pad. A pool of 50% of the mech's max HP to hand out: hold the mouse on
## a damaged part to heal it slowly, and the pool drains as it goes.
## Destroyed parts can't be repaired. Whatever's left in the pool is lost on
## leaving. The right screen shows the pool and every damaged part, with
## Repair all (fewest HP missing first, so the most parts end up whole) and
## Even out (the most worn part first, a point at a time).

const CHASSIS_MAX := Vector2(306, 420)
const CHASSIS_CELL := 52.0
const HEAL_PER_SECOND := 24.0 # Proposed
const POOL_BAR := Rect2(14, 64, 302, 14)

var _grid: PackingGrid
var _info: Label
var _pool_label: Label
var _pool_bar: Control
var _damaged: VBoxContainer
var _holding: bool = false
var _heal_carry: float = 0.0
var _hovered: ComponentData = null
var _pool_max: int = 1
var _preview_timer: float = 0.0

func screen_phase() -> String:
	return RunData.PHASE_REPAIR

func screen_title() -> String:
	return "Repair Bay"

func bay_art() -> String:
	return "res://assets/run/repair_bay.png"

func pad_center() -> Vector2:
	return Vector2(310, 318)

func leave_text() -> String:
	return "Leave the bay"

func has_bench() -> bool:
	return false

func _build_left() -> void:
	_pool_max = maxi(run.repair_pool, 1)
	var title := UIKit.label("CHASSIS  ·  %s  ·  hold on a part to repair it" % run.player_mech.name.to_upper(), 11, Color("b9d8d4"))
	title.position = Vector2(12, 10)
	_left.add_child(title)
	_grid = PackingGrid.new()
	_grid.part_pressed.connect(func(_g, _p, _c): _holding = true)
	_grid.part_hovered.connect(_on_hovered)
	_left.add_child(_grid)
	_info = UIKit.label("", 11, Color("9fb9b6"), true)
	_info.size = Vector2(LEFT.size.x - 24, 40)
	_left.add_child(_info)
	var hint := UIKit.label("Destroyed parts can't be repaired. What's left in the pool is lost when you leave.", 11, Color("7f9d9a"), true)
	hint.position = Vector2(12, LEFT.size.y - 52)
	hint.size = Vector2(LEFT.size.x - 24, 40)
	_left.add_child(hint)

func _build_right_panel() -> void:
	var head := UIKit.label("REPAIR POOL", 11, Color("b9d8d4"))
	head.position = Vector2(12, 10)
	_right.add_child(head)
	_pool_label = UIKit.label("", 22, Palette.OK)
	_pool_label.position = Vector2(12, 28)
	_right.add_child(_pool_label)
	_pool_bar = Control.new()
	_pool_bar.position = POOL_BAR.position
	_pool_bar.size = POOL_BAR.size
	_pool_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pool_bar.draw.connect(_draw_pool_bar)
	_right.add_child(_pool_bar)
	var all := GlassPanel.button("Repair all", 13, false, Palette.OK)
	all.position = Vector2(12, 88)
	all.size = Vector2(147, 32)
	all.tooltip_text = "Pour the pool into damaged parts, the ones missing the least first, so the most parts end up whole."
	all.pressed.connect(_quick_repair.bind(true))
	_right.add_child(all)
	var even := GlassPanel.button("Even out", 13, false, Palette.OK)
	even.position = Vector2(171, 88)
	even.size = Vector2(147, 32)
	even.tooltip_text = "Raise whichever part is most worn, a point at a time, so no part is left near breaking."
	even.pressed.connect(_quick_repair.bind(false))
	_right.add_child(even)
	var dh := UIKit.label("DAMAGED PARTS", 11, Color("b9d8d4"))
	dh.position = Vector2(12, 132)
	_right.add_child(dh)
	_damaged = VBoxContainer.new()
	_damaged.position = Vector2(12, 154)
	_damaged.size = Vector2(RIGHT.size.x - 24, RIGHT.size.y - 166)
	_damaged.add_theme_constant_override("separation", 4)
	_right.add_child(_damaged)

func _draw_pool_bar() -> void:
	var r := Rect2(Vector2.ZERO, _pool_bar.size)
	_pool_bar.draw_rect(r, Color(0, 0, 0, 0.4), true)
	var f := clampf(float(run.repair_pool) / _pool_max, 0.0, 1.0)
	_pool_bar.draw_rect(Rect2(r.position, Vector2(r.size.x * f, r.size.y)), Color(Palette.OK, 0.75), true)
	_pool_bar.draw_rect(r, Color(Palette.OK, 0.6), false, 1.0)

func _after_build() -> void:
	_say("Hold the mouse on a damaged part to repair it.")
	set_process(true)

static func _bounds_of(cells: Array[Vector2i]) -> Vector2i:
	var b := Vector2i.ZERO
	for c in cells:
		b = Vector2i(maxi(b.x, c.x + 1), maxi(b.y, c.y + 1))
	return b

func _refresh_extra() -> void:
	var m := run.player_mech
	var b := _bounds_of(m.cells)
	var cell := minf(CHASSIS_CELL, minf((CHASSIS_MAX.x + PackingGrid.GAP) / b.y, (CHASSIS_MAX.y + PackingGrid.GAP) / b.x) - PackingGrid.GAP)
	if _grid.cell_size != floorf(cell) or _grid.parts != m.components:
		_grid.setup(run.chassis_cells(), b, floorf(cell))
		_grid.set_parts(m.components)
		_grid.position = Vector2(floorf((LEFT.size.x - _grid.size.x) / 2.0), 34)
	_grid.queue_redraw()
	_info.position = Vector2(12, _grid.position.y + _grid.size.y + 10.0)
	_info.text = "%d / %d HP" % [m.current_hp(), m.max_hp()]
	_pool_label.text = "%d HP left" % run.repair_pool
	_pool_bar.queue_redraw()
	_refresh_damaged()

func _refresh_damaged() -> void:
	for c in _damaged.get_children():
		c.queue_free()
	var any := false
	for c in run.player_mech.components:
		if c.destroyed or c.current_hp < c.max_hp:
			any = true
			var l := UIKit.label("%s  ·  %s" % [c.name, "destroyed" if c.destroyed else "%d / %d HP" % [c.current_hp, c.max_hp]], 12, Palette.DANGER if c.destroyed else Palette.WARNING)
			_damaged.add_child(l)
	if not any:
		_damaged.add_child(UIKit.label("Every part is at full HP.", 12, Color("9fb9b6")))

func _quick_repair(all: bool) -> void:
	var healed := run.repair_all() if all else run.repair_even()
	if healed <= 0:
		Audio.play("denied", 0.0)
		_say("Nothing to repair." if run.repair_pool > 0 else "The pool is empty.", Palette.TEXT_MUTED)
		return
	Audio.play("vent")
	_say("Repaired %d HP." % healed, Palette.OK)
	_refresh()

func _on_hovered(_g: PackingGrid, part: ComponentData) -> void:
	_hovered = part
	if part != null:
		_preview.show_part(part)

func _process(delta: float) -> void:
	if not _holding:
		return
	if not Gamepad.left_held():
		_holding = false
		_heal_carry = 0.0
		if _hovered != null:
			_preview.show_part(_hovered)
		return
	var part := _grid.part_at(_grid.cell_at_global(get_global_mouse_position()))
	if part == null or part.destroyed or part.current_hp >= part.max_hp or run.repair_pool <= 0:
		return
	_heal_carry += HEAL_PER_SECOND * delta
	var n := int(_heal_carry)
	if n <= 0:
		return
	_heal_carry -= n
	run.repair(part, n)
	_refresh()
	_preview_timer -= delta
	if _preview_timer <= 0.0:
		_preview_timer = 0.12
		_preview.show_part(part)
		_say("Repairing %s: %d / %d HP." % [part.name, part.current_hp, part.max_hp], Palette.OK)

## Repair HP left in the pool while a part is still damaged.
func leave_warnings() -> Array[String]:
	var out := super()
	var missing := 0
	for c in run.player_mech.non_destroyed_components():
		missing += c.max_hp - c.current_hp
	if run.repair_pool > 0 and missing > 0:
		out.append("%d HP of repairs is unused and your parts are missing %d" % [run.repair_pool, missing])
	return out

func _on_leave() -> void:
	if SceneRouter.is_busy() or not _confirm_leave():
		return
	run.finish_repair()
	RunState.advance()

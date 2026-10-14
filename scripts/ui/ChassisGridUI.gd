class_name ChassisGridUI
extends Control
## Reusable grid: lays out one ComponentCellUI per chassis cell for a given
## MechData, manually positioned (not a GridContainer — chassis shapes are
## sparse and irregular, see Chassis page). Used for both the player and
## every enemy (Combat Slice §6). No assumption that a component's own
## cells are contiguous (Targeting Computer isn't).
##
## Also owns each component's *displayed* HP: when real HP changes, the
## shown number counts down through every value quickly instead of jumping,
## and a component only draws as Destroyed once its count reaches 0.
##
## The grid is faint over the mech's art until it matters: the mouse is on
## it, one of its parts is targeted, it's spotlit (the passive reveal), or an
## attack card is dragged over its aim area (an enemy's panel). The part
## under the mouse gets a yellow outline around its outer edges. While the
## mouse is on it (or aiming at it) the mech's sprite behind it fades, so
## the parts' art stands out.

const HP_TICK_SECONDS := 0.035 # per HP point counted down
const HP_ANIM_MIN := 0.12
const HP_ANIM_MAX := 0.7
const FAINT_ALPHA := 0.35
const FADE_SPEED := 6.0 # alpha per second
const BACKDROP_ALPHA := 0.35 # the mech's sprite while the grid is hovered
const HOVER_OUTLINE := 2.0

var mech: MechData
var cell_size: float = 24.0
var gap: float = 3.0
## Fully visible regardless of the mouse (the opening passive reveal).
var spotlight: bool = false
## While an attack card is dragged, the mouse anywhere over this control
## (an enemy's whole panel) shows the grid too.
var aim_area: Control = null
## The mech's sprite under the grid, faded while the grid is hovered (null = none).
var backdrop: CanvasItem = null

var _cells: Dictionary = {} # Vector2i -> ComponentCellUI
var _cells_by_component: Dictionary = {} # ComponentData -> Array[ComponentCellUI]
var _shown_hp: Dictionary = {} # ComponentData -> int
var _hp_tweens: Dictionary = {} # ComponentData -> Tween
var _targeted: ComponentData = null
var _status_lit: String = ""
var _covering: ComponentData = null # the cover part that will actually take the hit
## The part an aimed attack would destroy: pulses red (sure) or amber (might).
var _doomed: ComponentData = null
var _doomed_sure: bool = false
var _t: float = 0.0
var _hovered: ComponentData = null # the part under the mouse (outlined)
## The part whose card is hovered in the hand (outlined like a hover).
var linked: ComponentData = null
var _outline: Control

func setup(p_mech: MechData, p_cell_size: float = 24.0) -> void:
	mech = p_mech
	cell_size = p_cell_size
	mouse_filter = Control.MOUSE_FILTER_PASS
	modulate.a = FAINT_ALPHA
	_rebuild()

func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_cells.clear()
	_cells_by_component.clear()
	_shown_hp.clear()
	if mech == null:
		return

	var occupied: Dictionary = {} # Vector2i -> ComponentData
	for c in mech.components:
		_shown_hp[c] = c.current_hp
		_cells_by_component[c] = []
		for cell in c.placed_cells:
			occupied[cell] = c

	var max_row := 0
	var max_col := 0
	for cell in mech.cells:
		max_row = maxi(max_row, cell.x)
		max_col = maxi(max_col, cell.y)

	for cell in mech.cells:
		var cell_ui := ComponentCellUI.new()
		add_child(cell_ui)
		var comp: ComponentData = occupied.get(cell, null)
		cell_ui.position = Vector2(cell.y, cell.x) * (cell_size + gap)
		cell_ui.custom_minimum_size = Vector2(cell_size, cell_size)
		cell_ui.size = Vector2(cell_size, cell_size)
		cell_ui.setup(cell, comp, mech, self)
		_cells[cell] = cell_ui
		if comp != null:
			_cells_by_component[comp].append(cell_ui)

	custom_minimum_size = Vector2(max_col + 1, max_row + 1) * (cell_size + gap) - Vector2(gap, gap)
	size = custom_minimum_size

	_hovered = null
	_outline = Control.new() # last, so it draws over the cells
	_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outline.size = size
	_outline.draw.connect(_draw_hover_outline)
	add_child(_outline)

func _process(delta: float) -> void:
	var hovered_ctrl := get_viewport().gui_get_hovered_control()
	var over_grid := hovered_ctrl != null and (hovered_ctrl == self or is_ancestor_of(hovered_ctrl))
	var aiming := aim_area != null and UIState.is_dragging_attack_card() \
		and aim_area.get_global_rect().has_point(get_global_mouse_position())
	var lit := spotlight or over_grid or aiming or _targeted != null or linked != null or _status_lit != ""
	modulate.a = move_toward(modulate.a, 1.0 if lit else FAINT_ALPHA, FADE_SPEED * delta)
	if backdrop != null:
		var faded := over_grid or aiming
		backdrop.modulate.a = move_toward(backdrop.modulate.a, BACKDROP_ALPHA if faded else 1.0, FADE_SPEED * delta)

	var part: ComponentData = null
	if hovered_ctrl is ComponentCellUI and hovered_ctrl.grid == self and UIState.dragging_card == null:
		part = hovered_ctrl.component
	if part != _hovered:
		_hovered = part
		_outline.queue_redraw()
	if _doomed != null:
		_t += delta
		_outline.queue_redraw()

## A yellow line around the hovered part's outer edges (not around each of
## its cells): every cell side facing off the part, drawn in the gap outside
## it and run on across the gap wherever the part continues, so the line is
## unbroken around the whole shape.
func _draw_hover_outline() -> void:
	if _doomed != null:
		var k := 0.75 if GameSettings.reduce_motion else 0.55 + 0.35 * sin(_t * 6.0)
		var col: Color = Palette.DANGER if _doomed_sure else Palette.WARNING
		for cell in _doomed.placed_cells:
			var r := Rect2(Vector2(cell.y, cell.x) * (cell_size + gap), Vector2(cell_size, cell_size))
			_outline.draw_rect(r, Color(col, 0.35 * k), true)
			_outline.draw_rect(r, Color(col, k), false, 2.0)
	var part := _hovered if _hovered != null else linked
	if part == null:
		return
	var cells: Dictionary = {}
	for cell in part.placed_cells:
		cells[cell] = true
	var w := HOVER_OUTLINE
	var step := cell_size + gap
	for cell in cells:
		var r := Rect2(Vector2(cell.y, cell.x) * step, Vector2(cell_size, cell_size))
		# Each side: [neighbor off that side, the two neighbors along it (before, after)].
		for side in [[Vector2i(-1, 0), Vector2i(0, -1), Vector2i(0, 1)], [Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)],
				[Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0)], [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]]:
			if cells.has(cell + side[0]):
				continue
			var before: float = gap if cells.has(cell + side[1]) else w
			var after: float = gap if cells.has(cell + side[2]) else w
			var off: Vector2i = side[0] # (row, col)
			var edge: Rect2
			if off.x != 0: # top or bottom
				edge = Rect2(r.position.x - before, r.position.y - w if off.x < 0 else r.end.y, r.size.x + before + after, w)
			else: # left or right
				edge = Rect2(r.position.x - w if off.y < 0 else r.end.x, r.position.y - before, w, r.size.y + before + after)
			_outline.draw_rect(edge, Palette.LINK, true)

func set_linked(component: ComponentData) -> void:
	if component != linked:
		linked = component
		_outline.queue_redraw()

func shown_hp(component: ComponentData) -> int:
	return _shown_hp.get(component, component.current_hp)

## Syncs every cell to the mech's current state, animating any HP change.
func refresh_all() -> void:
	for c in _cells_by_component.keys():
		var shown := shown_hp(c)
		if shown != c.current_hp:
			_animate_hp(c, shown, c.current_hp)
	for cell_ui in _cells.values():
		cell_ui.refresh()

func _animate_hp(component: ComponentData, from: int, to: int) -> void:
	var old: Tween = _hp_tweens.get(component, null)
	if old != null:
		old.kill()
	var duration := clampf(absi(to - from) * HP_TICK_SECONDS, HP_ANIM_MIN, HP_ANIM_MAX)
	var tw := create_tween()
	tw.tween_method(_set_shown_hp.bind(component), float(from), float(to), duration)
	_hp_tweens[component] = tw

func _set_shown_hp(value: float, component: ComponentData) -> void:
	var v := roundi(value)
	if _shown_hp.get(component, -1) == v:
		return
	_shown_hp[component] = v
	_refresh_component_cells(component)

## A status just landed on `component`: its markers pop.
func pop_status(component: ComponentData) -> void:
	for cell_ui in _cells_by_component.get(component, []):
		cell_ui.pop_status()

func _refresh_component_cells(component: ComponentData) -> void:
	for cell_ui in _cells_by_component.get(component, []):
		cell_ui.refresh()

## The cell under a global point (the gaps between cells count toward the
## nearest cell, so a crosshair between two cells of a part still hits it).
func cell_at(global_point: Vector2) -> ComponentCellUI:
	for cell_ui in _cells.values():
		if cell_ui.get_global_rect().grow(gap / 2.0).has_point(global_point):
			return cell_ui
	return null

func is_targeted(component: ComponentData) -> bool:
	return component != null and component == _targeted

func is_covering(component: ComponentData) -> bool:
	return component != null and component == _covering

## Outlines every cell of one component as the current crosshair target, and
## the cover part that would take the hit instead, if any (null clears).
## A hovered status (UIState.status_hover_changed): every part holding it
## lights in its colour; a mech-wide one (Absorb, Deflect, Smoke) lights the
## whole mech. "" clears.
func set_status_lit(status: String) -> void:
	if status == _status_lit:
		return
	_status_lit = status
	refresh_all()

func status_lit(component: ComponentData) -> bool:
	if _status_lit == "" or component == null or component.destroyed:
		return false
	if CardResolver.MECH_STATUSES.has(_status_lit):
		return mech.mech_status_stacks(_status_lit) > 0
	return component.status_stacks(_status_lit) > 0

func lit_status() -> String:
	return _status_lit

func set_targeted(component: ComponentData) -> void:
	var covering: ComponentData = mech.cover_for(component) if component != null else null
	if component == _targeted and covering == _covering:
		return
	var previous := [_targeted, _covering]
	_targeted = component
	_covering = covering
	for c in previous + [component, covering]:
		if c != null:
			_refresh_component_cells(c)

## Marks the part an aimed attack would destroy (`sure`), or might (null clears).
func set_doomed(component: ComponentData, sure: bool = false) -> void:
	if component == _doomed and sure == _doomed_sure:
		return
	_doomed = component
	_doomed_sure = sure
	_t = 0.0
	_outline.queue_redraw()

## A brief white flash over every cell of a component (a hit landing).
func flash(component: ComponentData) -> void:
	for cell_ui in _cells_by_component.get(component, []):
		cell_ui.flash()

## Global center of the component's cell nearest its centroid — a point
## that's always on the part itself, even for a non-contiguous one.
func component_center_global(component: ComponentData) -> Vector2:
	var cells: Array = _cells_by_component.get(component, [])
	if cells.is_empty():
		return get_global_rect().get_center()
	var centroid := Vector2.ZERO
	for cell_ui in cells:
		centroid += cell_ui.get_global_rect().get_center()
	centroid /= float(cells.size())
	var best: Vector2 = cells[0].get_global_rect().get_center()
	for cell_ui in cells:
		var c: Vector2 = cell_ui.get_global_rect().get_center()
		if c.distance_to(centroid) < best.distance_to(centroid):
			best = c
	return best

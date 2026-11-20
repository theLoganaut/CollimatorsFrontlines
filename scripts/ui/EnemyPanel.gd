class_name EnemyPanel
extends Control
## One enemy slot, everything above the sprite so its feet can stand on the
## floor (Logan, 2026-10-16), from the sprite up: the mech image with its
## part grid laid over it → a health bar exactly as wide as the image, with
## the heat box to its left, bottoms aligned → its badge row (passives,
## statuses, a primed protocol; PassiveRow) → its intents → its name bar.
## As the fight opens the name sits where the badges go, right over the
## health bar; once its passives are revealed it rises to the top and the
## badges and intents appear under it (show_full).
## The grid is faint at rest and fully visible while the mouse is on it, an
## attack card's crosshair is over this panel, or its passives are being
## revealed (see ChassisGridUI).
##
## The panel's origin is the heat box's left edge; IMAGE_X is where the
## mech image (and so the "unit") starts. Place panels by image center
## using image_center_offset().
##
## The image shows the enemy's sprite (MechArt). Elites are drawn bigger than
## regulars and bosses bigger still, and the rows above the image (health
## bar, passives, intents) follow its width.

const IMAGE_SIZE := Vector2(180, 160) # a regular's
const TIER_SCALE := {"elite": 1.15, "boss": 1.3}
const HEAT_BOX_SIZE := Vector2(44, 32)
const HEAT_GAP := 6.0
const IMAGE_X := HEAT_BOX_SIZE.x + HEAT_GAP
const NAME_BAR_H := 24.0
const HP_BAR_H := 20.0
const INTENT_GAP := 12.0 # room for the little order chevrons between icons
const CELL_SIZE := 28.0

var mech: MechData
var display_name: String = ""
## This enemy's image size (IMAGE_SIZE scaled by its tier) and the rows above it.
var image_size: Vector2 = IMAGE_SIZE
var intent_y: float # what this enemy plans to do next turn, in order, under its name
var passive_y: float
var hp_bar_y: float
var image_y: float
## Before the reveal: the name and health bar sit right on the image.
var _compact_shift: float = 0.0
var _full: bool = true
var panel_size: Vector2
var grid: ChassisGridUI

var _name_bar: Control
var _acting: bool = false
var _name_label: Label
var _image_rect: ColorRect
var _sprite: TextureRect
var _heat_box: HeatBox
var _health_bar: HealthBar
var _defeated_label: Label
var _intent_row: Control
## Its passives, statuses (its own and its parts') and a primed protocol.
var passive_row: PassiveRow
var defeat_played: bool = false

func image_center_offset() -> Vector2:
	return Vector2(IMAGE_X + image_size.x / 2.0, image_y + image_size.y / 2.0)

## Where this enemy's feet are from the panel's origin: the lowest pixel of
## its sprite (the image's bottom without art), centered. The sprite is
## square and fills the image's height.
func feet_offset() -> Vector2:
	var bottom := image_size.y
	if _sprite != null:
		bottom -= MechArt.bottom_inset(MechArt.enemy(mech.id)) * image_size.y # the still sprite
	return Vector2(IMAGE_X + image_size.x / 2.0, image_y + bottom)

func _ready() -> void:
	# its rect reaches over its neighbours' rows: only its children take the mouse
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func setup(p_mech: MechData, p_display_name: String) -> void:
	mech = p_mech
	display_name = p_display_name
	image_size = (IMAGE_SIZE * float(TIER_SCALE.get(mech.tier, 1.0))).round()
	intent_y = NAME_BAR_H + 8.0
	passive_y = intent_y + IntentIcon.ICON_SIZE.y + 6.0 + PassiveRow.NUMBER_ROOM # stack numbers over the badges
	hp_bar_y = passive_y + PassiveIcon.ICON_SIZE.y + 6.0
	image_y = hp_bar_y + HP_BAR_H + 8.0
	_compact_shift = hp_bar_y - 6.0 - NAME_BAR_H # the name, before the reveal: just over the health bar
	panel_size = Vector2(IMAGE_X + image_size.x, image_y + image_size.y)
	custom_minimum_size = panel_size
	size = panel_size
	_build_children()
	refresh()

func _build_children() -> void:
	# The name plate looks like a hardpoint card's face (Logan, 2026-10-02):
	# dark holo glass washed and edged in the hardpoint orange, with brackets.
	_name_bar = Control.new()
	_name_bar.position = Vector2(IMAGE_X, 0)
	_name_bar.size = Vector2(image_size.x, NAME_BAR_H)
	_name_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_bar.draw.connect(_draw_name_bar)
	add_child(_name_bar)

	_name_label = Label.new()
	_name_label.position = _name_bar.position
	_name_label.size = _name_bar.size
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 14)
	_name_label.add_theme_color_override("font_color", Color("eefcfa"))
	_name_label.text = display_name
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)

	var image_pos := Vector2(IMAGE_X, image_y)
	_image_rect = ColorRect.new()
	_image_rect.position = image_pos
	_image_rect.size = image_size
	_image_rect.color = Palette.PANEL_2
	_image_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_image_rect)
	_sprite = MechArt.enemy_sprite(mech.id, image_size) # animated if it has a strip
	if _sprite != null:
		_image_rect.color = Color.TRANSPARENT # the sprite stands on the field
		_image_rect.add_child(_sprite)

	grid = ChassisGridUI.new()
	# Bigger frames (elites 5×5, bosses 6×6) get smaller cells to fit the image.
	var frame := 0
	for c in mech.cells:
		frame = maxi(frame, maxi(c.x, c.y) + 1)
	var cell := minf(CELL_SIZE, floorf((image_size.y - 12.0) / float(maxi(frame, 1))) - 3.0)
	grid.setup(mech, cell)
	grid.position = image_pos + (image_size - grid.size) / 2.0
	grid.aim_area = self
	grid.backdrop = _sprite
	add_child(grid)

	_health_bar = HealthBar.new()
	_health_bar.position = Vector2(IMAGE_X, hp_bar_y)
	_health_bar.size = Vector2(image_size.x, HP_BAR_H)
	_health_bar.threshold = mech.defeat_hp_threshold()
	_health_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	UIState.describe_on_hover(_health_bar, func(): return ["%s: %d / %d HP" % [display_name, mech.current_hp(), mech.max_hp()],
		"Destroyed at %d HP (the dark red end of the bar), or once all its hardpoints are." % mech.defeat_hp_threshold()
		+ ("" if mech.threat <= 0 else " Threat %d (%s): the chevrons on its name plate." % [mech.threat, Threat.level_name(mech.threat)])])
	add_child(_health_bar)

	_heat_box = HeatBox.new()
	add_child(_heat_box)
	_heat_box.custom_minimum_size = HEAT_BOX_SIZE
	_heat_box.size = HEAT_BOX_SIZE
	_heat_box.position = Vector2(0, hp_bar_y + HP_BAR_H - HEAT_BOX_SIZE.y) # bottoms aligned

	_intent_row = Control.new()
	_intent_row.position = Vector2(IMAGE_X, intent_y)
	_intent_row.size = Vector2(image_size.x, IntentIcon.ICON_SIZE.y)
	_intent_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intent_row.draw.connect(_draw_intent_chevrons)
	add_child(_intent_row)

	_defeated_label = Label.new()
	_defeated_label.position = image_pos
	_defeated_label.size = image_size
	_defeated_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_defeated_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_defeated_label.add_theme_font_size_override("font_size", 20)
	_defeated_label.add_theme_color_override("font_color", Palette.DANGER)
	_defeated_label.text = "DESTROYED"
	_defeated_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_defeated_label.visible = false
	add_child(_defeated_label)

	# The badge row last, over the grid: its overflow opens over the image.
	passive_row = PassiveRow.new()
	passive_row.numbers_below = false
	passive_row.part_statuses = true # Shock on a weapon...: the grid is faint at rest
	passive_row.position = Vector2(IMAGE_X, passive_y)
	add_child(passive_row)
	passive_row.setup(mech, image_size.x)
	passive_row.expanded_changed.connect(func(open: bool): _health_bar.visible = not open) # its overflow opens over the bar
	_set_full(false, false)

## The opening layout (full = false: the name and health bar on the image,
## no intents or badges) or the fight's.
func show_full() -> void:
	_set_full(true, true)

func _set_full(on: bool, animated: bool) -> void:
	if on == _full:
		return
	_full = on
	var y := 0.0 if on else _compact_shift
	for node in [_name_bar, _name_label]:
		if animated and not GameSettings.reduce_motion:
			node.create_tween().tween_property(node, "position:y", y, 0.35).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
		else:
			node.position.y = y
	for node in [_intent_row, passive_row]:
		if node == passive_row and mech != null and mech.is_defeated():
			continue
		if animated:
			node.modulate.a = 0.0
			node.visible = true
			node.create_tween().tween_property(node, "modulate:a", 1.0, 0.3).set_delay(0.2)
		else:
			node.visible = on

func refresh() -> void:
	if mech == null:
		return
	_heat_box.set_heat(mech.current_heat, mech.heat_capacity())
	_health_bar.set_hp(mech.current_hp(), mech.max_hp())
	grid.refresh_all()
	passive_row.refresh()
	_defeated_label.visible = mech.is_defeated()
	if mech.is_defeated(): # no statuses or protocol over the wreck
		passive_row.visible = false

## A primed protocol's badge on the badge row ([title, text]; [] hides it).
func set_protocol(info: Array) -> void:
	passive_row.set_protocol(info)

## Shows the upcoming actions ([{card, active, target}], in order) as
## icons centered over the mech image, plus a flame when the plan will
## overheat it. Hovering an icon shows what it'll do and to which part.
## `venting`: it has nothing to play and spends its turn venting (shown
## as its one intent).
func set_intents(actions: Array, overheat: bool = false, venting: bool = false) -> void:
	for child in _intent_row.get_children():
		_intent_row.remove_child(child)
		child.queue_free()
	if actions.is_empty() and venting:
		var v := IntentIcon.new()
		v.position = Vector2((image_size.x - IntentIcon.ICON_SIZE.x) / 2.0, 0)
		_intent_row.add_child(v)
		v.setup(IntentIcon.INTENT_VENT, false)
		_intent_row.queue_redraw()
		return
	var n := actions.size() + (1 if overheat and not actions.is_empty() else 0)
	var step := IntentIcon.ICON_SIZE.x + INTENT_GAP
	var x0 := (image_size.x - (n * IntentIcon.ICON_SIZE.x + (n - 1) * INTENT_GAP)) / 2.0
	for i in range(actions.size()):
		var icon := IntentIcon.new()
		icon.position = Vector2(x0 + i * step, 0)
		var a: Dictionary = actions[i]
		var comp: ComponentData = a.get("component", null)
		icon.cancelled = a.get("cancelled", false)
		icon.charged = a.get("charged", false)
		icon.added = a.get("added", false)
		icon.weakened = comp != null and comp.status_stacks("shock") > 0 and (a["card"] as CardData).hits > 0
		if a.get("charge", false):
			# Charge shows only "charging", never what (Decided).
			icon.charging_part = comp.name if comp != null else ""
			_intent_row.add_child(icon)
			icon.setup(IntentIcon.INTENT_CHARGE, a["active"])
			continue
		icon.intent = {"mech": mech, "card": a["card"], "target": a.get("target", null),
			"cancelled": icon.cancelled, "weakened": icon.weakened, "charged": icon.charged, "added": icon.added}
		_intent_row.add_child(icon)
		icon.setup((a["card"] as CardData).intent(), a["active"])
	if n > actions.size():
		var warn := IntentIcon.new()
		warn.position = Vector2(x0 + actions.size() * step, 0)
		_intent_row.add_child(warn)
		warn.setup(IntentIcon.INTENT_OVERHEAT, false)
	_intent_row.queue_redraw()

## The aimed card's marks on the intents (CombatAttack.preview_plan, in
## set_intents' order; [] clears them).
func preview_intents(marks: Array[String]) -> void:
	var icons := _intent_row.get_children()
	for i in range(icons.size()):
		(icons[i] as IntentIcon).set_preview(marks[i] if i < marks.size() else "")

func _draw_intent_chevrons() -> void:
	# No theme word ("GUARD", "AFFLICT"...) beside them: the icons say it (Logan, 2026-10-16).
	var icons := _intent_row.get_children()
	for i in range(icons.size() - 1):
		if (icons[i + 1] as IntentIcon).kind == IntentIcon.INTENT_OVERHEAT:
			continue
		var x: float = icons[i].position.x + IntentIcon.ICON_SIZE.x + INTENT_GAP / 2.0
		var y := IntentIcon.ICON_SIZE.y / 2.0
		_intent_row.draw_polyline(PackedVector2Array([Vector2(x - 2, y - 4), Vector2(x + 2, y), Vector2(x - 2, y + 4)]), Palette.TEXT_MUTED, 1.5, true)

## A hovered part's HP lit on the health bar (0 clears it).
func highlight_hp(amount: int) -> void:
	_health_bar.set_highlight(amount)

## The HP an aimed attack would take off, on the health bar (0 clears it).
func preview_damage(lo: int, hi: int) -> void:
	_health_bar.set_preview_loss(lo, hi)

func image_global_rect() -> Rect2:
	return _image_rect.get_global_rect()

## Defeated: the sprite flashes white, then sinks a little and dims with
## the grid while DESTROYED punches in (CombatScene adds the blasts).
func play_defeated() -> void:
	defeat_played = true
	_defeated_label.visible = true
	_defeated_label.pivot_offset = _defeated_label.size / 2.0
	_defeated_label.scale = Vector2(2.2, 2.2)
	_image_rect.modulate = Color(2.6, 2.6, 2.6)
	var tw := create_tween()
	tw.tween_property(_image_rect, "modulate", Color(1.4, 0.8, 0.6), 0.18)
	tw.set_parallel(true)
	tw.tween_property(_defeated_label, "scale", Vector2.ONE, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_image_rect, "modulate", Color(1, 1, 1, 0.45), 0.7).set_delay(0.25)
	tw.tween_property(_image_rect, "position:y", _image_rect.position.y + 10.0, 0.7).set_delay(0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(grid, "self_modulate:a", 0.45, 0.4)

## Retreated (nothing left to play): no blasts, it backs off and fades
## under RETREATED.
func play_retreated() -> void:
	defeat_played = true
	_defeated_label.text = "RETREATED"
	_defeated_label.add_theme_color_override("font_color", Palette.TEXT_MUTED)
	_defeated_label.visible = true
	_defeated_label.modulate.a = 0.0
	_image_rect.pivot_offset = Vector2(_image_rect.size.x / 2.0, _image_rect.size.y) # shrinks toward its feet
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_defeated_label, "modulate:a", 1.0, 0.3)
	tw.tween_property(_image_rect, "modulate", Color(1, 1, 1, 0.3), 0.9)
	tw.tween_property(_image_rect, "scale", Vector2(0.85, 0.85), 0.9).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_image_rect, "position:y", _image_rect.position.y - 14.0, 0.9).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(grid, "self_modulate:a", 0.3, 0.6)

# ---------- a boss's phase 2 ----------

## How much bigger a boss's phase-2 form stands (it grows from its feet).
const P2_SCALE := 1.15
const P2_CHARGE_TIME := 0.9 # it shudders and flares before it changes
const P2_BURN_TIME := 1.1   # the new form burns in over the old, feet first

## Pixel dissolve for the change: each pixel shows once `progress` passes
## its threshold (noise, rising from the feet), and the line where they meet
## burns in `edge_color`. `reverse` dissolves the old form away instead.
const DISSOLVE_SHADER := """
shader_type canvas_item;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform bool reverse = false;
uniform vec4 edge_color : source_color = vec4(1.0, 0.45, 0.15, 1.0);
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	vec2 px = floor(UV / TEXTURE_PIXEL_SIZE);
	float h = clamp(hash(px) * 0.5 + (1.0 - UV.y) * 0.5, 0.0, 1.0);
	bool shown = reverse ? h >= progress : h < progress;
	if (!shown) {
		c.a = 0.0;
	} else if (abs(h - progress) < 0.07 && progress > 0.0 && progress < 1.0) {
		c.rgb = mix(c.rgb, edge_color.rgb * 1.6, 0.85);
	}
	COLOR = c;
}
"""

var _aura: TextureRect = null
var in_phase2_form: bool = false

## A boss enters phase 2: its phase-2 form (MechArt.enemy_phase2) replaces
## the sprite, bigger, with a pulsing aura in `tint`. Animated: it shudders
## and flares, then the new form burns in pixel by pixel from the feet up
## while the old one burns away, and it flashes as it settles. Reduce motion
## (or not animated): a quick crossfade. Without phase-2 art it keeps its
## sprite and only gains the aura.
func play_phase2(animate: bool, tint: Color) -> void:
	if in_phase2_form:
		return
	in_phase2_form = true
	var settings := get_node_or_null("/root/GameSettings")
	var still: bool = settings != null and settings.reduce_motion
	var old := _sprite
	var neo: TextureRect = MechArt.enemy_sprite(mech.id, image_size, true) if MechArt.enemy_phase2(mech.id) != null else null
	if neo == null:
		if old != null:
			_add_aura(old, tint, still)
		return
	_stand_phase2(neo)
	_image_rect.add_child(neo)
	_sprite = neo
	grid.backdrop = neo
	if old == null:
		_add_aura(neo, tint, still)
		return
	if not animate or still:
		neo.modulate.a = 0.0
		var fade := create_tween().set_parallel(true)
		fade.tween_property(old, "modulate:a", 0.0, 0.35)
		fade.tween_property(neo, "modulate:a", 1.0, 0.35)
		fade.chain().tween_callback(old.queue_free)
		_add_aura(neo, tint, still)
		return
	# hidden until it burns in; the old form keeps its place meanwhile
	var burn_in := ShaderMaterial.new()
	burn_in.shader = _dissolve_shader()
	burn_in.set_shader_parameter("edge_color", tint)
	neo.material = burn_in
	var burn_out := ShaderMaterial.new()
	burn_out.shader = burn_in.shader
	burn_out.set_shader_parameter("edge_color", tint)
	burn_out.set_shader_parameter("reverse", true)
	old.material = burn_out
	var target_scale := neo.scale
	neo.scale = Vector2.ONE
	var home := old.position
	var tw := create_tween()
	# charge: it shudders and flares three times, harder each time
	for i in range(3):
		var k := float(i + 1) / 3.0
		tw.tween_property(_image_rect, "modulate", Color(1.0 + 0.6 * k, 1.0 + 0.3 * k, 1.0 + 0.2 * k), P2_CHARGE_TIME / 6.0)
		tw.parallel().tween_property(old, "position", home + Vector2(3.0 * k * (1 if i % 2 == 0 else -1), 0), P2_CHARGE_TIME / 6.0)
		tw.tween_property(_image_rect, "modulate", Color.WHITE, P2_CHARGE_TIME / 6.0)
		tw.parallel().tween_property(old, "position", home, P2_CHARGE_TIME / 6.0)
	# burn: the new form rises in from the feet as the old one goes, growing
	tw.tween_method(func(v: float) -> void:
		burn_in.set_shader_parameter("progress", v)
		burn_out.set_shader_parameter("progress", v), 0.0, 1.0, P2_BURN_TIME)
	tw.parallel().tween_property(neo, "scale", target_scale, P2_BURN_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	# settle: a flash, then it stands there
	tw.tween_property(_image_rect, "modulate", Color(2.4, 2.2, 2.0), 0.06)
	tw.tween_property(_image_rect, "modulate", Color.WHITE, 0.45)
	tw.tween_callback(func() -> void:
		old.queue_free()
		neo.material = null
		_add_aura(neo, tint, still))

static var _dissolve: Shader = null

static func _dissolve_shader() -> Shader:
	if _dissolve == null:
		_dissolve = Shader.new()
		_dissolve.code = DISSOLVE_SHADER
	return _dissolve

## The phase-2 sprite stands where the old one did: its lowest pixel on the
## same line, grown P2_SCALE from there.
func _stand_phase2(neo: TextureRect) -> void:
	var p1 := MechArt.enemy(mech.id)
	var p2 := MechArt.enemy_phase2(mech.id)
	var inset1 := MechArt.bottom_inset(p1) if p1 != null else 0.0
	var inset2 := MechArt.bottom_inset(p2)
	neo.position.y += (inset2 - inset1) * neo.size.y
	neo.pivot_offset = Vector2(neo.size.x / 2.0, neo.size.y * (1.0 - inset2))
	neo.scale = Vector2(P2_SCALE, P2_SCALE)

## A glow of the sprite in `tint` behind it, breathing slowly (still with
## Reduce motion).
func _add_aura(over: TextureRect, tint: Color, still: bool) -> void:
	_aura = TextureRect.new()
	_aura.texture = over.texture # the same AtlasTexture: it animates with the sprite
	_aura.size = over.size
	_aura.position = over.position
	_aura.expand_mode = over.expand_mode
	_aura.stretch_mode = over.stretch_mode
	_aura.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_aura.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aura.pivot_offset = over.pivot_offset
	_aura.scale = over.scale * 1.06
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_aura.material = add
	_aura.modulate = Color(tint.r, tint.g, tint.b, 0.3)
	_image_rect.add_child(_aura)
	if over.get_parent() == _image_rect:
		_image_rect.move_child(_aura, over.get_index())
	if not still:
		var tw := _aura.create_tween().set_loops()
		tw.tween_property(_aura, "modulate:a", 0.5, 1.1).set_trans(Tween.TRANS_SINE)
		tw.tween_property(_aura, "modulate:a", 0.15, 1.1).set_trans(Tween.TRANS_SINE)

## Highlights the name bar while this enemy is taking its turn.
func set_acting(acting: bool) -> void:
	_acting = acting
	_name_bar.queue_redraw()

func _draw_name_bar() -> void:
	var r := Rect2(Vector2.ZERO, _name_bar.size)
	var accent := Palette.HARDPOINT
	_name_bar.draw_rect(r, Color(0.015, 0.03, 0.04, 0.9), true)
	GlassPanel.draw_glass(_name_bar, r, 1.0, accent, 6.0, 0.85)
	_name_bar.draw_rect(r, Color(accent, 1.0 if _acting else 0.9), false, 2.5 if _acting else 1.5)
	if _acting:
		_name_bar.draw_rect(r.grow(3.0), Color(accent, 0.3), false, 2.0)
	if mech.tier != "regular": # elites and bosses: a tag in the corner
		var tag := mech.tier.to_upper()
		_name_bar.draw_string(get_theme_default_font(), Vector2(r.end.x - 52, r.size.y - 7), tag, HORIZONTAL_ALIGNMENT_RIGHT, 46, 9, Color(Palette.LINK, 0.9))
	# the run's threat level: a rank chevron per level, stacked at the left (Veterans)
	for i in range(mech.threat):
		var y := r.size.y - 7.0 - i * 3.0
		var x := 9.0
		_name_bar.draw_polyline(PackedVector2Array([Vector2(x - 4.0, y), Vector2(x, y - 3.0), Vector2(x + 4.0, y)]), Palette.WARNING, 1.4, true)

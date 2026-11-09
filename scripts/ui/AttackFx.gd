class_name AttackFx
extends Control
## Attack animations: PixelLab sprite sheets (assets/fx/<name>.png + .json,
## made in PixelLab's effects tool) played from the firing part to the part
## it hits. Which animation a card plays belongs to its hardpoint
## (data/attack_fx.json), so a part looks the same on the player's mech and
## an enemy's. CombatScene plays them on one layer over the enemies and under
## the player's mech, so an enemy's shot lands on the mech's front and the
## player's comes out from behind it (from its front). Coordinates are global
## (the layer sits at the origin and covers the screen).
##
## Per hit, launch() starts the attack and says how long until it lands; the
## scene resolves the hit then and calls land() on each part it struck. With
## Reduce motion on nothing flies (no shots, sprays or beams) and launch()
## returns 0; the hit's own impact still plays.

## Every sheet drawn this much bigger than its mech's pixel scale (Logan,
## 2026-11-09: 1.5x, more impact). Sprays and beams still just reach their target.
const SIZE := 1.5
const SHOT_SPEED := 1500.0 # px/s
const BURST_SPEED := 1800.0
const MISSILE_SPEED := 750.0
const MORTAR_DROP := 320.0 # px above the target a shell falls from
const BEAM_SECONDS := 0.32
const SPRAY_FADE := 0.15

var _loops: Array[Node2D] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

# ---------- playing ----------

## Starts hit `i` (0-based) of an attack in `style` from `from` to `to`,
## `k_from` / `k_to` the pixel scale at each end (the mech's sprite size
## over its 128 px art). Returns the seconds until it lands.
func launch(style: String, from: Vector2, to: Vector2, k_from: float, k_to: float, i: int) -> float:
	if style == "":
		return 0.0
	var kind := style.get_slice(":", 0)
	var tint := style.get_slice(":", 1) if style.contains(":") else ""
	var dir := to - from
	var dist := maxf(dir.length(), 1.0)
	var ang := dir.angle()
	if GameSettings.reduce_motion:
		if kind == "slash" or kind == "smash":
			_strike(kind, to, k_to, i)
		return 0.0
	match kind:
		"shot", "burst":
			var heavy := kind == "shot"
			_play("muzzle_heavy" if heavy else "muzzle_small", from, ang, k_from * (1.0 if heavy else 0.9))
			var t := dist / (SHOT_SPEED if heavy else BURST_SPEED)
			_fly("round_heavy" if heavy else "round_small", from, to, k_from, k_to, t)
			return t
		"missile":
			var t := dist / MISSILE_SPEED
			_fly("missile", from, to, 0.55 * k_from, 0.55 * k_to, t, (1.0 if i % 2 == 0 else -1.0) * 0.22 * dist)
			return t
		"swarm":
			var longest := 0.0
			for n in range(3):
				var jitter := Vector2(randf_range(-18, 18), randf_range(-14, 14)) * k_to
				var t := dist / (MISSILE_SPEED * randf_range(0.9, 1.25))
				var wait := n * 0.07
				_fly("missile", from, to + jitter, 0.2 * k_from, 0.2 * k_to, t, randf_range(-0.35, 0.35) * dist, wait, n > 0)
				longest = maxf(longest, wait + t)
			return longest
		"mortar":
			_play("muzzle_heavy", from, -PI / 2.0, k_from)
			var top := to + Vector2(0, -MORTAR_DROP)
			_fly("missile", top, to, 0.55 * k_to, 0.55 * k_to, 0.3, 0.0, 0.25)
			return 0.55
		"spray":
			if i == 0:
				var fx := _play("spray_" + tint, from, ang + PI, k_from * 0.85) # drawn tip-first: turned round
				fx.scale.x = dist / float(AttackFxData.meta("spray").get("reach", 100.0)) # it reaches the target
				_loops.append(fx)
			return 0.18 if i == 0 else 0.0
		"slash", "smash":
			return _strike(kind, to, k_to, i)
		"beam":
			var fx := _play("beam_" + tint, from, ang, k_from * 0.6, BEAM_SECONDS)
			fx.scale.x = dist / float(AttackFxData.meta("beam").get("reach", 150.0))
			return 0.08
	return 0.0

## A hit landing on a part at `at` (each part it struck, the extra targets of
## a card that hits several too): the style's impact, if it has its own.
func land(style: String, at: Vector2, k: float) -> void:
	match style.get_slice(":", 0):
		"shot":
			_play("hit_heavy", at, 0.0, k)
		"burst":
			_play("hit_small", at + Vector2(randf_range(-6, 6), randf_range(-6, 6)) * k, 0.0, k * 0.8)
		"missile", "mortar":
			_play("explosion", at, 0.0, k * 0.7)
		"swarm":
			_play("explosion", at, 0.0, k * 0.4)
		"beam":
			_play("hit_small", at, 0.0, k * 0.7)

## The attack is over: sprays stop (a short fade).
func stop_loops() -> void:
	for fx in _loops:
		if is_instance_valid(fx):
			var tw := fx.create_tween()
			tw.tween_property(fx, "modulate:a", 0.0, SPRAY_FADE)
			tw.tween_callback(fx.queue_free)
	_loops.clear()

## Everything off at once (the fight restarted or ended).
func clear() -> void:
	_loops.clear()
	for c in get_children():
		c.queue_free()

## A blow at the target itself: the slash (mirrored on every other hit, so a
## flurry criss-crosses) or the smash. Returns when it connects.
func _strike(kind: String, at: Vector2, k: float, i: int) -> float:
	if kind == "slash":
		var fx := _play("slash", at, deg_to_rad(randf_range(-12, 12)), k * 1.3)
		if i % 2 == 1:
			fx.scale.x = -fx.scale.x
		return 0.12
	_play("smash", at, 0.0, k * 1.1)
	return 0.06

## One sheet at `at`, turned `ang`, `k` times its pixels; one-shots free
## themselves at their last frame, loops after `life` seconds (or when stopped).
func _play(sheet_name: String, at: Vector2, ang: float, k: float, life: float = -1.0) -> FxSprite:
	var fx := FxSprite.new()
	fx.setup(AttackFxData.sheet(sheet_name), AttackFxData.meta(sheet_name), life)
	fx.position = at - global_position
	fx.rotation = ang
	fx.scale = Vector2(k, k) * SIZE
	add_child(fx)
	return fx

## A projectile from `from` to `to` over `t` seconds, scaled k_from -> k_to
## (smaller as it flies away from the player), bowed `bend` px to one side,
## after `wait` seconds; it frees itself where it lands. `boom` = it makes
## its own small explosion there (a swarm's extra missiles).
func _fly(sheet_name: String, from: Vector2, to: Vector2, k_from: float, k_to: float, t: float, bend: float = 0.0, wait: float = 0.0, boom: bool = false) -> void:
	var fx := _play(sheet_name, from, (to - from).angle(), k_from)
	fx.visible = wait <= 0.0
	var a := from - global_position
	var b := to - global_position
	var mid := (a + b) / 2.0 + (b - a).orthogonal().normalized() * bend
	var step := func(u: float) -> void:
		if not is_instance_valid(fx):
			return
		var p := a.lerp(mid, u).lerp(mid.lerp(b, u), u) # quadratic curve
		var ahead := a.lerp(mid, u + 0.02).lerp(mid.lerp(b, u + 0.02), u + 0.02)
		fx.position = p
		if ahead != p:
			fx.rotation = (ahead - p).angle()
		var k := lerpf(k_from, k_to, u) * SIZE
		fx.scale = Vector2(k, k)
	var tw := fx.create_tween()
	if wait > 0.0:
		tw.tween_interval(wait)
		tw.tween_callback(func(): fx.visible = true)
	tw.tween_method(step, 0.0, 1.0, maxf(t, 0.01))
	if boom:
		tw.tween_callback(func(): _play("explosion", to, 0.0, k_to * 0.9))
	tw.tween_callback(fx.queue_free)

## One playing sheet.
class FxSprite extends Node2D:
	var _tex: Texture2D
	var _rects: Array[Rect2] = []
	var _ms := 70.0
	var _anchor := Vector2.ZERO
	var _loop := false
	var _life := -1.0
	var _t := 0.0
	var _frame := 0

	func setup(s: Dictionary, meta: Dictionary, life: float) -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if s.is_empty():
			return
		_tex = s["tex"]
		_rects = s["rects"]
		_ms = s["ms"]
		_anchor = meta.get("anchor", _rects[0].size / 2.0)
		_loop = meta.get("loop", false)
		_life = life

	func _process(delta: float) -> void:
		if _rects.is_empty():
			queue_free()
			return
		_t += delta
		var f := int(_t * 1000.0 / _ms)
		if _loop:
			_frame = f % _rects.size()
			if _life >= 0.0 and _t >= _life:
				queue_free()
		elif f >= _rects.size():
			queue_free()
			return
		else:
			_frame = f
		queue_redraw()

	func _draw() -> void:
		if _rects.is_empty():
			return
		var r: Rect2 = _rects[_frame]
		draw_texture_rect_region(_tex, Rect2(-_anchor, r.size), r)

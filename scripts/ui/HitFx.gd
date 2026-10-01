class_name HitFx
extends Control
## Hit feedback layer over the combat screen: screen shake, spark bursts,
## floating damage numbers and full-screen flashes. Coordinates are global
## (this layer sits at the origin and covers the screen).
##
## Shake is a "trauma" value (0–1) that decays; the offset is trauma² so
## small hits barely move the screen and big ones really kick. It moves the
## viewport's canvas transform, so every layer — reticles, dragged cards,
## numbers — shakes together. Off when the Screen shake setting is off.

const MAX_SHAKE := 14.0
const TRAUMA_DECAY := 1.8 # per second

var _trauma: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 150

func _exit_tree() -> void:
	get_viewport().canvas_transform = Transform2D.IDENTITY

func shake(amount: float) -> void:
	if GameSettings.screen_shake and not GameSettings.reduce_motion:
		_trauma = minf(1.0, _trauma + amount)

func _process(delta: float) -> void:
	if _trauma <= 0.0:
		return
	_trauma = maxf(0.0, _trauma - delta * TRAUMA_DECAY)
	var a := MAX_SHAKE * _trauma * _trauma
	var offset := Vector2(randf_range(-a, a), randf_range(-a, a)) if _trauma > 0.0 else Vector2.ZERO
	get_viewport().canvas_transform = Transform2D(0.0, offset)

## A hit landing at `global_point`: sparks, a number sized by the damage,
## and shake (more when it's the player getting hit).
func impact(global_point: Vector2, damage: int, color: Color, on_player: bool) -> void:
	sparks(global_point, color, 6 + mini(damage, 30) / 2, 1.0)
	var font_size := clampi(22 + damage / 2, 22, 40)
	# A little sideways jitter so back-to-back hits' numbers don't stack exactly.
	var jitter := Vector2(randf_range(-18.0, 18.0), randf_range(-6.0, 6.0))
	float_text(global_point + jitter, str(damage), Palette.DANGER if on_player else color, font_size)
	if on_player:
		shake(0.22 + damage / 45.0)
	else:
		shake(0.08 + damage / 90.0)

## Running totals by where they're shown: Vector2i -> Label.
var _totals: Dictionary = {}

## A multi-hit attack's total so far, above the part it's hitting: one
## label per part that counts up with each hit, then fades once the hits stop.
func running_total(global_point: Vector2, total: int, on_player: bool) -> void:
	var key := Vector2i(global_point.round())
	var l: Label = _totals.get(key, null)
	if l == null or not is_instance_valid(l):
		l = Label.new()
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 30)
		l.add_theme_color_override("font_color", Palette.DANGER if on_player else Palette.LINK)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 6)
		l.size = Vector2(200, 42)
		l.position = global_point - Vector2(100, 98)
		l.pivot_offset = l.size / 2.0
		add_child(l)
		_totals[key] = l
	l.text = "%d total" % total
	l.modulate.a = 1.0
	var old: Tween = l.get_meta("tween") if l.has_meta("tween") else null
	if old != null:
		old.kill()
	l.scale = Vector2(1.25, 1.25)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.12).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.9)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func(): _totals.erase(key); l.queue_free())
	l.set_meta("tween", tw)

## A part destroyed: a big burst in its color plus white, and a kick.
func part_destroyed(global_point: Vector2, color: Color) -> void:
	sparks(global_point, color, 36, 1.6)
	sparks(global_point, Color.WHITE, 14, 1.2)
	float_text(global_point + Vector2(0, 26), "DESTROYED", Palette.DANGER, 15)
	shake(0.45)

func float_text(global_point: Vector2, text: String, color: Color, font_size: int = 24) -> void:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	add_child(l)
	var w := maxf(160.0, get_theme_default_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 24.0)
	var lines := text.count("\n") + 1
	l.size = Vector2(w, (font_size + 6) * lines + 6)
	l.position = global_point - Vector2(w / 2.0, font_size + 10)
	l.pivot_offset = l.size / 2.0
	l.scale = Vector2(1.5, 1.5)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "scale", Vector2.ONE, 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(l, "position:y", l.position.y - 44.0, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.45)
	tw.chain().tween_callback(l.queue_free)

## A wrecked part keeps smoking for the rest of the fight: grey puffs
## drifting up and the odd ember (particles only). Off with reduce motion.
func smolder(global_point: Vector2) -> void:
	if GameSettings.reduce_motion:
		return
	var smoke := CPUParticles2D.new()
	smoke.position = global_point
	smoke.amount = 7
	smoke.lifetime = 1.8
	smoke.direction = Vector2(0, -1)
	smoke.spread = 18.0
	smoke.initial_velocity_min = 10.0
	smoke.initial_velocity_max = 26.0
	smoke.gravity = Vector2(4, -6)
	smoke.scale_amount_min = 3.0
	smoke.scale_amount_max = 7.0
	smoke.color = Color(0.45, 0.45, 0.48, 0.5)
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.55))
	fade.set_color(1, Color(1, 1, 1, 0))
	smoke.color_ramp = fade
	add_child(smoke)
	var embers := CPUParticles2D.new()
	embers.position = global_point
	embers.amount = 2
	embers.lifetime = 0.7
	embers.direction = Vector2(0, -1)
	embers.spread = 50.0
	embers.initial_velocity_min = 30.0
	embers.initial_velocity_max = 70.0
	embers.gravity = Vector2(0, 90)
	embers.scale_amount_min = 1.5
	embers.scale_amount_max = 2.5
	embers.color = Palette.HARDPOINT
	embers.color_ramp = fade
	add_child(embers)

## A one-shot burst of spark particles.
func sparks(global_point: Vector2, color: Color, amount: int, power: float) -> void:
	var p := CPUParticles2D.new()
	p.position = global_point
	p.amount = maxi(amount, 1)
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.55
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 90.0 * power
	p.initial_velocity_max = 260.0 * power
	p.gravity = Vector2(0, 520)
	p.damping_min = 40.0
	p.damping_max = 80.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.5 * power
	p.color = color
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	add_child(p)
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.3, false).timeout.connect(p.queue_free)

## A full-screen color flash that fades out (overheat, taking a big hit).
func flash_screen(color: Color, alpha: float = 0.3, duration: float = 0.35) -> void:
	var r := ColorRect.new()
	r.color = Color(color, alpha)
	r.size = size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	var tw := r.create_tween()
	tw.tween_property(r, "color:a", 0.0, duration)
	tw.tween_callback(r.queue_free)

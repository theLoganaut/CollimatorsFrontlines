class_name Hotspot
extends Control
## One station in the War Room: its piece of the room art (assets/warroom/),
## drawn in its rect. The mouse only counts over the art's opaque pixels, so
## where stations overlap (the Info Bay in front of the R&D rack) the one
## really under the cursor wins. Hovering brightens the art and outlines
## its shape in yellow; the War Room shows the station's HoloLabel from
## `anchor`, a fixed point on the station, wherever the mouse is on it.
## A station that isn't built yet still labels itself but ignores clicks.

signal pressed()
signal hover_changed(hovered: bool)

const OUTLINE := Palette.LINK
const OUTLINE_W := 2.0
const HOVER_BRIGHT := Color(1.12, 1.12, 1.12)

var id: String = ""
var title: String = ""
var subtitle: String = ""
var enabled: bool = true
## Label anchor in room coordinates (WarRoomScreen), and which way the
## label's panel grows from it: "up", "up_left", "up_right" or "right".
var anchor: Vector2 = Vector2.ZERO
var label_dir: String = "up"
## Extra drawing on top of the art (the dailies on the Directives glass,
## the sectors on the War Table): func(spot: Hotspot).
var draw_extra: Callable
## Off while the camera is zoomed into the table.
var interactive: bool = true:
	set(v):
		interactive = v
		if not v:
			_set_hover(false)

var texture: Texture2D
var _region: Rect2 # the part of `texture` this station draws
var _alpha: Image  # that part's pixels, for hit testing
var _outline: Array[PackedVector2Array] = []
var _hover: bool = false

## `region`: the station's pixels within `texture` (the whole texture when
## empty); `rect`: where they go, in room coordinates.
func setup(p_id: String, p_title: String, p_subtitle: String, p_enabled: bool, tex: Texture2D, rect: Rect2, region: Rect2 = Rect2()) -> void:
	id = p_id
	title = p_title
	subtitle = p_subtitle
	enabled = p_enabled
	texture = tex
	_region = region if region.has_area() else Rect2(Vector2.ZERO, tex.get_size())
	position = rect.position
	size = rect.size
	_alpha = tex.get_image().get_region(Rect2i(_region))
	if _alpha.is_compressed():
		_alpha.decompress()
	_outline = _trace_outline()

## Swaps the art (the Memorial Wall as trophies appear); same size.
func set_texture(tex: Texture2D) -> void:
	texture = tex
	queue_redraw()

func is_hovered() -> bool:
	return _hover

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_ARROW
	mouse_entered.connect(func(): _set_hover(true))
	mouse_exited.connect(func(): _set_hover(false))
	gui_input.connect(_on_gui_input)

## The art's pixels per local pixel.
func _px() -> Vector2:
	return _region.size / size

func _has_point(p: Vector2) -> bool:
	if not interactive or not Rect2(Vector2.ZERO, size).has_point(p):
		return false
	var ip := Vector2i((p * _px()).floor())
	ip = ip.clamp(Vector2i.ZERO, _alpha.get_size() - Vector2i.ONE)
	return _alpha.get_pixelv(ip).a > 0.5

## The outer edges of the art's opaque pixels, as closed local polylines.
func _trace_outline() -> Array[PackedVector2Array]:
	var bm := BitMap.new()
	bm.create_from_image_alpha(_alpha, 0.5)
	var out: Array[PackedVector2Array] = []
	var k := Vector2.ONE / _px()
	for poly in bm.opaque_to_polygons(Rect2i(Vector2i.ZERO, _alpha.get_size()), 1.0):
		if poly.size() < 3:
			continue
		var pts := PackedVector2Array()
		for p in poly:
			pts.append(p * k)
		pts.append(pts[0])
		out.append(pts)
	return out

func _set_hover(h: bool) -> void:
	if h == _hover:
		return
	_hover = h
	queue_redraw()
	hover_changed.emit(h)

func _on_gui_input(event: InputEvent) -> void:
	if enabled and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		accept_event()
		pressed.emit()

func _draw() -> void:
	draw_texture_rect_region(texture, Rect2(Vector2.ZERO, size), _region, HOVER_BRIGHT if _hover else Color.WHITE)
	if draw_extra.is_valid():
		draw_extra.call(self)
	if _hover:
		for pts in _outline:
			draw_polyline(pts, Color(OUTLINE, 0.25), OUTLINE_W * 3.0)
			draw_polyline(pts, OUTLINE, OUTLINE_W)

extends Node
## Autoload. Gamepad support. The game is built for the mouse (drags,
## hover, hotspots on pixel art), so the left stick drives the mouse cursor
## and A clicks: every screen works as it is, with no screen of its own to
## keep in step. The other buttons press the bound keys (GameSettings), so
## they follow rebinding:
##   Left stick           move the cursor (D-pad: slowly, for small targets)
##   A                    click (hold to drag)
##   B / Start            Esc: back, cancel, the settings menu
##   X / Y                Vent / End turn
##   LB / RB              combat: pick the previous / next playable card;
##                        elsewhere LB undoes a move, RB rotates a held part
##   Back (Select)        show / hide the combat log
##   Right stick          scroll
##   RT (hold)            Shift: fast-forward enemy turns, details if set to need Shift
## A screen can take buttons first (`handler`, with pad_button(button) ->
## bool): the combat screen does while a card is picked (A plays it, the
## D-pad steps its target, B puts it back). Joypad events are taken out of
## Godot's ui_* actions so its focus moves don't fight the cursor.

## The screen that sees buttons first (a node with pad_button(button) -> bool).
var handler: Node = null
## Logical pixels a second at full tilt (GameSettings.pad_cursor_speed scales it).
const SPEED := 1100.0
const DPAD_SPEED := 260.0
const DEADZONE := 0.18
const SCROLL_EVERY := 0.09 # seconds between wheel steps at full tilt
const TRIGGER_ON := 0.5

var _device: int = -1
var _a_down: bool = false
var _rt_down: bool = false
var _scroll_t: float = 0.0
var _cursor := Vector2(-1, -1)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # works in the (pausing) settings menu
	for action in InputMap.get_actions():
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
				InputMap.action_erase_event(action, ev)

## A held (a drag in progress), for code that polls the mouse button.
func a_held() -> bool:
	return _a_down

## Whether the left mouse button, or A on a pad, is held.
func left_held() -> bool:
	return _a_down or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		_device = event.device
		get_viewport().set_input_as_handled()
		_button(event.button_index, event.pressed)
	elif event is InputEventJoypadMotion:
		_device = event.device
		if event.axis == JOY_AXIS_TRIGGER_RIGHT:
			var on: bool = event.axis_value > TRIGGER_ON
			if on != _rt_down:
				_rt_down = on
				_key(KEY_SHIFT, on)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and not _a_down:
		_cursor = Vector2(-1, -1) # the real mouse moved: follow it from here

func _button(b: JoyButton, pressed: bool) -> void:
	if pressed and handler != null and is_instance_valid(handler) and handler.has_method("pad_button") and handler.pad_button(b):
		return
	match b:
		JOY_BUTTON_A:
			if pressed != _a_down:
				_a_down = pressed
				_mouse_button(MOUSE_BUTTON_LEFT, pressed)
		JOY_BUTTON_B, JOY_BUTTON_START:
			_tap(KEY_ESCAPE, pressed)
		JOY_BUTTON_Y:
			_tap(GameSettings.key("end_turn"), pressed)
		JOY_BUTTON_BACK:
			_tap(GameSettings.key("log"), pressed)
		JOY_BUTTON_RIGHT_SHOULDER:
			_tap(GameSettings.key("rotate"), pressed)
		JOY_BUTTON_LEFT_SHOULDER:
			_tap(GameSettings.key("undo"), pressed, true)

func _process(delta: float) -> void:
	if _device < 0:
		return
	var v := Vector2(Input.get_joy_axis(_device, JOY_AXIS_LEFT_X), Input.get_joy_axis(_device, JOY_AXIS_LEFT_Y))
	var move := Vector2.ZERO
	if v.length() > DEADZONE:
		var k := (v.length() - DEADZONE) / (1.0 - DEADZONE)
		move = v.normalized() * pow(minf(k, 1.0), 1.7) * SPEED * GameSettings.pad_cursor_speed
	var claimed: bool = handler != null and is_instance_valid(handler) and handler.has_method("pad_dpad_claimed") and handler.pad_dpad_claimed()
	if not claimed:
		var d := Vector2(
			float(Input.is_joy_button_pressed(_device, JOY_BUTTON_DPAD_RIGHT)) - float(Input.is_joy_button_pressed(_device, JOY_BUTTON_DPAD_LEFT)),
			float(Input.is_joy_button_pressed(_device, JOY_BUTTON_DPAD_DOWN)) - float(Input.is_joy_button_pressed(_device, JOY_BUTTON_DPAD_UP)))
		move += d * DPAD_SPEED * GameSettings.pad_cursor_speed
	if move != Vector2.ZERO:
		_move_cursor(move * delta / maxf(Engine.time_scale, 0.01)) # the same speed whatever the game speed
	var sy := Input.get_joy_axis(_device, JOY_AXIS_RIGHT_Y)
	_scroll_t -= delta / maxf(Engine.time_scale, 0.01)
	if absf(sy) > DEADZONE and _scroll_t <= 0.0:
		_scroll_t = SCROLL_EVERY / absf(sy)
		_mouse_button(MOUSE_BUTTON_WHEEL_DOWN if sy > 0 else MOUSE_BUTTON_WHEEL_UP, true)
		_mouse_button(MOUSE_BUTTON_WHEEL_DOWN if sy > 0 else MOUSE_BUTTON_WHEEL_UP, false)

## Moves the cursor (logical pixels): the real mouse pointer goes there, and
## the screen gets a mouse motion (holding the left button while A is down).
func _move_cursor(by: Vector2) -> void:
	var vp := get_viewport()
	var from := _cursor if _cursor.x >= 0.0 else vp.get_mouse_position()
	var rect := vp.get_visible_rect()
	var to := (from + by).clamp(rect.position, rect.end - Vector2.ONE)
	_cursor = to
	vp.warp_mouse(to)
	var ev := InputEventMouseMotion.new()
	ev.position = to
	ev.global_position = to
	ev.relative = to - from
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if _a_down else 0
	get_tree().root.push_input(ev, true)

func _mouse_button(index: MouseButton, pressed: bool) -> void:
	var at := _cursor if _cursor.x >= 0.0 else get_viewport().get_mouse_position()
	var ev := InputEventMouseButton.new()
	ev.position = at
	ev.global_position = at
	ev.button_index = index
	ev.pressed = pressed
	ev.factor = 1.0
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if _a_down else 0
	get_tree().root.push_input(ev, true)

## A key press or release, as if typed (Input sees it held, too).
func _tap(keycode: int, pressed: bool, ctrl: bool = false) -> void:
	if keycode == KEY_NONE:
		return
	_key(keycode, pressed, ctrl)

func _key(keycode: int, pressed: bool, ctrl: bool = false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = pressed
	ev.ctrl_pressed = ctrl
	ev.shift_pressed = keycode == KEY_SHIFT and pressed
	Input.parse_input_event(ev)

extends RunScreen
## An event stop (data/events.json, Claude's drafts for Logan to vet): the
## event's text and its choices; picking one shows what happened, then
## Continue moves on (or, for a choice that leads on, what happened so far
## and then the next step's text and choices). The event was picked when
## the stop was entered and is saved, so leaving and continuing shows the
## same one.

const PANEL_W := 620.0

var _content: VBoxContainer
var _title: Label
var _text: Label
var _choices: VBoxContainer
var _result: Label
var _continue: Button
var _backdrop: Texture2D = null

func screen_phase() -> String:
	return RunData.PHASE_EVENT

func screen_title() -> String:
	return "Event"

## The event's own scene (assets/events/<event id>.png), dimmed under the text.
func backdrop() -> Texture2D:
	return _backdrop

func _build() -> void:
	var path := "res://assets/events/%s.png" % run.event.get("id", "")
	_backdrop = load(path) if ResourceLoader.exists(path) else null
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 16)
	add_child(_content)
	_content.add_child(UIKit.label("EVENT", 12, Palette.LINK))
	_title = UIKit.label("", 28)
	_content.add_child(_title)
	_text = UIKit.label("", 16, Color("aab2c3"), true)
	_content.add_child(_text)
	_result = UIKit.label("", 16, Palette.TEXT, true)
	_content.add_child(_result)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 10)
	_content.add_child(_choices)
	var row := HBoxContainer.new()
	row.add_child(UIKit.spacer())
	_continue = UIKit.button("Continue", Palette.HARDPOINT, Vector2(170, 46))
	_continue.pressed.connect(_on_continue)
	row.add_child(_continue)
	_content.add_child(row)
	_refresh()

## The step's choices (an event with steps rebuilds them as it goes on).
func _build_choices() -> void:
	for c in _choices.get_children():
		c.queue_free()
	for v in RunEvents.visible_choices(run):
		# the choice and what it costs, now or in the next fight (EventOutcome)
		var b := UIKit.button(EventOutcome.button_text(v["choice"], RunEvents.has_alert(run)), Color.TRANSPARENT, Vector2(PANEL_W, 48), 16)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		for state in ["normal", "hover", "pressed", "disabled"]:
			var st: StyleBoxFlat = b.get_theme_stylebox(state).duplicate()
			st.content_margin_left = 16
			b.add_theme_stylebox_override(state, st)
		if not RunEvents.affordable(run, v["choice"]):
			b.disabled = true
			b.text += "  ·  not enough scraps"
		b.pressed.connect(_choose.bind(v["index"]))
		_choices.add_child(b)

func _layout(screen: Vector2) -> void:
	_content.position = Vector2((screen.x - PANEL_W) / 2.0, TOP_BAR_H + 60.0)
	_content.size = Vector2(PANEL_W, 0)

func _refresh() -> void:
	var def := RunEvents.current(run)
	var done: bool = run.event.get("resolved", false) or RunEvents.event_def(run).is_empty()
	_title.text = def.get("title", "Nothing here")
	_text.text = def.get("text", "") if not done else RunEvents.event_def(run).get("text", "")
	_result.text = run.event.get("result", "")
	_result.visible = _result.text != ""
	# mid-event, what happened so far reads before the next step's text
	var stepping: bool = not done and str(run.event.get("step", "")) != ""
	_content.move_child(_result, 2 if stepping else 3)
	_build_choices()
	_choices.visible = not done
	_continue.visible = done
	refresh_header()

func _choose(i: int) -> void:
	run.resolve_event(i)
	SaveGame.save(run)
	_refresh()

func _on_continue() -> void:
	if SceneRouter.is_busy():
		return
	run.finish_event()
	RunState.advance()

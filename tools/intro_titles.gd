extends SceneTree
## Renders the studio intro's title pieces (title_trismeg, title_studios) in
## FONT, at the cap height of the originals with LETTER spacing, and updates their size
## and pivot (centre of the baseline) in layout.json, so they land where the
## old ones did. Needs a window (not --headless):
## Godot --path . -s tools/intro_titles.gd [-- <font file in _preview/fonts>]

const DIR := "res://assets/intro/trismeg/"
const FONT := "Chomsky.otf"
const FILL := Color("#f3f3f8")

# text, cap height (px; the originals were 60 and 20), extra space between
# letters (px). Blackletter reads in mixed case, so a touch taller.
const TITLES := {
	"title_trismeg": ["Trismeg", 64.0, 1.0],
	"title_studios": ["Studio", 24.0, 2.0],
}

var _view: SubViewport
var _canvas: Node2D
var _jobs: Array = []
var _font: Font
var _wait := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var file: String = args[0] if args.size() > 0 else FONT
	var f := FontFile.new()
	f.load_dynamic_font(ProjectSettings.globalize_path(DIR + "_preview/fonts/" + file))
	_font = f
	_view = SubViewport.new()
	_view.size = Vector2i(1400, 400)
	_view.transparent_bg = true
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_view)
	_canvas = Node2D.new()
	_view.add_child(_canvas)
	_canvas.draw.connect(_draw_job)
	# each title twice: once plain to measure, once sized and spaced
	for id in TITLES:
		_jobs.append({"id": id, "size": 100, "spacing": 0.0, "measure": true})

func _process(_d: float) -> bool:
	if _jobs.is_empty():
		quit()
		return true
	_wait += 1
	if _wait == 1:
		_canvas.queue_redraw()
	if _wait < 4:
		return false
	_wait = 0
	var job: Dictionary = _jobs.pop_front()
	var img := _view.get_texture().get_image()
	var used := img.get_used_rect()
	var spec: Array = TITLES[job.id]
	if job.measure:
		# cap height = ink above the baseline; scale the size to match
		var cap := float(BASELINE - used.position.y)
		var size := int(round(float(job.size) * float(spec[1]) / cap))
		_jobs.push_front({"id": job.id, "size": size, "spacing": float(spec[2]), "measure": false})
	else:
		var piece := img.get_region(used)
		piece.save_png(ProjectSettings.globalize_path(DIR + job.id + ".png"))
		_set_layout(job.id, used.size, Vector2(used.size.x / 2.0, BASELINE - used.position.y))
		print("saved %s.png  %dx%d, font size %d, spacing %.1f" % [job.id, used.size.x, used.size.y, job.size, job.spacing])
	return false

const BASELINE := 250

var _current: Dictionary
func _draw_job() -> void:
	if _jobs.is_empty():
		return
	_current = _jobs[0]
	var spec: Array = TITLES[_current.id]
	var font := FontVariation.new()
	font.base_font = _font
	font.spacing_glyph = int(round(_current.spacing))
	_canvas.draw_string(font, Vector2(50, BASELINE), spec[0], HORIZONTAL_ALIGNMENT_LEFT, -1, _current.size, FILL)

func _set_layout(id: String, size: Vector2i, pivot: Vector2) -> void:
	var path := ProjectSettings.globalize_path(DIR + "layout.json")
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	layout.pieces[id].size = [size.x, size.y]
	layout.pieces[id].pivot_in_image = [snappedf(pivot.x, 0.1), snappedf(pivot.y, 0.1)]
	var out := FileAccess.open(path, FileAccess.WRITE)
	out.store_string(JSON.stringify(layout, "  ", false))

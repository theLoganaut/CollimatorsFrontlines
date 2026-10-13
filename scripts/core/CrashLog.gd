class_name CrashLog
extends Node
## Crash reports (Logan, 2026-10-01: a tester's game crashed about once a
## run, seemingly on hovering an enemy part; it never has for Logan).
## Autoload `CrashWatch`, first in the list so it's up before anything loads.
## - While the game runs, a session file says so (this machine's OS, GPU,
##   graphics API) and is touched every HEARTBEAT seconds; a clean quit
##   removes it. Found at the next launch, the last session ended without
##   quitting: a crash, a freeze the player closed, or a force-quit (the
##   editor's Stop button too).
## - A trail of what the player just did (screens, hovered parts, cards and
##   intents, cards played, turns; crumb()) and every engine or script error
##   with its backtrace goes to disk line by line, flushed at once, so it
##   outlives a crash.
## A crash found at launch is written up (session, verdict, trail, the end
## of that session's Godot log) as <stamp>_crash.txt in the playtest reports
## folder; a run continued after it lists it in RunData.resumes, and its
## playtest report carries the text (PlaytestReport).

const SESSION_DIR := "user://session"
const LOCK := SESSION_DIR + "/running.json"
const TRAIL := SESSION_DIR + "/trail.log"
const TRAIL_MAX := 3000 # lines before the trail file is cut back to TRAIL_KEEP
const TRAIL_KEEP := 300
const HEARTBEAT := 2.0 # seconds
const LOG_TAIL := 200 # lines of the Godot log kept in a report
const KEEP_REPORTS := 20
const SUFFIX := "_crash.txt"
const ERROR_MARK := "! "

## The crash report written at this launch (its file name in the reports
## folder), "" if the last session quit cleanly. RunState takes it into the
## run continued next (take_crash).
static var last_crash: String = ""

static var _file: FileAccess = null
static var _recent: PackedStringArray = []
static var _written: int = 0
static var _busy: bool = false # a crumb that errors doesn't crumb again
static var _last_action_unix: float = 0.0
static var _mutex := Mutex.new()

var _session: Dictionary = {}
var _beat: float = 0.0

## One line in the trail ("hover part: Needle Drone › Fang Blade"). Safe
## from any thread; does nothing outside the game (tests, sims, headless).
## Errors (ErrorTrail) go in marked ERROR_MARK, not as the player's action.
static func crumb(text: String, is_error: bool = false) -> void:
	_mutex.lock()
	if _file != null and not _busy:
		_busy = true
		if not is_error:
			_last_action_unix = Time.get_unix_time_from_system()
		var line := "[%s] %s%s" % [_clock(), ERROR_MARK if is_error else "", text]
		_recent.append(line)
		if _recent.size() > TRAIL_KEEP:
			_recent = _recent.slice(_recent.size() - TRAIL_KEEP)
		_written += 1
		if _written > TRAIL_MAX: # cut the file back to the recent lines
			_file.close()
			_file = FileAccess.open(TRAIL, FileAccess.WRITE)
			_written = _recent.size()
			if _file != null:
				_file.store_string("\n".join(_recent) + "\n")
		elif _file != null:
			_file.store_line(line)
		if _file != null:
			_file.flush()
		_busy = false
	_mutex.unlock()

## The crash report this launch found, once: "" after the first call.
static func take_crash() -> String:
	var name := last_crash
	last_crash = ""
	return name

## A crash report's text by its file name ("" if it's gone).
static func report_text(name: String) -> String:
	var path := "%s/%s" % [PlaytestReport.DIR, name]
	return FileAccess.get_file_as_string(path) if name != "" and FileAccess.file_exists(path) else ""

func _init() -> void:
	if DisplayServer.get_name() == "headless":
		return
	OS.add_logger(ErrorTrail.new())

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SESSION_DIR))
	if FileAccess.file_exists(LOCK):
		last_crash = _write_report()
	_session = {"started": Time.get_datetime_string_from_system(false, true), "started_unix": Time.get_unix_time_from_system(),
		"system": system_info()}
	_touch()
	_mutex.lock()
	_file = FileAccess.open(TRAIL, FileAccess.WRITE)
	_recent.clear()
	_written = 0
	_mutex.unlock()
	crumb("launch%s" % (" (the last session didn't quit: %s)" % last_crash if last_crash != "" else ""))

func _process(delta: float) -> void:
	if _session.is_empty():
		return
	_beat += delta
	if _beat >= HEARTBEAT:
		_beat = 0.0
		_touch()

## A clean quit: no crash to report next time.
func _exit_tree() -> void:
	if _session.is_empty():
		return
	crumb("quit")
	_mutex.lock()
	if _file != null:
		_file.close()
		_file = null
	_mutex.unlock()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LOCK))

func _touch() -> void:
	var s := _session.duplicate()
	s["alive"] = Time.get_datetime_string_from_system(false, true)
	s["alive_unix"] = Time.get_unix_time_from_system()
	s["last_action_unix"] = _last_action_unix
	var scene := get_tree().current_scene if is_inside_tree() else null
	s["screen"] = scene.scene_file_path.get_file() if scene != null else ""
	var f := FileAccess.open(LOCK, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(s, " "))
		f.close()

## What this machine runs the game on (crashes that only one tester sees
## are usually about their GPU, driver or OS).
static func system_info() -> Dictionary:
	var driver := OS.get_video_adapter_driver_info()
	var screen := DisplayServer.window_get_current_screen()
	return {
		"godot": Engine.get_version_info().get("string", ""),
		"os": "%s %s" % [OS.get_name(), OS.get_version()],
		"cpu": "%s (%d threads)" % [OS.get_processor_name(), OS.get_processor_count()],
		"gpu": "%s · %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor()],
		"gpu_driver": " ".join(driver),
		"graphics_api": "%s %s" % [RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_video_adapter_api_version()],
		"renderer": RenderingServer.get_current_rendering_method(),
		"screen": "%s at %.2fx, %d Hz" % [DisplayServer.screen_get_size(screen), DisplayServer.screen_get_scale(screen), roundi(DisplayServer.screen_get_refresh_rate(screen))],
		"window": str(DisplayServer.window_get_size()),
		"from_editor": OS.has_feature("editor"),
		"data_hash": PlaytestReport.game_info().get("data_hash", ""),
	}

## The last session didn't quit: writes up what it left behind and returns
## the report's file name ("" if it couldn't be written).
func _write_report() -> String:
	var lock = JSON.parse_string(FileAccess.get_file_as_string(LOCK))
	if typeof(lock) != TYPE_DICTIONARY:
		lock = {}
	var trail := FileAccess.get_file_as_string(TRAIL).strip_edges().split("\n", false)
	var log_path := _previous_log(float(lock.get("started_unix", 0.0)))
	var log_lines: PackedStringArray = []
	if log_path != "":
		log_lines = FileAccess.get_file_as_string(log_path).strip_edges().split("\n", false)
		if log_lines.size() > LOG_TAIL:
			log_lines = log_lines.slice(log_lines.size() - LOG_TAIL)
	var log_text := "\n".join(log_lines)
	var engine_crash := log_text.contains("Program crashed") or log_text.contains("handle_crash") or log_text.contains("CrashHandlerException")

	var out: PackedStringArray = ["COLLIMATORS: FRONTLINES · CRASH REPORT", ""]
	out.append("Session: started %s, last sign of life %s (it checks in every %d s), on %s" % [
		lock.get("started", "?"), lock.get("alive", "?"), int(HEARTBEAT), lock.get("screen", "?")])
	if engine_crash:
		out.append("Verdict: the engine crashed (its crash handler wrote to the Godot log below).")
	else:
		out.append("Verdict: the game stopped without quitting, and the Godot log has no crash handler output:")
		out.append("  a crash the log didn't catch, a freeze the player closed, or a force-quit (the editor's Stop too).")
	var last_action := float(lock.get("last_action_unix", 0.0))
	var alive := float(lock.get("alive_unix", 0.0))
	var last := -1 # the player's last action: not an error, nor a backtrace line under one
	for i in range(trail.size() - 1, -1, -1):
		if trail[i].begins_with("[") and not trail[i].contains("] " + ERROR_MARK):
			last = i
			break
	if last >= 0:
		out.append("Last action: %s" % trail[last])
		if last_action > 0.0 and alive > 0.0:
			var gap := alive - last_action
			if gap <= HEARTBEAT + 0.5: # the next check-in never came
				out.append("  The game stopped within about %d s of it: the likely trigger." % ceili(HEARTBEAT * 2.0))
			else:
				out.append("  The game was still running %d s after it." % int(gap))
		for i in range(last + 1, trail.size()):
			if trail[i].contains("] " + ERROR_MARK):
				out.append("First error after it: %s" % trail[i])
				break
	out.append("")
	out.append("System")
	var sys: Dictionary = lock.get("system", {})
	for k in sys:
		out.append("  %s: %s" % [k, sys[k]])
	out.append("")
	out.append("Trail, oldest first (%d lines)" % trail.size())
	for line in trail:
		out.append("  " + line)
	out.append("")
	if log_path != "":
		out.append("Godot log, last %d lines (%s)" % [log_lines.size(), log_path.get_file()])
		for line in log_lines:
			out.append("  " + line)
	else:
		out.append("No Godot log found for that session (file logging off, or it was already rotated away).")

	var started := str(lock.get("started", Time.get_datetime_string_from_system(false, true)))
	var name := "%s%s" % [started.replace("-", "").replace(":", "").replace(" ", "T"), SUFFIX]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PlaytestReport.DIR))
	var f := FileAccess.open("%s/%s" % [PlaytestReport.DIR, name], FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string("\n".join(out) + "\n")
	f.close()
	_prune()
	return name

## The Godot log the last session wrote. Godot moves the old godot.log
## aside (godot<stamp>.log) at launch, before any script runs, so it's the
## newest of those, if it was written after that session started.
static func _previous_log(started_unix: float) -> String:
	var base: String = ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log")
	var dir := base.get_base_dir()
	var stem := base.get_file().get_basename()
	var names := Array(DirAccess.get_files_at(dir)).filter(func(n): return n.begins_with(stem) and n != base.get_file())
	names.sort()
	if names.is_empty():
		return ""
	var path := "%s/%s" % [dir, names.back()]
	return path if FileAccess.get_modified_time(path) + 5 >= int(started_unix) else ""

static func _prune() -> void:
	var names := Array(DirAccess.get_files_at(PlaytestReport.DIR)).filter(func(n): return n.ends_with(SUFFIX))
	names.sort()
	while names.size() > KEEP_REPORTS:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s" % [PlaytestReport.DIR, names.pop_front()]))

static func _clock() -> String:
	var t := Time.get_time_dict_from_system()
	return "%02d:%02d:%02d.%03d" % [t.hour, t.minute, t.second, int(fmod(Time.get_unix_time_from_system(), 1.0) * 1000.0)]

## Engine and script errors (and printerr) into the trail, with the script
## backtrace when there is one.
class ErrorTrail extends Logger:
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		var kind: String = {ERROR_TYPE_WARNING: "WARNING", ERROR_TYPE_SCRIPT: "SCRIPT ERROR", ERROR_TYPE_SHADER: "SHADER ERROR"}.get(error_type, "ERROR")
		var text := "%s: %s (%s, %s:%d)" % [kind, rationale if rationale != "" else code, function, file, line]
		for bt in script_backtraces:
			if not bt.is_empty():
				text += "\n" + bt.format(4, 6)
		CrashLog.crumb(text, true)

	func _log_message(message: String, error: bool) -> void:
		if error:
			CrashLog.crumb("printerr: " + message.strip_edges(), true)

class_name Feedback
extends RefCounted
## In-game feedback (Logan, 2026-10-13): the pilot writes a note and the
## game posts it, with everything needed to look into it, to a private
## Discord channel through a webhook. No folders for the tester to dig in.
## The webhook address isn't in the code: tools/steam_release.sh stamps it
## into build_info.json from FEEDBACK_WEBHOOK in tools/steam/config.sh
## (BuildInfo). For a dev test, a user://feedback_webhook.txt holding the
## address works too. FeedbackDialog is the form.

const OVERRIDE := "user://feedback_webhook.txt"
const GODOT_LOG := "user://logs/godot.log"
## Discord takes up to 25 MB a message; keep under it.
const MAX_BYTES := 24 * 1024 * 1024
const MAX_CONTENT := 1900
## Only a crash report from the last week goes along (older ones are old news).
const CRASH_MAX_AGE := 7 * 24 * 3600

## The webhook address, or "" when this build has none.
static func webhook_url() -> String:
	if FileAccess.file_exists(OVERRIDE):
		var s := FileAccess.get_file_as_string(OVERRIDE).strip_edges()
		if s != "":
			return s
	return str(BuildInfo.info().get("feedback_webhook", ""))

static func enabled() -> bool:
	var url := webhook_url()
	return url.begins_with("https://") or url.begins_with("http://127.0.0.1") # (the second: a local test server)

## The chat message: who, which build, where they were, and their note.
static func message(note: String, screen: String) -> String:
	var who := "no Steam"
	var steam := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("SteamService")
	if steam != null and steam.available:
		who = steam.user_name
	var head := "**Feedback** · %s · %s · %s · %s" % [BuildInfo.label(), OS.get_name(), who, screen]
	var body := note.strip_edges()
	var text := head + ("\n>>> " + body if body != "" else "\n(no note)")
	return text.substr(0, MAX_CONTENT)

## The zip sent with it: the note and system info, a screenshot, the run
## so far (or the last finished run's report), the newest crash report,
## this session's trail and Godot log, the profile and settings. Returns
## {"bytes": PackedByteArray, "name": file name, "left_out": [what didn't fit]}.
static func bundle(note: String, screenshot: Image, run_report: Dictionary) -> Dictionary:
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "").replace(" ", "_").replace("-", "")
	var name := "feedback_%s.zip" % stamp
	var files := {
		"note.txt": ("%s\n\n%s\n\n%s" % [note.strip_edges(), BuildInfo.label(), JSON.stringify(CrashLog.system_info(), "  ")]).to_utf8_buffer(),
	}
	if screenshot != null:
		files["screenshot.png"] = screenshot.save_png_to_buffer()
	if not run_report.is_empty():
		files["run_report.json"] = JSON.stringify(run_report).to_utf8_buffer()
	else:
		var last := _newest(PlaytestReport.DIR, ".json")
		if last != "":
			files["last_run_report.json"] = FileAccess.get_file_as_bytes(last)
	var crash := _newest(PlaytestReport.DIR, CrashLog.SUFFIX)
	if crash != "" and Time.get_unix_time_from_system() - FileAccess.get_modified_time(crash) < CRASH_MAX_AGE:
		files[crash.get_file()] = FileAccess.get_file_as_bytes(crash)
	for p in [CrashLog.TRAIL, GODOT_LOG, "user://profile.json", GameSettings.PATH]:
		if FileAccess.file_exists(p):
			files[p.get_file()] = FileAccess.get_file_as_bytes(p)
	var left_out: Array = []
	var bytes := _zip(files)
	# too big for Discord: drop the heaviest optional pieces until it fits
	for heavy in ["run_report.json", "last_run_report.json", "godot.log", "screenshot.png"]:
		if bytes.size() <= MAX_BYTES:
			break
		if files.erase(heavy):
			left_out.append(heavy)
			bytes = _zip(files)
	return {"bytes": bytes, "name": name, "left_out": left_out}

## The multipart body Discord's webhook takes: the message as payload_json,
## the zip as files[0]. Returns {"body": PackedByteArray, "content_type": String}.
static func multipart(content: String, file_name: String, file_bytes: PackedByteArray) -> Dictionary:
	var boundary := "----collimators%d" % Time.get_ticks_usec()
	var payload := JSON.stringify({
		"content": content,
		"attachments": [{"id": 0, "filename": file_name}],
		"allowed_mentions": {"parse": []},
	})
	var body := PackedByteArray()
	body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"payload_json\"\r\nContent-Type: application/json\r\n\r\n%s\r\n" % [boundary, payload]).to_utf8_buffer())
	body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"files[0]\"; filename=\"%s\"\r\nContent-Type: application/zip\r\n\r\n" % [boundary, file_name]).to_utf8_buffer())
	body.append_array(file_bytes)
	body.append_array(("\r\n--%s--\r\n" % boundary).to_utf8_buffer())
	return {"body": body, "content_type": "multipart/form-data; boundary=%s" % boundary}

## The newest file in `dir` ending in `suffix` ("" if none).
static func _newest(dir: String, suffix: String) -> String:
	var best := ""
	var best_t := -1
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(suffix):
			continue
		var p := "%s/%s" % [dir, f]
		var t := FileAccess.get_modified_time(p)
		if t > best_t:
			best_t = t
			best = p
	return best

static func _zip(files: Dictionary) -> PackedByteArray:
	var tmp := "user://feedback_tmp.zip"
	var z := ZIPPacker.new()
	if z.open(tmp) != OK:
		return PackedByteArray()
	for n in files:
		z.start_file(n)
		z.write_file(files[n])
		z.close_file()
	z.close()
	var out := FileAccess.get_file_as_bytes(tmp)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	return out

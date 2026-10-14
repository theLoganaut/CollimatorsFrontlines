class_name BuildInfo
extends RefCounted
## Which build this is, so a tester's report or crash can be matched to
## the code it came from. tools/steam_release.sh writes res://build_info.json
## ({"stamp": "2026-10-13 14:02", "commit": "dc7f97b", "feedback_webhook":
## the Discord webhook from tools/steam/config.sh}) just for the export
## and deletes it after, so a run from the editor or a dev export reads as
## "dev build".

const PATH := "res://build_info.json"

static var _info: Dictionary = {}
static var _read: bool = false

## {"stamp", "commit"}, or {} for a dev build.
static func info() -> Dictionary:
	if not _read:
		_read = true
		if FileAccess.file_exists(PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
			if typeof(parsed) == TYPE_DICTIONARY:
				_info = parsed
	return _info

## "Build 2026-10-13 14:02 (dc7f97b)", or "Dev build".
static func label() -> String:
	var i := info()
	if i.is_empty():
		return "Dev build"
	return "Build %s (%s)" % [i.get("stamp", "?"), i.get("commit", "?")]

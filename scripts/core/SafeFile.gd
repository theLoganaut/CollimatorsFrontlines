class_name SafeFile
extends RefCounted
## JSON files that survive a crash mid-write: written to "<path>.tmp" and
## renamed over the file, keeping the previous one as "<path>.bak". Reading
## falls back to the backup when the file is missing or doesn't parse, and a
## file that doesn't parse is moved aside to "<path>.corrupt" so it can be
## looked at instead of silently overwritten.

static func write_json(path: String, data) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("SafeFile: can't write %s" % tmp)
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(abs_path, abs_path + ".bak")
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), abs_path) == OK

## The parsed file, else its backup; null when neither is usable.
static func read_json(path: String):
	var d = _parse(path)
	if d == null and FileAccess.file_exists(path):
		push_warning("SafeFile: %s doesn't parse; kept as .corrupt, using the backup" % path)
		var abs_path := ProjectSettings.globalize_path(path)
		DirAccess.rename_absolute(abs_path, abs_path + ".corrupt")
	if d == null:
		d = _parse(path + ".bak")
	return d

static func _parse(path: String):
	if not FileAccess.file_exists(path):
		return null
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if typeof(d) == TYPE_DICTIONARY else null

## Removes the file and its backup.
static func remove(path: String) -> void:
	for p in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

class_name Audio
extends RefCounted
## Plays a sound through the Sfx autoload when it's there (the game), and
## does nothing when it isn't (headless tests and tools).

## The music bed ("hub", "map", "combat", "boss"; "" = none).
static func music(key: String) -> void:
	var sfx := _sfx()
	if sfx != null:
		sfx.set_music(key)

## The ambience bed ("hub", "coast", "flank", "backline", "rain"; "" = none).
static func ambience(key: String) -> void:
	var sfx := _sfx()
	if sfx != null:
		sfx.set_ambience(key)

## A location's ambience, by where it sits on the theater map (map_zone).
static func location_ambience(location: Dictionary) -> String:
	var zone := str(location.get("map_zone", ""))
	return zone if zone in ["coast", "flank", "backline"] else ""

static func _sfx() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Sfx")

static func play(key: String, pitch_jitter: float = 0.06, volume_db: float = 0.0) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var sfx := tree.root.get_node_or_null("Sfx")
	if sfx != null:
		sfx.play(key, pitch_jitter, volume_db)

class_name AttackFxData
extends RefCounted
## The data half of AttackFx (no autoloads, so validate_data can use it):
## which animation each hardpoint plays (data/attack_fx.json) and the
## PixelLab sheets (assets/fx/<name>.png + .json).

const DATA_PATH := "res://data/attack_fx.json"
const SHEET_DIR := "res://assets/fx/"
## The sheets: where each attaches (in its frame's pixels) and whether it
## loops; directional ones are drawn pointing right (+x), `reach` px long.
const SHEETS := {
	"muzzle_heavy": {"anchor": Vector2(4, 13)},
	"muzzle_small": {"anchor": Vector2(4, 13)},
	"round_heavy": {"anchor": Vector2(34, 7), "loop": true},
	"round_small": {"anchor": Vector2(34, 7), "loop": true},
	"missile": {"anchor": Vector2(122, 10), "loop": true},
	"slash": {"anchor": Vector2(79, 37)}, # where the blade is through its whole swing, so it cuts across the part it hits
	"smash": {"anchor": Vector2(52, 52)},
	"explosion": {"anchor": Vector2(48, 48)},
	"hit_heavy": {"anchor": Vector2(35, 30)},
	"hit_small": {"anchor": Vector2(35, 30)},
	# the jet's thin tip is its right end: it fires backwards (turned round), widening toward the target
	"spray": {"anchor": Vector2(110, 30), "loop": true, "reach": 100.0},
	"beam": {"anchor": Vector2(10, 18), "loop": true, "reach": 150.0},
}
const STYLES := ["shot", "burst", "missile", "swarm", "mortar", "spray", "slash", "smash", "beam"]
const TINTS := {"spray": ["fire", "acid", "frost", "steam"], "beam": ["electric", "laser", "heat", "nova"]}

static var _sheets: Dictionary = {}
static var _data: Dictionary = {}

## The style a card plays ("shot", "spray:fire", ...): its own entry in
## attack_fx.json, else its part's, else "" (nothing plays).
static func style_for(card: CardData, part: ComponentData) -> String:
	if card == null or part == null:
		return ""
	var d := data()
	var lib := part.library_id if part.library_id != "" else part.id
	var by_card: Dictionary = d.get("cards", {})
	var key := "%s/%s" % [lib, card.id]
	if by_card.has(key):
		return by_card[key]
	return d.get("parts", {}).get(lib, "")

static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			_data = parsed if parsed is Dictionary else {}
	return _data

## Whether a style names a real animation (validate_data).
static func valid_style(style: String) -> bool:
	var bits := style.split(":")
	if not STYLES.has(bits[0]):
		return false
	if TINTS.has(bits[0]):
		return bits.size() == 2 and (TINTS[bits[0]] as Array).has(bits[1])
	return bits.size() == 1

## A sheet's frames: {"tex", "rects": Array[Rect2], "ms"}.
static func sheet(sheet_name: String) -> Dictionary:
	if not _sheets.has(sheet_name):
		var entry := {}
		var tex := load(SHEET_DIR + sheet_name + ".png") as Texture2D
		var f := FileAccess.open(SHEET_DIR + sheet_name + ".json", FileAccess.READ)
		if tex != null and f != null:
			var d = JSON.parse_string(f.get_as_text())
			var rects: Array[Rect2] = []
			var ms := 70.0
			for fr in (d.get("frames", []) if d is Dictionary else []):
				var r: Dictionary = fr["frame"]
				rects.append(Rect2(r["x"], r["y"], r["w"], r["h"]))
				ms = float(fr.get("duration", ms))
			if not rects.is_empty():
				entry = {"tex": tex, "rects": rects, "ms": ms}
		_sheets[sheet_name] = entry
	return _sheets[sheet_name]

static func meta(sheet_name: String) -> Dictionary:
	return SHEETS.get(sheet_name.get_slice("_", 0) if sheet_name.begins_with("spray_") or sheet_name.begins_with("beam_") else sheet_name, {})


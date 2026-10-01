class_name Meta
extends RefCounted
## Meta progression (Logan, 2026-09-28). Pure rules; Profile holds the state.
##
## - Chips: the meta currency (cosmetics now, unlocks later). A run pays
##   per fight, elite and boss won, plus a bonus for clearing the location
##   (balance.json "meta"). Scraps are the in-run money and don't carry over.
## - Directives: each day 3 are drawn from data/directives.json (seeded by
##   the date, so everyone's day is the same). Progress builds across the
##   day's runs; a finished one pays its Chips at once.
## - Liveries (data/liveries.json): paint schemes bought with Chips.

const DIRECTIVES_PATH := "res://data/directives.json"
const LIVERIES_PATH := "res://data/liveries.json"

static var _directives: Array = []
static var _weekly: Array = []
static var _liveries: Array = []

# ---------- chips ----------

## What a finished run pays in Chips.
static func chips_for_run(run: RunData) -> int:
	var s := run.stats
	var elites := s.get_stat("elites_beaten")
	var bosses := s.get_stat("bosses_beaten")
	var regular := maxi(0, s.get_stat("fights_won") - elites - bosses)
	var chips := regular * Balance.get_int("meta", "chips_per_fight", 4) \
		+ elites * Balance.get_int("meta", "chips_per_elite", 10) \
		+ bosses * Balance.get_int("meta", "chips_per_boss", 25)
	if run.result == RunData.Result.CLEARED:
		chips += Balance.get_int("meta", "chips_for_clear", 30)
	return chips

# ---------- memorial wall ----------

## Memorial points a finished run adds: a little for the run itself, more
## per elite and boss beaten (balance.json "meta").
static func memorial_points_for(elites: int, bosses: int) -> int:
	return Balance.get_int("meta", "memorial_per_run", 1) \
		+ elites * Balance.get_int("meta", "memorial_per_elite", 2) \
		+ bosses * Balance.get_int("meta", "memorial_per_boss", 5)

## How many of the wall's `slots` trophies show at `points`: the first
## (the candle) with the first point, then one per memorial_per_trophy.
static func memorial_trophies(points: int, slots: int) -> int:
	if points <= 0:
		return 0
	var per := maxi(1, Balance.get_int("meta", "memorial_per_trophy", 5))
	return mini(slots, 1 + (points - 1) / per)

# ---------- directives ----------

static func directive_defs() -> Array:
	if _directives.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DIRECTIVES_PATH))
		_directives = parsed.get("directives", []) if typeof(parsed) == TYPE_DICTIONARY else []
	return _directives

## The weekly tier: bigger goals, a few a week.
static func weekly_defs() -> Array:
	if _weekly.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DIRECTIVES_PATH))
		_weekly = parsed.get("weekly", []) if typeof(parsed) == TYPE_DICTIONARY else []
	return _weekly

static func directive(id: String) -> Dictionary:
	for d in directive_defs() + weekly_defs():
		if d["id"] == id:
			return d
	return {}

## "2026-W40": the ISO week a date falls in (weeklies roll per week).
static func week_of(date: String) -> String:
	var unix := Time.get_unix_time_from_datetime_string(date + "T12:00:00")
	var d := Time.get_datetime_dict_from_unix_time(unix)
	var weekday: int = (int(d["weekday"]) + 6) % 7 # Monday 0
	var thursday := unix + (3 - weekday) * 86400 # the ISO year is the Thursday's
	var td := Time.get_datetime_dict_from_unix_time(thursday)
	var jan1 := Time.get_unix_time_from_datetime_string("%04d-01-01T12:00:00" % int(td["year"]))
	return "%04d-W%02d" % [int(td["year"]), int((thursday - jan1) / 86400) / 7 + 1]

## This week's weekly directive ids (the same for the whole week).
static func weeklies_for(week: String) -> Array:
	var pool: Array = weekly_defs().map(func(d): return d["id"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("weekly:" + week)
	var out: Array = []
	var count := mini(Balance.get_int("meta", "weekly_per_week", 2), pool.size())
	while out.size() < count:
		var id: String = pool[rng.randi_range(0, pool.size() - 1)]
		if not out.has(id):
			out.append(id)
	return out

## The day before `date` ("2026-09-30" -> "2026-09-29").
static func day_before(date: String) -> String:
	var unix := Time.get_unix_time_from_datetime_string(date + "T12:00:00") - 86400
	return Time.get_date_string_from_unix_time(unix)

static func today() -> String:
	return Time.get_date_string_from_system()

## The day's directive ids (always the same for the same date).
static func directives_for(date: String) -> Array:
	var pool: Array = directive_defs().map(func(d): return d["id"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("directives:" + date)
	var out: Array = []
	var count := mini(Balance.get_int("meta", "directives_per_day", 3), pool.size())
	while out.size() < count:
		var id: String = pool[rng.randi_range(0, pool.size() - 1)]
		if not out.has(id):
			out.append(id)
	return out

static func directive_text(d: Dictionary) -> String:
	return str(d.get("text", "")).format({"n": int(d.get("n", 0))})

## How far one run takes a directive: its stat for sums, 1 or 0 for the
## one-run goals. Runs in the wrong mech or mission count 0.
static func run_progress(d: Dictionary, run: RunData) -> int:
	if d.has("mech") and run.player_mech.id != d["mech"]:
		return 0
	if d.has("mission") and run.mission.get("id", "") != d["mission"]:
		return 0
	if d.has("location") and run.location.get("id", "") != d["location"]:
		return 0
	var stats: Array = d["stat"] if typeof(d["stat"]) == TYPE_ARRAY else [d["stat"]]
	var total := 0
	for key in stats:
		if key == "clears":
			total += 1 if run.result == RunData.Result.CLEARED else 0
		else:
			total += run.stats.get_stat(key)
	match str(d.get("kind", "sum")):
		"at_least":
			return 1 if total >= int(d["n"]) else 0
		"at_most":
			return 1 if run.stats.values.has(stats[0]) and total <= int(d["n"]) and run.stats.get_stat("fights_won") > 0 else 0
	return total

## Progress needed to finish a directive.
static func directive_goal(d: Dictionary) -> int:
	return 1 if str(d.get("kind", "sum")) in ["at_least", "at_most"] else int(d["n"])

# ---------- liveries ----------

static func liveries() -> Array:
	if _liveries.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(LIVERIES_PATH))
		_liveries = parsed.get("liveries", []) if typeof(parsed) == TYPE_DICTIONARY else []
	return _liveries

static func livery(id: String) -> Dictionary:
	for l in liveries():
		if l["id"] == id:
			return l
	return liveries()[0] if not liveries().is_empty() else {}

static func livery_price(l: Dictionary) -> int:
	if l.get("tier", "free") == "free":
		return 0
	return int(Balance.get_dict("meta", "livery_prices").get(l.get("tier", "standard"), 900))

## Paints a livery onto a rect (the mech image placeholder): its base
## colour, then its accent in its pattern, kept faint so the grid on top
## stays readable.
static func paint_livery(ci: CanvasItem, rect: Rect2, l: Dictionary, strength: float = 1.0) -> void:
	var base := Color(str(l.get("base", "1b2230")))
	var accent := Color(str(l.get("accent", "2c3647")))
	ci.draw_rect(rect, base, true)
	var a := Color(accent, 0.3 * strength)
	match str(l.get("pattern", "solid")):
		"stripes":
			var w := rect.size.x / 9.0
			var x := -rect.size.y
			while x < rect.size.x:
				var p := rect.position
				var poly := _clip_poly(PackedVector2Array([
					p + Vector2(x, rect.size.y), p + Vector2(x + w, rect.size.y),
					p + Vector2(x + w + rect.size.y, 0), p + Vector2(x + rect.size.y, 0)]), rect)
				if poly.size() >= 3:
					ci.draw_colored_polygon(poly, a)
				x += w * 2.5
		"split":
			ci.draw_rect(Rect2(rect.position + Vector2(rect.size.x / 2.0, 0), Vector2(rect.size.x / 2.0, rect.size.y)), a, true)
		"chevron":
			var c := rect.position + Vector2(rect.size.x / 2.0, rect.size.y * 0.35)
			for i in range(3):
				var y := c.y + i * rect.size.y * 0.16
				ci.draw_polyline(PackedVector2Array([Vector2(rect.position.x + rect.size.x * 0.12, y + rect.size.y * 0.18), Vector2(c.x, y), Vector2(rect.end.x - rect.size.x * 0.12, y + rect.size.y * 0.18)]), a, rect.size.y * 0.05, true)
	ci.draw_rect(rect, Color(accent, 0.9 * strength), false, 2.0)

static func _clip_poly(poly: PackedVector2Array, rect: Rect2) -> PackedVector2Array:
	var box := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	var clipped := Geometry2D.intersect_polygons(poly, box)
	return clipped[0] if not clipped.is_empty() else PackedVector2Array()

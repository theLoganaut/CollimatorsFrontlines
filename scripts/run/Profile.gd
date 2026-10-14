extends Node
## Autoload. What carries over between runs, saved to user://profile.json:
## - recon_intel: a Deep Recon was finished; the next boss's hardpoints
##   start Disabled (Logan, 2026-09-28).
## - sector_seed: rolls each location's mission type; rerolled after every
##   run, so the sector map changes between runs.
## - bosses_faced: boss ids met, for the Memorial Wall.
## - runs / clears: counts for the Pilot Log.
## - loadouts: each mech's starting loadout, as edited in the Hangar
##   (mech id -> [{"id", "offset", "rotation"}]); missing = the default.
## - hangar_bench: parts each mech has on the Hangar's workbench, same form
##   (they stay in the Hangar; only the loadout launches).
## - mech: the mech picked in the Hangar.
## - chips / chips_earned: the meta currency (spendable / lifetime).
## - liveries / livery: cosmetics owned, and the one worn.
## - directives: today's {date, ids, progress: {id: n}, done: [ids]}.
## - weekly: this week's {week, ids, progress, done} (the weekly tier).
## - streak: {days, last}: days in a row every daily directive was done.
## - history: the last HISTORY_MAX runs, newest first (the Pilot Log).
## - boss_record: boss id -> {faced, beaten} (the Memorial Wall).
## - memorial_points: grows the War Room's Memorial Wall (Meta.memorial_trophies).
## - mech_record: mech id -> {runs, clears, fights_won, best_stops}
##   (the Pilot Log's per-mech numbers; backfilled from history once).
## - enemy_record: enemy id -> {fought, beaten, lost_to} (fights with it in:
##   won, and lost; counted from 2026-09-30).
## - daily: today's Daily Operation {date, played, score, result} and the
##   pilot's best {best, best_date} (Daily).
## - lifetime: every run's stats summed (RunStats.merge; backfilled from
##   history once), for career achievements.
## - achievements: id -> the date it was earned (Achievements).

const PATH := "user://profile.json"
const HISTORY_MAX := 50

var recon_intel: bool = false
var sector_seed: int = 0
var bosses_faced: Array = []
var runs: int = 0
var clears: int = 0
var loadouts: Dictionary = {}
var hangar_bench: Dictionary = {}
var mech: String = "bastion"
var chips: int = 0
var chips_earned: int = 0
var liveries: Array = ["standard_issue"]
var livery: String = "standard_issue"
var directives: Dictionary = {}
var weekly: Dictionary = {}
var streak: Dictionary = {}
var directives_done_total: int = 0
var history: Array = []
var boss_record: Dictionary = {}
var memorial_points: int = 0
var daily: Dictionary = {}
var mech_record: Dictionary = {}
## The Info Bay codex: enemy ids met in a fight, deployment order ids offered.
var seen_enemies: Array = []
var seen_orders: Array = []
var enemy_record: Dictionary = {}
var lifetime: Dictionary = {}
var achievements: Dictionary = {}
## The training run (or its skip) is behind this pilot.
var tutorial_done: bool = false
## The War Room's name, chosen the first time the game opens (Logan,
## 2026-10-13); "" until then.
var base_name: String = ""
## One-time Operator hints already shown (Tutorial.hint_once keys).
var seen_hints: Array = []
const BASE_NAME_MAX := 24
## What came out of the last run, for the Operator: {result, location,
## mission, stops, new_bosses: [names], intel, alert}.
var last_report: Dictionary = {}

func _ready() -> void:
	load_profile()
	if sector_seed == 0:
		reroll_sector()

func load_profile() -> void:
	var d = SafeFile.read_json(PATH) # falls back to the backup if the file is damaged
	if d == null:
		return
	recon_intel = bool(d.get("recon_intel", false))
	sector_seed = int(d.get("sector_seed", 0))
	bosses_faced = d.get("bosses_faced", [])
	runs = int(d.get("runs", 0))
	clears = int(d.get("clears", 0))
	loadouts = d.get("loadouts", {})
	hangar_bench = d.get("hangar_bench", {})
	mech = d.get("mech", "bastion")
	last_report = d.get("last_report", {})
	chips = int(d.get("chips", 0))
	chips_earned = int(d.get("chips_earned", 0))
	liveries = d.get("liveries", ["standard_issue"])
	livery = d.get("livery", "standard_issue")
	directives = d.get("directives", {})
	weekly = d.get("weekly", {})
	streak = d.get("streak", {})
	directives_done_total = int(d.get("directives_done_total", 0))
	history = d.get("history", [])
	boss_record = d.get("boss_record", {})
	if d.has("memorial_points"):
		memorial_points = int(d["memorial_points"])
	else: # a profile from before the wall grew: count what its history shows
		memorial_points = 0
		for h in history:
			var st: Dictionary = h.get("stats", {})
			memorial_points += Meta.memorial_points_for(int(st.get("elites_beaten", 0)), int(st.get("bosses_beaten", 0)))
	tutorial_done = bool(d.get("tutorial_done", false))
	base_name = str(d.get("base_name", ""))
	seen_hints = d.get("seen_hints", [])
	daily = d.get("daily", {})
	enemy_record = d.get("enemy_record", {})
	achievements = d.get("achievements", {})
	if d.has("lifetime"):
		lifetime = d["lifetime"]
	else: # a profile from before lifetime totals: sum what its history shows
		var total := RunStats.new()
		for h in history:
			total.merge(RunStats.from_dict(h.get("stats", {})))
		lifetime = total.to_dict()
	seen_orders = d.get("seen_orders", [])
	seen_enemies = d.get("seen_enemies", [])
	for id in bosses_faced + enemy_record.keys(): # from before the codex
		if not seen_enemies.has(id):
			seen_enemies.append(id)
	if d.has("mech_record"):
		mech_record = d["mech_record"]
	else: # a profile from before per-mech records: count what its history shows
		mech_record = {}
		for h in history:
			_count_mech(str(h.get("mech", "")), h.get("result", "") == "cleared", int(h.get("stats", {}).get("fights_won", 0)), int(h.get("stops", 0)))

func save() -> void:
	SafeFile.write_json(PATH, {
		"v": 1,
		"recon_intel": recon_intel, "sector_seed": sector_seed, "bosses_faced": bosses_faced,
		"runs": runs, "clears": clears, "loadouts": loadouts, "hangar_bench": hangar_bench, "mech": mech, "last_report": last_report,
		"chips": chips, "chips_earned": chips_earned, "liveries": liveries, "livery": livery,
		"directives": directives, "directives_done_total": directives_done_total, "weekly": weekly, "streak": streak,
		"history": history, "boss_record": boss_record, "tutorial_done": tutorial_done, "base_name": base_name, "seen_hints": seen_hints,
		"memorial_points": memorial_points, "daily": daily, "mech_record": mech_record, "enemy_record": enemy_record,
		"seen_enemies": seen_enemies, "seen_orders": seen_orders, "lifetime": lifetime, "achievements": achievements,
	})

func reroll_sector() -> void:
	sector_seed = randi() % 1000000000 + 1
	save()

## Each location's mission type for the current sector roll (location id -> mission id).
func sector_missions() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = sector_seed
	var ids: Array = GameData.missions().keys().filter(func(id): return not GameData.missions()[id].get("training", false))
	ids.sort()
	var out := {}
	for loc in GameData.sectors():
		out[loc["id"]] = ids[rng.randi() % ids.size()]
	return out

## Each location's mission variant for the current sector roll (location id
## -> variant id; Conditions). A separate stream from the mission roll, so
## adding variants didn't change which missions a sector rolled.
func sector_variants() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = sector_seed * 7717 + 3
	var out := {}
	for loc in GameData.sectors():
		var v := Conditions.roll_variant(rng)
		out[loc["id"]] = v if Conditions.enabled() else "standard"
	return out

## A location's mission for this sector roll, with its variant attached.
func sector_mission(location_id: String) -> Dictionary:
	var m := GameData.mission(sector_missions().get(location_id, "assault"))
	return Conditions.with_variant(m, sector_variants().get(location_id, "standard"))

## Called when a run ends: counts it, remembers bosses met, updates Recon intel.
func record_run(run: RunData) -> void:
	var new_bosses: Array = []
	for id in run.bosses_met:
		if not bosses_faced.has(id):
			var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/mechs/%s.json" % id))
			new_bosses.append(d.get("name", id) if typeof(d) == TYPE_DICTIONARY else id)
	last_report = {
		"result": "cleared" if run.result == RunData.Result.CLEARED else "ejected",
		"location": run.location.get("name", ""), "mission": run.mission_name(),
		"stops": run.path.size() + (1 if run.result == RunData.Result.EJECTED else 0),
		"total": run.encounter_count(),
		"new_bosses": new_bosses,
		"intel": run.result == RunData.Result.CLEARED and run.mission.get("grants_boss_intel", false),
		"alert": run.alert_tier(),
	}
	runs += 1
	if run.result == RunData.Result.CLEARED:
		clears += 1
		if run.mission.get("grants_boss_intel", false):
			recon_intel = true
	if run.boss_intel_used:
		recon_intel = false
	for id in run.bosses_met:
		if not bosses_faced.has(id):
			bosses_faced.append(id)
		var rec: Dictionary = boss_record.get(id, {"faced": 0, "beaten": 0})
		rec["faced"] = int(rec["faced"]) + 1
		if run.result == RunData.Result.CLEARED and run.mission.get("boss", false) and run.location.get("boss", "") == id:
			rec["beaten"] = int(rec["beaten"]) + 1
		boss_record[id] = rec
	memorial_points += Meta.memorial_points_for(run.stats.get_stat("elites_beaten"), run.stats.get_stat("bosses_beaten"))
	if Daily.is_daily(run):
		var sc := Daily.score(run)
		daily["score"] = sc
		daily["result"] = last_report["result"]
		last_report["daily_score"] = sc
		last_report["daily_best"] = sc > int(daily.get("best", 0))
		if sc > int(daily.get("best", 0)):
			daily["best"] = sc
			daily["best_date"] = str(run.mission["daily"])
	var earned := Meta.chips_for_run(run)
	add_chips(earned)
	var finished := advance_directives(run)
	last_report["chips"] = earned
	last_report["directives"] = finished
	_count_mech(run.player_mech.id, run.result == RunData.Result.CLEARED, run.stats.get_stat("fights_won"), last_report["stops"])
	var total := RunStats.from_dict(lifetime)
	total.merge(run.stats)
	lifetime = total.to_dict()
	for id in run.orders.get("offer", []):
		if not seen_orders.has(id):
			seen_orders.append(id)
	for id in run.bosses_met:
		if not seen_enemies.has(id):
			seen_enemies.append(id)
	for f in run.fight_log:
		for id in f.get("enemies", []):
			if not seen_enemies.has(id):
				seen_enemies.append(id)
			var rec: Dictionary = enemy_record.get(id, {"fought": 0, "beaten": 0, "lost_to": 0})
			rec["fought"] = int(rec["fought"]) + 1
			if f.get("won", false):
				rec["beaten"] = int(rec["beaten"]) + 1
			else:
				rec["lost_to"] = int(rec["lost_to"]) + 1
			enemy_record[id] = rec
	last_report["achievements"] = _earn_achievements(run)
	history.push_front({
		"date": Meta.today(), "mech": run.player_mech.id, "location": run.location.get("name", ""),
		"mission": run.mission_name(), "result": last_report["result"], "stops": last_report["stops"],
		"seed": run.seed_value, "chips": earned + (finished + last_report["achievements"]).reduce(func(a, f): return a + int(f["chips"]), 0),
		"stats": run.stats.values.duplicate(), "cause": run.end_cause,
		"order": run.orders.get("chosen", ""), "variant": Conditions.variant(run.mission).get("name", ""),
		"daily": Daily.is_daily(run), "fights": run.fight_log.duplicate(true),
	})
	if history.size() > HISTORY_MAX:
		history.resize(HISTORY_MAX)
	reroll_sector()

## Achievements this run earns: each is marked with today's date and pays
## its Chips. Returns [{id, name, text, chips}].
func _earn_achievements(run: RunData) -> Array:
	var bosses_beaten: Array = boss_record.keys().filter(func(id): return int(boss_record[id].get("beaten", 0)) > 0)
	var clears := {}
	for id in mech_record:
		clears[id] = int(mech_record[id].get("clears", 0))
	var career := {"runs": runs, "stats": lifetime, "mech_clears": clears, "mechs": GameData.PLAYER_MECHS,
		"streak": streak_days(), "bosses_beaten": bosses_beaten, "bosses": GameData.boss_ids()}
	var out := []
	for d in Achievements.newly_earned(run, career, achievements.keys()):
		achievements[d["id"]] = Meta.today()
		add_chips(int(d.get("chips", 0)))
		out.append({"id": d["id"], "name": d["name"], "text": d["text"], "chips": int(d.get("chips", 0))})
	# by path, not name: tests load this script without the autoloads
	var steam := get_node_or_null("/root/SteamService") if is_inside_tree() else null
	if steam != null:
		steam.unlock_achievements(out.map(func(a): return a["id"]))
	return out

## Whether today's Daily Operation has been launched already.
func daily_played_today() -> bool:
	return daily.get("date", "") == Meta.today() and daily.get("played", false)

## Marks today's Daily Operation launched (one scored attempt a day).
func start_daily() -> void:
	var best := int(daily.get("best", 0))
	var best_date: String = daily.get("best_date", "")
	daily = {"date": Meta.today(), "played": true, "score": 0, "result": "", "best": best, "best_date": best_date}
	save()

func _count_mech(id: String, cleared: bool, fights_won: int, stops: int) -> void:
	if id == "":
		return
	var rec: Dictionary = mech_record.get(id, {"runs": 0, "clears": 0, "fights_won": 0, "best_stops": 0})
	rec["runs"] = int(rec["runs"]) + 1
	rec["clears"] = int(rec["clears"]) + (1 if cleared else 0)
	rec["fights_won"] = int(rec["fights_won"]) + fights_won
	rec["best_stops"] = maxi(int(rec["best_stops"]), stops)
	mech_record[id] = rec

func add_chips(n: int) -> void:
	chips += n
	chips_earned += n

## Today's directives ({date, ids, progress, done}), rolled fresh when the day changes.
func todays_directives() -> Dictionary:
	var date := Meta.today()
	if directives.get("date", "") != date:
		directives = {"date": date, "ids": Meta.directives_for(date), "progress": {}, "done": []}
	return directives

## This week's weekly directives, rolled fresh when the week changes.
func this_weeks_directives() -> Dictionary:
	var week := Meta.week_of(Meta.today())
	if weekly.get("week", "") != week:
		weekly = {"week": week, "ids": Meta.weeklies_for(week), "progress": {}, "done": []}
	return weekly

## Days in a row with every daily directive done (0 once a day is missed).
func streak_days() -> int:
	var last: String = streak.get("last", "")
	if last == Meta.today() or last == Meta.day_before(Meta.today()):
		return int(streak.get("days", 0))
	return 0

## Adds a finished run to today's and this week's directives; each one it
## completes pays its Chips, and finishing the last of today's extends the
## streak (and pays its bonus). Returns the completed ones: [{id, text, chips}].
func advance_directives(run: RunData) -> Array:
	var finished: Array = _advance(todays_directives(), run)
	var today := todays_directives()
	if not finished.is_empty() and (today["done"] as Array).size() >= (today["ids"] as Array).size() and streak.get("last", "") != Meta.today():
		var days := streak_days() + 1
		streak = {"days": days, "last": Meta.today()}
		var bonus := mini(days, Balance.get_int("meta", "streak_max_days", 5)) * Balance.get_int("meta", "streak_chips_per_day", 5)
		add_chips(bonus)
		finished.append({"id": "streak", "text": "%d-day streak" % days, "chips": bonus})
	finished.append_array(_advance(this_weeks_directives(), run))
	return finished

func _advance(today: Dictionary, run: RunData) -> Array:
	var finished: Array = []
	for id in today["ids"]:
		if (today["done"] as Array).has(id):
			continue
		var d := Meta.directive(id)
		if d.is_empty():
			continue
		var p := int(today["progress"].get(id, 0)) + Meta.run_progress(d, run)
		today["progress"][id] = mini(p, Meta.directive_goal(d))
		if p >= Meta.directive_goal(d):
			today["done"].append(id)
			directives_done_total += 1
			add_chips(int(d.get("chips", 0)))
			finished.append({"id": id, "text": Meta.directive_text(d), "chips": int(d.get("chips", 0))})
	return finished

## Buys a livery with Chips. Returns whether it went through.
func buy_livery(id: String) -> bool:
	var l := Meta.livery(id)
	var price := Meta.livery_price(l)
	if l.is_empty() or liveries.has(id) or chips < price:
		return false
	chips -= price
	liveries.append(id)
	save()
	return true

func wear_livery(id: String) -> void:
	if liveries.has(id):
		livery = id
		save()

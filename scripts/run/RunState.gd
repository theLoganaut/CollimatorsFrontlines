extends Node
## Autoload. The run in progress, if any (see RunData), shared by every run
## screen. advance() is how screens move the run on: it saves, then goes to
## the screen for the run's phase, or to the debrief once the run is over.

## The run that just ended, for the debrief screen.
var last_run: RunData = null
var run: RunData = null

const PHASE_SCENES := {
	RunData.PHASE_MAP: "res://scenes/LocationMap.tscn",
	RunData.PHASE_FIGHT: "res://scenes/CombatScene.tscn",
	RunData.PHASE_REWARD: "res://scenes/RewardScreen.tscn",
	RunData.PHASE_REFIT: "res://scenes/RefitScreen.tscn",
	RunData.PHASE_REPAIR: "res://scenes/RepairBayScreen.tscn",
	RunData.PHASE_SHOP: "res://scenes/ShopScreen.tscn",
	RunData.PHASE_EVENT: "res://scenes/EventScreen.tscn",
}
const DEBRIEF := "res://scenes/DebriefScreen.tscn"

func is_active() -> bool:
	return run != null and not run.is_over()

## `seed_value` < 0 picks a random seed; `mission_id` "" = this sector
## roll's mission for the location, with its variant.
func start_run(location_id: String, seed_value: int = -1, mission_id: String = "") -> RunData:
	if seed_value < 0:
		seed_value = randi() % 1000000000
	var mission := Profile.sector_mission(location_id) if mission_id == "" else GameData.mission(mission_id)
	var mech := GameData.player_mech(Profile.mech, Profile.loadouts.get(Profile.mech, []))
	run = RunData.new(GameData.sector(location_id), mech, seed_value, mission)
	run.boss_intel = Profile.recon_intel
	if not run.mission.get("training", false):
		DeploymentOrders.offer(run) # taken on the location map, before the first stop
	SaveGame.save(run)
	CrashLog.crumb("new run: %s, %s, seed %d" % [run.location.get("name", ""), run.player_mech.id, seed_value])
	return run

## Today's Daily Operation (Daily): the day's location, mission, variant,
## seed and mech (its default loadout). Launching it uses today's attempt.
func start_daily() -> RunData:
	var d := Daily.setup(Meta.today())
	var mech := GameData.player_mech(d["mech"], [])
	run = RunData.new(d["location"], mech, int(d["seed"]), d["mission"])
	run.boss_intel = Profile.recon_intel
	DeploymentOrders.offer(run)
	Profile.start_daily()
	SaveGame.save(run)
	return run

func continue_run() -> bool:
	run = SaveGame.load_run()
	if run == null:
		return false
	var crash := CrashLog.take_crash()
	run.resumes.append({"at": Time.get_datetime_string_from_system(false, true), "phase": run.phase, "stops": run.path.size(), "crash": crash})
	CrashLog.crumb("continue run: %s, stop %d%s" % [run.location.get("name", ""), run.path.size(), " (after %s)" % crash if crash != "" else ""])
	return true

## Saves and goes to wherever the run is now.
func advance() -> void:
	if run == null:
		SceneRouter.go(SceneRouter.WAR_ROOM)
		return
	if run.is_over():
		var cleared := run.result == RunData.Result.CLEARED
		end_run()
		SceneRouter.go(DEBRIEF, "SECTOR CLEARED" if cleared else "PILOT EJECTED", Palette.OK if cleared else Palette.DANGER)
		return
	SaveGame.save(run)
	SceneRouter.go(PHASE_SCENES.get(run.phase, SceneRouter.LOCATION_MAP))

func end_run() -> void:
	if run != null and not run.mission.get("training", false): # training doesn't count
		Profile.record_run(run)
		PlaytestReport.write(PlaytestReport.for_run(run, Profile.history[0]), "%s_%s" % [run.player_mech.id, run.location.get("id", "")])
	last_run = run
	run = null
	SaveGame.clear()

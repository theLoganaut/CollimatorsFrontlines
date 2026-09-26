extends SceneTree
## Headless test runner: godot --headless -s res://tests/run_tests.gd
## Exits 0 if every assertion passed, 1 otherwise (for CI / scripting).
## New test files are wired in here explicitly as they're added.

func _initialize() -> void:
	var t := TestContext.new()

	TestDataLoader.run_all(t)
	TestHeatRules.run_all(t)
	TestCardResolver.run_all(t)
	TestEnemyAI.run_all(t)
	TestCombatManager.run_all(t)

	t.summary()
	quit(1 if t.failed > 0 else 0)

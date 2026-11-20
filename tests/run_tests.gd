extends SceneTree
## Headless test runner: godot --headless -s res://tests/run_tests.gd
## Exits 0 if every assertion passed, 1 otherwise (for CI / scripting).
## New test files are wired in here explicitly as they're added.

func _initialize() -> void:
	var t := TestContext.new()
	# Rules are tested against Refit Bay's own numbers: balance.json's
	# "combat" scaling is off (TestLibrary tests the scaling itself).
	for k in ["damage_mult", "heat_mult", "hp_mult"]:
		Balance.set_value("combat", k, 1.0)
	Balance.set_value("combat", "heat_add", 0)
	Balance.set_value("combat", "utility_shield_mult", 1.0)
	# ...and heat vents by the ratio (TestHeatRules tests the full reset).
	Balance.set_value("heat", "full_reset", false)
	# The turn-variety rules (2026-11-19) are off too; TestTurnVariety turns
	# each on for its own tests.
	Balance.set_value("heat", "bank", false)
	Balance.set_value("analysis", "enabled", false)
	Balance.set_value("enemy_ai", "max_cards", {})
	Balance.set_value("enemy_ai", "intent_damage_mult", 1.0)

	TestDataLoader.run_all(t)
	TestHeatRules.run_all(t)
	TestCardResolver.run_all(t)
	TestEnemyAI.run_all(t)
	TestCombatManager.run_all(t)
	TestRun.run_all(t)
	TestLibrary.run_all(t)
	TestEffects.run_all(t)
	TestPhases.run_all(t)
	TestParts.run_all(t)
	TestProtocols.run_all(t)
	TestOrders.run_all(t)
	TestCommands.run_all(t)
	TestContent.run_all(t)
	TestMeta.run_all(t)
	TestSaves.run_all(t)
	TestThreat.run_all(t)
	TestTurnVariety.run_all(t)

	t.summary()
	quit(1 if t.failed > 0 else 0)

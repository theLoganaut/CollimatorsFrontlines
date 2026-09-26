class_name TestContext
extends RefCounted
## Minimal assert-and-count test context, passed into each test_*.gd's
## run_all(). No test framework addon needed to run headless via
## `godot --headless -s res://tests/run_tests.gd`.

var passed: int = 0
var failed: int = 0
var current_group: String = ""
var failures: Array[String] = []

func group(name: String) -> void:
	current_group = name

func _label(msg: String) -> String:
	return "[%s] %s" % [current_group, msg] if current_group != "" else msg

func assert_true(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		failures.append(_label(msg))

func assert_eq(actual, expected, msg: String) -> void:
	if actual == expected:
		passed += 1
	else:
		failed += 1
		failures.append(_label("%s — expected %s, got %s" % [msg, str(expected), str(actual)]))

func summary() -> void:
	print("")
	print("== %d passed, %d failed ==" % [passed, failed])
	if failed > 0:
		print("Failures:")
		for f in failures:
			print("  - " + f)

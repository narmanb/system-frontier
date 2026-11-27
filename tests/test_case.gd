class_name TestCase
extends RefCounted
## Minimal assertion base for tests/run_tests.gd.

var errors: Array = []
var _worlds: Array = []


## Register a SimWorld so the runner disposes it after the test (breaks reference cycles).
func track(w: SimWorld) -> SimWorld:
	_worlds.append(w)
	return w


func cleanup() -> void:
	for w in _worlds:
		w.dispose()
	_worlds.clear()


func check(cond: bool, what: String) -> void:
	if not cond:
		errors.append(what)


func near(actual: float, expected: float, tol: float, what: String) -> void:
	var scale := maxf(1.0, absf(expected))
	if absf(actual - expected) > tol * scale or is_nan(actual):
		errors.append("%s: actual %.9f expected %.9f" % [what, actual, expected])


func fixture(name: String) -> Dictionary:
	var f := FileAccess.open("res://tests/fixtures/" + name, FileAccess.READ)
	return JSON.parse_string(f.get_as_text())

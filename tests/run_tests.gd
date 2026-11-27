extends Node
## Headless test runner (runs as a scene so project autoloads exist, as in the game). Usage:
##   godot --headless --path . res://tests/run_tests.tscn [-- --filter=name]
## Runs every `test_*` method in res://tests/test_*.gd, prints a compact summary and
## exits non-zero on any failure (first few failures per test with actual/expected).

var failures := 0
var passed := 0


func _ready() -> void:
	var filter := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--filter="):
			filter = a.substr(9)
	var dir := DirAccess.open("res://tests")
	var files := []
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	var t0 := Time.get_ticks_msec()
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		if script == null or not script.can_instantiate():
			print("  FAIL %s (script failed to load/compile)" % f)
			failures += 1
			continue
		var inst: Object = script.new()
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_") or (filter != "" and not (f + ":" + name).contains(filter)):
				continue
			inst.set("errors", [])
			inst.call(name)
			if inst.has_method("cleanup"):
				inst.call("cleanup")
			var errs: Array = inst.get("errors")
			if errs.is_empty():
				passed += 1
				print("  ok   %s:%s" % [f.get_basename(), name])
			else:
				failures += 1
				print("  FAIL %s:%s (%d issue%s)" % [f.get_basename(), name, errs.size(), "" if errs.size() == 1 else "s"])
				for e in errs.slice(0, 5):
					print("       - ", e)
	print("\n%d passed, %d failed (%d ms)" % [passed, failures, Time.get_ticks_msec() - t0])
	get_tree().quit(1 if failures > 0 or passed == 0 else 0)

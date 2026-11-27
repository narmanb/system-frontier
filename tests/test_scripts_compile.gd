extends TestCase
## Every GDScript and scene in the project must load (catches parse/type errors in code
## paths the behavioural tests do not reach, e.g. UI scripts).


func _collect(path: String, ext: String, out: Array) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		if f.get_extension() == ext:
			out.append(path.path_join(f))
	for sub in d.get_directories():
		if not sub.begins_with("."):
			_collect(path.path_join(sub), ext, out)


func test_all_scripts_compile() -> void:
	var files := []
	for root in ["res://scripts", "res://tests", "res://tools"]:
		_collect(root, "gd", files)
	check(files.size() > 10, "found scripts")
	for f in files:
		var s: GDScript = load(f)
		check(s != null and s.can_instantiate(), "script compiles: %s" % f)


func test_all_scenes_load() -> void:
	var files := []
	_collect("res://scenes", "tscn", files)
	check(files.size() >= 2, "found scenes")
	for f in files:
		var p: PackedScene = load(f)
		check(p != null and p.can_instantiate(), "scene loads: %s" % f)

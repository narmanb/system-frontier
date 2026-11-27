extends Node
## Dev-only visual smoke capture (not used by the game). Run under a display:
##   godot --path . res://tools/capture.tscn -- --out=<dir> [--size=WxH] [--touch]
## Saves menu.png, sandbox.png, test.png into <dir>.

var out := "user://capture"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a == "--touch": AppState.settings["show_touch"] = "on"
		if a.begins_with("--size="):
			var p := a.substr(7).split("x")
			get_window().size = Vector2i(int(p[0]), int(p[1]))
	DirAccess.make_dir_recursive_absolute(out)
	# Survive scene changes: hand "current scene" to a placeholder and reparent to root.
	var placeholder := Node.new()
	get_tree().root.add_child.call_deferred(placeholder)
	await _frames(1)
	get_tree().current_scene = placeholder
	reparent(get_tree().root)
	await _frames(5)
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
	await _frames(20)
	_shot("menu")
	AppState.launch = {"mode": "sandbox", "threat": 3}
	get_tree().change_scene_to_file("res://scenes/mission/mission.tscn")
	await _frames(10)
	Input.action_press("thrust")
	Input.action_press("fire")
	await _frames(70)
	Input.action_press("turn_right")
	await _frames(25)
	Input.action_release("turn_right")
	await _frames(40)
	_shot("sandbox")
	var mission := get_tree().current_scene
	var w: SimWorld = mission.world
	var i := 0
	for s in w.ships:
		s.pos = w.player.pos + Vector2(260 + i * 90, -140 + i * 70)
		i += 1
	await _frames(45)
	_shot("combat")
	Input.action_release("thrust")
	Input.action_release("fire")
	AppState.launch = {"mode": "test", "threat": 1}
	get_tree().change_scene_to_file("res://scenes/mission/mission.tscn")
	await _frames(10)
	Input.action_press("thrust")
	await _frames(90)
	_shot("test")
	Input.action_release("thrust")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("saved ", out.path_join(name + ".png"))

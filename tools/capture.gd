extends Node
## Dev-only visual smoke capture (not used by the game). Run under a display:
##   godot --path . res://tools/capture.tscn -- --out=<dir> [--size=WxH] [--touch] [--insets=L,T,R,B]
## Saves menu.png, sandbox.png, test.png into <dir>.

var out := "user://capture"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a == "--touch": AppState.settings["show_touch"] = "on"
		if a.begins_with("--insets="):
			var v := a.substr(9).split(",")
			AppState.debug_insets = {"left": float(v[0]), "top": float(v[1]), "right": float(v[2]), "bottom": float(v[3])}
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
	get_tree().change_scene_to_file("res://scenes/setup/setup.tscn")
	await _frames(20)
	_shot("setup")
	SaveService.delete(SaveService.DRAFT)
	for tab in ["Paint", "Stats", "Telemetry", "Hull"]:
		AppState.settings["factory_tab"] = tab
		get_tree().change_scene_to_file("res://scenes/factory/factory.tscn")
		await _frames(15)
		_shot("factory_" + tab.to_lower())
	var c := Campaign.create({"pilot": "Ace", "team": "Avengers"})
	c["credits"] = 640
	c["noble"] = 4
	SaveService.save_campaign(c)
	get_tree().change_scene_to_file("res://scenes/directory_map/directory_map.tscn")
	await _frames(20)
	_shot("map")
	for spec in [[1, "rescue"], [5, "blackhole"], [11, "boss"], [8, "defrag"]]:
		AppState.launch = {"mode": "campaign", "dir_id": spec[0]}
		get_tree().change_scene_to_file("res://scenes/mission/mission.tscn")
		await _frames(10)
		var w: SimWorld = get_tree().current_scene.world
		w.player.invuln = 999
		if spec[1] == "blackhole":
			w.icons.clear()
			await _frames(3)
			w.player.pos = w.mission.black_hole + Vector2(-260, 120)
		elif spec[1] == "boss":
			for s in w.ships:
				if s.boss:
					w.player.pos = s.pos + Vector2(-330, 60)
		elif w.mission.nodes.size() > 0:
			w.player.pos = w.mission.nodes[0].pos + Vector2(-150, 60)
		elif w.mission.programs.size() > 0:
			w.player.pos = w.mission.programs[-1].pos + Vector2(-150, 60)
		Input.action_press("fire")
		await _frames(50)
		Input.action_release("fire")
		_shot("mission_" + spec[1])
	AppState.launch = {"mode": "test", "threat": 1}
	get_tree().change_scene_to_file("res://scenes/mission/mission.tscn")
	await _frames(10)
	Input.action_press("thrust")
	await _frames(90)
	_shot("test")
	Input.action_release("thrust")
	SaveService.reset("campaign")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("saved ", out.path_join(name + ".png"))

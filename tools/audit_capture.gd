extends Node
## Dev-only: captures every screen and popup for a visual audit.
##   godot --path . res://tools/audit_capture.tscn -- --out=<dir> --size=WxH [--touch]

var out := "user://audit"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a == "--touch": AppState.settings["show_touch"] = "on"
		if a.begins_with("--size="):
			var p := a.substr(7).split("x")
			get_window().size = Vector2i(int(p[0]), int(p[1]))
	DirAccess.make_dir_recursive_absolute(out)
	var placeholder := Node.new()
	get_tree().root.add_child.call_deferred(placeholder)
	await _f(1)
	get_tree().current_scene = placeholder
	reparent(get_tree().root)
	SaveService.root = "user://audit_saves/"
	SaveService.reset("all")
	var c := Campaign.create({"pilot": "Ace", "team": "Avengers"})
	c["credits"] = 900
	c["noble"] = 2
	c["salvage"] = {"alloy": 5, "circuitry": 3, "data": 4}
	c["warrant"] = 20
	SaveService.save_campaign(c)
	await _scene("res://scenes/main_menu/main_menu.tscn", "01_menu")
	await _popup_button("Options / Reset", "02_options")
	await _popup_button("Manual / Controls", "03_manual")
	await _scene("res://scenes/setup/setup.tscn", "04_setup")
	await _scene("res://scenes/free_flight/free_flight.tscn", "05_free_flight")
	await _scene("res://scenes/directory_map/directory_map.tscn", "06_map")
	await _popup_button("Upgrade Bay", "07_upgrade_bay")
	await _popup_button("Faction Relations", "08_relations")
	AppState.launch = {"mode": "campaign", "dir_id": 5}
	await _scene("res://scenes/mission/mission.tscn", "09_mission_blackhole")
	var m := get_tree().current_scene
	m.set_paused(true)
	await _f(4)
	_shot("10_pause")
	m.set_paused(false)
	m._ambulance()
	await _f(4)
	_shot("11_ambulance")
	for ov in _overlays():
		ov.queue_free()
	m.world.close_dialog()
	await _f(2)
	m.world.request_dialog("dragon", {"cost": 50})
	await _f(4)
	_shot("12_dragon")
	for ov in _overlays():
		ov.queue_free()
	m.world.close_dialog()
	m._toggle_map()
	await _f(4)
	_shot("13_tactical_map")
	m._toggle_map()
	m.world.end_mission(true, "Directory disinfected.")
	await _f(4)
	_shot("14_debrief")
	for tab in ["Paint", "Hull", "Engines", "Stats", "Modules", "Telemetry", "Library", "Test"]:
		AppState.settings["factory_tab"] = tab
		await _scene("res://scenes/factory/factory.tscn", "15_factory_" + tab.to_lower())
	AppState.settings["factory_tab"] = "Paint"
	await _scene("res://scenes/factory/factory.tscn", "15_factory_paint_again")
	get_tree().current_scene._toggle_precision()
	await _f(6)
	var sc: ScrollContainer = get_tree().current_scene.right_scroll
	sc.scroll_vertical = 100000
	await _f(4)
	_shot("17_precision")
	get_tree().current_scene._auto_clean()
	await _f(4)
	_shot("16_auto_clean")
	SaveService.reset("all")
	SaveService.root = "user://"
	get_tree().quit()


func _overlays() -> Array:
	return get_tree().current_scene.find_children("*", "Control", true, false).filter(func(c): return c is Win95.PopupOverlay)


func _popup_button(text: String, name: String) -> void:
	for b in get_tree().current_scene.find_children("*", "Button", true, false):
		if b.text == text:
			b.pressed.emit()
			break
	await _f(5)
	_shot(name)
	for ov in _overlays():
		ov.queue_free()
	await _f(2)


func _scene(path: String, name: String) -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(path)
	await _f(14)
	_shot(name)


func _f(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))

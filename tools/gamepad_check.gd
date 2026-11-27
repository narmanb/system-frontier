extends Node
## Dev/CI check: drives the real screens with simulated gamepad buttons (Retroid Pocket 5)
## and verifies navigation: focus exists, A activates, B backs out, Start/B pause handling,
## Factory precision cursor painting.  godot --headless --path . res://tools/gamepad_check.tscn

var failures := []


func _ready() -> void:
	var placeholder := Node.new()
	get_tree().root.add_child.call_deferred(placeholder)
	await _f(1)
	get_tree().current_scene = placeholder
	reparent(get_tree().root)
	SaveService.root = "user://gamepad_check/"
	SaveService.reset("all")
	await _scene("res://scenes/main_menu/main_menu.tscn")
	_check(get_viewport().gui_get_focus_owner() != null, "main menu has initial focus")
	var before := get_viewport().gui_get_focus_owner()
	await _press(JOY_BUTTON_DPAD_DOWN)
	_check(get_viewport().gui_get_focus_owner() != before, "D-pad moves focus")
	# focus "Free Flight" and press A
	for b in get_tree().current_scene.find_children("*", "Button", true, false):
		if b.text == "Free Flight":
			b.grab_focus()
	await _press(JOY_BUTTON_A)
	await _f(10)
	_check(get_tree().current_scene.name == "FreeFlight", "A activates the focused button (got %s)" % get_tree().current_scene.name)
	await _press(JOY_BUTTON_B)
	await _f(10)
	_check(get_tree().current_scene.name == "MainMenu", "B goes back to the main menu")
	# popup: Options opens a popup; B closes it
	for b in get_tree().current_scene.find_children("*", "Button", true, false):
		if b.text == "Options / Reset":
			b.grab_focus()
	await _press(JOY_BUTTON_A)
	await _f(3)
	_check(_overlays() == 1, "Options popup opened")
	await _press(JOY_BUTTON_B)
	await _f(3)
	_check(_overlays() == 0, "B closes the popup")
	# campaign map
	SaveService.save_campaign(Campaign.create({}))
	await _scene("res://scenes/directory_map/directory_map.tscn")
	var fo := get_viewport().gui_get_focus_owner()
	_check(fo != null and fo.get_class() == "Button", "directory map focuses a directory")
	await _press(JOY_BUTTON_A)
	await _f(2)
	await _press(JOY_BUTTON_B)
	await _f(10)
	_check(get_tree().current_scene.name == "MainMenu", "B leaves the directory map")
	# mission pause
	AppState.launch = {"mode": "campaign", "dir_id": 0}
	await _scene("res://scenes/mission/mission.tscn")
	await _press(JOY_BUTTON_START)
	await _f(2)
	_check(get_tree().paused, "Start pauses")
	await _press(JOY_BUTTON_START)
	await _f(2)
	_check(not get_tree().paused, "Start resumes while paused")
	await _press(JOY_BUTTON_START)
	await _f(2)
	await _press(JOY_BUTTON_B)
	await _f(2)
	_check(not get_tree().paused, "B resumes from pause")
	await _press(JOY_BUTTON_BACK)
	await _f(2)
	_check(get_tree().current_scene.map_view.visible, "Select opens the tactical map")
	await _press(JOY_BUTTON_B)
	await _f(2)
	_check(not get_tree().current_scene.map_view.visible, "B closes the map")
	get_tree().paused = false
	# factory precision painting
	await _scene("res://scenes/factory/factory.tscn")
	var fac := get_tree().current_scene
	fac.editor.new_blank(24, false)
	await _press(JOY_BUTTON_Y)
	_check(fac._precision and fac.canvas.cursor == Vector2i(12, 12), "Y enables the precision cursor")
	await _press(JOY_BUTTON_DPAD_LEFT)
	await _press(JOY_BUTTON_DPAD_UP)
	_check(fac.canvas.cursor == Vector2i(11, 11), "D-pad moves the cursor")
	await _press(JOY_BUTTON_A)
	_check(fac.editor.grid[11 * 24 + 11] != null, "A paints at the cursor")
	var tab: String = fac.current_tab
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	_check(fac.current_tab != tab, "RB switches tabs")
	await _press(JOY_BUTTON_B)
	_check(not fac._precision, "B leaves precision mode first")
	SaveService.reset("all")
	SaveService.root = "user://"
	print("GAMEPAD CHECK %s" % ("OK" if failures.is_empty() else "FAIL"))
	for f in failures:
		print("  - ", f)
	get_tree().quit(0 if failures.is_empty() else 1)


func _check(cond: bool, what: String) -> void:
	if not cond:
		failures.append(what)


func _overlays() -> int:
	return get_tree().current_scene.find_children("*", "Control", false, false).filter(func(c): return c is Win95.PopupOverlay).size()


func _scene(path: String) -> void:
	get_tree().change_scene_to_file(path)
	await _f(8)


func _press(button: int) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = true
	Input.parse_input_event(e)
	await _f(2)
	var r := InputEventJoypadButton.new()
	r.button_index = button
	r.pressed = false
	Input.parse_input_event(r)
	await _f(2)


func _f(n: int) -> void:
	for i in n:
		await get_tree().process_frame

extends Node
## Mission scene controller: owns the SimWorld, steps it on a fixed 60 Hz physics tick,
## maps input actions to the simulation, and hosts HUD, touch controls and menus.

var world := SimWorld.new()
var view: WorldView
var hud: Hud
var touch: TouchControls
var map_view: TacticalMap
var pause_panel: PanelContainer
var end_panel: PanelContainer
var end_label: Label
var _user_zoom := 1.0
var _pinch := {}          ## touch index -> position, for touches not on flight buttons
var _pinch_dist := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var hull := DataStore.starter_hull(str(AppState.settings["hull"]))
	world.message.connect(func(t, d): hud.show_message(t, d))
	world.sound.connect(func(f, d, w, v): Sfx.beep(f, d, w, v))
	world.finished.connect(_on_finished)
	view = WorldView.new()
	view.world = world
	add_child(view)
	var ui := CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = Win95.make_theme()
	ui.add_child(root)
	var bar := TitleBar.new()
	bar.title = "TEST RANGE" if str(AppState.launch.get("mode")) == "test" else "SANDBOX://FLIGHT"
	bar.add_button("zoom_out", func(): _set_zoom(_user_zoom - 0.15))
	bar.add_button("zoom_in", func(): _set_zoom(_user_zoom + 0.15))
	bar.add_button("map", _toggle_map)
	bar.add_button("pause", set_paused.bind(true))
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	map_view = TacticalMap.new()
	map_view.world = world
	map_view.visible = false
	root.add_child(map_view)
	hud = Hud.new()
	hud.world = world
	root.add_child(hud)
	root.add_child(bar)
	hud.top_inset = 40.0 if AppState.is_touch_ui() else 30.0
	touch = TouchControls.new()
	touch.bottom_inset = Hud.STATUS_BAR_H
	touch.visible = AppState.is_touch_ui()
	touch.map_pressed.connect(_toggle_map)
	root.add_child(touch)
	_build_pause(root)
	_build_end(root)
	_user_zoom = float(AppState.settings.get("zoom", 1.0))
	world.setup(hull, str(AppState.launch.get("mode", "sandbox")), int(AppState.launch.get("threat", 3)))


func _auto_zoom() -> float:
	var vs := get_viewport().get_visible_rect().size
	return clampf(minf(vs.x, vs.y) / 540.0, 0.75, 1.5)


func _set_zoom(z: float) -> void:
	_user_zoom = clampf(z, 0.5, 2.0)
	AppState.settings["zoom"] = _user_zoom


func _process(_dt: float) -> void:
	view.zoom = _auto_zoom() * _user_zoom


func _physics_process(dt: float) -> void:
	var input := {
		"turn": Input.get_axis("turn_left", "turn_right"),
		"thrust": Input.is_action_pressed("thrust"),
		"fire": Input.is_action_pressed("fire"),
		"missile": Input.is_action_pressed("missile"),
	}
	world.step(dt, input)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		set_paused(not get_tree().paused)
	elif event.is_action_pressed("map"):
		_toggle_map()
	elif event.is_action_pressed("zoom_in"):
		_set_zoom(_user_zoom + 0.15)
	elif event.is_action_pressed("zoom_out"):
		_set_zoom(_user_zoom - 0.15)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(_user_zoom + 0.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(_user_zoom - 0.1)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_pinch[event.index] = event.position
		else:
			_pinch.erase(event.index)
		_pinch_dist = _pinch_distance()
	elif event is InputEventScreenDrag and _pinch.has(event.index):
		_pinch[event.index] = event.position
		var d := _pinch_distance()
		if d > 0 and _pinch_dist > 0:
			_set_zoom(_user_zoom * d / _pinch_dist)
		_pinch_dist = d
	elif event is InputEventMagnifyGesture:
		_set_zoom(_user_zoom * event.factor)


func _pinch_distance() -> float:
	if _pinch.size() != 2:
		return 0.0
	var v := _pinch.values()
	return (v[0] as Vector2).distance_to(v[1])


func _toggle_map() -> void:
	map_view.visible = not map_view.visible
	view.visible = not map_view.visible
	hud.visible = not map_view.visible


func set_paused(p: bool) -> void:
	if world.over:
		return
	get_tree().paused = p
	pause_panel.visible = p
	AppState.release_gameplay_inputs()
	touch.release_all()
	touch.visible = AppState.is_touch_ui() and not p
	if p:
		Sfx.beep(300, 0.04)
		(pause_panel.find_child("Resume", true, false) as Button).grab_focus()
	else:
		AppState.save_settings()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			if is_inside_tree() and not world.over:
				set_paused(true)
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if get_tree().paused:
				_quit_to_menu()
			else:
				set_paused(true)


func _dialog(root: Control, title: String) -> Array:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var parts := Win95.window(title)
	parts[0].custom_minimum_size = Vector2(340, 0)
	center.add_child(parts[0])
	return [center, parts[0], parts[1]]


func _build_pause(root: Control) -> void:
	var d := _dialog(root, "Paused")
	d[0].process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	pause_panel = d[1]
	pause_panel.visible = false
	var box: VBoxContainer = d[2]
	box.add_child(Win95.label("Operation suspended.", 16))
	var resume := Win95.button("Resume")
	resume.name = "Resume"
	resume.pressed.connect(set_paused.bind(false))
	box.add_child(resume)
	var restart := Win95.button("Restart")
	restart.pressed.connect(_restart)
	box.add_child(restart)
	if not OS.has_feature("mobile"):
		var fs := Win95.button("Toggle Fullscreen (F11)")
		fs.pressed.connect(AppState.toggle_fullscreen)
		box.add_child(fs)
	var touch_btn := Win95.button("Touch pads: %s" % AppState.settings["show_touch"])
	touch_btn.pressed.connect(func():
		var order := ["auto", "on", "off"]
		var next: String = order[(order.find(str(AppState.settings["show_touch"])) + 1) % 3]
		AppState.set_setting("show_touch", next)
		touch_btn.text = "Touch pads: %s" % next)
	box.add_child(touch_btn)
	var quit := Win95.button("Quit to Menu")
	quit.pressed.connect(_quit_to_menu)
	box.add_child(quit)


func _build_end(root: Control) -> void:
	var d := _dialog(root, "Operation Debriefing")
	d[0].process_mode = Node.PROCESS_MODE_ALWAYS
	end_panel = d[1]
	end_panel.visible = false
	var box: VBoxContainer = d[2]
	end_label = Win95.label("", 17)
	end_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	end_label.custom_minimum_size = Vector2(300, 0)
	box.add_child(end_label)
	var again := Win95.button("Fly Again")
	again.name = "Again"
	again.pressed.connect(_restart)
	box.add_child(again)
	var menu := Win95.button("Main Menu")
	menu.pressed.connect(_quit_to_menu)
	box.add_child(menu)


func _on_finished(won: bool, reason: String) -> void:
	AppState.release_gameplay_inputs()
	touch.release_all()
	touch.visible = false
	(end_panel.get_child(0).get_child(0) as TitleBar).title = "Operation Debriefing" if won else "Ship Lost"
	end_label.text = "%s\n\nCredits: %d" % [reason, world.campaign["credits"]]
	end_panel.visible = true
	(end_panel.find_child("Again", true, false) as Button).grab_focus()


func _restart() -> void:
	get_tree().paused = false
	AppState.save_settings()
	get_tree().reload_current_scene()


func _quit_to_menu() -> void:
	get_tree().paused = false
	AppState.save_settings()
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")

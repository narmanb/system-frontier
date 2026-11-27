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
	root.theme = UiTheme.make()
	ui.add_child(root)
	map_view = TacticalMap.new()
	map_view.world = world
	map_view.visible = false
	root.add_child(map_view)
	hud = Hud.new()
	hud.world = world
	hud.pause_pressed.connect(set_paused.bind(true))
	hud.zoom_pressed.connect(func(d): _set_zoom(_user_zoom + d))
	root.add_child(hud)
	touch = TouchControls.new()
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


func _centered_panel(root: Control) -> PanelContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 0)
	center.add_child(panel)
	return panel


func _build_pause(root: Control) -> void:
	pause_panel = _centered_panel(root)
	pause_panel.get_parent().process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	pause_panel.visible = false
	var box := VBoxContainer.new()
	pause_panel.add_child(box)
	box.add_child(UiTheme.label("PAUSED", 28, UiTheme.ACCENT))
	var resume := UiTheme.button("Resume")
	resume.name = "Resume"
	resume.pressed.connect(set_paused.bind(false))
	box.add_child(resume)
	var restart := UiTheme.button("Restart")
	restart.pressed.connect(_restart)
	box.add_child(restart)
	if not OS.has_feature("mobile"):
		var fs := UiTheme.button("Toggle Fullscreen (F11)")
		fs.pressed.connect(AppState.toggle_fullscreen)
		box.add_child(fs)
	var touch_btn := UiTheme.button("Touch controls: %s" % AppState.settings["show_touch"])
	touch_btn.pressed.connect(func():
		var order := ["auto", "on", "off"]
		var next: String = order[(order.find(str(AppState.settings["show_touch"])) + 1) % 3]
		AppState.set_setting("show_touch", next)
		touch_btn.text = "Touch controls: %s" % next)
	box.add_child(touch_btn)
	var quit := UiTheme.button("Quit to Menu")
	quit.pressed.connect(_quit_to_menu)
	box.add_child(quit)


func _build_end(root: Control) -> void:
	end_panel = _centered_panel(root)
	end_panel.get_parent().process_mode = Node.PROCESS_MODE_ALWAYS
	end_panel.visible = false
	var box := VBoxContainer.new()
	end_panel.add_child(box)
	end_label = UiTheme.label("", 22, UiTheme.ACCENT)
	end_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	end_label.custom_minimum_size = Vector2(300, 0)
	box.add_child(end_label)
	var again := UiTheme.button("Fly Again")
	again.name = "Again"
	again.pressed.connect(_restart)
	box.add_child(again)
	var menu := UiTheme.button("Main Menu")
	menu.pressed.connect(_quit_to_menu)
	box.add_child(menu)


func _on_finished(won: bool, reason: String) -> void:
	AppState.release_gameplay_inputs()
	touch.release_all()
	touch.visible = false
	end_label.text = "%s\n%s\nCredits: %d" % ["OPERATION DEBRIEFING" if won else "SHIP LOST", reason, world.campaign["credits"]]
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

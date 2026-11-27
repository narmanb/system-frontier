extends Node
## Mission scene controller: owns the SimWorld, steps it on a fixed 60 Hz physics tick,
## maps input actions to the simulation, and hosts HUD, touch controls and menus.

var world := SimWorld.new()
var view: WorldView
var hud: Hud
var touch: TouchControls
var map_view: TacticalMap
var radar: RadarWindow
var pause_panel: PanelContainer
var end_panel: PanelContainer
var end_label: Label
var _user_zoom := 1.0
var _pinch := {}          ## touch index -> position, for touches not on flight buttons
var _pinch_dist := 0.0
var campaign_mode := false
var endless_mode := false   ## EXPERIMENTAL: Recycle Bin survival
var _campaign: Dictionary = {}
var _dir: Dictionary = {}
var _root: Control
var strategy_bar: StrategyBar


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	campaign_mode = str(AppState.launch.get("mode", "sandbox")) == "campaign"
	endless_mode = str(AppState.launch.get("mode", "")) == "endless"
	if campaign_mode:
		var loaded = SaveService.load_campaign()
		if loaded == null:
			get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu/main_menu.tscn")
			return
		_campaign = loaded
		_dir = Campaign.directory(_campaign, int(AppState.launch.get("dir_id", 0)))
	var hull := DataStore.starter_hull(str(AppState.settings["hull"]))
	world.dialog.connect(_on_dialog)
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
	_root = root
	# No window chrome in flight: pause/zoom/map live in the pause menu (Back/Esc/Start or
	# the small pause chip); the radar window opens the tactical map when tapped.
	hud = Hud.new()
	hud.world = world
	hud.pause_pressed.connect(set_paused.bind(true))
	root.add_child(hud)
	radar = RadarWindow.new()
	radar.world = world
	radar.open_map.connect(_toggle_map)
	root.add_child(radar)
	hud.radar = radar
	map_view = TacticalMap.new()
	map_view.world = world
	map_view.visible = false
	map_view.closed.connect(_toggle_map)
	root.add_child(map_view)
	var strategy := campaign_mode and str(_campaign.get("mode", "action")) == "strategy"
	touch = TouchControls.new()
	touch.visible = AppState.is_touch_ui()
	touch.show_ambulance = campaign_mode or endless_mode
	touch.flight_pads = not strategy
	touch.ambulance_pressed.connect(_ambulance)
	root.add_child(touch)
	AppState.input_mode_changed.connect(func(_g):
		touch.visible = AppState.is_touch_ui() and not get_tree().paused and not world.over
		if not touch.visible:
			touch.release_all())
	if strategy:
		strategy_bar = StrategyBar.new()
		strategy_bar.command.connect(func(cmd):
			world.strategy = cmd
			hud.show_message("Autopilot priority: %s" % cmd.to_upper(), 2.0)
			Sfx.beep(420, 0.04))
		root.add_child(strategy_bar)
		get_viewport().size_changed.connect(_layout_strategy)
		_layout_strategy()
	_build_pause(root)
	_build_end(root)
	var pin := PauseInput.new()
	pin.mission = self
	add_child(pin)
	_user_zoom = float(AppState.settings.get("zoom", 1.0))
	if campaign_mode:
		world.setup_directory(_campaign, _dir)
	elif endless_mode:
		world.setup_endless(hull)
	else:
		if AppState.launch.get("ship") is Dictionary:
			hull = Campaign.normalize_ship(AppState.launch["ship"])
			var opts: Dictionary = AppState.launch.get("test_options", {})
			world.infinite_test_resources = bool(opts.get("infinite", true))
			world.test_moving_target = bool(opts.get("moving", true))
		world.setup(hull, str(AppState.launch.get("mode", "sandbox")), int(AppState.launch.get("threat", 3)))


func _layout_strategy() -> void:
	var vs := get_viewport().get_visible_rect().size
	var w := minf(vs.x - 24, 460)
	strategy_bar.size = Vector2(w, 50)
	strategy_bar.position = Vector2((vs.x - w) / 2, vs.y - 64 - AppState.safe_insets().bottom)


# ---------------------------------------------------------------- dialogs

func _on_dialog(kind: String, payload: Dictionary) -> void:
	AppState.release_gameplay_inputs()
	touch.release_all()
	var choose := func(choice: String) -> bool:
		return world.resolve_dialog(kind, choice, payload)
	match kind:
		"dragon":
			Win95.popup(_root, "Dragon Process", "A corrupted dragon guards a Noble Program inside the black hole.\n\nSpend %d credits to deploy a logic bomb, or fight it as a high-risk simulated encounter. Damage inside the simulation is restored afterward." % payload.get("cost", 40), [
				["Logic Bomb (%d credits)" % payload.get("cost", 40), choose.bind("bomb")],
				["Fight", choose.bind("fight")],
				["Retreat", choose.bind("retreat")]])
		"vendor":
			var c := world.campaign
			Win95.popup(_root, "Wandering Patch Program", "PATCH.GRL: \"Your hull checksum looks rough. I can install a temporary repair patch.\"\n\nHull %d/%d · Credits %d" % [roundi(world.player.hull), roundi(world.player.max_hull), c["credits"]], [
				["Repair for 25", choose.bind("repair")],
				["Trade 1 data core", choose.bind("trade")],
				["Decline", choose.bind("decline")]])
		"quarantine":
			Win95.popup(_root, "Quarantined Cache", "A sealed cache contains unstable but valuable fabrication data.", [
				["Purge and recover", choose.bind("purge")],
				["Leave sealed", choose.bind("leave")]])


## Legacy showRelations (R key): current standing with every faction.
func _relations() -> void:
	var lines := []
	for f in DataStore.factions():
		var v: float = world.campaign["relations"].get(f, 0.0)
		lines.append("%-10s %5d   %s" % [f, roundi(v), "Friendly" if v > 20 else ("Hostile" if v < -20 else "Neutral")])
	var field := Win95.field("\n".join(lines), 15)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["monospace", "Courier New", "DejaVu Sans Mono"])
	(field.get_child(0) as Label).add_theme_font_override("font", mono)
	Win95.popup(_root, "Faction Relations", "Warrant level: %d" % world.campaign.get("warrant", 0), [["Close", func(): pass]], field)


## Legacy callAmbulance: refuel, repair, missiles, laser/armor upgrades, clear warrant.
func _ambulance() -> void:
	if not (campaign_mode or endless_mode) or world.over or world.blocked or get_tree().paused:
		return
	world.blocked = true
	AppState.release_gameplay_inputs()
	touch.release_all()
	var list := VBoxContainer.new()
	var credits := Win95.label("", 16, Win95.TEXT, true)
	list.add_child(credits)
	var rows := VBoxContainer.new()
	list.add_child(rows)
	var rebuild := func(again: Callable) -> void:
		credits.text = "Ambulance docked. Credits: %d" % world.campaign["credits"]
		for ch in rows.get_children():
			ch.queue_free()
		for o in world.ambulance_offers():
			var b := Win95.button("%s — %d credits" % [o[1], o[2]], 46)
			b.disabled = o[2] <= 0 or world.campaign["credits"] < o[2]
			var id: String = o[0]
			b.pressed.connect(func():
				world.buy_ambulance(id)
				again.call(again))
			rows.add_child(b)
	rebuild.call(rebuild)
	Win95.popup(_root, "Ambulance Service", "", [["Undock", func(): world.close_dialog()]], list)


func _exit_tree() -> void:
	world.dispose()


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
	if world.over:
		if event.is_action_pressed("ui_cancel"):
			_quit_to_menu()
		return
	if map_view.visible and event.is_action_pressed("ui_cancel"):
		_toggle_map()
		get_viewport().set_input_as_handled()
		return
	if strategy_bar and (event.is_action_pressed("turn_left") or event.is_action_pressed("turn_right")):
		var cmds := StrategyBar.COMMANDS
		var i := (cmds.find(strategy_bar.current) + (1 if event.is_action_pressed("turn_right") else -1) + cmds.size()) % cmds.size()
		strategy_bar.current = cmds[i]
		strategy_bar.command.emit(cmds[i])
		strategy_bar.queue_redraw()
		return
	if event.is_action_pressed("relations"):
		set_paused(true)
		_relations()
	elif event.is_action_pressed("ambulance"):
		_ambulance()
	elif event.is_action_pressed("pause"):
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
	radar.visible = not map_view.visible
	radar.cancel()


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
	var row := HBoxContainer.new()
	for spec in [["Zoom -", -0.15], ["Zoom +", 0.15]]:
		var zb := Win95.button(spec[0])
		zb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var dz: float = spec[1]
		zb.pressed.connect(func(): _set_zoom(_user_zoom + dz))
		row.add_child(zb)
	box.add_child(row)
	if campaign_mode or endless_mode:
		var amb := Win95.button("Ambulance Service")
		amb.pressed.connect(func(): set_paused(false); _ambulance())
		box.add_child(amb)
	var rel_btn := Win95.button("Faction Relations")
	rel_btn.pressed.connect(_relations)
	box.add_child(rel_btn)
	var map_btn := Win95.button("Tactical Map")
	map_btn.pressed.connect(func(): set_paused(false); _toggle_map())
	box.add_child(map_btn)
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
	var quit := Win95.button("Retreat to Directory Map" if campaign_mode else ("Return to Factory" if AppState.launch.get("return") == "factory" else "Quit to Menu"))
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
	menu.name = "Menu"
	menu.pressed.connect(_quit_to_menu)
	box.add_child(menu)


func _on_finished(won: bool, reason: String) -> void:
	AppState.release_gameplay_inputs()
	touch.release_all()
	touch.visible = false
	if strategy_bar:
		strategy_bar.visible = false
	var again := end_panel.find_child("Again", true, false) as Button
	var menu := end_panel.find_child("Menu", true, false) as Button
	(end_panel.get_child(0).get_child(0) as TitleBar).title = "Operation Debriefing" if won else "Ship Lost"
	if endless_mode:
		var m := world.mission
		var reached: int = m.wave - (0 if m.wave_state == "intermission" else 1)
		var rec := SaveService.record_endless(m.score, reached)
		(end_panel.get_child(0).get_child(0) as TitleBar).title = "Recycle Bin — Run Over"
		end_label.text = "%s\n\nScore: %d%s\nWaves cleared: %d · Ships destroyed: %d\nBest: %d (wave %d) · Runs: %d" % [reason, m.score,
			"   NEW BEST!" if rec["new_best"] else "", reached, world.player_kills, rec["best_score"], rec["best_wave"], rec["runs"]]
	elif not campaign_mode:
		end_label.text = "%s\n\nCredits: %d" % [reason, world.campaign["credits"]]
	else:
		var reward := {}
		if won:
			reward = Campaign.complete_directory(_campaign, int(_dir["id"]))
			SaveService.save_campaign(_campaign)
		var c := _campaign
		var salvage := ""
		if not reward.is_empty():
			salvage = "\n\nRecovered: %s\nSpend alloy, circuitry and data cores in the Ship Factory library." % Campaign.reward_text(reward)
		end_label.text = "%s\n\nCredits: %d\nDirectories cleared: %d/%d\nNoble Programs: %d/4%s" % [reason, c["credits"], c["wavesCleared"], c["dirs"].size(), c["noble"], salvage]
		menu.text = "Directory Map"
		again.text = "Restore Save" if not won else "Directory Map"
		again.visible = not won
	end_panel.visible = true
	(again if again.visible else menu).grab_focus()


func _restart() -> void:
	get_tree().paused = false
	AppState.save_settings()
	if campaign_mode and world.over:
		# Restore Save: discard this run and return to the map from the last save.
		get_tree().change_scene_to_file("res://scenes/directory_map/directory_map.tscn")
		return
	get_tree().reload_current_scene()


func _quit_to_menu() -> void:
	get_tree().paused = false
	AppState.save_settings()
	if campaign_mode:
		# Keep in-run earnings, relations and warrants (legacy kept them in memory and saved later).
		if not world.over or not world.campaign.is_empty():
			SaveService.save_campaign(_campaign)
		get_tree().change_scene_to_file("res://scenes/directory_map/directory_map.tscn")
		return
	if AppState.launch.get("return") == "factory":
		var t := world.telemetry
		AppState.set_meta("last_test", "Last test: peak %d, 90%% speed %s, %d shots, %.1f s." % [roundi(t.maxSpeed),
			("%.2f s" % t.timeTo90) if t.timeTo90 >= 0 else "not reached", t.shots, world.time - t.started])
		get_tree().change_scene_to_file("res://scenes/factory/factory.tscn")
		return
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")


## Handles Start / Esc / B while the tree is paused (the mission node itself is pausable).
class PauseInput:
	extends Node
	var mission

	func _init() -> void:
		process_mode = Node.PROCESS_MODE_WHEN_PAUSED

	func _unhandled_input(event: InputEvent) -> void:
		if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
			for ch in mission._root.get_children():
				if ch is Win95.PopupOverlay:
					return
			get_viewport().set_input_as_handled()
			mission.set_paused(false)
